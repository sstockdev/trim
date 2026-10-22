# Trim

A personal food log and weight-loss coach for iPhone and Android, written in Flutter.

Trim sets calorie, protein, fat, fibre and step targets from published formulas. After about three weeks of logging and weigh-ins, it recalculates maintenance from what was actually eaten and how the weight trend moved. [docs/PROGRAM.md](docs/PROGRAM.md) has the math and the sources.

Food comes from USDA search, barcode scanning and quick add. Plugins, installed from Settings, add more: Nutritionix search and describing a meal in words, Open Food Facts barcodes, and the daily menus at NDSU's Union Market, Residence and West Dining Centers and Twisted Taco with their nutrition labels. Favourites, recents and copying a meal from yesterday make repeat meals fast. Steps, active energy, sleep, resting heart rate, workouts and smart-scale weigh-ins come from Apple Health on iPhone or Health Connect on Android, from whatever watch, scale or app writes there. A weekly check-in asks about waist, hunger, energy and adherence, reviews the week and updates the maintenance estimate.

Everything stays on the phone in one JSON file. There's no server and no account.

Trim is not medical advice. It holds targets at maintenance for people under 18, pregnant or breastfeeding, or under a BMI of 18.5, and warns about some medical conditions ([docs/PROGRAM.md](docs/PROGRAM.md#safety-warnings-apprepositorytrendalerts)), but it doesn't replace a doctor or dietitian.

## Quick start

GitHub Actions builds the app on every push to `main`: `Trim.apk` on Ubuntu and `Trim.ipa` on macOS. Pushing a `v*` tag also attaches both files to a GitHub Release.

On Android, download `Trim.apk` from a release and open it on the phone. On iPhone, install `Trim.ipa` with [xtool](https://github.com/xtool-org/xtool) and an Apple ID. With a free Apple ID the install stops opening after 7 days and has to be installed again. [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md) covers both.

To work on the code you need the Flutter SDK. `flutter test` and `flutter analyze` run anywhere; `flutter run` needs a connected Android phone or emulator, or a Mac for iOS. [docs/SETUP.md](docs/SETUP.md) covers the toolchain.

On first launch the app walks through a 9-step onboarding, which asks for a free USDA key from https://api.data.gov/signup/ for food search. Install plugins and enter their keys in Settings, Plugins. For watch data, turn on sharing with Apple Health or Health Connect in the watch's own app.

## Docs

| Doc | For |
|---|---|
| [docs/SETUP.md](docs/SETUP.md) | Installing Flutter, the Android tools, and xtool for iPhone installs |
| [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md) | CI builds, installing the IPA and APK, Android signing, moving data between installs |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | How the code is organised: state, persistence, data model, screens, conventions |
| [docs/PROGRAM.md](docs/PROGRAM.md) | The weight-loss math, the reasoning behind each number, and sources |
| [docs/INTEGRATIONS.md](docs/INTEGRATIONS.md) | NDSU Dining menus (Jamix scraping), food search APIs, Apple Health and Health Connect |
| [docs/DEBUGGING.md](docs/DEBUGGING.md) | Device logs, the data file, tests, the scraper off-device |
| [ROADMAP.md](ROADMAP.md) | Known issues, what hasn't been verified, and ideas |

## Repository layout

```
pubspec.yaml         Flutter package (name: trim) and dependencies
lib/                 All app code: domain/ (plan math, models), data/ (repository, services), plugins/, ui/
test/                Unit and widget tests
android/             Android app (applicationId com.sstock.trim, Health Connect permissions)
ios/                 iOS app (bundle ID com.sstock.Trim, HealthKit entitlement in Runner/Runner.entitlements)
Resources/           AppIcon.png and the script that draws it (trim_icon.py)
.github/workflows/   build.yml: tests, then the APK and IPA, then a release for v* tags
docs/                Engineering docs
```

## License

MIT. See [LICENSE](LICENSE).
