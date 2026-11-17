# Pixel Deck v2: core feature list (to review)

Saved 16 Nov 2026 for later review. Nothing here is built. Aim: make people love pixel art, and
let them create amazing, complex art with absolute ease.

Based on a look at competing apps and where beginners struggle. The search results were thin, so
items marked *(research)* are backed by a source below, and the rest are judgement. The broader
idea pool (growth, families, beyond the phone) is in `v2-ideas.md`.

## Make complex art easy

1. **Pixel-perfect strokes**: cleans up doubled pixels and jagged corners as you draw, the most
   common beginner mistakes. *(research)*
2. **Shading assistant**: pick a light direction, then a shade/highlight brush steps colours darker
   or lighter along a ramp. Prevents "pillow shading", the most cited beginner problem. *(research)*
3. **Smart palettes**: a colour-ramp generator, a palette pulled from any photo, and a gentle
   "you're using a lot of colours" hint. *(research)*
4. **One-tap animation presets**: bounce, blink, float, shake and colour-cycle applied to a
   selection or layer, with the frames drawn for you.
5. **Motion guides**: pose and skeleton overlays and traceable templates for walk, run and jump.
   Reviewers of a rival app call this out as missing. *(research)*
6. **Stamps library**: save your own pieces (eyes, trees, clouds) and drop them into any canvas.
7. **Photo → pixel art**: turn a photo into pixel art in your palette, ready to tidy and animate.
8. **Better selection and shapes**: lasso and magic wand, rotate and scale, and shape outline
   thickness.
9. **Deeper animation tools**: onion skin showing two frames back plus the next, per-frame hold
   times, and ping-pong loops.
10. **Tiles and scene builder**: draw tiles and paint big scenes with them, with a seamless
    preview. A leading iPad rival has tilemaps. *(research)*

## Make people love pixel art

11. **Pixel Playground**: make your sprite the hero of a small playable retro level, and share
    levels.
12. **Retro modes**: 1-bit, 4-shade handheld green and monochrome ink canvases, with matching
    palettes and dither.
13. **Pixel Academy**: short guided lessons on the tour engine (a walk cycle, squash and stretch,
    a looping campfire).
14. **Inspiration without guilt**: Idea of the day, remix family tree with credit, and curated
    collections.
15. **Share-ready video**: free watermarked GIF and video, plus a vertical format for Reels and
    TikTok with an end card.
16. **Off-screen crafts**: printable bead and cross-stitch patterns from any sprite.
17. **Aseprite file import and export**: lets serious artists move work to and from the desktop.
    A rival app leads on this. *(research)*

## Colour editing

19. **Adjust colours of selected pixels** (requested 17 Nov 2026): select a group of pixels, of
    any mix of colours, and raise or lower their **brightness, contrast, hue and saturation**
    with sliders.
    - Each pixel is adjusted from its own colour, so a multi-coloured selection keeps its colour
      relationships: brightening doesn't shift hues, and a hue shift doesn't change how light or
      dark each pixel is. Transparent pixels are left alone.
    - Work in a hue/saturation/lightness space per pixel, with a live preview on the canvas and
      one undo step for the whole adjustment.
    - Scope choices: the selection, the current layer, this frame, or all frames (so a whole
      animation can be recoloured consistently).
    - Open question: adjusted colours won't match the 10 palette swatches any more. Offer "add
      the new colours to the palette" or "snap to the nearest palette colour" as options.
    - Fits with the shading assistant (2) and smart palettes (3). Simple version could be free,
      with all-frames scope as Pro. *Small–medium.*

## On more devices

18. **Mac app** (requested 16 Nov 2026): Pixel Deck on the Mac.
    - Simplest route: Mac Catalyst (or "Designed for iPad" on Apple silicon Macs as a first step),
      since the app is SwiftUI and already supports keyboard shortcuts, trackpad and mouse, hover,
      and resizable layouts.
    - Mac touches to add: a menu bar with the shortcuts, right-click menus, window resizing,
      drag and drop of images and palette files, and opening and saving files in Finder.
    - Sprites, palettes and Community come along through the same iCloud container, so work
      started on iPhone or iPad opens on the Mac.
    - One purchase should unlock Pro on every device (universal purchase).
    - Check on the Mac: the StoreKit paywall, the widget, the age-range check, and the photo picker.

## AI

20. **Draw with AI assistants on the Mac** (requested 17 Nov 2026): let Claude, ChatGPT and other
    assistants draw pixel art in Pixel Deck, through MCP (Model Context Protocol, an open standard
    for connecting assistants to apps).
    - **Recommended design: Pixel Deck is the MCP server.** The Mac app exposes its drawing
      actions as tools, and the user's own assistant app calls them. Example tools: new canvas,
      set pixels, line / rectangle / fill, set palette, add or select a frame, add a layer,
      flip / rotate, read the canvas back as an image, export.
    - Why this design: the AI draws with the same actions a person uses, so the result is real,
      editable layers and frames, with undo and a timelapse. The assistant can look at the canvas
      and correct itself. It runs on the user's own AI subscription, so there's no AI cost or API
      key for us, and no art passes through any server of ours.
    - Mac only at first: an assistant app on the Mac can reach a local server; iPhone and iPad
      apps can't be driven this way.
    - Safeguards: off by default; the user turns it on and approves each connecting app; each AI
      action is one undo step; a visible "AI is drawing" indicator with a Stop button.
    - To verify when building: which assistants accept a **local** MCP server and which only
      **remote** ones (Claude's desktop app and Claude Code accept local servers; ChatGPT's MCP
      support should be checked at the time, as it may need a remote server); and how a sandboxed
      Mac App Store app may host the server (a localhost server or a small helper command).
    - **Alternative: AI inside Pixel Deck** ("describe it and the app draws it", calling the
      Claude API directly). More seamless and works on iPhone and iPad, but someone pays per
      request (us through a server, or the user's own API key), Apple requires clear disclosure
      and consent before sending user data to a third-party AI (guideline 5.1.2), the privacy
      answers change, and it needs thought for younger users. Consider after the MCP version.
    - Fits the aim (complex art with ease) and the Mac app (18). *Medium for the MCP server.*

**Suggested heart of v2:** 1, 2, 4 and 11.

## Sources

- Guideflow, best pixel art tools (Pixquare, Aseprite compatibility): https://www.guideflow.com/blog/pixel-art-software
- Best Pixel Art Apps for iPad (Pixaki, tilemaps): https://beatcopgame.com/?p=21666
- Common pixel art mistakes (PixelPad Pro): https://pixelpadpro.pages.dev/pixel-art-mistakes.html
- How to start making pixel art #4 (Pixel Grimoire): https://medium.com/pixel-grimoire/how-to-start-making-pixel-art-4-f57f51dcfa02
- Pixel Art Glossary (Pixnote): https://pixnote.net/en/learn/glossary
- Common Palette Mistakes and How to Fix Them: https://pixelpaletteswap.pages.dev/guides/common-palette-mistakes.html
- Pixaki 4 Pro, App Store reviews: https://apps.apple.com/ua/app/pixaki-4-pro/id1447665380
- Pixel Studio listing: https://appshunter.io/ios/app/1440580518
