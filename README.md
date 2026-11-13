# Pixel Deck (iOS)

A native SwiftUI pixel-art and sprite-animation app for iPhone (and iPad).

## Features

- **Canvas sizes**: 8×8, 16×16, 32×32, 64×64, 128×128 and 256×256, scaled up crisply with no smoothing.
- **Zoom**: pinch with two fingers (drag with two fingers to pan), or use the zoom out / fit / zoom in buttons.
- **Pixel grid**: shown whenever pixels are big enough on screen. You can turn it off in the ••• menu.
- **Colours**: black by default. Use the system colour picker, a 16-colour starter palette, recent colours, or the eyedropper.
- **Tools**: pencil, eraser, flood fill, eyedropper, select & move, and undo/redo.
- **Swipe the card**:
  - **Swipe left** to add a keyframe after the current one. The new frame is blank and shows the previous frame underneath as an onion skin you can trace. The opacity can be set to 15–70% in the ••• menu.
  - **Swipe right** to start a whole new canvas. The current sprite is saved first.
  - You can always drag the card by its top strip. Tap the stack icon in the tool row to make the whole card swipeable.
- **Motion tweening**: select a group of pixels and drag it to a new spot. The app records the route your finger took, removes the jitter (Ramer–Douglas–Peucker), smooths it into a curve (Catmull–Rom), and shows it as a pink dotted line. Then tap **Tween** to choose:
  - *Follow my drag* or *Straight line*
  - Linear, ease in, ease out, or ease in & out
  - *Insert new frames*: you pick how many, with a suggestion based on distance. Or *Use existing next frames*: the selection moves through the frames you've already drawn and everything else in them is kept.
  - A live looping preview before you commit.
- **Frames**: a film strip to jump between frames. Long-press a frame to duplicate, reorder or delete it. You can also play the animation at 1–30 fps.
- **Export**: a sprite sheet PNG (in a row or a grid) with an optional JSON file of frame positions for game engines, an animated GIF, or one PNG per frame, at 1×–32× scale. Files go to the share sheet, so you can save them to Files or Photos, AirDrop them, and so on.
- **Saving**: everything saves automatically to the app's Documents folder.

## Building

Requirements: **Xcode 16 or newer** and **iOS 17+**.

1. Open `iOS/PixelDeck.xcodeproj`.
2. Select the **PixelDeck** target. Under *Signing & Capabilities*, pick your team. A free Apple ID works for running on your own phone. Change the bundle identifier (`com.example.pixeldeck`) to something unique.
3. Choose an iPhone simulator or your device, then press **Run**.

The project uses folder-synced groups, so any file you add under `iOS/PixelDeck/` is picked up automatically.

## Tests

The editing logic (drawing, flood fill, selection, path smoothing, tweening, undo, sprite-sheet layout and saving) is in `PixelDeck/Core`. It has no UIKit or SwiftUI dependencies, so it is also a Swift package:

```sh
cd iOS
swift test
```

## Layout

```
PixelDeck/
  PixelDeckApp.swift      App entry point
  Core/                   Platform-independent model and logic (unit-tested)
  Editor/                 Editor screen, UIKit canvas, swipe deck, colours, film strip, tween, playback
  Library/                Sprite gallery and new-canvas picker
  Export/                 PNG/GIF/JSON export and share sheet
  Support/                CGImage rendering and thumbnail cache
Tests/                    Unit tests for Core
```
