# Roadmap and known issues

## Status (October 2026)

Trim started as a SwiftUI app and was rewritten in Flutter to run on Android too. The Flutter version reads the same data file and keeps the same screens and program. On an iPhone it has been checked to open a `trim.json` written by the Swift version with all history, read steps from Apple Health, and load menus and labels from Union Market, Residence and West, including taps that wait behind a background read.

Not yet verified on a device with the Flutter build:

- Everything on Android, including Health Connect permissions and watch data arriving through it.
- The plugin system (v1.1.0): installing and setting up plugins, the migration of an existing trim.json, the USDA key check in onboarding, and USDA barcode lookups.
- Switching halls while a read is running.
- Union Market on Android, and the harder paths on iPhone: timers, the `wl.abort` handoff when a tap preempts a background read, and retry after an expired session.
- Barcode scanning with `mobile_scanner`.

Never verified in either version:

- Apple Health sync with real watch data beyond steps: sleep merging across sources, workouts, smart-scale import, writing weights back.
- The Nutritionix plugin: search, describe-a-meal and barcodes. The code hasn't run against the live API.
- The adaptive maintenance update with real data (first possible about 3 weeks after onboarding). The math has only been checked on simulated data.
- The weekly check-in flow end to end.

## Known issues and limitations

Nutritionix needs paid keys, since the free tier is gone, so the core app searches USDA, which is good for generic foods and thin on restaurants. A possible addition is a FatSecret Platform API plugin implementing `FoodSearch`. FatSecret's free Basic edition includes food search; barcode lookups need its Premier Free edition.

The NDSU Dining plugin depends on Jamix's markup. A redesign of usa.jamix.cloud can break the scraper (see the selector list in [docs/INTEGRATIONS.md](docs/INTEGRATIONS.md)). Errors are shown, and the rest of the app keeps working.

Dining hall labels are cached forever by hall and name. A recipe change is picked up only when that station is read again, which happens only for items that aren't cached. Expiring labels after about 30 days would fix it.

Until the ANDROID_KEYSTORE_* secrets are set, the Android APK is signed with the CI runner's debug key, which changes between runs, so updates can refuse to install over each other (see [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md)).

`flutter_inappwebview` is on 6.2.0-beta.3. The stable 6.1.5 release still calls `getDefaultProguardFile('proguard-android.txt')`, which the Android Gradle Plugin 9 refuses, so the APK won't build with it. Move back to a stable release once one ships with the fix.

A free Apple ID limits the iPhone install to a 7-day signature, 3 apps and 10 App IDs.

All data is one JSON file, rewritten on every change (debounced). That's fine for years of personal data. If it ever gets slow, move `market` and `menus`, which are caches, into a separate file.

There are unit tests for the math, the data format and the repository, and widget tests for onboarding and the Today tab, but no integration tests on a device.

## Ideas

- Expire cached dining labels and show when a label was read.
- A "usuals by time of day" list on the Today tab (breakfast items in the morning).
- Meal templates: log a saved group of foods in one tap.
- Import past intake from Apple Health or Health Connect if another app logged it.
- A Home Screen widget with calories left. On iPhone that needs App Groups, so a paid developer account.
- A FatSecret (or other free) search plugin.
