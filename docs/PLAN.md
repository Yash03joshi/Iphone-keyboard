# Hindi Handwriting Keyboard — Feasibility & Plan

_Last verified: 2026-10-22_

## 1. Feasibility verdict

| Platform | Verdict | Main risk |
|---|---|---|
| Android | **Feasible, low risk.** `InputMethodService` + ML Kit Digital Ink on-device works in any IME. | None blocking. |
| iOS | **Feasible, medium risk.** Custom keyboard extension + ML Kit pod. | Extension memory limit (≈ 48–70 MB, device dependent, not documented by Apple) with a ~20 MB model loaded; needs an on-device spike early. |

## 2. Recognition engine: Google ML Kit Digital Ink Recognition (verified)

- **Hindi supported**: language tag `hi` = "Hindi, Devanagari script" (also `hi-Latn` for romanised, not what we want). Source: ML Kit base-models page.
- **Android**: `com.google.mlkit:digital-ink-recognition:19.0.0`, minSdk 23. Not marked beta.
- **iOS**: `pod 'GoogleMLKit/DigitalInkRecognition', '8.0.0'` — **CocoaPods only**, no SPM.
- **Offline**: model (~20 MB per language) is downloaded once via `RemoteModelManager` / `ModelManager`; recognition is fully on-device afterwards. Download needs network once.
- **Free**, no API key, no account. ML Kit terms apply (Google APIs ToS); no keystroke data leaves the device — only the model download request.
- Supports multi-word input (ink is free-form; returns up to ~10 candidates) and `preContext` (last ≤20 chars before cursor) + `WritingArea` to improve accuracy and spacing.

### Alternatives considered
| Option | Why not primary |
|---|---|
| Apple Vision / PencilKit / Scribble | No public Hindi handwriting-recognition API usable from a keyboard. |
| Google Input Tools cloud endpoint | Unofficial/undocumented, network required, sends handwriting off-device. |
| Screenshot → LLM vision API | Slow, costly, privacy-hostile, needs network. Rejected. |
| Own TFLite model | Huge effort for worse accuracy. |

### Honest note
On Android, **Gboard already offers Hindi handwriting**. Our value is a much simpler, bigger, parent-friendly UI (and the iOS side, where Gboard has no handwriting mode). Worth trying Gboard with your parents as a baseline.

## 3. Platform limitations to accept up front

**Both**
- Keyboard must be enabled manually by the user in system Settings; apps cannot enable it.
- Secure/password fields always use the system keyboard.

**Android**
- Companion app can detect "enabled" (`InputMethodManager.enabledInputMethodList`) and "selected as current" (`Settings.Secure.DEFAULT_INPUT_METHOD`) and open the settings screens / IME picker.
- Android shows a standard warning ("this keyboard may collect all text…") when enabling — unavoidable.
- Model download from the companion app is shared with the IME automatically (same app process/package, same storage).

**iOS**
- Keyboard extension is a separate process with its own container. ML Kit stores the model in the *extension's* container, so the **extension must download the model itself**, which requires network → `RequestsOpenAccess = YES` → user must turn on **"Allow Full Access"**. (Shared App Group storage is not configurable in ML Kit.)
- Apps can disallow third-party keyboards; phone-number pads and secure fields fall back to the system keyboard.
- Companion app cannot reliably detect whether the keyboard is enabled; we show a guide + a "try it here" text box.
- Memory cap in extensions → load one recognizer, release on `viewWillDisappear`, keep UI light.
- ML Kit iOS frameworks historically lack **arm64-simulator** slices → test on a real iPhone.
- CocoaPods trunk goes **read-only on 2026-12-02**; existing pods keep installing, but future ML Kit updates may require a different channel. Pin versions.

**iOS toolchain / accounts**
- Ubuntu can: write all Swift code, JS, configs. Cannot: build/sign iOS.
- Builds need **macOS + Xcode** or **EAS Build** (cloud macOS, free tier exists).
- **Free Apple ID (Personal Team)**: can install on your own/parents' iPhone via Xcode on a Mac; apps expire after **7 days**; App Groups likely unavailable (we design to not need them). EAS Build cannot sign for physical devices with a free account.
- **Paid ($99/yr)**: TestFlight / ad-hoc / App Store, 1-year profiles, EAS device builds. Realistically needed for parents' iPhones long-term.

## 4. Architecture (native core, thin React Native shell)

Key decision: **the handwriting view and recognizer are written once natively per platform** and used by both the keyboard and the companion app's "test" screen. So Phase 1 validates the exact code the keyboard will run, and the keyboards never depend on React Native.

```
keyboard/                          ← this folder = Expo app root
├── src/
│   ├── app/                       Expo Router screens (TypeScript)
│   │   ├── _layout.tsx
│   │   ├── index.tsx              Home: setup status + big buttons
│   │   ├── setup.tsx              Step-by-step enable guide
│   │   ├── practice.tsx           Handwriting test (uses native view)
│   │   └── settings.tsx           Few prefs (stroke width, auto-insert delay)
│   └── theme.ts, hooks/, strings  shared TS
├── modules/
│   └── hindi-ink/                 Expo local module (create-expo-module --local)
│       ├── expo-module.config.json
│       ├── index.ts               JS API: downloadModel, isModelReady, recognize, keyboard status
│       ├── src/HindiInkView.tsx   RN wrapper for native canvas view
│       ├── android/
│       │   ├── build.gradle       + ML Kit dependency
│       │   └── src/main/
│       │       ├── AndroidManifest.xml   ← declares the IME <service> (merged into app)
│       │       ├── res/xml/method.xml    ← IME metadata
│       │       ├── res/layout|values/... keyboard UI resources
│       │       └── java/.../hindiink/
│       │           ├── core/InkRecognizer.kt     ML Kit wrapper (shared)
│       │           ├── core/HandwritingView.kt   stroke capture + drawing (shared)
│       │           ├── ime/HindiInputMethodService.kt
│       │           ├── HindiInkModule.kt         Expo module (JS bridge)
│       │           └── HindiInkView.kt           Expo view wrapping HandwritingView
│       └── ios/
│           ├── HindiInk.podspec
│           ├── HindiInkModule.swift / HindiInkView.swift
│           └── Shared/ (InkRecognizer.swift, HandwritingView.swift)
├── targets/ios-keyboard/          (Phase 3) KeyboardViewController.swift, Info.plist
├── plugins/withIosKeyboard.js     (Phase 3) config plugin adding the extension target + Podfile entry
├── app.json
└── docs/PLAN.md, PRIVACY.md
```

Why this layout:
- Android IME lives in the module's library manifest → **merged into the app automatically on `expo prebuild`**; no hand-edited `android/` folder, CNG stays intact (`android/` and `ios/` are generated, git-ignored).
- iOS extension needs a new Xcode target, which prebuild doesn't create → a small config plugin (or, fallback, commit `ios/` and manage in Xcode). Decided at Phase 3 start.
- No backend, no accounts, no analytics. Only network use: one-time model download from Google.

### Expo specifics
- **Expo Go cannot work** (custom native code). We use a **development build**: `npx expo run:android` (local, works on Ubuntu) and later `eas build` or `npx expo run:ios` on a Mac.
- Target Expo **SDK 58** (latest, `expo@58.0.17`). Android Studio only needed for SDK/emulator/logcat; builds run from CLI.

## 5. Milestones

### Phase 1 — Validate recognition (Android first, on Ubuntu)
- **M1.1** Scaffold Expo app (SDK 58, Router, TS) in this folder; dev build runs on a physical Android phone.
- **M1.2** Local module `hindi-ink` with ML Kit: `isModelDownloaded`, `downloadModel` (Hindi), progress/errors in UI.
- **M1.3** Native `HandwritingView` (Kotlin) exposed to RN; captures strokes (x, y, t), draws them, emits stroke count.
- **M1.4** `recognize()` with preContext + writing area → show top result + candidates; clear/undo-stroke.
- **M1.5** Real-handwriting test session (parents), airplane-mode test, note accuracy issues.

### Phase 2 — Android keyboard
- **M2.1** Register IME (service, `BIND_INPUT_METHOD`, method.xml); minimal keyboard with Space/Backspace/Enter that types into WhatsApp.
- **M2.2** Embed `HandwritingView` + recognizer; auto-recognize after pause; candidate bar; tap to insert.
- **M2.3** Editing: undo last insertion, delete word, punctuation row (।  ,  ?  !), `preContext` from `getTextBeforeCursor`, switch-keyboard button.
- **M2.4** Companion: setup status (enabled/selected), deep links to settings + IME picker, model-missing state inside keyboard.
- **M2.5** Device test matrix: WhatsApp, SMS, Telegram, Chrome, Gmail; small screen; dark mode.

### Phase 3 — iOS keyboard (needs Mac or EAS)
- **M3.0** Memory/feasibility spike: bare extension + ML Kit + Hindi model on a real iPhone; measure memory.
- **M3.1** Config plugin adds keyboard extension target + pod; signing setup.
- **M3.2** Swift `HandwritingView` + `InkRecognizer`; model download inside extension (Full Access).
- **M3.3** Keyboard UI parity; `textDocumentProxy` insert/delete; `needsInputModeSwitchKey` globe key.
- **M3.4** Companion iOS screens (guide, practice via native view).

### Phase 4 — Polish & release
- Accuracy tuning (writing-area, preContext, stroke smoothing), large-type UI review with parents, error states, PRIVACY.md, release builds (signed APK/AAB sideload or Play; TestFlight/ad-hoc for iOS).

## Status (2026-10-22)
- Done: M1.1–M1.4 (practice screen works on device), M2.1–M2.3 first version, M2.4 setup card.
- Android keyboard renamed "Keshu Keyboard", English UI, Gboard-style with dark mode and ?123 symbol pages.
- iOS: no Mac / no paid account, so iOS is a separate pure-Swift project in `ios-keyboard/` built with
  **xtool** on Linux (free Apple ID, 7-day re-sign) using `d-date/google-mlkit-swiftpm` for ML Kit.
  Code written but not yet built (needs Swift + xtool + Xcode.xip set up). See `ios-keyboard/README.md`.
- Next: first `xtool dev` build on iPhone; M3.0 memory check; M1.5 parent test.

## 6. First milestone: M1.1
Commands (run in this folder):
```bash
npm install
npm run android        # = npx expo run:android → builds + installs dev client on the USB phone
npm start              # later: just start Metro; open the installed "Hindi Likho" app
```
Success = app opens on the phone from the dev build (not Expo Go) and hot-reloads.
