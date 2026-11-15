# Pixel Deck (iOS)

A native SwiftUI pixel-art and sprite-animation app for iPhone (and iPad).

## Features

The look follows the design handoff and **follows the system appearance**. Dark uses the "Night" palette; Light uses the design's "Paper" palette, with the brand pink a shade deeper and Paper's blue instead of yellow so links stay readable. The night-sky illustrations (welcome scene, Easel stage) stay night in both. Both palettes have a flip-pink accent, square corners, Silkscreen and Space Grotesk fonts, and buttons with a solid drop shadow that press in.

- **Infinite canvas**: there is no size to pick. Draw anywhere and the canvas grows. Pinch to change how big pixels look; zooming snaps to whole points so pixels stay crisp. Drag with two fingers to move around, and tap with two fingers to fit the art. The checkerboard and pixel grid go on forever. Saved sprites and exports are trimmed to the art.
- **Swipes**:
  - **Swipe left** from the right edge of the canvas to add a keyframe. The previous frame shows underneath as a flat pink onion skin at 38%.
  - **Swipe right** from the left edge to start a new canvas.
  - Small pulsing pixel chevrons mark both edges. "Swipe anywhere", in the sprite menu, lets you drag the whole canvas instead. Both actions also have buttons.
- **Dock**:
  - Row 1: play/pause (the animation plays in place on the canvas), the frame thumbnails and a button to add a frame.
  - Row 2: a 10-colour palette that each sprite keeps its own copy of. Long-press a swatch to change it.
  - Row 3: the tools, which are pencil, eraser, fill, **shapes**, colour picker, **mirror** and select. Mirror draws on both sides of the centre line and works with the pencil, eraser and fill.
  - Row 4: gallery, undo, redo, onion skin, frame rate and export.
- **Shapes**: line, rectangle/square, circle/ellipse, triangle, diamond, pentagon, hexagon, octagon, parallelogram and star, in a strip that scrolls on narrow screens. Drag to draw, with a live preview. Outline or filled, and **1:1** locks proportions (squares, circles, regular polygons, 45° lines). Symmetric shapes stay pixel-for-pixel symmetric at any size. Shapes work with mirror and grow the canvas like the pencil. The first shape on a one-layer sprite goes on a new **Shapes** layer above your art, so it never draws over your pixels.
- **Layers**: up to 8 per sprite, shared by every frame. The layers button at the top right of the canvas shows the layer you're drawing on. The panel lets you add, select, show/hide, rename, reorder, merge down and delete layers. Hidden layers are left out of the canvas, thumbnails, onion skin and exports. Tweening moves the active layer and keeps the other layers (e.g. a background) in every new frame. Undo covers all of these.
- **Sprite menu**: tap the name chip at the top left to rename, fit the art, turn the pixel grid on or off, use swipe-anywhere, set the onion skin strength, or duplicate, clear or delete the frame.
- **Motion tweening**: select pixels and drag them along any path. The app removes the jitter from your drag (Ramer–Douglas–Peucker), smooths it into a curve (Catmull–Rom) and draws it as a dotted line. Tap **Tween** to fill in the frames between, with a choice of path, timing and frame count and a live preview.
- **Gallery**: a grid of every sprite, each looping its animation live, with a Moving / Stills filter. It starts with six example sprites (slime, campfire, coin, ghost, sprout and moon). You can also swipe right anywhere in the gallery for a new canvas.
- **Welcome screens**: an animated pixel night scene, then a two-step tutorial on the swipes. Both can be opened again from Settings.
- **Export**: a looping preview, scale choices of 1×, 4×, 8× and 16× with the output size shown, and four formats:
  - Animated GIF
  - Sprite sheet, as a row or a grid, with an optional JSON file of frame positions for game engines
  - PNG frames
  - **MP4 video** at 1080 × 1080 for Reels, Shorts and TikTok
  
  **Save** adds the files to Photos, asking only for permission to add. **Share** opens the share sheet.
- **Pixel Deck Pro** (a one-time in-app purchase, StoreKit 2):
  - Free: art up to 64 × 64 px, 12 frames per sprite, every tool including mirror and tweening, and PNG or sprite sheet export up to 4×.
  - Pro: art up to 512 × 512, up to 999 frames (fewer for very large sprites, to protect memory), GIF and video export, exports up to 16×, and **eased playback timing**: Ease in, Ease out or Ease in & out, chosen from the frame-rate menu or the sprite menu. Frames are held for different lengths of time, so motion speeds up or slows down while the loop stays the same length. The timing applies to playback, every preview, GIF frame delays, MP4 frame timing and the sprite sheet JSON's per-frame `durationMs`.
  - All the limits are in `Core/FeatureAccess.swift`.
- **iPad and Apple Pencil**:
  - **Pencil-only drawing** (palm rejection): the first Pencil touch switches it on. The Pencil draws while one finger pans and two fingers pinch, and a resting palm can't draw or interrupt a stroke. You can switch it in the sprite menu or Settings.
  - Strokes use every Pencil sample (up to 240 a second), so fast curves keep their shape.
  - **Double-tap and squeeze** follow your Settings › Apple Pencil choice: switch to the eraser, switch to the previous tool, or open the colour picker.
  - **Hover preview**: a hovering Pencil (M2 iPads and later) or pointer outlines the pixel it will paint.
  - **Trackpad and mouse**: click to draw, two-finger scroll to pan, pinch to zoom, and right-click for the frame and layer menus.
  - **Keyboard shortcuts** (hold ⌘ to see the ⌘ ones):

    | Key | Action |
    |---|---|
    | B | Pencil |
    | E | Eraser |
    | X | Toggle eraser |
    | G | Fill |
    | I | Colour picker |
    | U | Shapes |
    | M | Select |
    | Y | Mirror |
    | O | Onion skin |
    | 1–0 | Palette colours |
    | ← / → | Previous / next frame |
    | N | New frame |
    | Space | Play / pause |
    | Esc | Deselect |
    | ⌘Z / ⇧⌘Z | Undo / redo |
    | ⌘= / ⌘− / ⌘0 | Zoom in / zoom out / fit |
    | ⌘D | Duplicate frame |
    | ⌘N | New canvas |
    | ⌘L | Layers |
    | ⌘E | Export |
    | ⌘' | Pixel grid |
  - **Layout**: the gallery adds columns as the window widens, and the welcome and export screens stay at a readable width.
  - **Drag and drop**: drag the export preview into another app in Split View or Stage Manager to drop the file.
- **iPhone Duo** (design handoff section 8). The layout follows the space available and switches with a 200 ms cross-fade. The project, frame, tool, colour, onion skin and undo history carry over, and a stroke in progress during a fold is finished, never lost.
  - **Closed (Pocket):** the regular Studio, with everything in the bottom dock for one thumb.
  - **Open flat (Flipbook spread):** a big landscape space, which also covers iPad in landscape.
    - Two pages either side of the hinge gutter.
    - The left page shows **Last frame**, **Playback** or **Reference**. Reference pins a photo, picked with the system photo picker, and the colour picker can sample from it.
    - The right page is the canvas. Turn the page to add a frame: tap the pulsing corner or swipe left. The frame you drew folds over onto the left page.
    - A tool rail sits by the left thumb and a palette rail by the right. The bottom bar holds play, frames, onion skin and fps.
  - **Half open on a desk (Easel):** a live Stage on the upright half shows the animation on the night backdrop with its fps and frame count. The flat Desk has the tools, undo/redo, canvas, palette and fps − / +. iOS doesn't yet document a fold-posture API, so Easel is turned on in the sprite menu. `StudioLayout.choose` is the single place to hook such an API in.
- **Adaptive layout**: when there's room, such as an unfolded iPhone Duo, an iPad or landscape, the dock becomes a side panel. Your zoom and position survive folding, rotating and resizing.
- **Localisation-ready**: the text uses a String Catalog with English plurals, and the layout mirrors for right-to-left languages.
- **Accessibility**: Reduce Motion pauses the decorative animations (stars, swipe hints and gallery previews). Controls have VoiceOver labels, and body text scales with Dynamic Type.

## Selling it on the App Store

See [`AppStore/SUBMISSION_CHECKLIST.md`](AppStore/SUBMISSION_CHECKLIST.md) for what's done and what you need to do, the business model, and review notes. [`AppStore/metadata.md`](AppStore/metadata.md) has the listing text, and [`AppStore/privacy-policy.html`](AppStore/privacy-policy.html) is the policy to host.

## Building

Requirements: **Xcode 26 or newer** (27.1+ for full iPhone Duo support) (App Store uploads have required the iOS 26 SDK since April 2026; Xcode 16 still builds it for testing) and **iOS 17+** on devices.

1. Open `iOS/PixelDeck.xcodeproj`.
2. Select the **PixelDeck** target. Under *Signing & Capabilities*, pick your team. A free Apple ID works for running on your own phone. Change the bundle identifier (`com.example.pixeldeck`) to something unique.
3. Choose an iPhone simulator or your device, then press **Run**.
4. To test the in-app purchase locally, go to Product → Scheme → Edit Scheme → Run → Options and set **StoreKit Configuration** to `PixelDeck.storekit`.

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
  Editor/                 Studio: infinite UIKit canvas, swipe container, dock, tween
  Library/                Gallery
  Export/                 PNG/GIF/MP4/JSON export, Photos saving and the share sheet
  Store/                  In-app purchase (StoreKit 2) and paywall
  Resources/              Bundled fonts (with their OFL licence) and the starter sprites (sprites.json)
  Support/                Theme (colours, fonts, buttons, icons), rendering, welcome, settings, privacy, AppConfig
Tests/                    Unit tests for Core
```
