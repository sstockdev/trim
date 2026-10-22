# Toolchain setup

Trim is a Flutter app. The release builds happen on GitHub Actions (see [DEPLOYMENT.md](DEPLOYMENT.md)), so a local setup is only needed to change the code, run the tests, or try the app on an Android phone. Installing on an iPhone needs xtool, but no Mac and no Xcode.

## Flutter

Install the Flutter SDK from https://docs.flutter.dev/get-started/install, or clone the stable branch:

```bash
git clone -b stable https://github.com/flutter/flutter.git ~/dev/flutter
```

Add `flutter/bin` to `PATH`, then check it:

```bash
flutter doctor
```

The CI workflow pins the Flutter version in `FLUTTER_VERSION` at the top of `.github/workflows/build.yml`. Use the same version locally when you can, and bump both together.

From the project folder:

```bash
flutter pub get
```

```bash
flutter analyze
```

```bash
flutter test
```

## Android

For `flutter run` on an Android phone or emulator, and for local APK builds, install Android Studio (it brings the Android SDK and a JDK), then run `flutter doctor --android-licenses`. Turn on USB debugging on the phone (Settings, About phone, tap Build number seven times, then Developer options).

```bash
flutter run
```

```bash
flutter build apk --release
```

The APK lands in `build/app/outputs/flutter-apk/app-release.apk`.

## iPhone installs with xtool

Building for iOS needs Xcode, so the IPA comes from the macOS runner on GitHub Actions. Installing it only needs [xtool](https://github.com/xtool-org/xtool), which runs on Linux (including WSL on Windows) and macOS. Follow xtool's own install guide, which also covers connecting the iPhone, then log in with an Apple ID:

```bash
xtool auth login
```

A free account works. `xtool auth status` shows the Apple ID, team ID and token expiry. `xtool install` doesn't need the Darwin SDK; that's only for building Swift apps.

Plug in the iPhone, unlock it and tap Trust. `xtool devices` should list it. Turn on Developer Mode on the iPhone (Settings, Privacy & Security) the first time an app is installed.

## On a Mac

With Xcode installed, `flutter run` works on a connected iPhone, and `flutter build ipa` makes a properly signed IPA if you have a paid developer account. Open `ios/Runner.xcworkspace` to set the team. `Runner.entitlements` already has HealthKit.
