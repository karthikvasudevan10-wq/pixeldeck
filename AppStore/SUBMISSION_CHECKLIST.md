# App Store submission checklist

What's already done in the code, and what only you can do. Checked against Apple's
[App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/) (last updated
16 Oct 2026) and [Upcoming Requirements](https://developer.apple.com/news/upcoming-requirements/)
as of 13 Nov 2026.

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
| Photo-library usage string, for "Save Image" from the share sheet | Build settings |
| Ratings are requested only through the system API (no custom prompt, 5.6.1) | `ExportSheet.exportSucceeded()` |
| Every gesture also has a visible button | ••• menu → New frame / New canvas; frame strip "+" |
| No hidden or dormant features (2.5.19) | Everything gated is listed on the paywall |
| Runs on iPad (2.4.1) | Universal target, all iPad orientations |
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
- [ ] **App Privacy**: "Data Not Collected" is accurate for this code.
- [ ] **Age rating questionnaire**: answer None or No throughout. That includes the newer questions on social media, in-app controls, Shared Location and Dating, which every app must answer by 12 Jan 2027. The result should be the lowest rating.
- [ ] **Category**: Graphics & Design (primary). Entertainment or Productivity are possible secondaries.
- [ ] **Pricing**: Free, with the in-app purchase. See the business model notes below.
- [ ] Paste the text from `metadata.md` and the review notes.

### Testing (guideline 2.1: crashes and bugs are the top rejection reason)
- [ ] In Xcode, go to Product → Scheme → Edit Scheme → Run → Options → StoreKit Configuration and choose `PixelDeck.storekit`. Then test buying, cancelling, restoring, and Ask to Buy (pending) in the simulator.
- [ ] Run `swift test` in `iOS/`.
- [ ] Test on a real iPhone and iPad: every canvas size, around 100 frames at 256×256, export at the largest scale, low-storage behaviour, and dark mode.
- [ ] Ship a TestFlight build to a few people. Ask them to try the swipes without being told how.
- [ ] Use a sandbox Apple Account to buy and restore on a TestFlight build.

### Assets
- [ ] **App icon**: the included heart is a placeholder. A distinctive icon matters a lot for downloads. Make one in Icon Composer, which Xcode 26+ uses for Liquid Glass icons with light, dark and tinted versions. Or replace `AppIcon.png` (1024×1024, no transparency).
- [ ] **Screenshots**: take them from the simulator or a device, showing the app in use, not just a title card (2.3.3). You need iPhone 6.9" (1320 × 2868) and, because the app runs on iPad, iPad 13" (2064 × 2752). Good shots: drawing, the swipe for a new frame with onion skin, the tween path, the GIF/sheet export, and the gallery. Apple says that from April 2027 every submission must also include iPhone Duo screenshots.
- [ ] Optional: a 15–30 s App Preview video of a swipe and a tween, which is the most persuasive thing you can show.

## Business model (what's implemented)

The app is free to download, with **Pixel Deck Pro** as a one-time non-consumable purchase. The code suggests 4.99 USD. Each line below, free tier then Pro:

- **Canvases**: free gets 8, 16 and 32 px; Pro adds 64, 128 and 256 px.
- **Frames per sprite**: free allows 12; Pro allows 999.
- **Drawing tools, onion skin, motion tweening**: all included free.
- **Export**: free gets PNG frames and sprite sheets with JSON at up to 4×; Pro adds GIF and up to 32×.

Why this model:
- A one-time unlock suits an offline tool with no running costs. A subscription needs continuing value to justify it (3.1.2), and reviewers and users push back when there isn't any.
- The signature features (swipes, onion skin, tweening) are free, so people get hooked before they hit a limit. The paywall appears at the moment someone wants more, and highlights the feature they just reached for.
- Every limit is in `Core/FeatureAccess.swift`, so it's easy to tune after launch.

Ideas for later versions:
- Import a photo and turn it into pixel art
- Layers
- iCloud sync
- Custom palettes, including .hex and .gpl palette files
- Apple Pencil hover preview
- Localisation (start with Japanese, German, Spanish and Brazilian Portuguese)
- A seasonal discount using a promotional offer

## Review notes (paste into App Store Connect → App Review Information)

> Pixel Deck is an offline pixel-art and sprite-animation editor. No account or login is needed.
>
> Key interactions:
> - Draw with one finger. Pinch with two fingers to zoom, and drag with two fingers to pan.
> - Drag the canvas card's top strip **left** to add a frame (the previous frame shows as an onion skin), or **right** to start a new canvas. The same actions are in the ••• menu.
> - To tween: choose the Select tool (the dashed square) and drag over pixels to select them. Then drag the selection along any path and tap **Tween**.
>
> In-app purchase: "Pixel Deck Pro" (non-consumable) unlocks 64–256 px canvases, more than 12 frames, GIF export and exports above 4×. To see the paywall, tap New Canvas → 64 × 64, or go to Settings → Unlock Pro. Restore Purchases is in Settings and on the paywall.
>
> The app collects no data.
