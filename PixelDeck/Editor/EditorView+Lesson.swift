import SwiftUI

// Pixel Academy lessons in the Studio: the guide for the frame being drawn, the card that says
// what to do, and moving on when a step is finished. (The lessons are in Core/Academy.swift.)

extension EditorView {
    /// The lesson running on this sprite, if any.
    var activeLesson: Lesson? {
        guard !lessonProjectID.isEmpty, lessonProjectID == model.project.id.uuidString else { return nil }
        return Academy.lesson(id: lessonID)
    }

    /// Read in `body`, so SwiftUI re-checks it whenever the drawing changes.
    var lessonStepDone: Bool {
        guard let lesson = activeLesson else { return false }
        return Academy.isDone(lesson, step: lessonStep, model: model, playCountAtStart: lessonPlayBaseline)
    }

    /// Adds the lesson's dotted guide to the frame it belongs on.
    func withLessonGuide(_ state: CanvasState) -> CanvasState {
        guard let lesson = activeLesson, !model.isPlaying, model.currentIndex == lessonStep,
              let guide = Academy.guide(lesson, step: lessonStep) else { return state }
        var s = state
        s.guide = guide
        return s
    }

    /// Called when the lesson's sprite opens: go to the frame being drawn.
    func prepareLesson() {
        guard let lesson = activeLesson else { return }
        model.onionSkinEnabled = true
        if model.tool != .pencil { model.tool = .pencil }
        lessonPlayBaseline = model.playCount
        let frame = min(lessonStep, lesson.frames.count - 1)
        if model.frameCount > frame, model.currentIndex != frame { model.selectFrame(frame) }
        if model.project.fps != lesson.fps { model.setFPS(lesson.fps) }
    }

    func advanceLesson() {
        guard let lesson = activeLesson else { return }
        guard lessonStep + 1 < lesson.stepCount else {
            finishLesson()
            return
        }
        lessonStep += 1
        if lessonStep < lesson.frames.count {
            // The next frame: a new blank one, with the frame just drawn showing through in pink.
            if model.frameCount <= lessonStep { model.addKeyframe() } else { model.selectFrame(lessonStep) }
        } else {
            lessonPlayBaseline = model.playCount
        }
    }

    func finishLesson() {
        AcademyProgress.markDone(lessonID)
        lessonProjectID = ""
        lessonID = ""
        lessonStep = 0
        lessonCelebrating = true
        Task {
            try? await Task.sleep(for: .seconds(4))
            lessonCelebrating = false
        }
    }
}

/// The lesson card, and moving on when a step is done. Kept out of `EditorView.body`.
struct LessonOverlay: ViewModifier {
    let lesson: Lesson?
    let step: Int
    let stepDone: Bool
    let celebrating: Bool
    var onAdvance: () -> Void
    var onLeave: () -> Void
    var onAppear: () -> Void

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if let lesson {
                    LessonCard(lesson: lesson, step: step, onLeave: onLeave)
                        .padding(.top, 64)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .id(step)
                } else if celebrating, let any = Academy.lessons.first {
                    LessonCard(lesson: any, step: 0, celebrating: true, onLeave: {})
                        .padding(.top, 64)
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.25), value: step)
            .onChange(of: stepDone) { _, done in if done { onAdvance() } }
            .sensoryFeedback(.success, trigger: step)
            .onAppear(perform: onAppear)
    }
}

/// Motion guides (Pro): choose a movement and a figure size; a pose appears on every frame.
struct MotionGuideMenu: View {
    let model: EditorModel

    var body: some View {
        Menu {
            Picker(selection: Binding(get: { model.motionGuide }, set: { model.motionGuide = $0 })) {
                Text("Off").tag(MotionGuide?.none)
                ForEach(MotionGuide.allCases) { g in
                    if model.access.allowsMotionGuides {
                        Text(g.title).tag(MotionGuide?.some(g))
                    } else {
                        Text("\(Text(g.title)) · Pro", comment: "A locked option; the placeholder is the option name").tag(MotionGuide?.some(g))
                    }
                }
            } label: {
                Text("Movement")
            }
            Picker(selection: Binding(get: { model.motionGuideHeight }, set: { model.motionGuideHeight = $0 })) {
                ForEach(MotionGuides.heights, id: \.self) { h in
                    Text("\(h) pixels tall", comment: "Motion guide figure height").tag(h)
                }
            } label: {
                Text("Figure size")
            }
            .pickerStyle(.menu)
        } label: {
            Label("Motion guides", systemImage: "figure.walk")
        }
    }
}

/// Connects this Studio to AI assistants on the Mac (Support/AIBridge.swift): tools draw in the
/// Studio that's on screen, and a banner shows while they do.
struct AIStudioLink: ViewModifier {
    let model: EditorModel
    /// False in the desk layout, which shows the banner over its canvas instead.
    var showsBanner = true
    var onNewCanvas: () -> Void

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if showsBanner && ProcessInfo.processInfo.isMacCatalystApp { AIBanner() }
            }
            .onAppear {
                AIBridge.shared.model = model
                AIBridge.shared.startNewCanvas = onNewCanvas
            }
            .onDisappear {
                if AIBridge.shared.model === model {
                    AIBridge.shared.model = nil
                    AIBridge.shared.startNewCanvas = nil
                }
            }
    }
}
