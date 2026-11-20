import SwiftUI

/// Where timelapses are kept: Application Support/Timelapse/<sprite id>.json, on this device only
/// (they can be large, so they don't sync).
enum TimelapseStore {
    private static var folder: URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let dir = base.appendingPathComponent("Timelapse", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func url(_ id: UUID) -> URL? { folder?.appendingPathComponent(id.uuidString).appendingPathExtension("json") }
    private static let io = DispatchQueue(label: "PixelDeck.Timelapse", qos: .utility)

    static func load(for id: UUID) -> Timelapse {
        guard let u = url(id), let data = try? Data(contentsOf: u),
              let t = try? JSONDecoder().decode(Timelapse.self, from: data) else { return Timelapse() }
        return t
    }

    static func save(_ t: Timelapse, for id: UUID) {
        guard !t.isEmpty, let u = url(id) else { return }
        io.async { if let data = try? JSONEncoder().encode(t) { try? data.write(to: u, options: .atomic) } }
    }

    static func delete(for id: UUID) {
        guard let u = url(id) else { return }
        io.async { try? FileManager.default.removeItem(at: u) }
    }

    static func copy(from id: UUID, to newID: UUID) {
        guard let a = url(id), let b = url(newID) else { return }
        io.async { try? FileManager.default.copyItem(at: a, to: b) }
    }
}

/// Replays how a sprite was drawn. Pro saves it as a video (1080 × 1080 MP4).
struct TimelapseView: View {
    let name: String
    let timelapse: Timelapse
    @Environment(\.dismiss) private var dismiss
    @Environment(PurchaseManager.self) private var purchases
    @State private var frames: [PixelGrid] = []
    @State private var index = 0
    @State private var playing = true
    @State private var working = false
    @State private var message: String?
    @State private var upgrade: ProFeature?
    @State private var shareItems: ShareItems?

    /// nonisolated: also read by the background video export.
    private nonisolated static let fps = 15.0

    var body: some View {
        VStack(spacing: 14) {
            SheetHeader(title: "Timelapse", onClose: { dismiss() })
            if frames.isEmpty {
                Spacer()
                Text("Your timelapse records itself as you draw. Draw a little, then come back to watch it.")
                    .font(AppFont.body(15, relativeTo: .body))
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                    .padding(32)
                Spacer()
            } else {
                player
                controls
            }
        }
        .padding(.bottom, 16)
        .screenBackground()
        .presentationDetents([.large])
        .task { frames = timelapse.playbackFrames() }
        .proUpgradeSheet($upgrade)
        .sheet(item: $shareItems) { items in
            ActivityView(items: items.urls) { _ in shareItems = nil }.ignoresSafeArea()
        }
    }

    private var player: some View {
        TimelineView(.periodic(from: .now, by: 1 / Self.fps)) { ctx in
            ZStack {
                Theme.chip
                PixelImage(grid: frames[min(index, frames.count - 1)], checker: false).padding(20)
            }
            .onChange(of: ctx.date) { _, _ in
                guard playing else { return }
                // Hold the finished art a moment before looping.
                if index < frames.count - 1 { index += 1 } else if Int(ctx.date.timeIntervalSince1970 * Self.fps) % 30 == 0 { index = 0 }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 320)
        .padding(.horizontal, 16)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Timelapse of \(name), step \(index + 1) of \(frames.count)"))
    }

    private var controls: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Button { playing.toggle() } label: {
                    (playing ? PixelIcon.pause : .play).view(size: 18).frame(width: 48, height: 44)
                }
                .buttonStyle(TileButtonStyle(fill: Theme.surface))
                .accessibilityLabel(playing ? Text("Pause") : Text("Play"))
                Slider(value: Binding(get: { Double(index) }, set: { index = Int($0); playing = false }),
                       in: 0...Double(max(1, frames.count - 1)), step: 1)
                    .tint(Theme.accent)
                    .accessibilityLabel("Position")
            }
            .padding(.horizontal, 16)
            HStack(spacing: 8) {
                Button { makeVideo(share: false) } label: {
                    HStack(spacing: 10) {
                        if working { ProgressView().tint(Theme.onAccent) } else { PixelIcon.download.view(size: 18, lineWidth: 2.5) }
                        Text("Save video").font(AppFont.pixel(15))
                        if !purchases.access.allowsTimelapseVideo { ProBadge() }
                    }
                    .frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(PrimaryButtonStyle(depth: 4))
                Button { makeVideo(share: true) } label: {
                    PixelIcon.share.view(size: 20).frame(width: 52, height: 52)
                }
                .buttonStyle(TileButtonStyle(fill: Theme.surface))
                .accessibilityLabel("Share video")
            }
            .disabled(working)
            .padding(.horizontal, 16)
            if let message {
                Text(verbatim: message).font(AppFont.body(13, relativeTo: .footnote)).foregroundStyle(Theme.accent2)
            }
        }
    }

    private func makeVideo(share: Bool) {
        guard purchases.access.allowsTimelapseVideo else { upgrade = .timing; return }
        working = true
        message = nil
        let grids = frames
        let base = name
        Task.detached(priority: .userInitiated) {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("Export-\(UUID().uuidString)", isDirectory: true)
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            let file = url.appendingPathComponent("\(base) timelapse.mp4")
            var durations = Array(repeating: 1 / Self.fps, count: grids.count)
            if !durations.isEmpty { durations[durations.count - 1] = 1.5 }   // linger on the finished art
            let result = Result { try VideoExporter.write(grids: grids, durations: durations, to: file) }
            await MainActor.run {
                working = false
                switch result {
                case .failure(let e): message = e.localizedDescription
                case .success:
                    if share {
                        shareItems = ShareItems(urls: [file])
                    } else {
                        Task {
                            do {
                                try await PhotoSaver.save([file])
                                message = String(localized: "Saved to Photos")
                            } catch {
                                message = error.localizedDescription
                            }
                        }
                    }
                }
            }
        }
    }
}
