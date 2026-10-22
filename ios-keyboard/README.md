# Keshu Keyboard — iOS

Pure Swift (UIKit keyboard extension + SwiftUI companion app), built and installed from
Linux with [xtool](https://xtool.sh). Separate from the Expo app (which is Android-only).

```
Sources/KeshuKeyboard/   the keyboard extension (port of the Android HindiInputMethodService)
Sources/KeshuApp/        companion app: setup guide + "Try writing" box
xtool.yml                app + extension bundle IDs, Info.plists, resources
```

## One-time setup (Ubuntu)

1. Swift toolchain: see https://www.swift.org/install/linux/ (swiftly).
2. `sudo apt install usbmuxd libimobiledevice-utils`
3. Download Xcode (`.xip`) from https://developer.apple.com/download/all/?q=Xcode with any Apple ID.
4. Install xtool and run `xtool setup` (choose "Password" login for a free Apple ID, then give
   the path to `Xcode.xip`). Details: https://xtool.sh/documentation/xtooldocs/installation-linux
5. `./scripts/fetch-mlkit-bundle.sh` (ML Kit resource bundle the extension must embed).

## Build & install

Plug the iPhone in via USB, unlock it, tap "Trust", then:

```bash
xtool dev
```

On the iPhone the first time: Settings → General → VPN & Device Management → trust your
Apple ID. With a free Apple ID the app stops launching after 7 days; run `xtool dev` again.

Then follow the steps in the app (add the keyboard, turn on Allow Full Access, download).
