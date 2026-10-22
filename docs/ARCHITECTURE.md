# Architecture

Trim is a single Flutter app for iOS and Android. There's no server and no database: one repository holds all state and saves it as JSON. Network calls go to USDA FoodData Central and to whatever installed plugins use (Nutritionix, Open Food Facts, NDSU Dining's menu site), and nowhere else.

The code follows Flutter's recommended layering (the flutter/skills `flutter-apply-architecture-best-practices` skill): services that wrap the outside world, a repository that is the single source of truth, pure domain logic, and screens split by feature with a ViewModel where a screen has real work to do.

```
 ui/features/<feature>/views       Flutter widgets. Read state, call methods, no I/O.
            │      ▲
            ▼      │ notifyListeners
 ui/features/<feature>/view_models Screen state and async work (search, check-in, onboarding, …)
            │
            ▼
 data/repositories/AppRepository   AppData (everything in trim.json) + derived values; applies Health syncs
            │                 │
            ▼                 ▼
 domain/plan.dart        data/services/                                        plugins/
 (pure Dart math)        DataFileService · KeyService · UsdaService · HealthService   PluginRegistry, a folder each
                                │               │              │             │                │
                           trim.json      Keychain or      USDA FDC    Apple Health or   Nutritionix, Open Food Facts,
                                          Keystore                     Health Connect    NDSU Dining (Jamix)
```

`main.dart` creates the services, the repository, the plugins and the `PluginRegistry`, and provides them with `provider`. Nothing is a global singleton, so tests can build any piece with stand-ins.

## Layers

### Services (`lib/data/services/`)

Each service wraps one outside thing and holds no app state:

| Service | Wraps |
|---|---|
| `DataFileService` | `trim.json` in the app's Documents folder. Parses it on a background isolate with `compute`, keeps an unreadable file aside, and writes atomically (temporary file, then rename) |
| `KeyService` | `flutter_secure_storage` (the iOS Keychain or the Android Keystore) for `usda.key` and every plugin's fields, cached in memory after launch |
| `UsdaService` | USDA FoodData Central over an injected `http.Client`: search, barcodes (a Branded search matched on `gtinUpc`) and checking a key. Throws `FoodError` on failures rather than returning null. The same file has the JSON helpers plugins share (`jsonOf`, `listOf`, `parseNum`) |
| `HealthService` | The `health` plugin. `fetch()` returns a `HealthSnapshot` (activity by day and smart-scale weigh-ins); it never writes into app state |

### Repository (`lib/data/repositories/app_repository.dart`)

`AppRepository` is a `ChangeNotifier` with one `AppData data`. Screens read it with `context.watch<AppRepository>()` (or `context.select` for a single value) and change it through its methods.

Any change to `data` ends with `changed()`, or goes through `update((d) => ...)`, which calls it. `changed()` drops the cached values (entries by day, the trend line), notifies listeners, and schedules a save 0.4 s later, so a burst of edits is one write. `saveNow()` also runs when the app goes to the background.

The repository also owns the derived values the program needs (`targets`, `calorieTarget()`, `weekReview()`, `trendAlerts`, `warnings`, `updateMaintenanceIfDue()`), the dining hall cache, and Health: `connectHealth()`, `syncHealth()` (applies a `HealthSnapshot`), and `recordWeighIn()` (saves a weigh-in and copies it to Health when that's on).

If decoding fails at launch, the bad file is copied to `trim-unreadable-<unix time>.json` and the app starts empty rather than overwriting the user's history. `HomePage` shows an alert naming the copy (`AppRepository.unreadableBackup`). If the copy can't be written, `saveBlocked` stops all saving for that session.

On iOS, `UIFileSharingEnabled` is on, so the data file shows up in the Files app under On My iPhone, Trim. That's also how data moves between installs (see [DEPLOYMENT.md](DEPLOYMENT.md)).

### Plugins (`lib/plugins/`)

The core app searches USDA and reads Apple Health or Health Connect. Everything else is a plugin: a `TrimPlugin` subclass in its own folder, compiled into the app (iOS doesn't allow downloading code). Installing one from Settings, Plugins adds its id to `AppData.plugins` and shows its `fields`, which are saved in `KeyService`. A plugin is active once it's installed and every required field is filled in.

A plugin can add any of these, and screens ask `PluginRegistry` for them instead of knowing about any plugin:

| Hook | Used by |
|---|---|
| `foodSearch` | Add food. The first active one replaces USDA search; its `SearchGroup`s become sections with a filter button each |
| `addFoodLinks` | Rows at the top of Add food that open the plugin's own pages |
| `barcode()` | `ScanPage`. Active plugins are asked in order, then USDA |
| `todaySection()` | A section on the Today tab, above the meals |
| `settingsRows()` | Extra rows on the plugin's page in Settings |

| Plugin | What it adds |
|---|---|
| `nutritionix/` | Search as you type in Common and Branded groups, `DescribeMealPage`, barcodes. Needs an app ID and key |
| `open_food_facts/` | Barcodes only, no key |
| `ndsu_dining/` | `JamixService` and its script, `DiningMenuPage` with `DiningMenuViewModel` (hall picker, menu, cached labels, the background prefetch loop), `DiningUsuals` on Today, and clearing the label cache |

Files from before plugins have no `plugins` key. On first launch `PluginRegistry` installs what that user was already using: NDSU Dining if there are cached menus or dining foods, Nutritionix if its keys are saved, and Open Food Facts, which used to handle every barcode. A new user starts with none.

To add a plugin, subclass `TrimPlugin` with a new, permanent `id`, add it to the list in `main.dart`, and keep its code inside its folder.

### Domain (`lib/domain/`)

`plan.dart` is the program: pure Dart with no Flutter imports. `models.dart` is the data in `trim.json`. `format.dart` has `Day` (local calendar-day keys and arithmetic that daylight-saving changes don't shift) and `Fmt` (units and number formatting). The math and the reasons for it are in [PROGRAM.md](PROGRAM.md).

### UI (`lib/ui/`)

`core/` has the theme (`TrimColors`, `TrimTheme`), the shared widgets (`Section` for an inset grouped list section, `GoalBar`, `CalorieRing`, `RatingPicker`, `NumberField`, `FoodRow`, picker and switch rows, `showToast` with Undo), and `ViewModel`, the base class that drops notifications after dispose so a slow request can't throw on a closed screen.

Each feature folder has `views/` and, where needed, `view_models/`. A view creates its ViewModel with `ChangeNotifierProvider(create: ...)`, passing in what it needs from the providers above it. Screens that only show repository state and change it with one call (Today, Trends, Settings, the guide) watch the repository directly, and short-lived form state (quick add, the weigh-in sheet) stays in the widget's `State`.

| Feature | Screens and ViewModels |
|---|---|
| `home` | `HomePage`: onboarding until `onboarded`, then four tabs (Today, Trends, Check-in with a badge when due, Settings). On resume it syncs Health and may update maintenance |
| `onboarding` | `OnboardingPage` with `OnboardingViewModel`: 9 steps, including the USDA key, then the computed targets and saving the plan |
| `today` | `TodayPage`: day navigation, calorie ring and macro bars, alerts, check-in prompt, `WeighInSheet`, plugin sections, the four meals, activity, hunger, energy, water and the log-complete flag |
| `add_food` | `AddFoodPage` with `AddFoodViewModel` (Your foods, then USDA or a plugin's search groups); `FoodDetailPage` with `FoodDetailViewModel` (amount and measure, which keeps the same quantity when switching, log or edit); `ScanPage` with `ScanViewModel`; `QuickAddPage` |
| `trends` | `TrendsPage`: `fl_chart` charts for weight (dots, trend line and goal), calories, protein, steps, sleep, waist and maintenance history |
| `check_in` | `CheckInPage` with `CheckInViewModel`: the weekly review, questions, maintenance update and feedback, and past check-ins |
| `settings` | `SettingsPage`, `WeightHistoryPage`, `GuidePage`, `UsdaKeySection` with `UsdaKeyViewModel` (also used in onboarding), and `PluginsPage` and `PluginPage` for installing and setting up plugins |

## The file format

`trim.json` has the same shape the Swift version of the app wrote: the same keys, enum names as strings, and dates as ISO 8601 in UTC with whole seconds (`2026-10-20T15:08:09Z`, from `encodeDate`). A file written by either version opens in the other. `test/models_test.dart` checks this against a sample written by the Swift app.

Every model's `fromJson` reads each field with a default, so adding a field is always safe: old files load and the new field gets its default. Don't rename or retype a field; add a new one and migrate in `fromJson`. Unknown enum values fall back to a default (an unknown `FoodSource` becomes `custom`). Optional fields are left out of the JSON when null, as Swift did.

| Type | What it is |
|---|---|
| `AppData` | Root: `profile`, `entries`, `saved`, `weights`, `waists`, `notes` (by day key), `activity` (by day key), `checkIns`, `market` (dining labels by `MarketItem.key`), `menus` (by `MarketMenu.key`), `diningHall` (the hall opened last), `onboarded`, `dismissedHealthWeights` |
| `Profile` | Body stats, goal, pace, activity level, diet, safety screening, `maintenance` (current kcal estimate) and when it last updated, maintenance-break end date, and the switches `eatBackExercise`, `useHealth`, `writeWeightToHealth`, `metric` |
| `Nutrients` | calories, protein, carbs, fat, fiber, sugar, sodium (mg), saturated fat; `scaled()` |
| `FoodItem` | A food: `base` nutrients for one base amount, plus `servings`. `key` identifies the same food across entries and saved foods |
| `Serving` | A measure (`"cup"`, `"100 g"`, `"portion (271 g)"`). `perUnit` is how many base amounts one unit is, so any measure scales the same base. `Serving.weightOptions()` adds g and oz when the gram weight is known |
| `FoodEntry` | One logged food: date and time, `Meal`, a full copy of the `FoodItem` (so later edits to saved foods don't rewrite history), serving index and amount |
| `SavedFood` | Recents, favourites and dining usuals: an item, last serving and amount, use count, `favorite` |
| `WeightEntry`, `WaistEntry` | Stored in kg and cm; at most one weight per day (`setWeight` replaces) |
| `DayNote` | Hunger, energy, water, and `complete` (`bool?`), the "food log complete" flag that decides whether a day counts for the maintenance estimate |
| `DayActivity` | Per-day Health data: steps, active and resting kcal, resting HR, sleep hours, workouts, strength sessions and minutes, cardio minutes |
| `CheckIn` | Weekly answers plus the maintenance estimate before and after |
| `DiningHall`, `MarketItem`, `MarketMenu` | An NDSU dining hall (title, menu URL, food source), a hall's nutrition label (per portion, with grams), and a hall's menu for a day (tabs, stations, items) |

Weights are stored in kg, lengths in cm and energy in kcal. Convert only at the edges, in `Fmt` and the number fields.

## When maintenance updates

At the weekly check-in (at most once every 6 days), and also when the app comes to the foreground if there's been no check-in for 10 or more days, so the estimate keeps learning when check-ins are skipped.

## Platform projects

`ios/Runner/Info.plist` has the display name, the Health and camera usage strings, and Files-app sharing. `ios/Runner/Runner.entitlements` has HealthKit and is wired into the Xcode project with `CODE_SIGN_ENTITLEMENTS`. The bundle ID is `com.sstock.Trim` and the deployment target is iOS 16.

`android/app/src/main/AndroidManifest.xml` has the internet, camera and Health Connect permissions, the permissions-rationale intent filter Health Connect requires, and the query for the Health Connect package. `MainActivity` extends `FlutterFragmentActivity`, which the health plugin needs. The application ID is `com.sstock.trim` and `minSdk` is 26. `android/app/build.gradle.kts` signs release builds with `android/key.properties` when it exists.

## Conventions

- Run `flutter analyze` (strict casts, inference and raw types are on) and `dart format lib test` before committing.
- Services don't hold app state and don't call the repository; the repository and ViewModels call services.
- New persisted fields: add them to the model with a default in `fromJson` and to `toJson`.
- New program constants go in `plan.dart` with a comment citing the source. Add the explanation to `guide_page.dart` if the user would care.
- Screens read derived values from repository getters rather than recomputing them.
- Short doc comments that explain why, plain-English UI copy, no `!` on data from the network.
- The bundle ID `com.sstock.Trim` and the application ID `com.sstock.trim` must not change. A new ID is a separate app with an empty data folder.
