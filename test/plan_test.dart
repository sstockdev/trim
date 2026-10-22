import 'package:flutter_test/flutter_test.dart';
import 'package:trim/domain/format.dart';
import 'package:trim/domain/plan.dart';

void main() {
  test('Mifflin-St Jeor', () {
    expect(Plan.bmr(Sex.male, 90, 180, 30), closeTo(10 * 90 + 6.25 * 180 - 150 + 5, 1e-9));
    expect(Plan.bmr(Sex.female, 70, 165, 40), closeTo(700 + 1031.25 - 200 - 161, 1e-9));
  });

  test('age counts birthdays', () {
    expect(Plan.age(DateTime(2000, 10, 21), DateTime(2026, 10, 20)), 25);
    expect(Plan.age(DateTime(2000, 10, 20), DateTime(2026, 10, 20)), 26);
  });

  test('trend smooths 10 % a day and handles gaps', () {
    final t = Plan.trend([
      WeightPoint(DateTime(2026, 1, 1, 7), 100),
      WeightPoint(DateTime(2026, 1, 2, 7), 90),
      WeightPoint(DateTime(2026, 1, 4, 7), 90),
    ]);
    expect(t[1].kg, closeTo(99, 1e-9));
    // Two days elapsed: alpha = 1 - 0.9^2 = 0.19.
    expect(t[2].kg, closeTo(99 + 0.19 * (90 - 99), 1e-9));
    expect(Plan.trendValue(DateTime(2026, 1, 3), t), closeTo(99, 1e-9));
    expect(Plan.trendValue(DateTime(2025, 12, 31), t), isNull);
  });

  test('targets: deficit from pace, floors and macros', () {
    final t = Plan.targets(
      sex: Sex.male,
      age: 30,
      heightCm: 180,
      trendKg: 100,
      goalKg: 80,
      pace: Pace.steady,
      tdee: 2800,
      maintenanceBreak: false,
    );
    // 0.75 % of 100 kg a week is 825 kcal a day, over the 25 % cap of 700, so the cap applies.
    expect(t.deficit, 700);
    expect(t.calories, 2100);
    expect(t.protein, 128);
    expect(t.notes.first, contains('capped'));
    expect(t.steps, 8000);

    final low = Plan.targets(
      sex: Sex.female,
      age: 30,
      heightCm: 160,
      trendKg: 60,
      goalKg: 55,
      pace: Pace.faster,
      tdee: 1400,
      maintenanceBreak: false,
    );
    expect(low.calories, 1200);

    final atGoal = Plan.targets(
      sex: Sex.male,
      age: 30,
      heightCm: 180,
      trendKg: 80.2,
      goalKg: 80,
      pace: Pace.steady,
      tdee: 2600,
      maintenanceBreak: false,
      baselineSteps: 9800,
    );
    expect(atGoal.maintaining, isTrue);
    expect(atGoal.deficit, 0);
    expect(atGoal.steps, 10000);
  });

  test('adaptive TDEE learns from intake and weight slope', () {
    final planStart = DateTime(2026, 1, 1);
    final end = DateTime(2026, 2, 15);
    final days = [for (var i = 0; i < 21; i++) DayLog(Day.add(-i, end), 2000)];
    // Losing 0.1 kg a day: 2,000 + 0.1 × 7,700 = 2,770 kcal observed.
    final weights = [
      for (var i = 0; i < 21; i++) WeightPoint(Day.add(-i, end).add(const Duration(hours: 7)), 90 - (20 - i) * 0.1),
    ];
    final r = Plan.adaptiveTDEE(
      days: days,
      weighIns: weights,
      prior: 2500,
      bmr: 1800,
      planStart: planStart,
      through: end,
    )!;
    expect(r.observed, closeTo(2770, 1));
    expect(r.loggedDays, 21);
    // Full coverage moves halfway.
    expect(r.tdee, closeTo(2500 + 0.5 * (2770 - 2500), 1));

    expect(
      Plan.adaptiveTDEE(
        days: days.take(5).toList(),
        weighIns: weights,
        prior: 2500,
        bmr: 1800,
        planStart: planStart,
        through: end,
      ),
      isNull,
    );
  });

  test('warnings block a deficit for minors and low BMI', () {
    final w = Plan.warnings(age: 17, heightCm: 180, weightKg: 55, goalKg: 50, screening: Screening());
    expect(Plan.blocksDeficit(w), isTrue);
    expect(w.where((x) => x.level == WarningLevel.stop).length, 2);
  });

  test('formatting', () {
    expect(Fmt.amount(1.25), '1.25');
    expect(Fmt.amount(2), '2');
    expect(Fmt.amount(12.5), '12.5');
    expect(Fmt.int_(12500), '12,500');
    expect(Fmt.int_(-1234567), '-1,234,567');
    expect(Fmt.height(177.8, false), '5′ 10″');
    expect(Day.key(DateTime(2026, 3, 8)), '2026-03-08');
    expect(Day.between(DateTime(2026, 3, 7, 23), DateTime(2026, 3, 9, 1)), 2);
  });
}
