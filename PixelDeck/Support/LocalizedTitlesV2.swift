import Foundation

// Display names for the v2 core enums (see LocalizedTitles.swift for why they live here).

extension SelectionMode {
    var title: LocalizedStringResource {
        switch self {
        case .box: LocalizedStringResource("Box", comment: "Selection mode: drag a rectangle")
        case .lasso: LocalizedStringResource("Lasso", comment: "Selection mode: draw around pixels")
        case .wand: LocalizedStringResource("Magic wand", comment: "Selection mode: tap a colour")
        }
    }

    /// The tooltip.
    var tip: LocalizedStringKey {
        switch self {
        case .box: "Box: drag a rectangle over the pixels you want"
        case .lasso: "Lasso: draw around the pixels you want, any shape"
        case .wand: "Magic wand: click a colour to select the pixels touching it"
        }
    }

    var hint: LocalizedStringResource {
        switch self {
        case .box: "Drag over pixels to select them"
        case .lasso: "Draw around the pixels you want"
        case .wand: "Tap a colour to select the pixels touching it"
        }
    }
}

extension LightDirection {
    /// As in "Light from the top left".
    var title: LocalizedStringResource {
        switch self {
        case .topLeft: "Light from the top left"
        case .top: "Light from the top"
        case .topRight: "Light from the top right"
        case .left: "Light from the left"
        case .right: "Light from the right"
        case .bottomLeft: "Light from the bottom left"
        case .bottom: "Light from below"
        case .bottomRight: "Light from the bottom right"
        }
    }
}

extension ShadeMode {
    var title: LocalizedStringResource {
        switch self {
        case .shade: LocalizedStringResource("Shade", comment: "Shading assistant: darken away from the light")
        case .highlight: LocalizedStringResource("Highlight", comment: "Shading assistant: lighten towards the light")
        }
    }
}

extension AnimationPreset {
    var title: LocalizedStringResource {
        switch self {
        case .bounce: LocalizedStringResource("Bounce", comment: "Animation preset")
        case .blink: LocalizedStringResource("Blink", comment: "Animation preset: eyes close and open")
        case .float: LocalizedStringResource("Float", comment: "Animation preset: gentle rise and fall")
        case .shake: LocalizedStringResource("Shake", comment: "Animation preset")
        case .colorCycle: LocalizedStringResource("Colour cycle", comment: "Animation preset: colours turn through the rainbow")
        case .squash: LocalizedStringResource("Squash", comment: "Animation preset: squash and stretch")
        }
    }

    /// Label for the "how far" slider.
    var amountTitle: LocalizedStringResource {
        switch self {
        case .bounce, .float: "How high"
        case .shake: "How far"
        case .squash: "How much"
        case .blink, .colorCycle: "Amount"
        }
    }
}

extension LoopMode {
    var title: LocalizedStringResource {
        switch self {
        case .loop: LocalizedStringResource("Loop", comment: "Playback: start again at the end")
        case .pingPong: LocalizedStringResource("Ping-pong", comment: "Playback: forwards then backwards")
        case .once: LocalizedStringResource("Once", comment: "Playback: stop at the end")
        }
    }
}

extension AdjustScope {
    var title: LocalizedStringResource {
        switch self {
        case .selection: LocalizedStringResource("Selection", comment: "Adjust colours of: the selected pixels")
        case .layer: LocalizedStringResource("Layer", comment: "Adjust colours of: this layer in this frame")
        case .frame: LocalizedStringResource("Frame", comment: "Adjust colours of: every layer of this frame")
        case .allFrames: LocalizedStringResource("All frames", comment: "Adjust colours of: the whole animation")
        }
    }
}

extension RetroMode {
    var title: LocalizedStringResource {
        switch self {
        case .oneBit: LocalizedStringResource("1-bit", comment: "Retro mode: two colours")
        case .handheld: LocalizedStringResource("Handheld", comment: "Retro mode: four greens, like an old handheld console")
        case .ink: LocalizedStringResource("Ink", comment: "Retro mode: black ink on paper")
        case .eightColor: LocalizedStringResource("8-colour", comment: "Retro mode: eight bright colours")
        }
    }

    var detail: LocalizedStringResource {
        switch self {
        case .oneBit: "Two colours, ordered dither"
        case .handheld: "Four greens, like a pocket console"
        case .ink: "Black ink, two greys and paper"
        case .eightColor: "Eight bright colours, like an early home computer"
        }
    }
}

extension PhotoOptions.Colors {
    var title: LocalizedStringResource {
        switch self {
        case .own: LocalizedStringResource("Photo's own", comment: "Photo to pixel art: use colours from the photo")
        case .palette: LocalizedStringResource("My palette", comment: "Photo to pixel art: use the sprite's palette")
        case .retro: LocalizedStringResource("Retro", comment: "Photo to pixel art: use a retro palette")
        }
    }
}

extension VideoShape {
    var title: LocalizedStringResource {
        switch self {
        case .square: LocalizedStringResource("Square", comment: "Video shape: 1:1")
        case .vertical: LocalizedStringResource("9:16 Reels", comment: "Video shape: tall, for Reels, Shorts and TikTok")
        case .timelapse: LocalizedStringResource("Timelapse", comment: "Video of how the art was drawn")
        }
    }
}

extension Lesson {
    var title: LocalizedStringResource {
        switch id {
        case "blink": "Blinking eye"
        case "walk": "Walk cycle"
        case "squash": "Squash and stretch"
        case "campfire": "A looping campfire"
        case "coin": "Spinning coin"
        case "explosion": "An explosion"
        default: "Lesson"
        }
    }

    /// What to notice while drawing frame `step` (counted from 0).
    func tip(step: Int) -> LocalizedStringResource {
        let tips: [LocalizedStringResource]
        switch id {
        case "blink":
            tips = ["The open eye: an almond outline with a round pupil.",
                    "Half shut: the lids come towards the middle.",
                    "Shut: one line, with lashes underneath.",
                    "Half shut again, so it opens smoothly."]
        case "walk":
            tips = ["Passing: the legs are together and the body is at its tallest.",
                    "The front leg reaches forward as the body starts to drop.",
                    "Contact: legs wide apart, the body at its lowest.",
                    "The legs swing back towards each other.",
                    "Passing again, with the other leg in front.",
                    "The other leg reaches forward.",
                    "Contact on the other side: arms always swing opposite to legs.",
                    "Back towards the start, so the loop joins up."]
        case "squash":
            tips = ["A round ball at the top of its bounce.",
                    "Falling: a little taller and thinner.",
                    "Faster: stretched the most just before it lands.",
                    "Squash! Wide and flat on the ground.",
                    "Springing up: stretched tall again.",
                    "Slowing near the top: almost round."]
        case "campfire":
            tips = ["Logs crossed at the bottom, the flame leaning left.",
                    "The flame stands up straight.",
                    "Now it leans right.",
                    "Straight again, a little different, so it flickers."]
        case "coin":
            tips = ["The coin facing you: a full oval.",
                    "Turning: narrower.",
                    "Edge on: just a thin bar.",
                    "Opening up again on its way round."]
        case "explosion":
            tips = ["A tiny flash.", "It swells.", "At its biggest and brightest.",
                    "The middle clears: now it's a ring.", "The ring thins and sparks fly.", "Only sparks are left."]
        default:
            tips = []
        }
        return tips.indices.contains(step) ? tips[step] : "Draw the next frame."
    }
}

extension MotionGuide {
    var title: LocalizedStringResource {
        switch self {
        case .walk: LocalizedStringResource("Walk", comment: "Motion guide")
        case .run: LocalizedStringResource("Run", comment: "Motion guide")
        case .jump: LocalizedStringResource("Jump", comment: "Motion guide")
        case .idle: LocalizedStringResource("Idle bob", comment: "Motion guide: standing and breathing")
        }
    }
}
