# Pixel Deck: ideas for version 2

Notes from planning, 16 Nov 2026. Nothing here is built yet. Guiding values: inspiration rather than
guilt (no streaks), families and kids, people who just admire pixel art, and a love of
single-colour pixel art, pixel-art games and that retro feeling. ★ marks the top picks.

## Theme: "From pixels to play"

Version 1 lets people draw, animate and share. Version 2 lets them bring their art to life in a
little retro game.

- ★ **Pixel Playground** (headline): pick one of your sprites as the hero, paint a level with tiles,
  tap Play, and run and jump through it. Share levels so others can play them with your character.
  Pro: bigger levels, enemies and items, sound. *Large.*
- ★ **Tile and level painter**: draw a set of tiles, paint scenes with them, with a seamless-tiling
  preview. Useful for indie game makers, and the building block for the Playground. *Medium.*
- **Chiptune sound**: a small set of retro sound effects and loops for MP4 and timelapse exports
  and the Playground. *Medium.*

## Single-colour and retro art

- ★ **Retro modes**: start a canvas in a constrained style with the right palette, dither and grid:
  - 1-bit (two colours)
  - 4-shade handheld green
  - monochrome ink
  - 8-colour home computer

  Add a Community tag per mode, such as a Monochrome gallery. *Small–medium.*
- **Shading helpers**: a hue-shifted shading ramp from one colour, an auto-outline tool, and replace
  a colour across all frames. *Small.*
- **Shape outline thickness**: outlined shapes (rectangle, circle, hexagon, star…) are always 1 px
  today. Use the brush size (1–4, square or round) for shape outlines too, showing the size chips in
  the shape strip, so there's one thickness control everywhere. Thick outlines should grow inwards,
  so a shape keeps the size you dragged; lines get the same thickness. *Small.*

## Inspiration, without guilt

- ★ **Idea of the day**: a gentle prompt in the gallery ("a frog waiting for rain"), with a few
  community pieces made for it. No counters, no "you missed a day". *Small.*
- ★ **Remix family tree**: each post shows the remixes made from it, remixes credit the original
  artist, and a kind notification says "Your slime inspired 3 remixes". *Medium.*
- **Curated collections**: hand-picked galleries such as "Monochrome Monday", "Tiny Heroes" and "Cosy
  Rooms". *Small.*
- **Pixel Academy**: more guided lessons on the tour engine (a walk cycle, a blinking eye, squash and
  stretch, an explosion, a looping campfire). First two free, the rest Pro. *Small per lesson.*

## Families and making things together

- ★ **Bead and cross-stitch patterns**: turn a sprite into a printable fuse-bead or cross-stitch
  pattern, with a grid and a colour shopping list. *Small–medium.*
- **Draw together**: share a sprite with family through iCloud, or draw live over FaceTime with
  SharePlay. *Medium–large.*
- **Photo → pixel art** (Pro): turn a photo of the dog, the kids or the house into pixel art in your
  palette, ready to tidy and animate. *Medium.*

## Beyond the phone

- **Lock Screen and StandBy widgets**: a favourite looping sprite on the Lock Screen or bedside clock.
- **Apple Watch app**: your animations on your wrist.
- **Live wallpaper**: export an animation as a Live Photo.
- **Mac app**: Pixel Deck on the Mac, using the trackpad and keyboard support already built.
- **Translations**: Japanese first, then Spanish, German and Portuguese.

## Growing through Instagram and TikTok sharing

Goal: encourage people to share their work on Instagram and TikTok, carrying the app's logo and
"Available on the App Store".

**Don't build "share on social media to unlock Pro".**
- Apple guideline 3.2.2 forbids requiring "rate, review, watch videos… or other similar actions" to
  unlock functionality, so it would be rejected.
- Instagram and TikTok also ban rewarding people for sharing.
- The app can't tell whether anything was actually posted.

Ways to get the same effect within the rules:

- ★ **Free GIF and video export, with the watermark**: free exports carry "Made with Pixel Deck ·
  Available on the App Store", and Pro removes it, as with PNG today. Every free share is an
  advert. Biggest lever. *Small.*
- ★ **Reels and TikTok format**: a vertical 9:16 (1080 × 1920) export of an animation or its
  timelapse, ending with a short card (app name, slime, "Available on the App Store"). Timelapse
  "watch me draw" videos suit both apps. *Small–medium.*
- ★ **Free Pro trial**: a free, time-limited non-consumable purchase (for example "7-Day Pro Trial",
  which Apple allows), so everyone tries every Pro tool, shares, and buys if they love it.
  *Small–medium.*
- **Creator gifts outside the app**: give Apple offer codes for free Pro to pixel artists and
  creators, or to people who tag the app in great posts. You find them and send codes yourself;
  nothing in the app asks anyone to post. Creators should mark posts as gifted or #ad.
- **Effortless sharing**: a "Share to Instagram or TikTok" button after export, with a ready-made
  caption ("Made with #PixelDeck ✨") and the App Store link in the caption. Direct posting through
  Instagram's and TikTok's own developer kits adds third-party services and privacy declarations,
  so leave it for later.
- **Community challenges with prizes** (later): for example "Monochrome week", where the
  most-hearted entry wins a Pro code. In-app contests must follow guideline 5.3 (official rules,
  Apple isn't the sponsor), so run them small, ideally from the website or social accounts.

## Suggested v2 lineup

- **Headline:** Pixel Playground with the tile painter.
- **Delight:** Retro modes, Idea of the day, remix family tree.
- **Families:** bead and cross-stitch patterns.
- **Pro value:** Photo → pixel art, more Pixel Academy lessons, chiptune sound.
- **Growth:** free watermarked GIF and video, the 9:16 Reels and TikTok format, and a free Pro trial.

Before choosing, check App Store Connect › App Analytics after launch (day 1, 7 and 28 retention):
- If people leave after the tour, lessons and prompts matter most.
- If they stay but rarely share, the remix family tree and the Playground matter most.

## Also noted earlier (not yet built)

- Community likes are done (hearts and Popular).
- Multi-frame onion skin (two frames back plus the next), per-frame hold times, ping-pong loops.
- Selection rotate and scale.
- Several animations in one sprite (idle, run, jump) exported as one tagged sprite sheet.
- iMessage stickers (low priority).
