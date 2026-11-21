import Foundation
import Network
import Observation
import SwiftUI
import UIKit

// Drawing with AI assistants on the Mac. Pixel Deck is an MCP server: a small web server that
// only this Mac can reach, which offers Pixel Deck's drawing actions as tools. The person's own
// assistant (Claude, Claude Code, or anything else that speaks MCP) calls them.
//
// Safeguards: it's off until switched on in Settings; each assistant app has to be approved once;
// the address includes a private key; every action is one undo step and goes in the timelapse; a
// banner shows while an assistant draws, with Stop. Nothing is sent to any Pixel Deck server.

/// One HTTP request, as much as the MCP server needs.
struct HTTPRequest {
    var method: String
    var path: String
    /// Lower-cased names.
    var headers: [String: String]
    var body: Data

    /// Parses a request from the start of `data`. Nil if it hasn't all arrived yet. Returns the
    /// request and how many bytes it used.
    static func parse(_ data: Data) -> (HTTPRequest, Int)? {
        let bytes = [UInt8](data)
        let separator: [UInt8] = [13, 10, 13, 10]
        guard bytes.count >= 4 else { return nil }
        var headerEnd = -1
        var i = 0
        while i + 3 < bytes.count {
            if bytes[i] == 13, Array(bytes[i..<(i + 4)]) == separator { headerEnd = i; break }
            i += 1
        }
        guard headerEnd >= 0 else { return nil }
        let head = String(decoding: bytes[0..<headerEnd], as: UTF8.self)
        var lines = head.components(separatedBy: "\r\n")
        let parts = lines.removeFirst().split(separator: " ")
        guard parts.count >= 2 else { return nil }
        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            headers[line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()] =
                line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        let length = Int(headers["content-length"] ?? "0") ?? 0
        let bodyStart = headerEnd + 4
        guard length >= 0, bytes.count >= bodyStart + length else { return nil }
        let path = String(parts[1]).components(separatedBy: "?")[0]
        return (HTTPRequest(method: String(parts[0]).uppercased(), path: path, headers: headers,
                            body: Data(bytes[bodyStart..<(bodyStart + length)])), bodyStart + length)
    }
}

struct HTTPResponse {
    var status = 200
    var headers: [String: String] = [:]
    var body = Data()

    static func json(_ object: Any, status: Int = 200, headers: [String: String] = [:]) -> HTTPResponse {
        var h = headers
        h["Content-Type"] = "application/json"
        return HTTPResponse(status: status, headers: h, body: (try? JSONSerialization.data(withJSONObject: object)) ?? Data("{}".utf8))
    }

    static func plain(_ status: Int, _ text: String = "") -> HTTPResponse {
        HTTPResponse(status: status, headers: ["Content-Type": "text/plain; charset=utf-8"], body: Data(text.utf8))
    }

    var data: Data {
        let reasons = [200: "OK", 202: "Accepted", 400: "Bad Request", 403: "Forbidden", 404: "Not Found", 405: "Method Not Allowed", 503: "Service Unavailable"]
        var head = "HTTP/1.1 \(status) \(reasons[status] ?? "OK")\r\n"
        var all = headers
        all["Content-Length"] = "\(body.count)"
        all["Connection"] = "keep-alive"
        for (k, v) in all { head += "\(k): \(v)\r\n" }
        head += "\r\n"
        return Data(head.utf8) + body
    }
}

/// A web server that only this Mac can reach (it listens on the loopback interface).
final class LocalServer {
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "PixelDeck.LocalServer")
    /// Called on the main actor for each request.
    var handler: (@MainActor (HTTPRequest) -> HTTPResponse)?
    /// Called on the main queue when the server is up (with its port) or has given up (nil).
    var onState: ((UInt16?) -> Void)?
    static let maxRequestBytes = 8 * 1024 * 1024

    /// Starts listening on `port`, or one of the nine after it if that one is taken.
    func start(port: UInt16, attemptsLeft: Int = 10) {
        stop()
        let parameters = NWParameters.tcp
        parameters.acceptLocalOnly = true
        parameters.requiredInterfaceType = .loopback
        parameters.allowLocalEndpointReuse = true
        guard attemptsLeft > 0, let endpointPort = NWEndpoint.Port(rawValue: port),
              let listener = try? NWListener(using: parameters, on: endpointPort) else {
            DispatchQueue.main.async { self.onState?(nil) }
            return
        }
        self.listener = listener
        listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
        listener.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                DispatchQueue.main.async { self?.onState?(port) }
            case .failed:
                // Most likely the port is in use: try the next one.
                listener.cancel()
                DispatchQueue.main.async { self?.start(port: port &+ 1, attemptsLeft: attemptsLeft - 1) }
            default:
                break
            }
        }
        listener.start(queue: queue)
    }

    func stop() {
        listener?.stateUpdateHandler = nil
        listener?.cancel()
        listener = nil
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(on: connection, buffer: Data())
    }

    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 18) { [weak self] data, _, finished, error in
            guard let self else { return }
            var pending = buffer
            if let data { pending.append(data) }
            let ending = finished || error != nil || pending.count > LocalServer.maxRequestBytes
            var answered = false
            while let (request, used) = HTTPRequest.parse(pending) {
                pending = Data(pending.dropFirst(used))
                // A client that closes its side after sending still gets its answer first.
                self.respond(to: request, on: connection, thenClose: ending && error == nil)
                answered = true
            }
            if ending {
                if !answered || error != nil { connection.cancel() }
                return
            }
            self.receive(on: connection, buffer: pending)
        }
    }

    private func respond(to request: HTTPRequest, on connection: NWConnection, thenClose: Bool) {
        let handler = self.handler
        Task { @MainActor in
            let response = handler?(request) ?? .plain(503)
            connection.send(content: response.data, completion: .contentProcessed { _ in
                if thenClose { connection.cancel() }
            })
        }
    }
}

/// The app's side of AI drawing: who may connect, what they're doing, and the Studio they draw in.
@MainActor
@Observable
final class AIBridge {
    static let shared = AIBridge()

    struct Step: Identifiable {
        let id = UUID()
        let number: Int
        let client: String
        let tool: String
        /// The call as the assistant made it, e.g. `rect(6,14 → 33,31)`.
        let call: String
        let note: String
        let failed: Bool
    }

    /// Off until the person turns it on (Settings › AI assistants).
    var enabled: Bool {
        didSet {
            UserDefaults.standard.set(enabled, forKey: "aiEnabled")
            enabled ? startServer() : stopServer()
        }
    }
    /// Assistant apps allowed to draw, and ones waiting to be allowed.
    private(set) var approved: [String]
    private(set) var pending: [String] = []
    /// When each app was allowed, and when it last drew.
    private(set) var approvedAt: [String: Date] = [:]
    private(set) var lastUsed: [String: Date] = [:]
    /// The port the server is listening on, once it's running.
    private(set) var port: UInt16?
    private(set) var serverFailed = false
    /// What the assistant did last (for the banner), and its recent steps.
    private(set) var current: Step?
    private(set) var steps: [Step] = []
    private(set) var lastActivity = Date.distantPast
    /// After Stop, tool calls are refused until this time.
    private(set) var stoppedUntil = Date.distantPast

    /// The Studio on screen, registered by the editor. Tools draw here.
    @ObservationIgnored weak var model: EditorModel?
    @ObservationIgnored var startNewCanvas: (() -> Void)?

    @ObservationIgnored private let server = LocalServer()
    @ObservationIgnored private var sessions: [String: String] = [:]
    @ObservationIgnored private var lastClient = "Assistant"
    @ObservationIgnored private var layered = Set<String>()
    @ObservationIgnored private var counter = 0
    /// A private key in the server's address, so only apps the person set up can find it.
    let token: String

    static let preferredPort: UInt16 = 47_860
    static let bannerSeconds = 6.0

    private init() {
        let defaults = UserDefaults.standard
        approved = defaults.stringArray(forKey: "aiApprovedClients") ?? []
        let dates = (defaults.dictionary(forKey: "aiApprovedDates") as? [String: Double]) ?? [:]
        approvedAt = dates.mapValues { Date(timeIntervalSince1970: $0) }
        if let saved = defaults.string(forKey: "aiToken"), saved.count >= 16 {
            token = saved
        } else {
            token = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
            defaults.set(token, forKey: "aiToken")
        }
        enabled = defaults.bool(forKey: "aiEnabled")
        server.handler = { [weak self] request in self?.handle(request) ?? .plain(503) }
        server.onState = { [weak self] port in
            self?.port = port
            self?.serverFailed = port == nil
        }
    }

    /// Called at launch: the server only runs on the Mac, and only when switched on.
    func startIfEnabled() {
        if enabled { startServer() }
    }

    private func startServer() {
        guard ProcessInfo.processInfo.isMacCatalystApp else { return }
        serverFailed = false
        server.start(port: AIBridge.preferredPort)
    }

    private func stopServer() {
        server.stop()
        port = nil
        sessions = [:]
        pending = []
        current = nil
    }

    var address: String? { port.map { "http://127.0.0.1:\($0)/mcp/\(token)" } }

    /// What to paste into a terminal to connect Claude Code.
    var claudeCodeSetup: String? { address.map { "claude mcp add --transport http pixeldeck \($0)" } }

    /// What to add to the Claude desktop app's settings file (it reaches local servers through a small bridge).
    var claudeDesktopSetup: String? {
        address.map { "{\n  \"mcpServers\": {\n    \"pixeldeck\": {\n      \"command\": \"npx\",\n      \"args\": [\"-y\", \"mcp-remote\", \"\($0)\"]\n    }\n  }\n}" }
    }

    func approve(_ client: String) {
        pending.removeAll { $0 == client }
        if !approved.contains(client) { approved.append(client) }
        approvedAt[client] = Date()
        save()
    }

    private func save() {
        UserDefaults.standard.set(approved, forKey: "aiApprovedClients")
        UserDefaults.standard.set(approvedAt.mapValues(\.timeIntervalSince1970), forKey: "aiApprovedDates")
    }

    func decline(_ client: String) {
        pending.removeAll { $0 == client }
    }

    func remove(_ client: String) {
        approved.removeAll { $0 == client }
        approvedAt[client] = nil
        save()
    }

    /// The banner's Stop: the assistant is told to stop, and can't draw for the next two minutes.
    func stop() {
        stoppedUntil = Date().addingTimeInterval(120)
        current = nil
    }

    func allowAgain() {
        stoppedUntil = .distantPast
    }

    var isStopped: Bool { stoppedUntil > Date() }

    /// An assistant drew something in the last few seconds.
    func isDrawing(at date: Date = Date()) -> Bool {
        current != nil && date.timeIntervalSince(lastActivity) < AIBridge.bannerSeconds
    }

    // MARK: MCP over HTTP

    private func handle(_ request: HTTPRequest) -> HTTPResponse {
        guard enabled else { return .plain(503, "AI drawing is switched off in Pixel Deck.") }
        // Web pages mustn't be able to reach the server: assistants don't send an Origin.
        if let origin = request.headers["origin"], !origin.hasPrefix("http://127.0.0.1"), !origin.hasPrefix("http://localhost") {
            return .plain(403)
        }
        guard request.path == "/mcp/\(token)" || request.path == "/mcp/\(token)/" else { return .plain(404) }
        switch request.method {
        case "POST":
            break
        case "DELETE":
            if let id = request.headers["mcp-session-id"] { sessions[id] = nil }
            return .plain(200)
        default:
            // No server-sent stream: every answer comes back on the POST.
            return HTTPResponse(status: 405, headers: ["Allow": "POST, DELETE"], body: Data())
        }
        guard let parsed = try? JSONSerialization.jsonObject(with: request.body) else {
            return .json(Self.error(id: NSNull(), code: -32700, message: "Parse error"), status: 400)
        }
        var sessionID = request.headers["mcp-session-id"]
        var extra: [String: String] = [:]
        let messages = (parsed as? [[String: Any]]) ?? (parsed as? [String: Any]).map { [$0] } ?? []
        var replies: [[String: Any]] = []
        for message in messages {
            guard let method = message["method"] as? String else { continue }
            let params = message["params"] as? [String: Any] ?? [:]
            guard let id = message["id"] else { continue }            // a notification: nothing to answer
            switch method {
            case "initialize":
                let info = params["clientInfo"] as? [String: Any]
                let name = Self.tidy((info?["title"] as? String) ?? (info?["name"] as? String) ?? "Assistant")
                let newID = UUID().uuidString
                sessions[newID] = name
                sessionID = newID
                lastClient = name
                extra["Mcp-Session-Id"] = newID
                if !approved.contains(name), !pending.contains(name) { pending.append(name) }
                replies.append(Self.result(id: id, [
                    "protocolVersion": (params["protocolVersion"] as? String) ?? "2025-03-26",
                    "capabilities": ["tools": ["listChanged": false]] as [String: Any],
                    "serverInfo": ["name": "pixeldeck", "title": "Pixel Deck", "version": AppConfig.version] as [String: Any],
                    "instructions": "You are drawing pixel art in Pixel Deck, an app on the user's Mac. Call read_canvas first. Work in small steps and read the canvas back to check them: pixel art is small, so every pixel shows. Keep to a few colours. Your drawing goes on its own layer; the user can undo any step.",
                ]))
            case "ping":
                replies.append(Self.result(id: id, [:]))
            case "tools/list":
                replies.append(Self.result(id: id, ["tools": Self.toolList]))
            case "tools/call":
                let client = sessionID.flatMap { sessions[$0] } ?? lastClient
                let outcome = callTool((params["name"] as? String) ?? "", params["arguments"] as? [String: Any] ?? [:],
                                       client: client, session: sessionID ?? client)
                replies.append(Self.result(id: id, ["content": outcome.content, "isError": outcome.failed]))
            default:
                replies.append(Self.error(id: id, code: -32601, message: "Method not found: \(method)"))
            }
        }
        if replies.isEmpty { return HTTPResponse(status: 202, headers: extra, body: Data()) }
        return .json(parsed is [Any] ? replies as Any : replies[0] as Any, headers: extra)
    }

    private static func result(id: Any, _ result: [String: Any]) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id, "result": result]
    }

    private static func error(id: Any, code: Int, message: String) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": message] as [String: Any]]
    }

    private static func tidy(_ name: String) -> String {
        let t = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? "Assistant" : String(t.prefix(40))
    }

    private static var toolList: [[String: Any]] {
        var tools: [[String: Any]] = AITools.all.map { tool in
            ["name": tool.name, "description": tool.summary,
             "inputSchema": (try? JSONSerialization.jsonObject(with: Data(tool.schema.utf8))) ?? ["type": "object"]]
        }
        let noArguments: [String: Any] = ["type": "object", "properties": [String: Any]()]
        tools.append(["name": "new_canvas", "description": "Start a new, empty sprite in the Studio (the current one is saved).",
                      "inputSchema": noArguments])
        tools.append(["name": "export", "description": "Get the current frame as a PNG image, enlarged so it's easy to see.",
                      "inputSchema": noArguments])
        return tools
    }

    private static let drawingTools: Set<String> = ["set_pixels", "line", "rect", "ellipse", "fill"]

    private func callTool(_ name: String, _ arguments: [String: Any], client: String, session: String) -> (content: [[String: Any]], failed: Bool) {
        func text(_ s: String) -> [String: Any] { ["type": "text", "text": s] }
        let call = Self.signature(name, arguments)
        func refuse(_ s: String) -> (content: [[String: Any]], failed: Bool) {
            note(client: client, tool: name, call: call, note: s, failed: true)
            return ([text(s)], true)
        }
        guard approved.contains(client) else {
            if !pending.contains(client) { pending.append(client) }
            return ([text("Pixel Deck is waiting for its user to allow \"\(client)\" to draw. Ask them to open Pixel Deck and choose Allow (it's also in Settings, under AI assistants), then try again.")], true)
        }
        if isStopped {
            return ([text("The person using Pixel Deck pressed Stop. Don't draw anything more unless they ask you to.")], true)
        }
        if name == "new_canvas" {
            guard let startNewCanvas else { return refuse("Open the Studio in Pixel Deck first (tap any sprite, or New canvas).") }
            startNewCanvas()
            note(client: client, tool: name, call: call, note: "A new canvas", failed: false)
            return ([text("Started a new, empty canvas.")], false)
        }
        guard let model else { return refuse("Open the Studio in Pixel Deck first (tap any sprite, or New canvas).") }
        if name == "export" {
            note(client: client, tool: name, call: call, note: "Looked at the result", failed: false)
            guard let image = Self.picture(of: model) else { return ([text("The canvas is empty.")], false) }
            return ([text("The current frame."), image], false)
        }
        // An assistant draws on its own layer unless it chose one itself.
        let key = "\(session)|\(model.project.id.uuidString)"
        if Self.drawingTools.contains(name), !layered.contains(key) {
            layered.insert(key)
            if !model.currentLayerGrid.isBlank, model.canAddLayer { model.addLayer(named: client) }
        }
        if name == "add_layer" || name == "select_layer" { layered.insert(key) }
        do {
            let reply = try AITools.call(name, arguments, model: model)
            note(client: client, tool: name, call: call, note: name == "read_canvas" ? "Looked at the canvas" : reply, failed: false)
            var content = [text(reply)]
            if name == "read_canvas", let image = Self.picture(of: model) { content.append(image) }
            return (content, false)
        } catch let e as AIToolError {
            return refuse(e.message)
        } catch {
            return refuse("That didn't work.")
        }
    }

    /// A short, readable form of a tool call for the steps list.
    private static func signature(_ name: String, _ a: [String: Any]) -> String {
        func n(_ key: String) -> String { AITools.int(a[key]).map(String.init) ?? "?" }
        switch name {
        case "line", "rect", "ellipse": return "\(name)(\(n("x1")),\(n("y1")) → \(n("x2")),\(n("y2")))"
        case "fill": return "fill(\(n("x")),\(n("y")))"
        case "set_pixels":
            let count = (a["pixels"] as? [Any])?.count ?? (a["rows"] as? [String])?.reduce(0) { $0 + $1.filter { $0 != "." }.count } ?? 0
            return "set_pixels(\(count))"
        case "add_layer": return "add_layer(\"\((a["name"] as? String) ?? "")\")"
        case "select_frame": return "select_frame(\(n("frame")))"
        case "select_layer": return "select_layer(\(n("layer")))"
        case "set_palette": return "set_palette(…)"
        case "flip", "rotate": return "\(name)(\((a["direction"] as? String) ?? ""))"
        case "set_speed": return "set_speed(\(n("fps")))"
        default: return "\(name)()"
        }
    }

    private func note(client: String, tool: String, call: String, note: String, failed: Bool) {
        counter += 1
        lastUsed[client] = Date()
        let step = Step(number: counter, client: client, tool: tool, call: call, note: String(note.prefix(80)), failed: failed)
        current = step
        steps.append(step)
        if steps.count > 40 { steps.removeFirst(steps.count - 40) }
        lastActivity = Date()
    }

    /// The current frame's art as an MCP image (PNG, enlarged to about 512 px).
    private static func picture(of model: EditorModel) -> [String: Any]? {
        guard let box = model.contentBounds else { return nil }
        let grid = model.currentGrid.reframed(from: model.bounds, to: box)
        let scale = max(1, min(16, 512 / max(box.width, box.height)))
        guard let image = PixelRenderer.cgImage(grid, scale: scale), let png = UIImage(cgImage: image).pngData() else { return nil }
        return ["type": "image", "data": png.base64EncodedString(), "mimeType": "image/png"]
    }
}

/// A four-pointed spark, the mark for AI assistants.
struct SparkShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = min(rect.width, rect.height) / 2, k = r * 0.28
        p.move(to: CGPoint(x: c.x, y: c.y - r))
        p.addLine(to: CGPoint(x: c.x + k, y: c.y - k))
        p.addLine(to: CGPoint(x: c.x + r, y: c.y))
        p.addLine(to: CGPoint(x: c.x + k, y: c.y + k))
        p.addLine(to: CGPoint(x: c.x, y: c.y + r))
        p.addLine(to: CGPoint(x: c.x - k, y: c.y + k))
        p.addLine(to: CGPoint(x: c.x - r, y: c.y))
        p.addLine(to: CGPoint(x: c.x - k, y: c.y - k))
        p.closeSubpath()
        return p
    }
}

/// Shown over the Studio while an assistant draws, or when one is waiting to be allowed.
struct AIBanner: View {
    @State private var bridge = AIBridge.shared
    /// The layer being drawn on, for "on Castle · step 14".
    var layerName: String = ""

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            VStack(spacing: 6) {
                ForEach(bridge.pending, id: \.self) { client in
                    HStack(spacing: 12) {
                        SparkShape().fill(Theme.accent2).frame(width: 18, height: 18)
                        Text("\(client) wants to draw in Pixel Deck", comment: "An AI assistant asking to connect; the placeholder is its name")
                            .font(AppFont.body(15, .bold, relativeTo: .subheadline)).foregroundStyle(Theme.cream)
                        Spacer(minLength: 4)
                        Button { bridge.approve(client) } label: {
                            Text("Allow").font(AppFont.pixel(12)).foregroundStyle(Theme.onAccent)
                                .padding(.horizontal, 14).frame(height: 34).background(Theme.accent)
                        }
                        Button { bridge.decline(client) } label: {
                            Text("Not now").font(AppFont.body(13, relativeTo: .footnote)).foregroundStyle(Theme.muted)
                        }
                    }
                    .padding(.horizontal, 14)
                    .frame(minHeight: 50)
                    .background(Theme.ink)
                    .overlay(Rectangle().strokeBorder(Theme.accent2, lineWidth: 2))
                }
                if bridge.isDrawing(at: timeline.date), let step = bridge.current {
                    HStack(spacing: 12) {
                        SparkShape().fill(Theme.accent2).frame(width: 18, height: 18)
                        Text("\(step.client) is drawing", comment: "An AI assistant is drawing; the placeholder is its name")
                            .font(AppFont.body(15, .bold, relativeTo: .subheadline)).foregroundStyle(Theme.cream)
                        (layerName.isEmpty
                            ? Text("step \(step.number)", comment: "Which step an AI assistant is on")
                            : Text("on \(layerName) · step \(step.number)", comment: "The layer an AI assistant is drawing on, and which step it is on"))
                            .font(AppFont.body(14, relativeTo: .subheadline)).foregroundStyle(Theme.muted)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Button { bridge.stop() } label: {
                            HStack(spacing: 6) {
                                Rectangle().frame(width: 8, height: 8)
                                Text("Stop").font(AppFont.pixel(12))
                            }
                            .foregroundStyle(Theme.onAccent)
                            .padding(.horizontal, 14).frame(height: 34).background(Theme.accent)
                        }
                    }
                    .padding(.horizontal, 14)
                    .frame(minHeight: 50)
                    .background(Theme.ink)
                    .overlay(Rectangle().strokeBorder(Theme.accent2, lineWidth: 2))
                }
            }
            .frame(maxWidth: 480)
            .padding(.top, 16)
            .buttonStyle(.plain)
        }
    }
}

/// The inspector's AI tab: who is connected, and what it did, step by step.
struct AIInspectorPanel: View {
    @State private var bridge = AIBridge.shared

    private var client: String? { bridge.current?.client ?? bridge.steps.last?.client ?? bridge.approved.last }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let client {
                HStack(spacing: 10) {
                    SparkShape().fill(Theme.accent2).frame(width: 18, height: 18).frame(width: 36, height: 36).background(Theme.tool)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: client).font(AppFont.body(16, .bold, relativeTo: .headline)).foregroundStyle(Theme.cream)
                        (bridge.approved.contains(client) ? Text("Connected over MCP · approved") : Text("Connected over MCP · waiting for you"))
                            .font(AppFont.body(13, relativeTo: .footnote)).foregroundStyle(Theme.muted)
                    }
                }
            } else {
                Text("No assistant has connected yet. Copy the setup from Settings › AI, then ask your assistant to draw.")
                    .font(AppFont.body(13, relativeTo: .footnote)).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !bridge.steps.isEmpty {
                Text("What it did").font(AppFont.pixel(11)).foregroundStyle(Theme.muted)
                VStack(spacing: 0) {
                    ForEach(bridge.steps.suffix(12)) { step in
                        let latest = step.id == bridge.current?.id
                        HStack(alignment: .top, spacing: 10) {
                            Text(verbatim: "\(step.number)").font(AppFont.pixel(9)).foregroundStyle(Theme.muted).frame(width: 22, alignment: .leading)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(verbatim: step.call)
                                    .font(.system(size: 13, design: .monospaced))
                                    .foregroundStyle(step.failed ? Theme.accent : latest ? Theme.accent2 : Theme.text)
                                    .lineLimit(1)
                                Text(verbatim: step.note).font(AppFont.body(12, relativeTo: .caption)).foregroundStyle(Theme.muted).lineLimit(2)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 6)
                        .overlay(alignment: .bottom) { Theme.line.frame(height: 1) }
                    }
                }
            }
            Text("Each step is one undo. Nothing leaves your Mac except through your own assistant.")
                .font(AppFont.body(13, relativeTo: .footnote)).foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Settings › AI (Mac).
struct AISettingsSection: View {
    @State private var bridge = AIBridge.shared
    @State private var copied = false

    private static var toolNames: [String] { ["new_canvas"] + AITools.all.map(\.name) + ["export"] }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Toggle(isOn: Binding(get: { bridge.enabled }, set: { bridge.enabled = $0 })) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Let AI assistants draw in Pixel Deck")
                        .font(AppFont.body(18, .bold, relativeTo: .headline)).foregroundStyle(Theme.cream)
                    Text("Off until you turn it on. Assistants on this Mac that support MCP can use the same tools you do, so their drawings are real layers and frames you can edit and undo. It uses your own assistant subscription; no art goes to any Pixel Deck server.")
                        .font(AppFont.body(13, relativeTo: .footnote)).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .tint(Theme.accent)

            Text("Connected apps · each one asks you first").font(AppFont.pixel(11)).foregroundStyle(Theme.muted)
            if bridge.approved.isEmpty && bridge.pending.isEmpty {
                Text("None yet.").font(AppFont.body(14, relativeTo: .subheadline)).foregroundStyle(Theme.muted)
            }
            ForEach(bridge.approved, id: \.self) { client in
                appRow(client, status: status(of: client)) {
                    Button { bridge.remove(client) } label: {
                        Text("Remove").font(AppFont.pixel(11)).foregroundStyle(Theme.text).padding(.horizontal, 12).frame(height: 34).background(Theme.tool)
                    }
                }
            }
            ForEach(bridge.pending, id: \.self) { client in
                appRow(client, status: Text("Asked to connect · waiting for you")) {
                    Button { bridge.approve(client) } label: {
                        Text("Allow").font(AppFont.pixel(11)).foregroundStyle(Theme.onAccent).padding(.horizontal, 12).frame(height: 34).background(Theme.accent)
                    }
                }
            }

            Text("Tools they can use").font(AppFont.pixel(11)).foregroundStyle(Theme.muted)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 6, alignment: .leading)], alignment: .leading, spacing: 6) {
                ForEach(Self.toolNames, id: \.self) { name in
                    Text(verbatim: name)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Theme.text)
                        .padding(.horizontal, 8)
                        .frame(height: 26)
                        .background(Theme.tool)
                }
            }

            Text("While an assistant draws").font(AppFont.pixel(11)).foregroundStyle(Theme.muted)
            VStack(alignment: .leading, spacing: 6) {
                Text("· A banner shows its name with a Stop button")
                Text("· Every action is one undo step, and goes in the timelapse")
                Text("· It works on a new layer unless you say otherwise")
            }
            .font(AppFont.body(14, relativeTo: .subheadline))
            .foregroundStyle(Theme.text)

            if bridge.isStopped {
                Button { bridge.allowAgain() } label: {
                    Text("You pressed Stop. Let assistants draw again").font(AppFont.body(14, .medium, relativeTo: .subheadline)).foregroundStyle(Theme.accent2)
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 10) {
                Group {
                    if !bridge.enabled {
                        Text("Server: off")
                    } else if let port = bridge.port {
                        Text("Server: local · pixeldeck-mcp · running on port \(String(port))", comment: "AI server status; the placeholder is a port number")
                    } else if bridge.serverFailed {
                        Text("Server: couldn't start. Turn this off and on again.")
                    } else {
                        Text("Server: starting…")
                    }
                }
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Theme.muted)
                Spacer(minLength: 4)
                Menu {
                    Button("For Claude Code (paste into Terminal)") { copy(bridge.claudeCodeSetup) }
                    Button("For the Claude app (developer settings file)") { copy(bridge.claudeDesktopSetup) }
                    Button("Just the server address") { copy(bridge.address) }
                } label: {
                    Text(copied ? "Copied" : "Copy setup for Claude").font(AppFont.pixel(11)).foregroundStyle(Theme.text)
                        .padding(.horizontal, 12).frame(height: 34)
                }
                .disabled(bridge.address == nil)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 52)
            .background(Theme.surface)
        }
    }

    private func status(of client: String) -> Text {
        var parts: [String] = []
        if let date = bridge.approvedAt[client] {
            parts.append(String(localized: "Approved \(date.formatted(.dateTime.day().month(.abbreviated)))", comment: "When an AI assistant was allowed; the placeholder is a date like 18 Nov"))
        } else {
            parts.append(String(localized: "Approved"))
        }
        if let used = bridge.lastUsed[client] {
            parts.append(Calendar.current.isDateInToday(used) ? String(localized: "last used today")
                         : String(localized: "last used \(used.formatted(.dateTime.day().month(.abbreviated)))", comment: "When an AI assistant last drew; the placeholder is a date"))
        }
        return Text(verbatim: parts.joined(separator: " · "))
    }

    private func copy(_ value: String?) {
        guard let value else { return }
        UIPasteboard.general.string = value
        copied = true
    }

    private func appRow<Trailing: View>(_ name: String, status: Text, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 12) {
            SparkShape().fill(Theme.accent2).frame(width: 18, height: 18).frame(width: 40, height: 40).background(Theme.tool)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: name).font(AppFont.body(16, .bold, relativeTo: .headline)).foregroundStyle(Theme.cream)
                status.font(AppFont.body(13, relativeTo: .footnote)).foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 4)
            trailing().buttonStyle(.plain)
        }
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) { Theme.line.frame(height: 1) }
    }
}
