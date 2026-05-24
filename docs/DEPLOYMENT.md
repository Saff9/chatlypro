# Chatly — Build & Deployment Guide

This document covers how to produce release-quality build artifacts for all
supported target platforms (Android APK, Windows EXE, and Web).

---

## Prerequisites

| Tool | Minimum Version | Install |
|---|---|---|
| Flutter SDK | 3.x | [flutter.dev](https://flutter.dev/docs/get-started/install) |
| Android Studio / NDK | Latest stable | Required for Android APK signing |
| Visual Studio 2022 | Community or higher | Required for Windows builds |
| Node.js | 18.x | Required to build the server bundle |

---

## Preparing for a Release Build

Before building for production, make sure you have your server URL ready.
All URLs are injected at compile time via `--dart-define` flags rather than
stored in source code.

```bash
# Replace with your actual production domain
export API_URL="https://api.chatly.app/api"
export WS_URL="wss://api.chatly.app"
```

---

## Android APK

### 1. Create a Keystore (First Time Only)

```bash
keytool -genkey -v \
  -keystore chatly-release.keystore \
  -alias chatly \
  -keyalg RSA \
  -keysize 2048 \
  -validity 10000
```

Store the keystore and its password securely — losing it means you cannot
publish updates under the same package identity.

### 2. Configure Signing in key.properties

Create `apps/mobile/android/key.properties`:

```properties
storePassword=YOUR_KEYSTORE_PASSWORD
keyPassword=YOUR_KEY_PASSWORD
keyAlias=chatly
storeFile=/absolute/path/to/chatly-release.keystore
```

### 3. Build the APK

```bash
cd apps/mobile
flutter build apk --release \
  --dart-define=BASE_URL=https://api.chatly.app/api \
  --dart-define=WS_URL=wss://api.chatly.app
```

Output location:
```
apps/mobile/build/app/outputs/flutter-apk/app-release.apk
```

### 4. Build App Bundle (for Google Play)

```bash
flutter build appbundle --release \
  --dart-define=BASE_URL=https://api.chatly.app/api \
  --dart-define=WS_URL=wss://api.chatly.app
```

Output location:
```
apps/mobile/build/app/outputs/bundle/release/app-release.aab
```

---

## Windows EXE (MSIX Installer)

### 1. Ensure Visual Studio Build Tools are Installed

Open Visual Studio Installer → Modify → ensure **Desktop development with C++** workload is selected.

### 2. Build the Windows Release

```bash
cd apps/mobile
flutter build windows --release \
  --dart-define=BASE_URL=https://api.chatly.app/api \
  --dart-define=WS_URL=wss://api.chatly.app
```

Output location:
```
apps/mobile/build/windows/x64/runner/Release/chatly.exe
```

### 3. Package as MSIX Installer (Optional)

Install the `msix` Flutter package and run:
```bash
flutter pub run msix:create
```

This generates a signed installer that end users can install by double-clicking,
without requiring a developer mode or separate DLL deployment.

---

## Web (Progressive Web App)

```bash
cd apps/mobile
flutter build web --release \
  --dart-define=BASE_URL=https://api.chatly.app/api \
  --dart-define=WS_URL=wss://api.chatly.app
```

Output location:
```
apps/mobile/build/web/
```

Deploy the entire `build/web/` directory to any static host:
- **Cloudflare Pages**: `wrangler pages deploy build/web`
- **Netlify**: Drag and drop `build/web/` to the Netlify dashboard
- **Firebase Hosting**: `firebase deploy --only hosting`

---

## Backend Server Build

```bash
cd packages/chatly-server
npm install
npm run build   # Compiles TypeScript to dist/
npm start       # Runs dist/server.js in production mode
```

The `npm run build` step uses `tsc` to compile to `dist/`. The Railway deployment
handles this automatically — you do not need to pre-build before pushing.

---

## GitHub Actions — Automated Release Builds

The repository includes a GitHub Actions workflow that:
1. Runs `flutter analyze` on every pull request.
2. Builds a release APK on every push to `main`.
3. Uploads the APK as a build artifact.

Workflow file: `.github/workflows/build.yml`

To use automated builds:
1. Add `KEYSTORE_BASE64` (base64-encoded keystore), `KEY_ALIAS`, `KEY_PASSWORD`,
   and `STORE_PASSWORD` as GitHub repository secrets.
2. Push to `main` — the workflow triggers automatically.

---

## Version Bumping

Before each release, update the version in `apps/mobile/pubspec.yaml`:

```yaml
# Format: major.minor.patch+buildNumber
version: 1.0.1+2
```

The build number must increment monotonically for Google Play and the App Store.
