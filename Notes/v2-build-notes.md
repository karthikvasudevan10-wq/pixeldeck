# Pixel Deck v2: what was built, and what to do next

Written 20 Nov 2026. The code is on the **`v2` branch**. `main` is untouched, so the 1.1 build in
App Review is safe; merge `v2` into `main` when 1.1 is out and you're ready to test v2.

The design is in [`Design/v2`](../Design/v2); feature numbers match
[`v2-core-features.md`](v2-core-features.md).

## How far this has been checked

- **The engine is tested.** Everything in `PixelDeck/Core` is compiled and unit-tested: 195 tests
  pass (104 from before, 91 new). Run them with `swift test`.
- **The screens have not been compiled.** There is no Xcode where this was written. Every Swift
  file passes a syntax check, and three separate read-throughs of the new screens against the
  code they call found no compile errors (and ten bugs, now fixed). But SwiftUI code can only
  really be type-checked by Xcode.
  **Expect some build errors the first time you open the `v2` branch.** Copy them back and they
  can be fixed quickly; they are usually one-line fixes.
- **Nothing has been run on a device or a Mac**: layouts, gestures, the game's feel, sound, video
  export, printing, the Mac window and menus all need trying.
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

- The Mac app is the same app built with **Mac Catalyst**, so sprites, palettes, Community and the
  Pro purchase are shared (same bundle ID, so it's a universal purchase).
- On iPad (landscape) and Mac the Studio uses a **desk layout**: a top bar, the tool rail on the
  left, an inspector on the right (Layers / Colours / Animate), and a timeline along the bottom.
  A sprite list can slide in on the far left (shown by default on the Mac).
- The Mac has a **menu bar** with every shortcut: File, Edit, Sprite, Frame, Layer, Select, View.
- Drop a picture from Finder onto the gallery to turn it into pixel art.
- Different from the design: the gallery is still the first screen on the Mac (the design opens
  straight into the Studio with a sidebar), and the top bar is the app's own rather than a native
  Mac toolbar. Both are safe starting points that can be refined once it runs.

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
