# Pixel Deck v2: what was built, and what to do next

Written 20 Nov 2026. The code is on the **`v2` branch**. `main` is untouched, so the 1.1 build in
App Review is safe; merge `v2` into `main` when 1.1 is out and you're ready to test v2.

The design is in [`Design/v2`](../Design/v2); feature numbers match
[`v2-core-features.md`](v2-core-features.md).

## How far this has been checked

- **The engine is tested.** Everything in `PixelDeck/Core` is compiled and unit-tested: 195 tests
  pass (104 from before, 91 new). Run them with `swift test`.
- **The whole app is compiled on every push.** GitHub builds the `v2` branch for the Mac and
  for iPhone on its own Macs each time something is pushed (the repository's **Actions** tab,
  "Build check"; set up in `.github/workflows/build-check.yml`). Both build with no errors and
  no warnings in Pixel Deck's own code. That build skips code signing, so signing and
  capability messages (iCloud, App Group) can still appear in your Xcode.
- **The Mac window has been checked by machine, not by eye.** The build check can open the Mac
  app and describe its window (put `[window-check]` in a commit message). That confirmed the
  toolbar, the narrow tool rail, the options bar and the full-screen layout are where they
  should be. Colours, text and the feel of it still need a person.
- **The Mac app is tried automatically.** Put `[monkey]` in a commit message and the build
  check opens the Mac app and uses it by itself for about twenty minutes (`Tools/ci/monkey.py`):
  it draws with every tool, presses every shortcut, clicks every button in the options bar, the
  inspector, the timeline and the toolbar, opens every sprite in the list, and clicks all over
  Export, Settings, New canvas, Palettes, Adjust colours and Stamps, and over the Photo,
  Playground and Pixel Academy screens (which debug builds open by themselves when started with
  `-monkeyOpen photo` and so on). Anything that stops the app is reported with its error. The
  last full run found nothing. It cannot try Community (the build machine's copy isn't signed
  for iCloud), choosing a real picture in the Finder window, sound recording or purchases.
- **Full screen on the Mac.** In full screen the Mac slides its menu bar and title bar down over
  the top of the window when the pointer goes there. The Studio's toolbar and every whole-window
  screen (Photo, Export, Community, Playground, Academy, welcome) sit below that strip
  (`Support/FullScreenWatcher.swift`), so their Back and Close buttons can always be reached.
- **Pictures on the Mac** come from the Finder's own window ("Choose a picture"), which lists the
  Photos library too. The separate Photos window and the system camera screen are not used on
  the Mac: they could open with no way to close them.
- **The crash it found.** Before 21 November the Mac app stopped on the first pencil stroke, and
  on opening Export, Share or the Pro screen ("No Observable object of type PurchaseManager
  found"): screens opened from the Studio did not receive the objects in SwiftUI's environment.
  The store, purchases, Community, the age check, iCloud sync and the router now live in
  `Support/Shared.swift` and every screen reads them from there.
- **Nothing has been tried by hand on a device**: gestures, the game's feel, sound, video
  export and printing all need trying.
- **Aseprite files** were tested by saving a sprite and reading it back, following Aseprite's
  published file format. They have not been tested with files saved by Aseprite itself: try a few.

## What's in each release

### v2.0 · Make complex art easy

| # | Feature | Where to find it | Free or Pro |
|---|---|---|---|
| 1 | Pixel-perfect strokes | Pencil › "Pixel-perfect" chip (on by default) | Free |
| 2 | Shading assistant | Pencil › "Shade" chip: light direction, Shade / Highlight | Free |
| 3 | Smart palettes | Colours › Ramps and From a photo tabs; a hint when a sprite has many colours | Free |
| 4 | Animation presets | Sprite menu › Animate with a preset; Select › Animate | Bounce, Blink free; Float, Shake, Colour cycle, Squash Pro |
| 7 | Photo to pixel art | Gallery › New canvas › From a photo (or drop a picture on the gallery) | Try it free; Pro to open the result |
| 8 | Lasso, wand, rotate, scale; shape thickness | Select tool strip; Shapes strip › thickness | Free |
| 9 | Onion skin 3 back + 2 ahead, holds, ping-pong | Sprite menu › Onion skin and timing; long-press the onion button | Free |
| 15 | Share-ready video | Export › Video: Square, 9:16, Timelapse, end card, caption | GIF and video are now free with the watermark; Pro removes it; Timelapse video is Pro |
| 19 | Adjust colours | Sprite menu › Adjust colours; Select › Colours | Free; "All frames" is Pro |
| 18 | Mac app, iPad desk layout | See below | Same purchase |

Also: a **free 7-day Pro trial** on the paywall (needs one step in App Store Connect, below).

### The Mac app and the desk layout (18)

Rebuilt on 21 Nov 2026 to follow the design screens in `Design/v2/screens/09-mac` and
`08-ipad` (the first version took shortcuts: it opened on the gallery and used its own top bar).

- The Mac app is the same app built with **Mac Catalyst**, so sprites, palettes, Community and the
  Pro purchase are shared (same bundle ID, so it's a universal purchase).
- **The Mac opens straight into the Studio**, with no separate gallery screen:
  - **Toolbar** in the window's top row, beside the close buttons: sidebar, the sprite's name
    (with "Edited" once it has changes; click it for the sprite's menu), undo, redo, play,
    layers, zoom %, share to Community, export, inspector.
  - **Sidebar**: Search, then Moving, Stills, Playground and Pixel Academy, with Community at
    the foot. The sprite on screen is filled pink. Right-click a sprite to rename, duplicate or
    delete it.
  - **Tool rail** floating over the top-left of the canvas.
  - **Inspector**: Layers (with Add and Merge down), Palette with the ramp of the current colour
    ("Ramp from Blue · hue shift +18°"), and Animation presets, in one column. The tabs jump to a
    section. While an AI assistant is connected, the third tab becomes **AI** and lists what it
    did, step by step.
  - **Timeline** under the canvas: the shortcut hints, the Onion, loop and fps chips, and
    numbered frames.
  - **Drop target**: drag a photo, an .aseprite file or a palette (.gpl, .hex) onto the canvas.
  - **Settings** has the designed tabs: General, Pencil, iCloud, Community, AI, Pro.
  - **Menu bar** worded as in the design (File, Edit, Sprite, Frame, Layer, Select, View), with
    Pixel Deck › Settings… and File › New from a photo, retro mode, tiles…
- **iPad (landscape)**: top bar (gallery, name, frame counter, undo, redo, zoom, share, export),
  the tool rail with brush sizes down the left, the same inspector on the right, and the
  timeline with Play under the canvas.
- Still to check on a real Mac, because it can't be run here:
  - whether the toolbar lines up with the window's close buttons (the title bar is hidden and
    the toolbar is drawn in its place);
  - that ⌫ (Delete frame, as in the design) and the single-letter shortcuts don't fire while
    typing a name;
  - the zoom figure: it shows true zoom (100% is one screen point per art pixel), so typical
    values are 800% to 3200% rather than the design's 400%.
- New sprites on the Mac come from File › New canvas (⌘N) or the swipe from the left edge; the
  design has no "new" button in the window.

### v2.1 · From pixels to play

| # | Feature | Where to find it | Free or Pro |
|---|---|---|---|
| 12 | Retro modes | New canvas › Retro mode: 1-bit, Handheld, Ink, 8-colour; the palette is locked and dither is free | Free |
| 10 | Tiles and scene builder | Play tab (or New canvas › Tiles): paint a scene with tiles, edit a tile with a 3 × 3 seamless preview | Free up to 24 × 12 tiles |
| 11 | Pixel Playground | Play tab: choose a hero from your sprites, place the start, coins, a goal; Play | Free; longer levels, enemies and sound are Pro |
| 13 | Pixel Academy | Gallery › the graduation-cap button: six lessons, a guide per frame | First two free, the rest Pro |
| 14 | Inspiration | Gallery › Idea of the day; Community posts show their remix family and credit | Free |

Sharing a level: post it to Community (others can play it and keep a copy), send it as a file
(AirDrop, Messages), or record a run (a screen recording, offered for sharing when you win).

### v2.2 · Beyond the canvas

| # | Feature | Where to find it | Free or Pro |
|---|---|---|---|
| 5 | Motion guides | Sprite menu › Motion guides: Walk, Run, Jump, Idle bob | Pro |
| 6 | Stamps | Sprite menu › Stamps; Select › Stamp: starter stamps and your own | Free |
| 16 | Bead and cross-stitch patterns | Sprite menu or Export › More: chart, shopping list, Print, Share PDF | Free |
| 17 | Aseprite files | New canvas › Open an Aseprite file; Export › More › Aseprite file | Pro |
| 20 | AI assistants on the Mac | Mac › Settings › AI assistants | Free |

### Sound on frames (added 21 Nov 2026)

- **What it does**: attach a sound to any frame, by recording with the microphone (up to two
  minutes) or choosing an audio file (M4A, MP3, WAV; up to ten minutes). The sound starts when
  the animation reaches that frame and plays for its own length. A frame can have four sounds, a
  sprite twenty-four, each with its own volume.
- **Where**: long-press a frame › Sound; sprite menu › Sound on this frame; on the Mac, Frame ›
  Sound on This Frame (⌥⌘S). Frames with a sound show a small speaker.
- **Where you hear it**: when you press Play in the Studio, and in exported videos (square and
  9:16), where the sounds are mixed into the soundtrack and repeat with the animation. GIFs,
  sprite sheets and Community posts are silent.
- **Kept with the sprite**: sounds follow their frame when frames are added or moved, are copied
  when a sprite is duplicated, are removed with the sprite, and sync through iCloud with it.
- **Changed with it**: pressing Play now always starts from the first frame (it used to start
  wherever the loop happened to be), so sound and picture stay in step.
- **Not checked**: recording, playback and the video soundtrack use the device's audio system,
  which can't be run here. Try a recording and a file, and export a video with each.
- **For App Store Connect**: the app now asks for the **microphone** (only when you tap Record;
  recordings stay with the sprite on the user's devices). Data collection is still "no".

A whole film (many scenes joined into one long video with one soundtrack, 60 fps, long holds)
is not built yet. Sound on frames is the first piece of it.

## Movies, and the limits that were lifted (22 November)

Not in the design: asked for directly, and built from the app's existing pieces.

- **Movies.** A movie is a list of scenes; each scene is a sprite, played through one or more
  times. Scenes are drawn, animated and given sound in the Studio like any sprite. In Movies they
  are put in order, previewed (with their sounds) and made into one video: widescreen 1920 × 1080,
  square, tall, or 4K. Reached from the gallery (film button), the Mac's sidebar and File menu,
  and the New canvas chooser. Code: `Core/Movie.swift`, `Movies/MoviesView.swift`,
  `Export/MovieExporter.swift`.
- **How a long film stays small.** The video is written one scene and one frame at a time, and
  the soundtrack ten seconds at a time, so making it needs no more memory than the biggest scene.
- **Layers** have no fixed number now (it was 8). What stops a new layer is the sprite's size in
  memory: every layer is kept for every frame.
- **Frame rate** goes up to 60 a second (it was 30). **Holds** go up to 600 beats (it was 8).
  Community posts and Playground heroes still play at up to 30, and a GIF frame lasts at least
  1/50 of a second.
- **Checked:** 206 engine tests, including where scenes and their sounds fall in a movie's
  running time. On GitHub's Mac the app made a three-scene movie with a sound: the video came
  out the expected length (6.125 s) with one picture track and one sound track.
- **Decisions made here that are yours to change:** free videos carry the "Made with Pixel
  Deck" band and 4K needs Pro, the same as other exports. Scenes of different sizes are each
  scaled to fit the frame. There are no titles or transitions between scenes.
- **What still stands between this and a three-hour film:**
  - Every sprite is loaded into memory when the app starts. A feature-length film has more
    drawn frames than that allows; sprites need to be loaded only when they are opened or
    played. That is the next piece of work.
  - A sprite still holds at most 999 frames, so a long film is many scenes.
  - Previewing a movie gets every remaining sound ready when Play is pressed; fine for minutes,
    untried for hours.
  - Nobody has timed making a long video. The six-second test took a few seconds.

## Not built, or built differently

- **"N people drew this today"** on Idea of the day: left out. It needs a count from Community.
- **Community tab in Stamps**: left out (starter stamps and your own are there).
- **Monochrome tag** on Community posts from retro canvases: left out.
- **Curated collections** in Community: left out (it wasn't in the design screens).
- **Blink** closes small dark shapes inside the art (eyes). If it finds none, the art blinks off
  and on instead. Select just the eyes first for the best result.
- **Record a run** records the whole screen as it is, not a 9:16 crop.
- **iPhone Duo**: the Duo layouts from v1 still work and show the new strips and panels, but the
  v2 Duo screens (tabletop controller, wide Photo and Tiles spreads) were not laid out specially.
- **Decisions the design left open** were taken as designed: the free/Pro split above, the 7-day
  trial, AI off by default. The price is whatever the Pro product costs in App Store Connect.

## What you need to do

### 1. Build it

1. On your Mac: `git fetch` then `git checkout v2`.
2. Open `PixelDeck.xcodeproj` and build for an iPhone simulator. Send back any errors.
3. Then build for **My Mac (Mac Catalyst)**. The first time, Xcode will ask to register the Mac
   app's signing; accept. If it complains about the **Declared Age Range** entitlement on the
   Mac, say so and it can be made iPhone/iPad-only.

### 2. App Store Connect

- **Free trial**: create a second in-app purchase: type **Non-Consumable**, product ID
  `karthikvasudevan.pixeldeck.trial`, price **Free (tier 0)**, name "7-day Pro trial". The app
  treats it as Pro for 7 days from the day it's "bought", then it ends by itself. Until the
  product exists the paywall simply doesn't offer a trial. (Apple has no built-in trial for a
  one-time purchase; a free product like this is the approach Apple suggests.)
- **Mac**: on the app's page choose **Add Platform › macOS**, and add Mac screenshots.
- **Privacy**: the app now uses the **camera** (to take a photo to pixelate; the photo stays on
  the device), the **microphone** (to record a sound for a frame) and the photo picker. The answer to "do you collect data" is still no.
- **App Store link in captions**: put your app's numeric Apple ID into `AppConfig.appStoreURL`
  so shared videos' captions link to the App Store instead of the website.
- **Before submitting**: set `AppConfig.allowReportingOwnPosts` back to `false`.

### 3. CloudKit Console (for remixes and shared levels)

The `Post` record type gets four new fields, created the first time a remix or a level is posted
from a development build:

- `remixOf` (Reference), `remixOfTitle` (String), `remixOfAuthor` (String), `level` (Asset).

Then in Schema › Indexes add **`remixOf`: Queryable** on `Post`, and deploy the schema to
Production as before.

### 4. Try AI drawing on the Mac

1. In the Mac app: Settings › AI assistants › turn on **Let AI assistants draw in Pixel Deck**.
2. Tap **Copy setup for Claude Code**, paste it into Terminal, and start Claude Code. (For the
   Claude app, use **Copy setup for the Claude app** and paste it into its developer settings
   file; that route needs Node.js installed.)
3. Open a sprite in the Studio, then ask the assistant to draw something. Pixel Deck shows
   "… wants to draw": tap **Allow**. A banner with **Stop** shows while it draws.

How it works: Pixel Deck runs a small server that only your Mac can reach, at an address with a
private key in it. The assistant calls Pixel Deck's own drawing tools (set pixels, line,
rectangle, fill, frames, layers, read the canvas back), so what it draws is ordinary layers and
frames. Each step is one undo. Nothing goes to any Pixel Deck server.

On the Mac, also check the menu shortcuts that have no ⌘ (B for Pencil, Space for Play, Delete):
typing a sprite's name in the Rename box should still type letters, not switch tools.

To check when testing: that the Mac App Store's sandbox lets the server start (the entitlement
is in place), and which other assistants can connect to a local address.

## Where things are in the code

```
PixelDeck/Core/
  Assist.swift            pixel-perfect strokes, shading assistant
  ColorMath.swift         HSL, ramps, colour adjustments, merging similar colours
  Selection.swift         lasso, magic wand, rotate / scale / flip
  AnimationPresets.swift  bounce, blink, float, shake, colour cycle, squash
  PhotoPixelizer.swift    photo to pixel art, retro modes
  Timing.swift            holds, loop modes, the playback sequence
  EditorModel+V2.swift    the editing actions for the above
  Tiles.swift             tiles, scenes, the scene store
  Playground.swift        the game
  Academy.swift           lessons, idea of the day
  Stamps.swift, Crafts.swift, MotionGuides.swift
  Aseprite.swift, Zlib.swift
  AITools.swift           the tools assistants call
PixelDeck/Editor/         StudioPanels, SmartPalettes, StampsSheet, EditorView+Desk, EditorView+Lesson
PixelDeck/Play/           scene and tile editors, the game view, the levels list
PixelDeck/Library/        PhotoToPixelView (and New canvas), AcademyView, AsepriteImport
PixelDeck/Export/         VideoExporter (9:16, end card), BeadPatternView
PixelDeck/Support/        AIBridge (the Mac's MCP server), StudioCommands (the Mac menu bar)
Tools/tiles_to_swift.py   turns the design's tile and stamp pictures into Swift
```
