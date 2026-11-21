# App Store submission checklist

What's already done in the code, and what only you can do. Start with the launch plan; the
sections below it have the details.

## Version 2 (the `v2` branch)

Everything for v2 is in [`Notes/v2-build-notes.md`](../Notes/v2-build-notes.md): what was built, how far it has been checked, and the steps only you can do. In short:

- [ ] Build the `v2` branch in Xcode for iPhone, then for **My Mac (Mac Catalyst)**, and send back any errors (the screens were written without Xcode).
- [ ] **Free trial**: add a second non-consumable in-app purchase, `karthikvasudevan.pixeldeck.trial`, priced Free. Without it the paywall doesn't offer a trial.
- [ ] **Mac**: App Store Connect › Add Platform › macOS, with Mac screenshots.
- [ ] **CloudKit**: after posting one remix and one level from a development build, add the index **`remixOf`: Queryable** on `Post`, then deploy the schema to Production.
- [ ] **Privacy answers**: the camera is now used (a photo you take to pixelate stays on the device), and the microphone (a sound you record for a frame stays with the sprite). Data collection is still "no".
- [ ] Put the app's Apple ID into `AppConfig.appStoreURL`, and set `AppConfig.allowReportingOwnPosts` back to `false`.
- [ ] Re-answer the age rating questionnaire if asked: nothing in v2 changes the answers (Community is still off under 13; Playground levels are shared through Community with the same reporting and blocking).

Review notes to add for v2: GIF and video export are free with a "Made with Pixel Deck" mark; Pro removes it. The trial is a free non-consumable product that unlocks Pro for 7 days and ends by itself. On the Mac, Settings › AI assistants starts a server that listens on this Mac only (off by default); it lets the user's own AI assistant call the app's drawing tools, and sends nothing to us.

## Launch plan (in order)

Identifiers already set in the code:

| | |
|---|---|
| Bundle ID | `karthikvasudevan.pixeldeck` |
| In-app purchase | `karthikvasudevan.pixeldeck.pro`, Non-Consumable, US$2.99 |
| iCloud / CloudKit container | `iCloud.karthikvasudevan.pixeldeck` |
| Support | karthik.vasudevan.10@gmail.com · https://karthikvasudevan10-wq.github.io/pixeldeck/support.html |
| Privacy policy | https://karthikvasudevan10-wq.github.io/pixeldeck/privacy.html |
| Seller / copyright | Karthik Vasudevan |

**1. Accounts (allow 1–2 days for approval)**
- [ ] Enrol in the Apple Developer Program (US$99 a year) as an individual. Your legal name is shown as the seller.
- [ ] In App Store Connect › Business, accept the agreements, including **Paid Apps**, and add bank and tax details. Until these are active, the in-app purchase won't load, even in TestFlight.

**2. Website (10 minutes)**
- [ ] In github.com/karthikvasudevan10-wq/pixeldeck › Settings › Pages, set Source to **GitHub Actions**. Then, in the Actions tab, run *Pixel Deck website* once (it also runs on every push to `main` that changes `Website/`). It publishes the `Website` folder only. The repo is public, so Pages is free.
- [ ] Open both URLs in the table above and check they load. App Review rejects broken links.

**3. Xcode project (once)**
- [ ] Copy the latest files into `~/Documents/PixelDeck` (everything except `PixelDeck.xcodeproj`).
- [ ] Target › Signing & Capabilities: choose your Team, and set the Bundle Identifier to `karthikvasudevan.pixeldeck`. Your copy of the project still has the old `com.example` one.
- [ ] **+ Capability › iCloud**: tick **iCloud Documents** and **CloudKit**, then add and tick the container `iCloud.karthikvasudevan.pixeldeck`.
- [ ] In-App Purchase needs nothing in Xcode. Apple turns it on for every App ID, so recent Xcode versions may not list it under + Capability, and it never shows for a free Personal Team. Make sure your paid team is selected. Once Xcode has registered the App ID, In-App Purchase appears ticked under developer.apple.com › Identifiers › `karthikvasudevan.pixeldeck`.
- [ ] Build (⌘B) and fix any compile errors. Much of the recent work (tracing image, palettes, iCloud, Community) has only been checked by unit tests on Linux, not compiled for iOS. Send any errors back to Claude to fix.

**4. CloudKit (30 minutes, development environment)**
- [ ] Run on a real device signed in to iCloud. Share a sprite to Community, then report it from a second Apple Account (a second device or a simulator signed in to another account). This creates the `Post` and `Report` record types.
- [ ] In CloudKit Console, add the indexes and the Moderator role (see *Community* below). Put your id from Settings › Community › Show my Community ID into `AppConfig.communityModeratorIDs`.
- [ ] **Deploy Schema Changes to Production.** TestFlight and App Store builds use production, so Community fails without this.

**5. App Store Connect records**
- [ ] Apps › **+** › New App: iOS, name `Pixel Deck: Sprite Animator`, bundle ID `karthikvasudevan.pixeldeck`, SKU `pixeldeck`, primary language English. If the name is taken, try `Pixel Deck – Pixel Animator`.
- [ ] Monetization › In-App Purchases › **+** Non-Consumable `karthikvasudevan.pixeldeck.pro`, US$2.99, Family Sharing on, with the display name and description from `metadata.md`. Add the review screenshot (the paywall, from Settings › Unlock Pro).
- [ ] App Privacy: answer as in *App Store Connect answers* below. Add the privacy policy URL.
- [ ] Age rating questionnaire (user-generated content: **Yes**).
- [ ] Pricing: Free, all territories (or exclude any you don't want).

**6. TestFlight (allow about a week)**
- [ ] Product › Archive, then Distribute › App Store Connect.
- [ ] Install from TestFlight on your iPhone (and an iPad if you have one). Test:
  - buying Pro, then Restore on a second device;
  - iCloud sync between two devices;
  - Community: post, report, block and delete;
  - export to Photos;
  - light and dark appearance.
- [ ] Invite a few friends as external testers. The first external build needs a short Beta App Review.
- [ ] Wait until Xcode › Organizer › Crashes shows zero crashes.

**7. Screenshots and listing**
- [ ] Screenshots (Dark appearance, real content such as the showcase scenes):
  - iPhone 6.9" (1320 × 2868), required. Smaller iPhone sizes are scaled from it.
  - iPad 13" (2064 × 2752), required because the app runs on iPad.
  - Up to 10 per device. Suggested: gallery with the showcase scenes, drawing, onion-skin swipe, tween path, layers and shapes, export, Community.
- [ ] Optional: a 15–30 second app preview video of the swipe-and-tween flow. It converts well for creative apps.
- [ ] Paste the name, subtitle, keywords, promotional text, description and URLs from `metadata.md`.

**8. Submit**
- [ ] In the version page, select the build, attach the **Pixel Deck Pro** in-app purchase, and paste the review notes from the bottom of this file.
- [ ] Choose **Manually release this version**, so you control launch day.
- [ ] Submit for Review. It usually takes 24–48 hours. If rejected, reply in Resolution Center; most first-time rejections are about metadata or links, and are quick to fix.

**9. Launch day and after**
- [ ] Release, then share the App Store link along with your own Community posts.
- [ ] Check CloudKit Console › Public Database › `Report` at least daily. Delete offending posts within 24 hours (a guideline 1.2 requirement).
- [ ] Watch Organizer › Crashes, and answer reviews in App Store Connect.
- [ ] Next update: translations (Japanese first), Duo screenshots, and Community likes.
 Checked against Apple's
[App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/) (last updated
16 Oct 2026) and [Upcoming Requirements](https://developer.apple.com/news/upcoming-requirements/)
as of 13 Nov 2026.

## Concerns about AI-built apps

Apple has been enforcing **guideline 2.5.2** since March 2026 against "vibe coding" apps such as Replit, Vibecode and Anything. Those apps generate code and then run it inside the app. Apple says it has no rule against apps that were *built* with AI; the rule is that an app may not download, install or run code that changes what it does. Other rejections reported for AI-built apps cite the long-standing rules: 2.1 (crashes or incomplete), 4.2 (too little functionality) and 4.3 (spam or copycat).

How Pixel Deck holds up:

| Concern | Status | Evidence |
|---|---|---|
| **2.5.2 running code** | Not applicable | No web views, JavaScript, scripting or plug-ins. Network use is limited to StoreKit, the user's private iCloud (sync) and CloudKit's public database (Community). Community downloads pixel data (validated JSON), never code. Tweening creates pixel data, not code. |
| **Hidden permissions** | One, explained | The only permission is Photos **add-only**. It's asked for the first time the user taps **Save** on the export screen, never at launch, and it can't read the photo library. There is no camera, microphone, location, contacts, tracking or network access. `PrivacyInfo.xcprivacy` declares the only required-reason API used (UserDefaults). |
| **Hidden features (2.5.19)** | None | Every paid feature is listed on the paywall and in the review notes. There are no feature flags, remote config or debug unlocks. |
| **Code bloat** | Small | About 10,000 lines of Swift with no third-party dependencies or SDKs. The only bundled assets are two open-licence fonts (OFL, licence shown in Settings) and the starter and showcase sprites (about 650 KB of JSON). |
| **Original functionality (4.2, 4.3)** | Original | The swipe-to-keyframe deck, path-traced tweening with jitter removal and smoothing, and the sprite-sheet and JSON exporter are original features, not a template or a wrapped website. |
| **Crashes (2.1)** | Mitigated, but needs device testing | See the hardening list below. 84 unit tests cover the editing, storage, sync-merge and Community logic, and run on Linux. **The latest iOS interface code hasn't been compiled yet, so build it in Xcode and test it in TestFlight before submitting.** |

Crash hardening done:
- **Damaged save files** load as something editable instead of crashing. Bad or wrong-sized frames are dropped, a project with no frames gets a blank one, and impossible sizes are rejected.
- **Memory** is capped:
  - Each sprite is limited to 16 million pixels across all its frames, about 64 MB. That means 256 frames at 256×256.
  - Sprite-sheet exports are limited to 4096 px per side.
  - The thumbnail cache is an `NSCache` capped at 48 MB, and the frame strip only draws the thumbnails on screen.
- **Saves are run-length encoded**, so a 256×256 frame is usually under 3 KB instead of 256 KB. Writes are batched off the main thread and atomic. If the disk is full, the app shows an alert instead of silently losing work.
- **Old export files are deleted**, so the temporary folder doesn't fill up.
- **Undo is capped at 50 steps and 256 MB**, and its snapshots share unchanged frames with the current project instead of copying them.
- **Community posts are validated** before display: size, frame count and frame rate are checked, and malformed posts are skipped. Titles and nicknames are filtered.

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
- [x] Bundle ID chosen: `karthikvasudevan.pixeldeck`. Set it (and your Team) in Xcode, under target → Signing & Capabilities.
- [ ] Create the app record in App Store Connect. Check the name is available, since "Pixel Deck" may already be taken. Do a quick trademark search as well.
- [ ] Create a **Non-Consumable** in-app purchase with product ID `karthikvasudevan.pixeldeck.pro`. Turn on Family Sharing (the paywall says it's supported), add a display name and description, a price, and a review screenshot of the paywall.
- [x] The same product ID is in `AppConfig.proProductID` and in `PixelDeck.storekit`.
- [ ] Attach the in-app purchase to the first app version before submitting (guideline 2.1(b): in-app purchases must be reviewable).

### Links (guideline 2.1: no placeholder or broken URLs)
- [ ] Publish `Website` (privacy policy, support and home pages) with GitHub Pages (launch plan step 2). The URLs are already in `AppConfig` and `metadata.md`.
- [ ] If you change what the app does with data, update both the in-app copy (`PrivacyPolicyView.swift`) and the HTML.

### App Store Connect answers
- [ ] **App Privacy**: with Community, declare **User Content → Other User Content** and **Identifiers → User ID**. Both are linked to the user, not used for tracking, and used for App Functionality. (Community posts and their CloudKit user ids are visible to you in CloudKit Console. `PrivacyInfo.xcprivacy` declares the same.) iCloud sync on its own isn't collection, because it uses the user's private container.
- [ ] **iCloud capability** (needs a paid Apple Developer Program membership): target → Signing & Capabilities → **+ Capability** → **iCloud**. Tick **iCloud Documents**, add the container `iCloud.karthikvasudevan.pixeldeck`, and tick it. Without this the app builds and works, but sprites stay on each device. Before release, test with two devices on the same Apple Account, and check the container in CloudKit Console → your container is created.
- [ ] **Age rating questionnaire**: answer as in *Age rating answers* below. Re-answer it in App Store Connect › App Information › Age Rating › **Edit** whenever the app's features change.
- [ ] **Declared Age Range and App Group capabilities**: they're already in `PixelDeck.entitlements` and `PixelDeckWidget.entitlements`. Automatic signing registers them the first time you build with your Team selected. If Xcode reports an entitlement error, open Signing & Capabilities and accept its fix.
- [ ] **Community (CloudKit public database)**. See also guideline 1.2 below.
  1. Under the iCloud capability, also tick **CloudKit**, using the same `iCloud.karthikvasudevan.pixeldeck` container (already set in `AppConfig.cloudKitContainerID`). Add the capability before opening Community, because CloudKit crashes apps that use a container they aren't entitled to. Setting `cloudKitContainerID` to nil turns Community off.
  2. Run the app in development, post one sprite and report it from a second Apple Account. That creates the `Post` and `Report` record types.
  3. In **CloudKit Console** → your container → Schema → Indexes, add:
     - `Post`: **recordName** Queryable, **createdTimestamp** Sortable, **createdUserRecordName** Queryable (for "Mine").
     - `Report`: **post** Queryable.
  4. Security Roles: keep the defaults (World: Read; Authenticated: Create; Creator: Write). There's one exception, for hearts: give **`HeartTally`** the permission **Authenticated: Write**, so anyone signed in can update a post's heart count.
  4b. Hearts and the widget add more record types and fields, which the app creates the first time someone hearts a post:
     - `Heart` (field `post`, a Reference);
     - `HeartTally` (fields `post`, a Reference, and `count`, an Int64);
     - a new `thumb` (Asset) field on `Post`.

     Add these indexes:
     - `HeartTally`: **count** Queryable *and* Sortable, and **recordName** Queryable.
     - `Heart`: **recordName** Queryable.

     Then deploy to Production again.
  5. For in-app moderation, create a **Moderator** role with Read/Write on `Post` and assign it to your own user record. Then add your id (Settings › Community › Show my Community ID) to `AppConfig.communityModeratorIDs`. You can also delete posts directly in CloudKit Console → Records (Public Database).
  6. **Deploy Schema Changes to Production** before you submit. Review uses production.
- [ ] **Guideline 1.2 (user-generated content)**. The app has:
  - a title and nickname filter,
  - Report (3 reports from different people hide a post for everyone),
  - Block,
  - delete-your-own-post,
  - rules the user agrees to before their first post (zero tolerance), and
  - contact details in Settings.

  You must act on reports within 24 hours. Check CloudKit Console → Public Database → `Report` records daily, delete offending posts, and keep a note of abusive users. Set `AppConfig.supportEmail` so people can reach you.
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
- [ ] Run `swift test` in the repository folder.
- [ ] Test on a real iPhone and iPad: every canvas size, around 100 frames at 256×256, export at the largest scale, low-storage behaviour, and dark mode.
- [ ] Ship a TestFlight build to a few people. Ask them to try the swipes without being told how.
- [ ] Use a sandbox Apple Account to buy and restore on a TestFlight build.

### Assets
- [ ] **App icon**: now the slime on flip pink, from the brand kit. For iOS 26+, consider rebuilding it in Icon Composer with dark and tinted versions.
- [ ] **Screenshots**: take them from the simulator or a device, showing the app in use, not just a title card (2.3.3). You need iPhone 6.9" (1320 × 2868) and, because the app runs on iPad, iPad 13" (2064 × 2752). Good shots: the welcome scene, the Studio with onion skin, a tween path, the gallery's live previews, and export. The design's sprite sheets (`sprites/*_sheet_8x.png` in the handoff) also suit marketing artwork. Apple says that from April 2027 every submission must also include iPhone Duo screenshots.
- [ ] Optional: a 15–30 s App Preview video of a swipe and a tween, which is the most persuasive thing you can show.

## Business model (what's implemented)

The app is free to download, with **Pixel Deck Pro** as a one-time non-consumable purchase. The price is set to 2.99 USD. Each line below, free tier then Pro:

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
- Community likes and a "popular" feed
- Import a photo and turn it into pixel art
- Custom palettes, including .hex and .gpl palette files
- A seasonal discount using a promotional offer

## Review notes (paste into App Store Connect → App Review Information)

Plain text, since the field doesn't render formatting. About 2,000 of the 4,000 characters allowed.

```
Pixel Deck is a pixel-art and sprite-animation editor. No account or login is needed. Drawings are stored on the device and synced through the user's own private iCloud.

KEY INTERACTIONS
- Draw with one finger. Pinch with two fingers to change the pixel size, drag with two fingers to move, and tap with two fingers to fit the art. The canvas has no fixed size; it grows as you draw.
- Swipe LEFT from the right edge of the canvas (small pink chevron) to add a frame; the previous frame shows as a pink onion skin. Swipe RIGHT from the left edge (yellow chevron) to start a new canvas. The + after the frame thumbnails also adds a frame, and the gallery has a New canvas tile.
- Tweening: choose the Select tool (dashed square), drag over pixels to select them, drag the selection along any path, then tap Tween.
- Shapes tool (4th tool): line, rectangle, circle, triangle, diamond, pentagon, hexagon, octagon, parallelogram and star. The layers button at the top right of the canvas opens the Layers panel.
- Colours: long-press a palette swatch to change it, or tap the grid button at the end of the palette for the colour picker and ready-made palettes.

IN-APP PURCHASE
"Pixel Deck Pro" (non-consumable, one-time) unlocks art larger than 64 x 64 (up to 512 x 512), more than 12 frames per sprite, GIF and MP4 export, exports above 4x, and eased playback timing (frame-rate menu > Timing). To see the paywall: Settings (gear at the top of the gallery) > Unlock Pro, or choose GIF on the export screen. Restore Purchases is in Settings and on the paywall. The two large "showcase" sprites in the gallery carry a PRO badge: anyone can view and export them, but editing them needs Pro.

PERMISSIONS
Save on the export screen asks for add-only Photos access. Share uses the system share sheet. No other permissions are requested.

COMMUNITY (USER-GENERATED CONTENT)
The globe button at the top of the gallery opens Community, which shares sprites through CloudKit's public database. Browsing needs no sign-in; posting needs an iCloud account. To post: long-press a sprite in the gallery > Share to Community, agree to the community rules, then enter a title and nickname. Each post has Report and Block, and your own posts have Delete. Titles and nicknames are filtered for objectionable text, links and contact details. Three reports from different people hide a post for everyone, and reports are reviewed within 24 hours. Blocked users can be unblocked in Settings > Community. Support: karthik.vasudevan.10@gmail.com
```

## Age rating answers (App Store Connect › App Information › Age Rating › Edit)

With Community off for under-13s:

| Question | Answer |
|---|---|
| Parental controls / in-app controls | No |
| Age assurance | **Yes**: the app asks iOS for the age range before Community. |
| Unrestricted web access | No |
| User-generated content | **Yes** |
| Messaging and chat | No |
| Advertising | No |
| **Social media** | **Yes** |
| **Social media disabled for users under 13** | **Yes**: the Declared Age Range API is called before Community, sharing and hearts are enabled, and under-13s get no Community content (including the widget). |
| Content questions (violence, profanity, mature themes, sexual content, horror, drugs and alcohol, medical, gambling, contests, loot boxes) | None or No |
| Made for Kids | No |

Save it. App Store Connect recalculates the rating, which should come down from the earlier teen rating. The new rating applies to the next version you submit.
