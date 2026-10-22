# Integrations

## NDSU Dining menus (Jamix)

This is the NDSU Dining plugin, in `lib/plugins/ndsu_dining/`: `data/jamix_service.dart` and `data/jamix_script.dart`, the menu page, `DiningMenuViewModel` (which runs the prefetch and the hall picker) and the Dining usuals section on Today.

Each hall is a Jamix kitchen of customer 99035, listed in `DiningHall` in `lib/domain/models.dart`:

| Hall | Page |
|---|---|
| Union Market | https://usa.jamix.cloud/menu/?anro=99035&k=10 |
| Residence Dining Center | https://usa.jamix.cloud/menu/?anro=99035&k=9&mt=3 (`k=9` alone opens a "Select menu" page, and its one menu is `mt=3`) |
| West Dining Center | https://usa.jamix.cloud/menu/?anro=99035&k=8 |
| Twisted Taco | https://usa.jamix.cloud/menu/?anro=99035&k=15 |

All four use the same page layout, so one script reads them all. The residence halls have Breakfast, Lunch and Dinner tabs (West also has Late Night) plus an "eMenu" tab of always-available stations. Twisted Taco has one menu and no tabs, so its stations sit on the home page and the script reads them as one unnamed tab. It's a Vaadin web app: the browser holds a server session and every click is a round trip, so there's no HTML or JSON to fetch. Jamix's REST endpoint (`/menuservice/rest/haku/menu/99035/10`) returns an empty list for these kitchens, so the app drives the real page:

1. `JamixService` starts a `HeadlessInAppWebView` from `flutter_inappwebview`, 390×844 so the page lays out like a phone. On iOS the plugin puts the web view behind the app's content in the key window, which matters because WebKit throttles timers in views that aren't in a window and the script depends on timers.
2. `jamixScript` is injected as a user script at document end. It defines `window.wl`.
3. Dart calls it with `callAsyncJavaScript`, and it returns a JSON string.

### The script (`window.wl`)

`home()` clicks View menus on the first visit, which accepts the site's terms of use. It then waits for the home page, the only page with day buttons, and briefly for its stations.

`goTo(iso)` steps the day buttons until the date label (for example "Tue, October 20, 2026") matches. The page remembers the last day shown.

`openTab(i)` opens a tab. Tabs are meals and venues ("Breakfast Fall 2026 Cycle", "Lunch …", "Dinner …", "Greens/Grains …", "Deli …", "Grille …", "Fall 2026 eMenu"). Tabs scrolled out of view need real mouse events (`press`), because `click()` doesn't select them.

`menu(iso)` reads every tab's stations, item names and diet tags, with no nutrition.

`station(iso, tab, station, {only, skip, background})` opens a station and reads each item's Nutritive values page, one round trip to the server per page. There are two layouts. Some stations list their products, and each product has its own Nutritive values page (product, Nutritive values, read, back, back). Others go straight to Nutritive values, which shows the station total plus one `.nutrition` button per item. `only` reads just the tapped item (names match loosely), and `skip` leaves out items that are already cached. If `wl.abort` is set during a `background` read, the read stops after its current item and returns `{items, aborted: true}`.

`readLabel()` reads the `.nv-list li` rows into `{fact: value}` plus the portion text (for example "Nutritive values (271 g)"). Fact names are `Calories`, `Total Fat`, `of which saturates`, `Total Carbohydrate`, `of which sugars`, `Fibre`, `Protein` and `Sodium` (mg). Values are per portion; `JamixService.grams()` gets the portion weight from the "(… g)" text.

### Client behaviour

One script job runs at a time, and the one web view loads the job's hall when it isn't already showing it. A finished load from a page that was replaced by a hall switch is ignored. Taps and menu loads are urgent and go to the front of the queue; if a background read is running, an urgent job first sets `wl.abort = true`. A background read that is still loading its page has no `wl` yet, so `JamixService` remembers the abort and sets it once the page is ready. A failed call reloads the page and tries once more, which covers an expired Vaadin session.

After the menu shows, `prefetch` reads the current tab's stations in the background, skipping cached items, so most taps are instant. An interrupted station resumes where it stopped. Leaving the menu screen or switching halls cancels the prefetch. The hall picker remembers the last hall in `AppData.diningHall`.

Labels go in `AppData.market` under `MarketItem.key(name, hall)`, and menus go in `AppData.menus` under `MarketMenu.key(day, hall)`, kept for 14 days and fetched again after 6 hours. Union Market's keys are the bare lower-cased name or day, as they were before there were other halls; the others start with the hall (`west|…`, `residence|…`). These are the keys the Swift app wrote. Halls are cached separately because their portions can differ. `AppRepository.saveMarket(items, hall, menuNames:)` also files a label under the menu's spelling when the label page names it slightly differently, and saving a label updates saved foods from the same hall with the same name, so recipe changes reach the usuals.

Each hall logs foods with its own `FoodSource` (`unionMarket`, `residenceDining`, `westDining`, `twistedTaco`, all titled "NDSU Dining") and the hall's name as the brand. Usuals on the menu screen are filtered to the open hall; the Today tab shows all of them and names the hall on each card when there's more than one.

The first open of the day waits for the page load plus the menu read. Tapping an uncached item waits for its label page; a cached one opens without touching the network.

### Testing changes to the script

Open the menu page in any browser, paste the contents of `jamixScript` into the console, then:

```js
await wl.menu("2026-10-20")
await wl.station("2026-10-20", 0, 0)
await wl.station("2026-10-20", 2, 2, { only: ["French Dressing"] })
```

If the site's markup changes, the selectors to check are `.v-tabsheet-tabitem`, `.v-button-product-list-group`, `.multiline-button-caption-text`, `.menu-item .item-name`, `.v-button-product`, `.nutrition`, `.nv-list li`, `.date--next` and `.date--previous`, `.navigation--previous` and `.navigation--home`, `.v-label-sub-caption`, and the loading indicator `.v-loading-indicator`.

## Food search

### USDA FoodData Central (`lib/data/services/usda_service.dart`, the core app)

`GET https://api.nal.usda.gov/fdc/v1/foods/search?api_key=…&query=…&pageSize=30&dataType=Foundation,SR Legacy,Survey (FNDDS),Branded`. Nutrients are per 100 g, except branded foods, which have a serving size. Onboarding asks for a personal key from https://api.data.gov/signup/ and checks it with a one-result search. With the shared `DEMO_KEY` the app searches only on submit, because of rate limits; with a personal key it searches as you type.

When no plugin knows a barcode, the app asks USDA: a Branded search for the digits, keeping the result whose `gtinUpc` matches once leading zeros are dropped.

USDA's server answers some encodings of the data type list with a 400: `Survey%20%28FNDDS%29` and `Survey%20(FNDDS)` fail, while `Survey+%28FNDDS%29`, the form Dart's `Uri.https(host, path, params)` produces, works. Build USDA URLs with `Uri.https` rather than string concatenation.

### Nutritionix plugin (`lib/plugins/nutritionix/`, needs the user's own keys)

The plugin uses Nutritionix's v2 API:

| Step | Endpoint |
|---|---|
| Search as you type | `GET v2/search/instant?query=…&detailed=true`, giving `common` (generic foods, deduplicated by `tag_id`) and `branded` (packaged and restaurant) |
| Open a common food | `POST v2/natural/nutrients` with `{query: food_name}` |
| Describe a meal | `POST v2/natural/nutrients` with the user's sentence; returns one food per item |
| Open a branded food | `GET v2/search/item?nix_item_id=…` |
| Barcode | `GET v2/search/item?upc=…` |

The base URL is `https://trackapi.nutritionix.com/`, with the headers `x-app-id`, `x-app-key` and `x-remote-user-id: 0`. `alt_measures` become extra `Serving`s.

Nutritionix ended its free public API tier, so the user has to supply their own app ID and key on the plugin's page in Settings, Plugins.

### Open Food Facts plugin (`lib/plugins/open_food_facts/`, barcodes)

`GET https://world.openfoodfacts.org/api/v2/product/<code>.json`, with a descriptive `User-Agent`. Nutrients are per 100 g, plus `serving_quantity` when present. A scan asks each active plugin in the order they're listed in `main.dart` (Nutritionix before Open Food Facts), then USDA. A scanner may report a UPC-A as a 13-digit EAN with a leading 0, so both forms are tried.

### Error mapping

401 and 403 mean the key was rejected (each source has its own message), 404 means not found, 429 means the limit was reached, and anything else shows "returned an error (code)".

## Apple Health and Health Connect (`lib/data/services/health_service.dart`)

Trim reads activity from the phone's health store through the `health` package and never talks to a watch or its maker directly. Any watch, scale or app that shares its data with Apple Health or Health Connect shows up, as long as sharing is turned on in that app.

Trim reads steps, active energy, resting energy, resting heart rate, sleep, workouts and body weight, and writes body weight only when "Save weigh-ins" is on. On iOS resting energy is HealthKit's basal energy. Health Connect has no basal energy samples, so on Android resting is total calories burned minus active.

`AppRepository.syncHealth()` runs whenever the app comes to the foreground. It calls `HealthService.fetch(days: 28)`, which reads one `DayActivity` per day, and applies the result:

- Steps use the platform's own daily total (`getTotalStepsInInterval`), which already removes the overlap when a watch and the phone both count the same walk.
- Active and resting energy are summed per source, and each day takes the source with the biggest total rather than adding sources together.
- Resting heart rate is a daily average.
- Sleep merges the asleep stages across sources, so a watch and a phone don't double-count, and credits them to the wake-up day.
- Workouts are split into strength (strength training, weightlifting, core, cross training) and cardio minutes.

Smart-scale weights from the last 90 days are imported from any source except Trim itself, with the first weigh-in of each day winning. Weights the user deleted are remembered in `dismissedHealthWeights` so a sync doesn't bring them back.

`averageTotalBurn` gives the 14-day average of resting plus active energy, used for the starting maintenance estimate.

On iOS the HealthKit entitlement is in `ios/Runner/Runner.entitlements`. A free Apple ID can sign HealthKit apps through xtool, but App Groups and some other entitlements aren't available on free accounts. On Android the Health Connect permissions are in `AndroidManifest.xml`, and the app asks for them when you turn Health on.
