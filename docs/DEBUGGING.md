# Debugging and testing

## Tests

```bash
flutter test
```

`test/plan_test.dart` covers the program math: BMR, the trend line, targets and their caps and floors, the adaptive maintenance estimate, safety warnings and formatting. `test/models_test.dart` loads a `trim.json` in the shape the Swift version of the app wrote, checks a round trip and the fallbacks for missing fields, and exercises the repository (counted intake, logging, favourites, CSV), older dining hall caches, and the Jamix number parsing. `test/widget_test.dart` pumps the onboarding flow and the Today tab with sample data, and checks that a file from before plugins keeps the plugins it was using. CI runs all three, plus `flutter analyze`, before building.

On Windows, `flutter test` can fail with "'C:\Users\…' is not recognized" when the Flutter SDK, the pub cache or the project sits under a path with a space in it. The error comes from compiling native-asset build hooks. Map each of those folders to a drive letter with `subst`, point `PUB_CACHE` at the mapped pub cache, and run `flutter test` from the mapped project folder. `flutter analyze` isn't affected.

To check `adaptiveTDEE` against a scenario, add a test that builds fake days and weigh-ins, as `test/plan_test.dart` does.

## Device logs

On Android, `flutter run` prints the app's logs, and `adb logcat` works for an installed release build.

On iPhone, `idevicesyslog` from libimobiledevice streams the device log. Flutter apps log under the process name `Runner`:

```bash
idevicesyslog -p Runner
```

Crash reports come from `idevicecrashreport -k <dir>`; an `.ips` file is a JSON header line followed by a JSON body.

`debugPrint` messages from the app start with `Trim:`. Every dining menu read logs a `Trim: Jamix` line with its hall, arguments, how long it waited behind other reads, and how long it ran.

## The data file

On iPhone, `trim.json` is in the Files app under On My iPhone, Trim: AirDrop it to the PC or open it there. On Android it's in the app's private storage, so use Settings, Export CSV, or `adb shell run-as com.sstock.trim cat app_flutter/trim.json` on a debug build. The format is plain JSON with ISO 8601 dates (see [ARCHITECTURE.md](ARCHITECTURE.md)). If it ever fails to load, the app keeps the file as `trim-unreadable-<time>.json` next to it, starts over with an empty `trim.json`, and names the kept file in an alert at launch.

Settings, Export CSV writes the food log, weights and daily activity as CSV and opens the share sheet.

## Testing the dining menu script

The scraper is plain JavaScript and runs the same in any browser. See "Testing changes to the script" in [INTEGRATIONS.md](INTEGRATIONS.md). Test at phone width (390 px) too: the page is responsive, and the app's web view is phone-sized.

## Testing food APIs

Use curl with the same URLs the app builds, for example:

```bash
curl -s "https://api.nal.usda.gov/fdc/v1/foods/search?api_key=DEMO_KEY&query=pear&pageSize=5&dataType=Foundation%2CSR+Legacy%2CSurvey+%28FNDDS%29%2CBranded"
```

## Common problems

| Symptom | Cause |
|---|---|
| iPhone app won't open, "no longer available" | The free-account signature expired after 7 days. Run `xtool install` again ([DEPLOYMENT.md](DEPLOYMENT.md)). Data is kept |
| Health stays empty on iPhone after a reinstall | The IPA was installed without the HealthKit entitlement. Check the "Package Trim.ipa" step of the build log prints `com.apple.developer.healthkit` |
| Android update says "App not installed" | The new APK was signed with a different key. See the Android section of [DEPLOYMENT.md](DEPLOYMENT.md) |
| Search shows "returned an error (400)" | A query URL encoded in a form USDA rejects (see [INTEGRATIONS.md](INTEGRATIONS.md#usda-fooddata-central-libdataservicesusda_servicedart-the-core-app)). Build it with `Uri.https(host, path, params)` |
| Search says a key wasn't accepted | A wrong or expired USDA key (Settings, Food search) or Nutritionix keys (the plugin's page), giving 401 or 403 |
| No steps or sleep | The watch's app isn't sharing with Apple Health or Health Connect, or access was denied. On iPhone check Settings, Health, Data Access & Devices, Trim; on Android check Health Connect, App permissions |
| Dining menu "Couldn't load the menu" | No network, or the site's markup changed. Try the script in a browser first |
