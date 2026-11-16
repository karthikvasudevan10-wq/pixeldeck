# Reply to App Review: Guideline 2.1 (Information Needed)

Paste the text below into App Store Connect > your app > the version > **App Review Information > Notes** (replacing the old notes), add the screen recording, and resubmit. 3572 of 4,000 characters.

```
SCREEN RECORDING
[Paste the link to the screen recording here, or say it's attached.] Recorded on a physical iPhone running the latest iOS, starting from launch. It shows the welcome screens and guided tour, drawing and animating, export, Community (posting, reporting with reasons, blocking, deleting a post), and buying and restoring Pixel Deck Pro. There's no account registration or login: the app has no accounts, so there's no account deletion flow.

1. PURPOSE AND AUDIENCE
Pixel Deck is a pixel-art drawing and frame-by-frame animation app for iPhone and iPad. It's for anyone who loves pixel art: beginners, families, hobbyists and indie game makers, and people who just like looking at it. Animation tools are usually desktop software with steep learning curves. Pixel Deck makes them simple and touch-first: swipe left for a new frame (the previous one shows as an onion skin), drag pixels along a path to tween the frames in between, and export GIFs, videos, PNGs or sprite sheets. A guided tour teaches everything in about two minutes. Community lets people share their art and give hearts.

2. SETUP AND MAIN FEATURES
No login, credentials or sample files are needed. The app opens with starter sprites in the gallery, then a welcome screen and an optional guided tour.
- Draw: tap a sprite or New canvas. One finger draws; pinch to zoom; two fingers move.
- Animate: swipe left from the right edge to add a frame; tap Play.
- Tween: Select tool (dashed square), drag over pixels, drag them along a path, tap Tween.
- Export: Export button (Save asks for add-only Photos access; Share uses the share sheet).
- Community: globe button at the top of the gallery. Needs an iCloud account to post and is age-gated: on iOS 26 the app asks for the user's age range (Declared Age Range) and Community is off for under-13s. To post: long-press a sprite > Share to Community, agree to the rules, enter a title and nickname. Each post has Report (with reasons), Block, and Delete for your own posts; 3 reports hide a post for everyone; titles and nicknames are filtered; blocked users can be unblocked in Settings > Community.
- Pro (paid, non-consumable "Pixel Deck Pro"): Settings (gear) > Unlock Pro, or choose GIF on the export screen. Unlocks art over 64x64, more than 12 frames, GIF/MP4/4K export, timelapse video, dither brush, four-way symmetry, palette import and eased timing. Restore Purchases is in Settings and on the paywall.

3. EXTERNAL SERVICES
Only Apple frameworks; no third-party SDKs, servers, analytics, advertising or AI services:
- StoreKit 2 (In-App Purchase)
- iCloud: a private iCloud container syncs the user's own drawings between their devices; CloudKit's public database stores Community posts, hearts and reports
- Declared Age Range (iOS 26) for the under-13 Community check
- WidgetKit (Home Screen widget of Community favourites)
- PhotosUI picker (to choose a tracing/reference image) and Photos add-only access (to save exports)

4. REGIONS
The app works the same in every region. All content and features are identical worldwide; only the App Store price of Pro varies by storefront. The interface is in English.

5. REGULATED INDUSTRY / THIRD-PARTY MATERIAL
Not applicable. The app isn't in a regulated industry and includes no protected third-party material. All built-in artwork (starter sprites and showcase scenes) is original and made for Pixel Deck. The bundled fonts (Silkscreen, Space Grotesk) are under the SIL Open Font License; the licence is shown in Settings > Font licences.

Support: karthik.vasudevan.10@gmail.com
```

## Screen recording shot list (about 3–4 minutes, on your iPhone)

Settings > Control Centre > add **Screen Recording**. Before recording:
- Delete the app and install the build from **TestFlight**, so it starts fresh.
- Sign in to a **Sandbox Apple Account**: iPhone Settings > Developer > Sandbox Apple Account, created in App Store Connect > Users and Access > Sandbox. The purchase is then free.
- Have one post already in Community from another account or device, so you can report and block it.

Record:
1. **Launch** the app from the Home Screen (the recording must start here).
2. Welcome screens, then the **guided tour**: pick pink, draw a few dots of the heart, swipe left for a frame, tap Play. You can tap Skip tour after that.
3. **Gallery**: open a starter sprite, draw a little, change colour, undo.
4. **Export**: choose PNG > Save (allow the add-only Photos prompt).
5. **Community** (globe button): the age-range prompt (if shown), browse, open someone else's post, **give a heart**, tap **Report**, pick a reason, then open another post and tap **Block**.
6. **Post your own**: long-press a sprite > Share to Community, agree to the rules, enter a title and nickname, Share. In Community > **Mine**, open it and **Delete my post**.
7. **Paid features**: Settings > **Unlock Pro** > buy with the sandbox account. Then show a Pro feature (Export > GIF, or Timelapse > Save video), and Settings > **Restore purchases**.
8. Return to the gallery and end the recording.

Upload: attach the video in the **Attachment** area of App Review Information if it accepts it, or reply in the App Review message (Resolution Center) with the file attached. Otherwise upload it to iCloud Drive or Google Drive, share it as "Anyone with the link can view", and paste the link at the top of the notes.
