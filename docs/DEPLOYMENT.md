# Deployment

Trim isn't in either app store. GitHub Actions builds it, and you install the files yourself.

## Builds

[`.github/workflows/build.yml`](../.github/workflows/build.yml) runs on every push to `main`, on pull requests, and by hand from the Actions tab. It has four jobs:

1. `test` runs `flutter analyze` and `flutter test` on Ubuntu.
2. `android` builds `Trim.apk` on Ubuntu with `flutter build apk --release`.
3. `ios` builds `Trim.ipa` on macOS with `flutter build ios --release --no-codesign`, then signs it ad hoc with `ios/Runner/Runner.entitlements` and zips `Payload/Runner.app`.
4. `release` runs only for tags that start with `v`. It attaches both files to a GitHub Release.

The APK and IPA from every run are also kept as workflow artifacts for 90 days. To cut a release, set `version:` in `pubspec.yaml` to the new version, commit it, then tag and push:

```bash
git tag v1.2.0
```

```bash
git push origin v1.2.0
```

The build number is the workflow run number, and the version name comes from `version:` in `pubspec.yaml`.

### Why the IPA is signed ad hoc

xtool re-signs an IPA with your Apple ID when it installs it. It decides which capabilities to turn on for the App ID by reading the entitlements already embedded in the app's executable. A `--no-codesign` build has no embedded entitlements, so xtool would install it without HealthKit and every Health call would fail. Signing ad hoc with `Runner.entitlements` (frameworks first, then the app) embeds `com.apple.developer.healthkit`, and the workflow prints the entitlements so you can check them in the log.

## iPhone

The IPA is installed with xtool and a free Apple ID, which has these limits:

- An install works for 7 days, then won't open until it's re-signed. Reinstalling keeps all data.
- At most 3 sideloaded apps on the device at once.
- At most 10 App IDs registered at a time, each lasting 7 days.
- No App Groups, push notifications or iCloud entitlements. HealthKit works.

### Installing and refreshing

Download `Trim.ipa` from the latest release (or a workflow run), connect the iPhone, and run:

```bash
xtool install Trim.ipa
```

When a free-account install expires ("Unable to verify app" or "no longer available"), run the same command again. Reinstalling resets the 7 days and keeps all data, so the same IPA can be reinstalled every week. [SETUP.md](SETUP.md) covers installing xtool.

### Bundle ID and data

The iOS bundle ID is `com.sstock.Trim`. Each install over an existing one keeps the same app container, so `Documents/trim.json` opens unchanged. A build with a different bundle ID installs as a separate app with no data.

### Why not AltStore

AltStore doesn't work for Trim. It re-signs apps under a new App ID (`com.sstock.Trim.<TEAMID>`) and only enables the App Groups and Inter-App Audio capabilities on it (`updateFeatures` in AltStore's `FetchProvisioningProfilesOperation.swift`; `ALTCapabilities.m` in AltSign). HealthKit is never enabled, so every Health call fails, and the new App ID installs as a separate app with no data. Installs from the phone also failed with "The data couldn't be read because it isn't in the correct format" (NSCocoaErrorDomain 3840), because Apple's GrandSlam sign-in endpoint returned an HTML 503 page that AltStore tried to parse as a property list (altstoreio/AltStore#1699, #1776).

## Android

Download `Trim.apk` from the latest release (or a workflow run) on the phone and open it. Android asks once to allow installs from that source. Updates install over the old version and keep data as long as they're signed with the same key.

Without a keystore, the release APK is signed with the CI runner's debug key. GitHub's runners don't keep that key between runs, so an update may refuse to install over the previous one ("App not installed" or "package conflicts"). If that happens, export your data first (Settings, Export CSV), uninstall, and install the new APK.

To avoid that, give CI a release keystore. Make one once (the JDK's `keytool` comes with Android Studio):

```bash
keytool -genkey -v -keystore trim-release.jks -keyalg RSA -keysize 2048 -validity 10000 -alias trim
```

Then add three repository secrets: `ANDROID_KEYSTORE_BASE64` (the file, base64-encoded), `ANDROID_KEYSTORE_PASSWORD` and `ANDROID_KEY_ALIAS` (`trim`). The workflow writes `android/key.properties` from them, and `android/app/build.gradle.kts` signs with it. Keep the `.jks` file somewhere safe outside the repository: losing it means the next APK can't update the installed app. Locally, put the same `key.properties` next to `android/release.jks` to sign release builds the same way.

Health Connect is built into Android 14 and later. On Android 9 to 13, install Health Connect from the Play Store; Trim offers to open it when you connect.

## Moving data between installs

Data is one file, `trim.json`, in the app's Documents folder. On iPhone it's visible in the Files app under On My iPhone, Trim, because `UIFileSharingEnabled` is on. To move it, copy it into the new install's folder, then force-quit and reopen the app. API keys are in secure storage, not the JSON, so re-enter them in Settings. Settings, Export CSV makes a read-only backup on either platform.
