import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:trim/data/repositories/app_repository.dart';
import 'package:trim/data/services/data_file_service.dart';
import 'package:trim/data/services/health_service.dart';
import 'package:trim/plugins/ndsu_dining/data/jamix_service.dart';
import 'package:trim/domain/format.dart';
import 'package:trim/domain/models.dart';
import 'package:trim/domain/plan.dart';

/// A trim.json in the shape the Swift app wrote (JSONEncoder, .iso8601 dates, sorted keys, nil fields left out).
const swiftJson = '''
{"activity":{"2026-10-18":{"activeKcal":512.5,"cardioMinutes":30,"restingKcal":1800,"sleepHours":7.2,"steps":9120,"strengthMinutes":45,"strengthSessions":1,"workouts":["Strength","Walk"]}},
"checkIns":[{"cardioMinutes":0,"date":"2026-10-12T14:00:00Z","feedback":["Solid week."],"id":"0F8FAD5B-D9CB-469F-A165-70867728950E","loggedDays":6,"maintenanceAfter":2650,"maintenanceBefore":2600,"note":"","strengthSessions":2}],
"dismissedHealthWeights":["1760000000|88.20"],
"entries":[{"amount":1.5,"date":"2026-10-19T17:30:00Z","id":"7C9E6679-7425-40DE-944B-E07FC1F90AE7","item":{"base":{"calories":200,"carbs":10,"fat":5,"fiber":2,"protein":30,"saturatedFat":1,"sodium":300,"sugar":3},"brand":"Union Market","externalID":"Grill","name":"Grilled Chicken","servings":[{"defaultAmount":1,"grams":120,"name":"portion (120 g)","perUnit":1},{"defaultAmount":120,"grams":1,"name":"g","perUnit":0.008333}],"source":"unionMarket"},"meal":"lunch","serving":0}],
"market":{"grilled chicken":{"fetched":"2026-10-19T17:00:00Z","name":"Grilled Chicken","nutrients":{"calories":200,"carbs":10,"fat":5,"fiber":2,"protein":30,"saturatedFat":1,"sodium":300,"sugar":3},"portion":"4.2 oz (120 g)","portionGrams":120,"station":"Grill"}},
"menus":{},
"notes":{"2026-10-19":{"complete":true,"hunger":3,"note":"","water":4}},
"onboarded":true,
"profile":{"activity":"light","birthDate":"2000-05-01T05:00:00Z","diet":"anything","eatBackExercise":false,"goalKg":80,"heightCm":180,"maintenance":2650,"maintenanceUpdated":"2026-10-12T14:00:00Z","metric":false,"pace":"steady","planStart":"2026-09-01T05:00:00Z","screening":{"diabetesMedication":false,"eatingDisorderHistory":false,"glp1Medication":false,"kidneyDisease":false,"pregnantOrBreastfeeding":false},"sex":"male","startWeightKg":92,"strength":"none","useHealth":true,"writeWeightToHealth":true},
"saved":[{"amount":1,"favorite":true,"item":{"base":{"calories":200,"carbs":10,"fat":5,"fiber":2,"protein":30,"saturatedFat":1,"sodium":300,"sugar":3},"brand":"Union Market","externalID":"Grill","name":"Grilled Chicken","servings":[{"defaultAmount":1,"grams":120,"name":"portion (120 g)","perUnit":1}],"source":"unionMarket"},"lastUsed":"2026-10-19T17:30:00Z","serving":0,"uses":3}],
"waists":[{"cm":95.5,"date":"2026-10-12T14:00:00Z","id":"A1B2C3D4-0000-4000-8000-000000000001"}],
"weights":[{"date":"2026-10-19T12:00:00Z","fromHealth":false,"id":"B1B2C3D4-0000-4000-8000-000000000002","kg":88.4}]}
''';

void main() {
  test('reads a trim.json written by the Swift app', () {
    final d = AppData.fromJson(jsonDecode(swiftJson));
    expect(d.onboarded, isTrue);
    expect(d.profile.sex, Sex.male);
    expect(d.profile.pace, Pace.steady);
    expect(d.profile.maintenanceUpdated!.toUtc(), DateTime.utc(2026, 10, 12, 14));
    expect(d.entries.single.item.source, FoodSource.unionMarket);
    expect(d.entries.single.nutrients.calories, closeTo(300, 1e-9));
    expect(d.entries.single.meal, Meal.lunch);
    expect(d.saved.single.favorite, isTrue);
    expect(d.notes['2026-10-19']!.complete, isTrue);
    expect(d.activity['2026-10-18']!.workouts, ['Strength', 'Walk']);
    expect(d.market['grilled chicken']!.portionGrams, 120);
    expect(d.dismissedHealthWeights, {'1760000000|88.20'});
    expect(d.checkIns.single.maintenanceAfter, 2650);
  });

  test('round trip keeps everything and writes Swift-style dates', () {
    final d = AppData.fromJson(jsonDecode(swiftJson));
    final out = jsonEncode(d.toJson());
    final again = AppData.fromJson(jsonDecode(out));
    expect(jsonEncode(again.toJson()), out);
    expect(out, contains('"2026-10-19T17:30:00Z"'));
  });

  test('missing fields and unknown enum values fall back to defaults', () {
    final d = AppData.fromJson({
      'profile': {'sex': 'robot'},
      'entries': [
        {'item': <String, dynamic>{}},
      ],
    });
    expect(d.profile.sex, Sex.male);
    expect(d.entries.single.item.servings.single.name, 'serving');
    expect(() => AppData.fromJson([1, 2]), throwsFormatException);
  });

  test('repository: counted intake, favorites and usuals', () {
    final store = AppRepository(
      files: DataFileService(),
      health: HealthService(),
      loaded: LoadedData(AppData.fromJson(jsonDecode(swiftJson))),
    );
    final day = DateTime.parse('2026-10-19T17:30:00Z').toLocal();
    expect(store.countedIntake(day), closeTo(300, 1e-9)); // marked complete, so counted under 1,000 kcal
    expect(store.marketUsuals().single.item.name, 'Grilled Chicken');
    store.setNote(day, (n) => n.complete = null);
    expect(store.countedIntake(day), isNull);
    final id = store.log(store.data.saved.single.item, serving: 0, amount: 1, meal: Meal.dinner, day: day);
    expect(store.entries(day).length, 2);
    expect(store.data.saved.single.uses, 4);
    store.deleteEntry(id);
    expect(store.entries(day).length, 1);
    expect(store.csv(), contains('Grilled Chicken'));
  });

  test('dining halls: data written by the Swift app after it added West and Residence', () {
    final j = jsonDecode(swiftJson) as Map<String, dynamic>;
    final west = (j['saved'] as List<dynamic>).cast<Map<String, dynamic>>().single;
    final label = (j['market'] as Map<String, dynamic>)['grilled chicken'] as Map<String, dynamic>;
    j['saved'] = [
      west,
      {
        ...west,
        'favorite': false,
        'item': {...west['item'] as Map<String, dynamic>, 'brand': 'West Dining Center', 'source': 'westDining'},
      },
    ];
    j['market'] = {
      ...j['market'] as Map<String, dynamic>,
      'west|grilled chicken': {...label, 'hall': 'west'},
    };
    j['menus'] = {
      'residence|2026-10-19': {
        'day': '2026-10-19',
        'hall': 'residence',
        'label': '',
        'tabs': <dynamic>[],
        'fetched': '',
      },
    };
    j['diningHall'] = 'west';
    final store = AppRepository(
      files: DataFileService(),
      health: HealthService(),
      loaded: LoadedData(AppData.fromJson(j)),
    );
    final d = store.data;
    expect(d.diningHall, DiningHall.west);
    expect(d.saved.last.item.source, FoodSource.westDining);
    // Union Market's keys stay bare, the others carry the hall.
    expect(store.marketItem('Grilled Chicken', DiningHall.unionMarket)!.hall, DiningHall.unionMarket);
    expect(store.marketItem('Grilled Chicken', DiningHall.west)!.hall, DiningHall.west);
    expect(store.marketItem('Grilled Chicken', DiningHall.residence), isNull);
    expect(d.menus['residence|2026-10-19']!.hall, DiningHall.residence);
    expect(store.marketUsuals().length, 2);
    expect(store.marketUsuals(DiningHall.west).single.item.source, FoodSource.westDining);
    expect(store.marketUsuals(DiningHall.residence), isEmpty);
    expect(jsonEncode(AppData.fromJson(jsonDecode(jsonEncode(d.toJson()))).toJson()), jsonEncode(d.toJson()));

    // A new label updates saved foods from its own hall only.
    store.saveMarket([
      MarketItem(
        name: 'Grilled Chicken',
        hall: DiningHall.west,
        station: 'Grill',
        nutrients: Nutrients(calories: 260),
        portion: '',
      ),
    ], DiningHall.west);
    expect(d.saved.last.item.base.calories, 260);
    expect(d.saved.first.item.base.calories, 200);
    final item = store.marketItem('grilled chicken ', DiningHall.west)!.foodItem;
    expect(item.source, FoodSource.westDining);
    expect(item.brand, 'West Dining Center');
  });

  test('dining halls: West and Residence caches that v1.0.0 saved without their hall', () {
    final j = jsonDecode(swiftJson) as Map<String, dynamic>;
    final label = (j['market'] as Map<String, dynamic>)['grilled chicken'] as Map<String, dynamic>;
    j['market'] = {...j['market'] as Map<String, dynamic>, 'west|grilled chicken': label};
    j['menus'] = {
      '2026-10-19': {'day': '2026-10-19', 'label': '', 'tabs': <dynamic>[], 'fetched': ''},
      'west|2026-10-19': {'day': '2026-10-19', 'label': '', 'tabs': <dynamic>[], 'fetched': ''},
    };
    final d = AppData.fromJson(j);
    expect(d.market['grilled chicken']!.hall, DiningHall.unionMarket);
    expect(d.market['west|grilled chicken']!.hall, DiningHall.west);
    expect(d.menus['2026-10-19']!.hall, DiningHall.unionMarket);
    expect(d.menus['west|2026-10-19']!.hall, DiningHall.west);
  });

  test('Jamix number parsing', () {
    expect(JamixService.number('1,050 mg'), 1050);
    expect(JamixService.number('2,5 g'), 2.5);
    expect(JamixService.number('12.3 g'), 12.3);
    expect(JamixService.grams('2.1 oz (72 g)'), 72);
    expect(JamixService.grams('1 each'), isNull);
  });

  test('Swift-style ISO dates', () {
    expect(encodeDate(DateTime.utc(2026, 10, 20, 15, 8, 9, 123)), '2026-10-20T15:08:09Z');
    expect(Day.key(decodeDate('2026-10-20T15:08:09Z')!), Day.key(DateTime.utc(2026, 10, 20, 15, 8, 9).toLocal()));
  });
}
