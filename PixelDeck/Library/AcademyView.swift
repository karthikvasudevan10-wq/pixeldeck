import SwiftUI

// Pixel Academy and Idea of the day: gentle ways in for people who don't know what to draw yet.
// No streaks, nothing lost by skipping a day.

/// Which lessons have been finished (kept on the device).
enum AcademyProgress {
    static func isDone(_ lesson: Lesson) -> Bool { UserDefaults.standard.bool(forKey: "lessonDone.\(lesson.id)") }
    static func markDone(_ id: String) { UserDefaults.standard.set(true, forKey: "lessonDone.\(id)") }
}

/// Pixel Academy: short lessons that end with a real animation.
struct AcademyView: View {
    /// Called with the lesson to start (or carry on with).
    var onStart: (Lesson) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(PurchaseManager.self) private var purchases
    @AppStorage("lessonID") private var lessonID = ""
    @AppStorage("lessonStep") private var lessonStep = 0
    @AppStorage("lessonProjectID") private var lessonProjectID = ""
    @State private var upgrade: ProFeature?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button { dismiss() } label: {
                    PixelIcon.back.view(size: 20, lineWidth: 2.5).frame(width: 44, height: 44)
                }
                .buttonStyle(TileButtonStyle(fill: Theme.surface))
                .accessibilityLabel("Back")
                VStack(alignment: .leading, spacing: 2) {
                    Text("Pixel Academy").font(AppFont.pixel(22)).foregroundStyle(Theme.cream)
                    Text("Short lessons that end with a real animation")
                        .font(AppFont.body(12, relativeTo: .caption)).foregroundStyle(Theme.muted)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300, maximum: 520), spacing: 10)], spacing: 10) {
                    ForEach(Array(Academy.lessons.enumerated()), id: \.element.id) { i, lesson in
                        row(lesson, number: i + 1)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
            }
        }
        .screenBackground()
        .proUpgradeSheet($upgrade)
    }

    private func row(_ lesson: Lesson, number: Int) -> some View {
        let done = AcademyProgress.isDone(lesson)
        let inProgress = lessonID == lesson.id && !lessonProjectID.isEmpty
        let locked = !purchases.access.allows(lesson)
        return Button {
            if locked { upgrade = .academy } else { onStart(lesson) }
        } label: {
            HStack(spacing: 12) {
                LessonThumbnail(lesson: lesson)
                    .frame(width: 64, height: 64)
                    .background(Theme.ink)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Lesson \(number)", comment: "Pixel Academy lesson number").font(AppFont.pixel(10)).foregroundStyle(Theme.muted)
                    Text(lesson.title).font(AppFont.body(17, .bold, relativeTo: .headline)).foregroundStyle(Theme.cream)
                    Text("\(lesson.minutes) min · \(lesson.frames.count) frames", comment: "Lesson length in minutes, and its number of frames (plural)")
                        .font(AppFont.body(13, relativeTo: .footnote)).foregroundStyle(Theme.muted)
                    if inProgress {
                        Text("Continue · step \(min(lessonStep + 1, lesson.stepCount)) of \(lesson.stepCount)", comment: "A lesson in progress")
                            .font(AppFont.pixel(10)).foregroundStyle(Theme.accent2)
                    }
                }
                Spacer(minLength: 4)
                if done {
                    HStack(spacing: 4) {
                        PixelIcon.check.view(size: 14, lineWidth: 3)
                        Text("Done").font(AppFont.pixel(10))
                    }
                    .foregroundStyle(Theme.accent2)
                } else if locked {
                    ProBadge()
                } else if lesson.isFree {
                    Text("Free").font(AppFont.pixel(10)).foregroundStyle(Theme.muted)
                }
            }
            .padding(12)
            .background(Theme.surface)
            .overlay(Rectangle().strokeBorder(inProgress ? Theme.accent2 : Theme.line, lineWidth: 2))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}

/// The lesson's frames, looping, as a silhouette in the accent colour.
struct LessonThumbnail: View {
    let lesson: Lesson
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static func grids(_ lesson: Lesson) -> [PixelGrid] {
        let all = lesson.frames.flatMap { $0 }
        guard let first = all.first else { return [] }
        var box = PixelRect(x: first.x, y: first.y, width: 1, height: 1)
        for p in all { box = box.union(p) }
        let ink = RGBA(hex: 0xFFD23F)
        return lesson.frames.map { frame in
            var g = PixelGrid(width: box.width, height: box.height)
            for p in frame { g[p - box.origin] = ink }
            return g
        }
    }

    var body: some View {
        let grids = Self.grids(lesson)
        return Group {
            if grids.count > 1 && !reduceMotion {
                TimelineView(.periodic(from: .now, by: 1 / Double(max(1, lesson.fps)))) { ctx in
                    let i = Int(ctx.date.timeIntervalSinceReferenceDate * Double(lesson.fps)) % grids.count
                    PixelImage(grid: grids[i], checker: false).padding(6)
                }
            } else if let first = grids.first {
                PixelImage(grid: first, checker: false).padding(6)
            }
        }
        .accessibilityHidden(true)
    }
}

/// The card shown over the Studio during a lesson.
struct LessonCard: View {
    let lesson: Lesson
    let step: Int
    var celebrating = false
    var onLeave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if celebrating {
                Text("Lesson complete!").font(AppFont.pixel(16)).foregroundStyle(Theme.onAccent2)
                Text("It's in your gallery now, yours to keep changing.")
                    .font(AppFont.body(14, relativeTo: .subheadline)).foregroundStyle(Theme.onAccent2)
            } else {
                HStack(spacing: 8) {
                    Text("\(Text(lesson.title)) · \(min(step + 1, lesson.stepCount)) of \(lesson.stepCount)", comment: "Lesson progress: its name, and step x of y")
                        .font(AppFont.pixel(11)).foregroundStyle(Theme.onAccent2)
                    Spacer(minLength: 4)
                    Button(action: onLeave) {
                        Text("Leave lesson").font(AppFont.body(12, .bold, relativeTo: .caption)).foregroundStyle(Theme.onAccent2).underline()
                    }
                    .buttonStyle(.plain)
                }
                if step < lesson.frames.count {
                    Text(lesson.tip(step: step)).font(AppFont.body(15, .bold, relativeTo: .body)).foregroundStyle(Theme.onAccent2)
                        .fixedSize(horizontal: false, vertical: true)
                    (step == 0
                        ? Text("Fill in the dotted guide. Any colours you like.")
                        : Text("Fill in the dotted guide. The frame before shows in pink underneath."))
                        .font(AppFont.body(13, relativeTo: .footnote)).foregroundStyle(Theme.onAccent2.opacity(0.85))
                } else {
                    Text("Press Play and watch it move").font(AppFont.body(15, .bold, relativeTo: .body)).foregroundStyle(Theme.onAccent2)
                    Text("You drew every frame of that. The lesson ends when it plays.")
                        .font(AppFont.body(13, relativeTo: .footnote)).foregroundStyle(Theme.onAccent2.opacity(0.85))
                }
            }
        }
        .padding(12)
        .frame(maxWidth: 420, alignment: .leading)
        .background(Theme.accent2)
        .padding(.horizontal, 16)
        .accessibilityElement(children: .combine)
    }
}

/// Retro mode: pick the look, then start drawing with its fixed colours.
struct RetroModeSheet: View {
    var onStart: (RetroMode) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var mode: RetroMode = .handheld

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "Retro mode", onClose: { dismiss() })
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(RetroMode.allCases) { m in
                        let on = m == mode
                        Button { mode = m } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(m.title).font(AppFont.body(16, .bold, relativeTo: .headline)).foregroundStyle(Theme.cream)
                                        Text(m.detail).font(AppFont.body(13, relativeTo: .footnote)).foregroundStyle(Theme.muted)
                                    }
                                    Spacer()
                                    if on { PixelIcon.check.view(size: 18).foregroundStyle(Theme.accent) }
                                }
                                HStack(spacing: 0) {
                                    ForEach(Array(m.colors.enumerated()), id: \.offset) { _, c in
                                        Rectangle().fill(c.color).frame(maxWidth: .infinity).frame(height: 26)
                                    }
                                }
                                .overlay(Rectangle().strokeBorder(Theme.line, lineWidth: 1))
                            }
                            .padding(12)
                            .background(Theme.surface)
                            .overlay(Rectangle().strokeBorder(on ? Theme.accent : Theme.line, lineWidth: 2))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                    Text("The palette is locked to the mode, and the dither brush paints the in-between shades.")
                        .font(AppFont.body(13, relativeTo: .footnote))
                        .foregroundStyle(Theme.muted)
                        .padding(.top, 4)
                }
                .padding(16)
            }
            Button { onStart(mode) } label: { PrimaryActionLabel(title: "Start drawing", icon: .create) }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
        }
        .screenBackground()
        .presentationDetents([.large])
    }
}

// MARK: Idea of the day

enum DailyIdeas {
    /// One a day, the same for everyone. Short, drawable in a small sprite, and friendly to kids.
    static let all: [LocalizedStringResource] = [
        "A frog waiting for rain", "A sleepy cat on a windowsill", "A tiny rocket", "A snail with a fancy shell",
        "A cup of something hot", "A ghost who is scared of the dark", "A cactus wearing a hat", "A fish in a bowl",
        "A dragon the size of a mouse", "A snowman on holiday", "A robot watering a plant", "A slice of cake",
        "A bird with a letter", "A treasure chest", "A mushroom house", "A dancing carrot",
        "A moon with a face", "A dog chasing its tail", "A knight's shield", "A bee and a flower",
        "A lighthouse at night", "A balloon that got away", "A pirate ship", "A penguin on ice skates",
        "A magic potion", "A campfire with marshmallows", "A bat hanging upside down", "A crown for a tiny king",
        "A rainbow after rain", "A hedgehog with an apple", "A flying carpet", "A lantern in the dark",
        "A whale saying hello", "A sword in a stone", "A plant that grew too big", "An owl in a tree",
        "A star that fell down", "A turtle with a house on its back", "A kite in the wind", "A friendly monster",
    ]

    static func today(_ date: Date = Date()) -> LocalizedStringResource {
        all[DailyIdea.index(for: date, count: all.count)]
    }
}

/// The gallery's "Idea of the day" card.
struct IdeaCard: View {
    var onDraw: (String) -> Void

    var body: some View {
        let idea = DailyIdeas.today()
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Idea of the day").font(AppFont.pixel(10)).foregroundStyle(Theme.accent2)
                Text(idea).font(AppFont.body(17, .bold, relativeTo: .headline)).foregroundStyle(Theme.cream)
                    .fixedSize(horizontal: false, vertical: true)
                Text("A new one every day. Draw it, or don't: it's only an idea.")
                    .font(AppFont.body(12, relativeTo: .caption)).foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 4)
            Button { onDraw(String(localized: idea)) } label: {
                Text("Draw it").font(AppFont.pixel(12)).foregroundStyle(Theme.onAccent2).padding(.horizontal, 14).frame(height: 40)
            }
            .buttonStyle(PrimaryButtonStyle(fill: Theme.accent2, shadow: Theme.accent2Shadow, depth: 3))
        }
        .padding(12)
        .background(Theme.surface)
        .overlay(Rectangle().strokeBorder(Theme.line, lineWidth: 2))
    }
}
