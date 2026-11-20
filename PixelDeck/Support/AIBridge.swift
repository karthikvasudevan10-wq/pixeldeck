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
            while let (request, used) = HTTPRequest.parse(pending) {
                pending = Data(pending.dropFirst(used))
                self.respond(to: request, on: connection)
            }
            if finished || error != nil || pending.count > LocalServer.maxRequestBytes {
                connection.cancel()
                return
            }
            self.receive(on: connection, buffer: pending)
        }
    }

    private func respond(to request: HTTPRequest, on connection: NWConnection) {
        let handler = self.handler
        Task { @MainActor in
            let response = handler?(request) ?? .plain(503)
            connection.send(content: response.data, completion: .contentProcessed { _ in })
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
    @ObservationIgnored let token: String

    static let preferredPort: UInt16 = 47_860
    static let bannerSeconds = 6.0

    private init() {
        let defaults = UserDefaults.standard
        approved = defaults.stringArray(forKey: "aiApprovedClients") ?? []
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
        UserDefaults.standard.set(approved, forKey: "aiApprovedClients")
    }

    func decline(_ client: String) {
        pending.removeAll { $0 == client }
    }

    func remove(_ client: String) {
        approved.removeAll { $0 == client }
        UserDefaults.standard.set(approved, forKey: "aiApprovedClients")
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
                    "capabilities": ["tools": ["listChanged": false]],
                    "serverInfo": ["name": "pixeldeck", "title": "Pixel Deck", "version": AppConfig.version],
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
        ["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": message]]
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
        tools.append(["name": "new_canvas", "description": "Start a new, empty sprite in the Studio (the current one is saved).",
                      "inputSchema": ["type": "object", "properties": [String: Any]()]])
        tools.append(["name": "export", "description": "Get the current frame as a PNG image, enlarged so it's easy to see.",
                      "inputSchema": ["type": "object", "properties": [String: Any]()]])
        return tools
    }

    private static let drawingTools: Set<String> = ["set_pixels", "line", "rect", "ellipse", "fill"]

    private func callTool(_ name: String, _ arguments: [String: Any], client: String, session: String) -> (content: [[String: Any]], failed: Bool) {
        func text(_ s: String) -> [String: Any] { ["type": "text", "text": s] }
        func refuse(_ s: String) -> (content: [[String: Any]], failed: Bool) {
            note(client: client, tool: name, note: s, failed: true)
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
            note(client: client, tool: name, note: "A new canvas", failed: false)
            return ([text("Started a new, empty canvas.")], false)
        }
        guard let model else { return refuse("Open the Studio in Pixel Deck first (tap any sprite, or New canvas).") }
        if name == "export" {
            note(client: client, tool: name, note: "Looked at the result", failed: false)
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
            note(client: client, tool: name, note: name == "read_canvas" ? "Looked at the canvas" : reply, failed: false)
            var content = [text(reply)]
            if name == "read_canvas", let image = Self.picture(of: model) { content.append(image) }
            return (content, false)
        } catch let e as AIToolError {
            return refuse(e.message)
        } catch {
            return refuse("That didn't work.")
        }
    }

    private func note(client: String, tool: String, note: String, failed: Bool) {
        counter += 1
        let step = Step(number: counter, client: client, tool: tool, note: String(note.prefix(80)), failed: failed)
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

/// Shown over the Studio while an assistant draws, or when one is waiting to be allowed.
struct AIBanner: View {
    @State private var bridge = AIBridge.shared

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            VStack(spacing: 6) {
                ForEach(bridge.pending, id: \.self) { client in
                    HStack(spacing: 10) {
                        Text("\(client) wants to draw in Pixel Deck", comment: "An AI assistant asking to connect; the placeholder is its name")
                            .font(AppFont.body(14, .bold, relativeTo: .subheadline)).foregroundStyle(Theme.onAccent2)
                        Spacer(minLength: 4)
                        Button("Allow") { bridge.approve(client) }
                            .font(AppFont.pixel(12)).foregroundStyle(Theme.onAccent2)
                            .padding(.horizontal, 10).frame(height: 32).background(Theme.surface.opacity(0.25))
                        Button("Not now") { bridge.decline(client) }
                            .font(AppFont.body(13, relativeTo: .footnote)).foregroundStyle(Theme.onAccent2)
                    }
                    .padding(.horizontal, 12)
                    .frame(minHeight: 44)
                    .background(Theme.accent2)
                }
                if bridge.isDrawing(at: timeline.date), let step = bridge.current {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(step.client) is drawing", comment: "An AI assistant is drawing; the placeholder is its name")
                                .font(AppFont.body(14, .bold, relativeTo: .subheadline)).foregroundStyle(Theme.onAccent)
                            Text(verbatim: "\(step.tool) · \(step.number)")
                                .font(AppFont.pixel(10)).foregroundStyle(Theme.onAccent.opacity(0.8))
                        }
                        Spacer(minLength: 4)
                        Button("Stop") { bridge.stop() }
                            .font(AppFont.pixel(12)).foregroundStyle(Theme.accent)
                            .padding(.horizontal, 12).frame(height: 32).background(Theme.ink)
                    }
                    .padding(.horizontal, 12)
                    .frame(minHeight: 44)
                    .background(Theme.accent)
                }
            }
            .frame(maxWidth: 460)
            .padding(.top, 8)
            .buttonStyle(.plain)
        }
    }
}

/// Settings › AI assistants (Mac).
struct AISettingsSection: View {
    @State private var bridge = AIBridge.shared
    @State private var copied: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: Binding(get: { bridge.enabled }, set: { bridge.enabled = $0 })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Let AI assistants draw in Pixel Deck")
                        .font(AppFont.body(15, .medium, relativeTo: .body)).foregroundStyle(Theme.text)
                    Text("Off until you turn it on. Assistants on this Mac that support MCP can use the same tools you do, so their drawings are real layers and frames you can edit and undo. It uses your own assistant; no art goes to any Pixel Deck server.")
                        .font(AppFont.body(12, relativeTo: .caption)).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .tint(Theme.accent)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Theme.surface)

            if bridge.enabled {
                Group {
                    if let port = bridge.port {
                        Text("Server: on this Mac only · port \(String(port)) · running", comment: "AI server status; the placeholder is a port number")
                    } else if bridge.serverFailed {
                        Text("The server couldn't start. Turn this off and on again.")
                    } else {
                        Text("Starting…")
                    }
                }
                .font(AppFont.body(12, relativeTo: .caption))
                .foregroundStyle(Theme.muted)
                .padding(.horizontal, 14)

                if let code = bridge.claudeCodeSetup {
                    copyRow("Copy setup for Claude Code", detail: "Paste it into Terminal once", value: code)
                }
                if let desktop = bridge.claudeDesktopSetup {
                    copyRow("Copy setup for the Claude app", detail: "Paste it into the app's developer settings file (it needs Node.js)", value: desktop)
                }
                if let address = bridge.address {
                    copyRow("Copy the server address", detail: "For any other assistant that connects to an MCP server by URL", value: address)
                }

                ForEach(bridge.pending, id: \.self) { client in
                    appRow(client, status: Text("Asked to connect · waiting for you")) {
                        Button("Allow") { bridge.approve(client) }.foregroundStyle(Theme.accent2)
                    }
                }
                ForEach(bridge.approved, id: \.self) { client in
                    appRow(client, status: Text("Allowed to draw")) {
                        Button("Remove") { bridge.remove(client) }.foregroundStyle(Theme.accent)
                    }
                }
                if bridge.isStopped {
                    Button("You pressed Stop. Let assistants draw again") { bridge.allowAgain() }
                        .font(AppFont.body(14, .medium, relativeTo: .subheadline))
                        .foregroundStyle(Theme.accent2)
                        .padding(.horizontal, 14)
                }
                Text("While an assistant draws, a banner shows its name with a Stop button. Every action is one undo step and goes in the timelapse, and it works on a new layer unless it's told otherwise.")
                    .font(AppFont.body(12, relativeTo: .caption)).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 14)
            }
        }
    }

    private func copyRow(_ title: LocalizedStringKey, detail: LocalizedStringKey, value: String) -> some View {
        Button {
            UIPasteboard.general.string = value
            copied = value
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(AppFont.body(15, .medium, relativeTo: .body)).foregroundStyle(Theme.text)
                    Text(detail).font(AppFont.body(12, relativeTo: .caption)).foregroundStyle(Theme.muted)
                }
                Spacer(minLength: 4)
                if copied == value { Text("Copied").font(AppFont.pixel(10)).foregroundStyle(Theme.accent2) }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Theme.surface)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func appRow<Trailing: View>(_ name: String, status: Text, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: name).font(AppFont.body(15, .bold, relativeTo: .body)).foregroundStyle(Theme.cream)
                status.font(AppFont.body(12, relativeTo: .caption)).foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 4)
            trailing().font(AppFont.body(14, .medium, relativeTo: .subheadline)).buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Theme.surface)
    }
}
