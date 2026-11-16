# Renta UG: publishing on Google Play and the Apple App Store

Renta UG is already an installable web app (PWA). The steps below wrap that same app so it can be listed in the stores. **One codebase; the stores just open your live site.** Updates you deploy to Netlify reach the store apps automatically.

## What is already done in the project
- `public/manifest.webmanifest`: name, icons (192, 512, maskable), shortcuts, start page, colours.
- `public/sw.js`: notifications, an offline page (`public/offline.html`), and cached app files.
- `public/.well-known/assetlinks.json`: proves to Android that the app owns your website (you fill in one value, below).
- `twa-manifest.json`: settings for the Android app (Bubblewrap).
- `capacitor.config.json`: settings for the iPhone app (and an optional Android build).
- Public pages the stores require: `/privacy`, `/terms`, `/delete-account`.
- Landing page at `/` for browsers; inside the installed app people go straight to the app.

## Before you start (both stores)
1. Deploy the latest code to Netlify and check `https://rentaug.netlify.app` opens.
2. Add `VITE_SUPPORT_EMAIL` (a real contact email) in Netlify so the Privacy and Delete-account pages show it. Redeploy.
3. Prepare: **512x512 icon** (`public/icon-512.png`), a **1024x500 feature graphic**, and **at least 2 phone screenshots** of the real app (take them on your phone).
4. Store listing text: short description (80 chars), full description, category *Finance* or *House & Home*.

## Google Play (Android), about USD 25 once
1. Create a Play Console account: <https://play.google.com/console> (one-time fee, ID check).
2. On your computer install Node 18+ and Java 17, then:
   ```
   npm i -g @bubblewrap/cli
   bubblewrap init --manifest https://rentaug.netlify.app/manifest.webmanifest
   bubblewrap build
   ```
   (`twa-manifest.json` in this folder holds the same answers. Keep the `.keystore` file and its passwords safe; losing it means you cannot update the app.)
3. `bubblewrap build` creates `app-release-bundle.aab`. Upload it in Play Console → **Production** (or *Internal testing* first).
4. **Digital Asset Links:** Play Console → Setup → *App signing* → copy the **SHA-256 certificate fingerprint** (use the *App signing key*, plus your upload key if you like). Paste it into `public/.well-known/assetlinks.json` in place of `REPLACE_WITH_YOUR_APP_SIGNING_SHA256_FINGERPRINT`, deploy, and check `https://rentaug.netlify.app/.well-known/assetlinks.json` opens. Without this, the app shows a browser address bar.
5. Fill in the Play forms:
   - **Privacy policy URL:** `https://rentaug.netlify.app/privacy`
   - **Account deletion URL** (Data safety → account deletion): `https://rentaug.netlify.app/delete-account`
   - **Data safety:** collects name, email, phone number, payment info (processed by Relworx), device identifiers (notifications). Data is encrypted in transit; users can request deletion.
   - **Content rating** questionnaire, **target audience** 18+, **ads:** none.
   - **Test account:** give Google a tenant login so reviewers can sign in.
6. Submit for review (usually a few days for a new developer account).

## Apple App Store (iPhone), USD 99 per year
Apple needs a **Mac with Xcode** and an Apple Developer account (<https://developer.apple.com/programs>). Apple also rejects apps that are only a website, so the app is wrapped with Capacitor, which adds a real native shell and push-notification support.
1. On the Mac, in this project:
   ```
   npm i @capacitor/core @capacitor/cli @capacitor/ios @capacitor/push-notifications
   npm run build
   npx cap add ios
   npx cap sync ios
   npx cap open ios
   ```
2. In Xcode: set the **Team**, the bundle id `ug.renta.app`, add the **Push Notifications** capability, set icons (1024x1024 App Store icon) and launch screen.
3. Product → **Archive** → **Distribute App** → App Store Connect.
4. In App Store Connect: add screenshots (6.7" and 5.5" iPhones), description, **Privacy Policy URL** `https://rentaug.netlify.app/privacy`, the **App Privacy** answers (same data as above), and a **demo account** for review.
5. Apple requires apps with accounts to let people **delete their account**: the `/delete-account` page covers the request process; mention it in the review notes.
6. Submit for review (about 1 to 3 days).

Note: iPhone web push (Safari/Home Screen) already works for people who use "Add to Home Screen". The Capacitor app is for the store listing.

## After publishing
- Every time you change the website and deploy to Netlify, the store apps show the new version automatically. Re-submit to the stores only when you change the app wrapper (icon, name, package settings) or want to bump the version.
- Keep the Android keystore, Apple certificates and their passwords in a safe place **outside GitHub**.