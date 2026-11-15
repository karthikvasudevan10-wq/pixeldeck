# App Store submission checklist

What's already done in the code, and what only you can do. Checked against Apple's
[App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/) (last updated
16 Oct 2026) and [Upcoming Requirements](https://developer.apple.com/news/upcoming-requirements/)
as of 13 Nov 2026.

## Concerns about AI-built apps

Apple has been enforcing **guideline 2.5.2** since March 2026 against "vibe coding" apps such as Replit, Vibecode and Anything. Those apps generate code and then run it inside the app. Apple says it has no rule against apps that were *built* with AI; the rule is that an app may not download, install or run code that changes what it does. Other rejections reported for AI-built apps cite the long-standing rules: 2.1 (crashes or incomplete), 4.2 (too little functionality) and 4.3 (spam or copycat).

How Pixel Deck holds up:

| Concern | Status | Evidence |
|---|---|---|
| **2.5.2 running code** | Not applicable | No web views, JavaScript, scripting, plug-ins or downloaded content. The app makes no network requests apart from StoreKit. Tweening creates pixel data, not code. |
| **Hidden permissions** | One, explained | The only permission is Photos **add-only**. It's asked for the first time the user taps **Save** on the export screen, never at launch, and it can't read the photo library. There is no camera, microphone, location, contacts, tracking or network access. `PrivacyInfo.xcprivacy` declares the only required-reason API used (UserDefaults). |
| **Hidden features (2.5.19)** | None | Every paid feature is listed on the paywall and in the review notes. There are no feature flags, remote config or debug unlocks. |
| **Code bloat** | Small | About 5,000 lines of Swift with no third-party dependencies or SDKs. The only bundled assets are two open-licence fonts (OFL, licence shown in Settings) and a 7 KB sprite data file. |
| **Original functionality (4.2, 4.3)** | Original | The swipe-to-keyframe deck, path-traced tweening with jitter removal and smoothing, and the sprite-sheet and JSON exporter are original features, not a template or a wrapped website. |
| **Crashes (2.1)** | Mitigated, but needs device testing | See the hardening list below. 25 unit tests run on Linux. **The iOS interface has not yet been built or run, so TestFlight testing is essential.** |

Crash hardening done:
- **Damaged save files** load as something editable instead of crashing. Bad or wrong-sized frames are dropped, a project with no frames gets a blank one, and impossible sizes are rejected.
- **Memory** is capped:
  - Each sprite is limited to 16 million pixels across all its frames, about 64 MB. That means 256 frames at 256×256.
  - Sprite-sheet exports are limited to 4096 px per side.
  - The thumbnail cache is an `NSCache` capped at 48 MB, and the frame strip only draws the thumbnails on screen.
- **Saves are run-length encoded**, so a 256×256 frame is usually under 3 KB instead of 256 KB. Writes are batched off the main thread and atomic. If the disk is full, the app shows an alert instead of silently losing work.
- **Old export files are deleted**, so the temporary folder doesn't fill up.
- **Undo is capped at 50 steps**, and its snapshots share unchanged frames with the current project instead of copying them.

You still need to do this, and no review can replace it:
- [ ] Build in Xcode and fix any compile errors.
- [ ] Run the app under Instruments (Leaks and Allocations) with a 256×256 sprite of 256 frames. Export at the maximum size.
- [ ] Turn on the Address Sanitizer and Main Thread Checker in the scheme's Diagnostics, then use the app for 10 minutes.
- [ ] Ship to TestFlight and wait for zero crashes in Xcode Organizer → Crashes before submitting.
- [ ] Get an experienced iOS developer to read the code if you can. AI-written code deserves the same review as a junior developer's.

## Already handled in the app

| Requirement | Where |
|---|---|
| Built with the current SDK. Uploads must use Xcode 26+ and the iOS 26 SDK (since 28 Apr 2026). | Build with Xcode 26 or 27. Deployment target is iOS 17. |
| Unlocking features uses In-App Purchase (3.1.1) | `Store/PurchaseManager.swift` (StoreKit 2, non-consumable) |
| Restore Purchases (3.1.1) | Paywall and Settings |
| The real localized price is shown, and the paywall can always be dismissed | `Store/ProUpgradeView.swift` |
| Privacy policy reachable inside the app (5.1.1) | Settings → Privacy Policy, and on the paywall |
| Privacy manifest with required-reason APIs | `PixelDeck/PrivacyInfo.xcprivacy` (UserDefaults, CA92.1) |
| No tracking, so no App Tracking Transparency prompt needed | — |
| Export compliance | `ITSAppUsesNonExemptEncryption = NO` in build settings |
| Photo-library add-only usage string, for Save on the export screen | Build settings (`NSPhotoLibraryAddUsageDescription`) |
| Ratings are requested only through the system API (no custom prompt, 5.6.1) | `ExportSheet.exportSucceeded()` |
| Every gesture also has a visible button | ••• menu → New frame / New canvas; frame strip "+" |
| No hidden or dormant features (2.5.19) | Everything gated is listed on the paywall |
| Runs on iPad (2.4.1) | Universal target, all iPad orientations |
| iPhone Duo and other resizable windows | The layout is chosen from the space available, never from the device type or orientation (`EditorView.prefersSidePanel`). Zoom and position survive a fold or unfold mid-session (`Viewport`). All orientations are allowed on iPhone, and there are no `UIScreen.main` or device-orientation checks. |
| Localisation-ready | All UI text is extractable into `Localizable.xcstrings`, and English plurals are set up. Text is whole sentences with placeholders. Dates and numbers use the user's locale formats. Swipes and labels mirror in right-to-left languages. |
| Reduce Motion respected, VoiceOver labels on controls | `SwipeDeck`, tool buttons, swatches |

## You need to do these

### Account and identifiers
- [ ] Join the Apple Developer Program, which costs 99 USD a year. In App Store Connect, accept the latest Program License Agreement (updated 13 Oct 2026) and the **Paid Apps agreement**. Fill in banking and tax details, or the in-app purchase won't load.
- [ ] Pick a unique bundle ID, for example `com.yourname.pixeldeck`, and set it in Xcode (target → Signing & Capabilities). Set your Team there too.
- [ ] Create the app record in App Store Connect. Check the name is available, since "Pixel Deck" may already be taken. Do a quick trademark search as well.
- [ ] Create a **Non-Consumable** in-app purchase with product ID `<your bundle ID>.pro`. Turn on Family Sharing (the paywall says it's supported), add a display name and description, a price, and a review screenshot of the paywall.
- [ ] Put the same product ID in `AppConfig.proProductID` and in `PixelDeck.storekit`.
- [ ] Attach the in-app purchase to the first app version before submitting (guideline 2.1(b): in-app purchases must be reviewable).

### Links (guideline 2.1: no placeholder or broken URLs)
- [ ] Host `privacy-policy.html` somewhere public, such as GitHub Pages. Put its URL in App Store Connect and in `AppConfig.privacyPolicyURL`.
- [ ] Set up a support URL (a simple page with a contact email is enough), required by App Store Connect. Put it in `AppConfig.supportURL` and `AppConfig.supportEmail`.
- [ ] If you change what the app does with data, update both the in-app copy (`PrivacyPolicyView.swift`) and the HTML.

### App Store Connect answers
- [ ] **App Privacy**: "Data Not Collected" is accurate for this code. iCloud sync stores sprites in the user's own private iCloud container, which the developer can't access, so it isn't collection.
- [ ] **iCloud capability** (needs a paid Apple Developer Program membership): target → Signing & Capabilities → **+ Capability** → **iCloud**. Tick **iCloud Documents**, add a container named `iCloud.<your bundle ID>`, and tick it. Without this the app builds and works, but sprites stay on each device. Before release, test with two devices on the same Apple Account, and check the container in CloudKit Console → your container is created.
- [ ] **Age rating questionnaire**: answer None or No throughout. That includes the newer questions on social media, in-app controls, Shared Location and Dating, which every app must answer by 12 Jan 2027. The result should be the lowest rating.
- [ ] **Category**: Graphics & Design (primary). Entertainment or Productivity are possible secondaries.
- [ ] **Pricing**: Free, with the in-app purchase. See the business model notes below.
- [ ] Paste the text from `metadata.md` and the review notes.

### Light and Dark
- [ ] Switch Settings › Display & Brightness between Light and Dark while the app is open, including with the Studio open. Check the gallery, Studio (canvas checker, grid, selection, hover), export, paywall, settings, layers and tween screens.
- [ ] Take App Store screenshots in Dark: the design was drawn there first.

### iPad
- [ ] Test on a real iPad with Apple Pencil:
  - Draw with a palm resting on the screen.
  - Make fast curved strokes.
  - Double-tap the Pencil, and squeeze it on a Pencil Pro.
  - Check the hover preview on an M2 iPad or later.
- [ ] Test with a Magic Keyboard or trackpad: hold ⌘ to see the shortcuts, scroll to pan, pinch to zoom, and right-click a frame.
- [ ] Use Split View and Stage Manager at several window sizes, and drag the export preview into Files or Notes.
- [ ] Take 13" iPad screenshots that show the Pencil workflow, since editors look for it when picking apps to feature.

### iPhone Duo
- [ ] Build with **Xcode 27.1 or later**. With the iOS 26 SDK the app is shown in a box in the middle of the inner display, with the iOS 27 SDK it nearly fills it, and from 27.1 it's fully optimised (Apple, "Prepare your apps for iPhone Duo").
- [ ] Check each layout from the design handoff:
  - Closed: the Pocket Studio.
  - Open flat: the Flipbook spread. Turn pages, and try all three left-page tabs, including pinning a reference and sampling a colour from it.
  - Half open: Easel. Turn it on from the sprite menu.
  Fold and unfold mid-stroke: the stroke must be kept.
- [ ] If Xcode 27.1+ documents a fold-posture API, read it in `StudioLayout.choose` so Easel turns on by itself when the device is half open.
- [ ] In Xcode's **Device Hub**, check every pose (folded, open like a book, tent, propped) in both orientations. Fold and unfold mid-stroke and while zoomed in: the canvas should keep its zoom and position, and the editor should switch between stacked and side-by-side.
- [ ] Check that system toolbars still fit when iOS shows them vertically below the status bar.
- [ ] Take Duo screenshots: outer display 1398 × 2034 and inner display 2007 × 2853 (portrait). Apple says these will be required for submissions from April 2027, and they earn an "optimised for iPhone Duo" badge.
- [ ] Apple's Duo design guidelines page didn't load when this was written. Read it for any advice on the fold crease.

### Localisation
- [ ] Build once in Xcode 26+. Xcode then fills `Localizable.xcstrings` with every string. English plurals are already defined for the frame counts.
- [ ] Add languages under Project → Info → Localizations, then translate in the catalog. Suggested first languages: Japanese, German, Simplified Chinese, Spanish, Brazilian Portuguese. Each string has a comment to help translators, including notes about mirroring the swipe directions for right-to-left languages.
- [ ] Test with the scheme's pseudo-languages (Edit Scheme → Run → Options → App Language): *Double-Length* catches cut-off text, and *Right-to-Left* checks mirroring, including that the card swipes follow the finger.
- [ ] Translate the App Store listing (name, subtitle, keywords, description and screenshots) for the same markets. Keywords are searched per storefront, so this alone can raise downloads.
- [ ] Translate the hosted privacy policy if you localise the app.

### Testing (guideline 2.1: crashes and bugs are the top rejection reason)
- [ ] In Xcode, go to Product → Scheme → Edit Scheme → Run → Options → StoreKit Configuration and choose `PixelDeck.storekit`. Then test buying, cancelling, restoring, and Ask to Buy (pending) in the simulator.
- [ ] Run `swift test` in `iOS/`.
- [ ] Test on a real iPhone and iPad: every canvas size, around 100 frames at 256×256, export at the largest scale, low-storage behaviour, and dark mode.
- [ ] Ship a TestFlight build to a few people. Ask them to try the swipes without being told how.
- [ ] Use a sandbox Apple Account to buy and restore on a TestFlight build.

### Assets
- [ ] **App icon**: now the slime on flip pink, from the brand kit. For iOS 26+, consider rebuilding it in Icon Composer with dark and tinted versions.
- [ ] **Screenshots**: take them from the simulator or a device, showing the app in use, not just a title card (2.3.3). You need iPhone 6.9" (1320 × 2868) and, because the app runs on iPad, iPad 13" (2064 × 2752). Good shots: the welcome scene, the Studio with onion skin, a tween path, the gallery's live previews, and export. The design's sprite sheets (`sprites/*_sheet_8x.png` in the handoff) also suit marketing artwork. Apple says that from April 2027 every submission must also include iPhone Duo screenshots.
- [ ] Optional: a 15–30 s App Preview video of a swipe and a tween, which is the most persuasive thing you can show.

## Business model (what's implemented)

The app is free to download, with **Pixel Deck Pro** as a one-time non-consumable purchase. The code suggests 4.99 USD. Each line below, free tier then Pro:

- **Art size** on the infinite canvas: free allows up to 64 × 64 px; Pro allows up to 512 × 512.
- **Frames per sprite**: free allows 12; Pro allows 999, or fewer for very large sprites to stay within memory on older iPhones.
- **Drawing tools, mirror, onion skin, motion tweening**: all included free.
- **Export**: free gets PNG frames and sprite sheets with JSON at up to 4×; Pro adds animated GIF, MP4 video and up to 16×.
- **Playback timing**: free plays every frame for the same time (Linear); Pro adds Ease in, Ease out and Ease in & out, carried into GIF, video and the sheet JSON. Tween easing for moved selections stays free.

Why this model:
- A one-time unlock suits an offline tool with no running costs. A subscription needs continuing value to justify it (3.1.2), and reviewers and users push back when there isn't any.
- The signature features (swipes, onion skin, tweening) are free, so people get hooked before they hit a limit. The paywall appears at the moment someone wants more, and highlights the feature they just reached for.
- Every limit is in `Core/FeatureAccess.swift`, so it's easy to tune after launch.

Ideas for later versions:
- Import a photo and turn it into pixel art
- Custom palettes, including .hex and .gpl palette files
- A seasonal discount using a promotional offer

## Review notes (paste into App Store Connect → App Review Information)

> Pixel Deck is an offline pixel-art and sprite-animation editor. No account or login is needed.
>
> Key interactions:
> - Draw with one finger. Pinch with two fingers to change the pixel size, drag with two fingers to move, and tap with two fingers to fit the art. The canvas has no fixed size; it grows as you draw.
> - Swipe **left** starting at the right edge of the canvas (marked by a small pink chevron) to add a frame. The previous frame shows as a pink onion skin. Swipe **right** from the left edge (yellow chevron) to start a new canvas. The **+** after the frame thumbnails also adds a frame, and the gallery has a **New canvas** tile.
> - To tween: choose the Select tool (the dashed square), drag over pixels to select them, drag the selection along any path, then tap **Tween**.
> - Long-press a palette colour to change it.
> - The shapes tool (4th tile) draws lines, rectangles, circles and triangles; the first shape goes on its own layer. The layers button at the top right of the canvas opens the layers panel.
>
> In-app purchase: "Pixel Deck Pro" (non-consumable) unlocks art larger than 64 × 64, more than 12 frames, GIF and video export, exports above 4×, and eased playback timing (frame-rate menu → Timing). To see the paywall, go to Settings (the icon at the top of the gallery) → Unlock Pro, or pick GIF on the export screen. Restore Purchases is in Settings and on the paywall.
>
> **Save** on the export screen asks for add-only Photos access; **Share** uses the share sheet.
>
> The app collects no data.
