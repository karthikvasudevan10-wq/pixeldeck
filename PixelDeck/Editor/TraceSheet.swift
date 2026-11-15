import SwiftUI
import PhotosUI

/// The tracing picture: a photo or sketch laid under every layer, at its own opacity, to draw
/// over. It is a guide only: never part of frames, the onion skin, thumbnails or exports.
/// Chosen with the system photo picker (no photo-library permission); saved on the device.
struct TraceSheet: View {
    let model: EditorModel
    @Binding var image: UIImage?
    @Environment(\.dismiss) private var dismiss
    @State private var item: PhotosPickerItem?
    @State private var loading = false

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "Tracing image", onClose: { dismiss() })
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let image, let trace = model.trace {
                        controls(image, trace)
                    } else {
                        picker
                    }
                }
                .padding(16)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .screenBackground()
        .presentationDetents([.medium, .large])
        // The canvas stays live behind the sheet, so changes can be seen as they're made.
        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        .onChange(of: item) { _, newItem in
            guard let newItem else { return }
            loading = true
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self), let picked = UIImage(data: data) {
                    use(picked.downscaled(maxSide: 2048))
                }
                item = nil
                loading = false
            }
        }
    }

    // MARK: Empty

    private var picker: some View {
        PhotosPicker(selection: $item, matching: .images) {
            VStack(spacing: 12) {
                if loading {
                    ProgressView().tint(Theme.accent)
                } else {
                    PixelIcon.gallery.view(size: 40, lineWidth: 1.5)
                }
                Text("Choose a picture").font(AppFont.pixel(13)).foregroundStyle(Theme.text)
                Text("It goes under every layer so you can trace over it. Set how see-through it is. It's never included in frames or exports.")
                    .font(AppFont.body(13, relativeTo: .footnote))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 260)
            }
            .foregroundStyle(Theme.muted)
            .padding(24)
            .frame(maxWidth: .infinity, minHeight: 220)
            .overlay(Rectangle().strokeBorder(Theme.muted, style: StrokeStyle(lineWidth: 2, dash: [6, 4])))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(loading)
    }

    // MARK: Controls

    @ViewBuilder
    private func controls(_ image: UIImage, _ trace: TraceSettings) -> some View {
        HStack(spacing: 12) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: 56, height: 56)
                .background(Theme.ink)
                .opacity(trace.isVisible ? 1 : 0.4)
            VStack(alignment: .leading, spacing: 2) {
                Text("Under every layer").font(AppFont.body(15, .bold, relativeTo: .body)).foregroundStyle(Theme.cream)
                Text("Not included in exports").font(AppFont.body(13, relativeTo: .footnote)).foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 0)
            Button { update { $0.isVisible.toggle() } } label: {
                (trace.isVisible ? PixelIcon.eye : .eyeOff).view(size: 20)
                    .foregroundStyle(trace.isVisible ? Theme.text : Theme.muted)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(trace.isVisible ? Text("Hide tracing image") : Text("Show tracing image"))
        }

        section("Opacity", value: Text(trace.opacity, format: .percent.precision(.fractionLength(0)))) {
            Slider(value: Binding(get: { trace.opacity }, set: { v in update { $0.opacity = v } }),
                   in: TraceSettings.opacityRange)
                .tint(Theme.accent)
                .accessibilityLabel("Opacity")
        }
        .disabled(!trace.isVisible)

        // Logarithmic, so small sizes get as much of the slider as big ones.
        section("Size", value: Text("\(Int(trace.width.rounded())) × \(Int(trace.height.rounded())) px")) {
            Slider(value: Binding(get: { log2(trace.width) }, set: { v in update { $0.width = pow(2, v) } }),
                   in: log2(TraceSettings.widthRange.lowerBound)...log2(TraceSettings.widthRange.upperBound))
                .tint(Theme.accent)
                .accessibilityLabel("Size")
                .accessibilityValue(Text("\(Int(trace.width.rounded())) pixels wide"))
        }
        .disabled(!trace.isVisible)

        section("Position", value: nil) {
            HStack(spacing: 6) {
                nudge(.arrowLeft, "Move left") { $0.centerX -= 1 }
                nudge(.arrowUp, "Move up") { $0.centerY -= 1 }
                nudge(.arrowDown, "Move down") { $0.centerY += 1 }
                nudge(.arrowRight, "Move right") { $0.centerX += 1 }
                Spacer(minLength: 6)
                Button {
                    let placed = TraceSettings.placed(aspect: trace.aspect, over: model.contentBounds)
                    update { $0.width = placed.width; $0.centerX = placed.centerX; $0.centerY = placed.centerY }
                } label: {
                    Text("Fit to art").font(AppFont.pixel(11)).padding(.horizontal, 12).frame(height: 40)
                }
                .buttonStyle(TileButtonStyle())
            }
        }
        .disabled(!trace.isVisible)

        HStack(spacing: 8) {
            PhotosPicker(selection: $item, matching: .images) {
                Text("Replace").font(AppFont.pixel(11)).frame(maxWidth: .infinity).frame(height: 44)
            }
            .buttonStyle(TileButtonStyle())
            Button(role: .destructive) { remove() } label: {
                Text("Remove").font(AppFont.pixel(11)).frame(maxWidth: .infinity).frame(height: 44)
            }
            .buttonStyle(TileButtonStyle(foreground: Theme.accent))
        }
        .disabled(loading)
    }

    private func section<Content: View>(_ title: LocalizedStringKey, value: Text?, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(AppFont.pixel(11)).foregroundStyle(Theme.muted)
                Spacer()
                value?.font(AppFont.body(13, .medium, relativeTo: .footnote)).foregroundStyle(Theme.text).monospacedDigit()
            }
            content()
        }
    }

    private func nudge(_ icon: PixelIcon, _ label: LocalizedStringKey, _ change: @escaping (inout TraceSettings) -> Void) -> some View {
        Button { update(change) } label: {
            icon.view(size: 18).frame(width: 44, height: 40).contentShape(Rectangle())
        }
        .buttonStyle(TileButtonStyle())
        .accessibilityLabel(label)
        .buttonRepeatBehavior(.enabled)
    }

    // MARK: Actions

    private func update(_ change: (inout TraceSettings) -> Void) {
        guard var t = model.trace else { return }
        change(&t)
        model.setTrace(t)
    }

    private func use(_ picked: UIImage) {
        guard picked.size.width > 0, picked.size.height > 0 else { return }
        let aspect = Double(picked.size.height / picked.size.width)
        ImageStore.traces.save(picked, for: model.project.id)
        image = picked
        if var t = model.trace {
            // Replacing keeps the place and width; the height follows the new picture.
            t.aspect = aspect
            t.isVisible = true
            model.setTrace(t)
        } else {
            model.setTrace(.placed(aspect: aspect, over: model.contentBounds))
        }
    }

    private func remove() {
        ImageStore.traces.delete(for: model.project.id)
        image = nil
        model.setTrace(nil)
    }
}
