# Pixel Deck

App to doodle pixel art, make it move and have fun: a native SwiftUI pixel-art and sprite-animation app for iPhone and iPad.

## Features

The look follows the design handoff and **follows the system appearance**. Dark uses the "Night" palette; Light uses the design's "Paper" palette, with the brand pink a shade deeper and Paper's blue instead of yellow so links stay readable. The night-sky illustrations (welcome scene, Easel stage) stay night in both. Both palettes have a flip-pink accent, square corners, Silkscreen and Space Grotesk fonts, and buttons with a solid drop shadow that press in.

- **Infinite canvas**: there is no size to pick. Draw anywhere and the canvas grows. Pinch to change how big pixels look; zooming snaps to whole points so pixels stay crisp. Drag with two fingers to move around, and tap with two fingers to fit the art. The checkerboard and pixel grid go on forever. Saved sprites and exports are trimmed to the art.
- **Swipes**:
  - **Swipe left** from the right edge of the canvas to add a keyframe. The previous frame shows underneath as a pink onion skin at 38%, shaded by brightness and edged where colours meet, so eyes, mouths and other inner details stay visible.
  - **Swipe right** from the left edge to start a new canvas.
  - Small pulsing pixel chevrons mark both edges. "Swipe anywhere", in the sprite menu, lets you drag the whole canvas instead. Both actions also have buttons.
- **Dock**:
  - Row 1: play/pause (the animation plays in place on the canvas), the frame thumbnails and a button to add a frame.
  - Row 2: a 10-colour palette that each sprite keeps its own copy of. Long-press a swatch to change it. The grid button at the end opens **Colours**.
  - Row 3: the tools, which are pencil, eraser, fill, **shapes**, colour picker, **mirror** and select. Mirror draws on both sides of the centre line and works with the pencil, eraser and fill.
  - Row 4: gallery, undo, redo, onion skin, frame rate and export.
- **Shapes**: line, rectangle/square, circle/ellipse, triangle, diamond, pentagon, hexagon, octagon, parallelogram and star, in a strip that scrolls on narrow screens. Drag to draw, with a live preview. Outline or filled, and **1:1** locks proportions (squares, circles, regular polygons, 45° lines). Symmetric shapes stay pixel-for-pixel symmetric at any size. Shapes work with mirror and grow the canvas like the pencil. The first shape on a one-layer sprite goes on a new **Shapes** layer above your art, so it never draws over your pixels.
- **Layers**: up to 8 per sprite, shared by every frame. The layers button at the top right of the canvas shows the layer you're drawing on. The panel lets you add, select, show/hide, rename, reorder, merge down and delete layers. Hidden layers are left out of the canvas, thumbnails, onion skin and exports. Tweening moves the active layer and keeps the other layers (e.g. a background) in every new frame. Undo covers all of these.
- **Colours**: the panel from the grid button by the palette, or from the sprite menu. **My palettes** saves the sprite's colours as a named palette (build them with the colour picker), to use in any sprite. Long-press a saved palette to rename it, update it or delete it. Saved palettes sync with iCloud like the sprites. Its **Change this colour** button opens Apple's colour picker (grid, spectrum, sliders, hex and an on-screen eyedropper) for the selected swatch. It also offers 10 ready-made palettes: Pixel Deck, Sunset, Forest, Ocean, Candy, Neon, Fire, Skin & hair, Pocket greens and Greys. A palette replaces the sprite's swatches, but art already drawn keeps its colours, and the selected slot stays selected.
- **Tracing image**: pick a photo or sketch to trace over. It sits at the very bottom of the layer stack, under every layer and the onion skin. You can set its opacity (5–100%), size and position (nudge it, or fit it to the art), and hide, replace or remove it. It's a guide only, so it never appears in frames, thumbnails, playback or exports. Open it by long-pressing the onion skin button, from the sprite menu, or from the bottom row of the Layers panel. Each sprite keeps its own picture (PNG, so transparent sketches stay transparent), which syncs with the sprite. Duplicating a sprite copies the picture, and deleting a sprite deletes it.
- **Copy and paste frames**: copy a frame from the sprite menu or by long-pressing its thumbnail, then paste it over another frame or as a new frame after it. The copy keeps its layers and lands where it was copied from. It works between sprites too: if the other sprite has a different number of layers, the art goes, flattened, onto the layer you're drawing on. Undo covers pasting.
- **Sprite menu**: tap the name chip at the top left to rename, fit the art, turn the pixel grid on or off, use swipe-anywhere, set the onion skin strength, or duplicate, copy, paste, clear or delete the frame.
- **Motion tweening**: select pixels and drag them along any path. The app removes the jitter from your drag (Ramer–Douglas–Peucker), smooths it into a curve (Catmull–Rom) and draws it as a dotted line. Tap **Tween** to fill in the frames between, with a choice of path, timing and frame count and a live preview.
- **Gallery**: a grid of every sprite, each looping its animation live, with a Moving / Stills filter. It always opens on Moving. **Select** lets you pick several sprites (or Select all) and delete them, after a confirmation. New canvas reuses an empty sprite instead of making another. The **Stills** tab starts with eight pictures: strawberry, potion, mushroom, cactus, ice cream, ringed planet, cottage and a sunset sail. All are within the free size, and they're drawn by `Tools/stills_art.py` into `Resources/Starter/stills.json`. It starts with six example sprites (slime, campfire, coin, ghost, sprout and moon) and two large animated **showcase scenes**: *Spring high street*, a 160×120 Japanese shopping street with falling cherry petals, swaying lanterns, a blinking neon sign, rippling banners and a cat; and *Valley mixtape*, a 192×108 valley of snowy mountains, a sparkling river and spring flowers, with a boy on a boulder nodding along to his cassette player. Both loop seamlessly over 16 frames. They're bigger than the free 64×64 limit, so for free users they carry a **PRO** badge: anyone can watch them, but editing needs Pro. Existing installs get them once, too. They're drawn by `Tools/showcase_art.py`, which writes `Resources/Starter/showcase.json` (`--preview DIR` also writes PNGs and GIFs). You can also swipe right anywhere in the gallery for a new canvas.
- **Welcome screens**: an animated pixel night scene, then a two-step tutorial on the swipes. Both can be opened again from Settings.
- **Guided tour**: after the welcome screens, new users make a **bouncing heart** in three frames. A card at the top says what to do, a pulsing yellow ring points at the control, and blinking dots on the canvas show which squares to fill. Each step finishes by itself once you've done it.
  - The 12 steps, in order:
    1. Pick pink.
    2. Draw the heart.
    3. Undo, then Redo.
    4. Zoom and move (Next).
    5. Swipe left for frame 2.
    6. Draw the heart higher, using the onion skin.
    7. Long-press the onion button.
    8. Long-press frame 1 › Duplicate.
    9. Long-press the copy › Move later, so it goes down, up, down.
    10. Play.
    11. A tour of the other tools (Next).
    12. Swipe right to start your own canvas.
  - Swiping right earlier is blocked with a reminder that it comes last.
  - Progress is saved, so leaving and coming back resumes the tour. It can be skipped at any time, replayed from Settings › Help › Take the guided tour, and existing users are offered it once with a banner in the gallery.
  - The steps and their checks are in `Core/GuidedTour.swift`, which is unit-tested by playing the whole tour; the card and highlights are in `Editor/GuidedTourUI.swift`.
- **Export**: a looping preview, scale choices of 1×, 4×, 8×, 16× and **4K** (Pro: long side up to 3840 px) with the output size shown, and four formats:
  - Animated GIF
  - Sprite sheet, as a row or a grid, with an optional JSON file of frame positions for game engines
  - PNG frames
  - **MP4 video** at 1080 × 1080, or 4K (2160 × 2160), for Reels, Shorts and TikTok

  Free PNG exports get a small **"Made with Pixel Deck · Available on the App Store"** footer below the art (never over it), and Pro exports don't. Sprite sheets are left clean for game engines, and GIF and video are Pro-only.
  
  **Save** adds the files to Photos, asking only for permission to add. **Share** opens the share sheet.
- **Pixel Deck Pro** (a one-time in-app purchase, StoreKit 2):
  - Free: art up to 64 × 64 px, 12 frames per sprite, every tool including mirror and tweening, and PNG or sprite sheet export up to 4×.
  - Pro: art up to 512 × 512, up to 999 frames (fewer for very large sprites, to protect memory), GIF and video export, exports up to 16× and 4K, no watermark, and **eased playback timing**: Ease in, Ease out or Ease in & out, chosen from the frame-rate menu or the sprite menu. Frames are held for different lengths of time, so motion speeds up or slows down while the loop stays the same length. The timing applies to playback, every preview, GIF frame delays, MP4 frame timing and the sprite sheet JSON's per-frame `durationMs`.
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
    | ⇧⌘C | Copy frame |
    | ⇧⌘V / ⌥⌘V | Paste over frame / paste as new frame |
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
- **iCloud sync**: sprites, with their tracing and reference pictures, are kept in the app's private iCloud container. They open on every iPhone and iPad signed in to the same Apple Account, and they're hidden from the Files app.
  - **Offline**: everything works offline, and iCloud uploads changes later.
  - **Conflicts**: when two devices change the same sprite, the most recent edit wins. A conflict iCloud reports is settled the same way, and a stale copy never overwrites a newer one.
  - **Moving work**: on the first sync, work already on the device moves into iCloud.
  - **Starters**: starter and showcase sprites have the same ids on every device, so a new device doesn't make duplicates.
  - **Settings**: **Settings › iCloud** turns sync off and on, and shows its status.
  - **Signed out**: when signed out, or with iCloud Drive off, the app keeps working on the device and copies your work there.
  - **Code**: `Support/CloudSync.swift` (an NSMetadataQuery watches the container, and writes go through NSFileCoordinator). `ProjectStore.relocate` and `mergeFromDisk` are unit-tested.
  - **Setup**: in Xcode, select the target → *Signing & Capabilities* → **+ Capability** → **iCloud**. Tick **iCloud Documents**, then add and tick the container `iCloud.<your bundle ID>`. This needs a paid developer account. Without it, sync shows as unavailable and everything stays on the device.
- **Community**: a public gallery of everyone's sprites, built on CloudKit's **public database**. Apple hosts it, so there's no server to run.
  - **Browsing**: tap the globe button in the gallery. Anyone can browse, without signing in, and posts play as live tiles, newest first.
  - **Sharing**: long-press a sprite in the gallery, or use the sprite menu, and choose *Share to Community…*. Posting needs an iCloud account.
  - **Remix** copies a post into your gallery.
  - **Mine** lists your own posts, so you can delete them.
  - **Moderation** works without approving posts first, which covers what App Store guideline 1.2 requires:
    - titles and nicknames are filtered (profanity and slurs, including letter swaps, plus links, emails and phone numbers);
    - anyone can report a post, and 3 reports from different people hide it for everyone;
    - anyone can block a poster;
    - people agree to the community rules before their first post;
    - a moderator mode lets your own account remove any post.
  - **Code**: `Core/Community.swift` holds the payload, filter and visibility rules, and it's unit-tested. `Community/` holds the CloudKit service and screens.
  - **Setup**: set `AppConfig.cloudKitContainerID`, then add the CloudKit indexes and roles from the submission checklist. Until the container ID is set, Community stays off.
- **Localisation-ready**: the text uses a String Catalog with English plurals, and the layout mirrors for right-to-left languages.
- **Accessibility**: Reduce Motion pauses the decorative animations (stars, swipe hints and gallery previews). Controls have VoiceOver labels, and body text scales with Dynamic Type.

## Selling it on the App Store

See [`AppStore/SUBMISSION_CHECKLIST.md`](AppStore/SUBMISSION_CHECKLIST.md) for what's done and what you need to do, the business model, and review notes. [`AppStore/metadata.md`](AppStore/metadata.md) has the listing text. [`Website/`](Website) holds the public website: home, privacy policy and support pages. `.github/workflows/pixeldeck-pages.yml` publishes it to GitHub Pages at https://karthikvasudevan10-wq.github.io/pixeldeck/.

## Building

Requirements: **Xcode 26 or newer** (27.1+ for full iPhone Duo support) (App Store uploads have required the iOS 26 SDK since April 2026; Xcode 16 still builds it for testing) and **iOS 17+** on devices.

1. Open `PixelDeck.xcodeproj`.
2. Select the **PixelDeck** target. Under *Signing & Capabilities*, pick your team. The bundle identifier is `karthikvasudevan.pixeldeck`. A free Apple ID can run it on your own phone, but iCloud sync, Community and App Store uploads need the paid Apple Developer Program.
3. Choose an iPhone simulator or your device, then press **Run**.
4. To test the in-app purchase locally, go to Product → Scheme → Edit Scheme → Run → Options and set **StoreKit Configuration** to `PixelDeck.storekit`.

The project uses folder-synced groups, so any file you add under `PixelDeck/` is picked up automatically.

## Tests

The editing logic (drawing, flood fill, selection, path smoothing, tweening, undo, sprite-sheet layout and saving) is in `PixelDeck/Core`. It has no UIKit or SwiftUI dependencies, so it is also a Swift package:

```sh
swift test
```

## Layout

```
PixelDeck/
  PixelDeckApp.swift      App entry point
  Core/                   Platform-independent model and logic (unit-tested)
  Editor/                 Studio: infinite UIKit canvas, swipe container, dock, tween
  Library/                Gallery
  Community/              Community: CloudKit public sharing (feed, post, share, report/block)
  Export/                 PNG/GIF/MP4/JSON export, Photos saving and the share sheet
  Store/                  In-app purchase (StoreKit 2) and paywall
  Resources/              Bundled fonts (with their OFL licence) and the starter sprites (sprites.json)
  Support/                Theme (colours, fonts, buttons, icons), rendering, welcome, settings, privacy, AppConfig
Tests/                    Unit tests for Core
Tools/                    showcase_art.py and stills_art.py: draw the showcase scenes and starter stills
```
