import 'dart:math' as math;

import 'format.dart';

// The weight-loss program. Pure Dart with no Flutter imports, so `flutter test test/plan_test.dart` checks the
// math anywhere. The reasoning and sources are shown in the app by guide_page.dart.

enum Sex {
  male,
  female;

  String get title => this == Sex.male ? 'Male' : 'Female';
}

/// Only used until there's enough logged data for the adaptive estimate (about three weeks).
enum ActivityLevel {
  sedentary,
  light,
  moderate,
  active;

  double get factor => const {
    ActivityLevel.sedentary: 1.2,
    ActivityLevel.light: 1.375,
    ActivityLevel.moderate: 1.55,
    ActivityLevel.active: 1.725,
  }[this]!;

  String get title => const {
    ActivityLevel.sedentary: 'Mostly sitting',
    ActivityLevel.light: 'Lightly active',
    ActivityLevel.moderate: 'Moderately active',
    ActivityLevel.active: 'Very active',
  }[this]!;

  String get detail => const {
    ActivityLevel.sedentary: 'Desk day, under ~5,000 steps, little exercise',
    ActivityLevel.light: '5,000 to 7,500 steps or exercise 1 to 3 days a week',
    ActivityLevel.moderate: '7,500 to 10,000 steps or exercise 3 to 5 days a week',
    ActivityLevel.active: 'Over 10,000 steps or hard exercise 6 or 7 days a week',
  }[this]!;
}

/// Weekly loss as a share of body weight. 0.5 to 1 % a week keeps most of the loss as fat when protein and
/// resistance training are in place; faster rates lose more lean mass (Garthe 2011, Helms 2014).
enum Pace {
  gentle,
  steady,
  faster;

  double get fractionPerWeek => const {Pace.gentle: 0.005, Pace.steady: 0.0075, Pace.faster: 0.01}[this]!;

  /// The deficit never goes past this share of maintenance, however heavy someone is.
  double get maxDeficitShare => this == Pace.faster ? 0.30 : 0.25;

  String get title => const {
    Pace.gentle: 'Gentle (0.5 % a week)',
    Pace.steady: 'Steady (0.75 % a week)',
    Pace.faster: 'Faster (1 % a week)',
  }[this]!;

  String get detail => const {
    Pace.gentle: "Easiest to stick with and best for keeping muscle. Good when you're already lean-ish.",
    Pace.steady: 'The recommended default: noticeable progress with little muscle loss.',
    Pace.faster: 'The fastest rate the evidence supports. Hunger is higher, so protein and lifting matter more.',
  }[this]!;
}

class Targets {
  int calories;
  int protein;
  int fat;
  int carbs;
  int fiber;
  int steps;

  /// Maintenance estimate the target was built from.
  int tdee;
  int bmr;
  int deficit;
  double expectedLossPerWeekKg;
  bool maintaining;
  List<String> notes;

  Targets({
    required this.calories,
    required this.protein,
    required this.fat,
    required this.carbs,
    required this.fiber,
    required this.steps,
    required this.tdee,
    required this.bmr,
    required this.deficit,
    required this.expectedLossPerWeekKg,
    required this.maintaining,
    required this.notes,
  });
}

enum WarningLevel { info, caution, stop }

class Warning {
  final WarningLevel level;
  final String text;
  const Warning(this.level, this.text);
}

/// A dated value: a weigh-in or a point on the trend line.
class WeightPoint {
  final DateTime date;
  final double kg;
  const WeightPoint(this.date, this.kg);
}

class DayLog {
  final DateTime date;

  /// null when the day wasn't fully logged; those days are left out rather than counted as low intake.
  final double? intake;
  const DayLog(this.date, this.intake);
}

class AdaptiveResult {
  final double tdee;
  final double observed;
  final int loggedDays;
  final double slopeKgPerWeek;
  const AdaptiveResult(this.tdee, this.observed, this.loggedDays, this.slopeKgPerWeek);
}

class Screening {
  bool pregnantOrBreastfeeding;
  bool eatingDisorderHistory;
  bool diabetesMedication;
  bool glp1Medication;
  bool kidneyDisease;

  Screening({
    this.pregnantOrBreastfeeding = false,
    this.eatingDisorderHistory = false,
    this.diabetesMedication = false,
    this.glp1Medication = false,
    this.kidneyDisease = false,
  });

  factory Screening.fromJson(Map<String, dynamic> j) => Screening(
    pregnantOrBreastfeeding: j['pregnantOrBreastfeeding'] as bool? ?? false,
    eatingDisorderHistory: j['eatingDisorderHistory'] as bool? ?? false,
    diabetesMedication: j['diabetesMedication'] as bool? ?? false,
    glp1Medication: j['glp1Medication'] as bool? ?? false,
    kidneyDisease: j['kidneyDisease'] as bool? ?? false,
  );

  Map<String, dynamic> toJson() => {
    'pregnantOrBreastfeeding': pregnantOrBreastfeeding,
    'eatingDisorderHistory': eatingDisorderHistory,
    'diabetesMedication': diabetesMedication,
    'glp1Medication': glp1Medication,
    'kidneyDisease': kidneyDisease,
  };

  Screening copy() => Screening.fromJson(toJson());
}

class WeekReview {
  double? trendStart;
  double? trendEnd;
  int loggedDays;
  double? avgCalories;
  double? avgProtein;
  int proteinDays;
  double? avgSteps;
  int strengthSessions;
  double cardioMinutes;
  double? avgSleepHours;

  WeekReview({
    this.trendStart,
    this.trendEnd,
    required this.loggedDays,
    this.avgCalories,
    this.avgProtein,
    required this.proteinDays,
    this.avgSteps,
    required this.strengthSessions,
    required this.cardioMinutes,
    this.avgSleepHours,
  });

  double? get changeKg => trendStart == null || trendEnd == null ? null : trendEnd! - trendStart!;

  double? changeFraction() {
    final a = trendStart, c = changeKg;
    if (a == null || c == null || a <= 0) return null;
    return c / a;
  }
}

class Plan {
  /// Energy in a kilogram of mostly-fat body tissue. It overstates the very first weeks (water and
  /// glycogen), which is why the adaptive estimate skips the first week (see `adaptiveTDEE`).
  static const kcalPerKg = 7700.0;
  static const poundsPerKg = 2.2046226;

  /// Common floors below which intake shouldn't go without medical supervision.
  static int calorieFloor(Sex sex) => sex == Sex.male ? 1500 : 1200;

  static int age(DateTime born, DateTime on) {
    var years = on.year - born.year;
    if (on.month < born.month || (on.month == born.month && on.day < born.day)) years--;
    return years;
  }

  static double bmi(double weightKg, double heightCm) {
    final m = heightCm / 100;
    return weightKg / (m * m);
  }

  static double weightForBmi(double bmi, double heightCm) {
    final m = heightCm / 100;
    return bmi * m * m;
  }

  /// Mifflin-St Jeor: the most accurate of the common equations, within 10 % for most adults with or without
  /// obesity (Frankenfield 2005).
  static double bmr(Sex sex, double weightKg, double heightCm, int age) =>
      10 * weightKg + 6.25 * heightCm - 5 * age + (sex == Sex.male ? 5 : -161);

  // Trend weight

  /// Exponentially smoothed weight, the "trend" from The Hacker's Diet: about 10 % of each new weigh-in's
  /// difference goes into the trend, so daily water swings barely move it. Gaps are handled by applying the
  /// smoothing once per day elapsed.
  static List<WeightPoint> trend(List<WeightPoint> weighIns, {double smoothing = 0.1}) {
    final sorted = [...weighIns]..sort((a, b) => a.date.compareTo(b.date));
    if (sorted.isEmpty) return [];
    final first = sorted.first;
    final result = [WeightPoint(first.date, first.kg)];
    var value = first.kg;
    var last = first.date;
    for (final entry in sorted.skip(1)) {
      final days = math.max(1, Day.between(last, entry.date)).toDouble();
      final alpha = 1 - math.pow(1 - smoothing, days);
      value += alpha * (entry.kg - value);
      result.add(WeightPoint(entry.date, value));
      last = entry.date;
    }
    return result;
  }

  /// The trend value on a given day, carried forward from the last weigh-in before it.
  static double? trendValue(DateTime day, List<WeightPoint> trend) {
    final end = Day.add(1, Day.start(day));
    for (var i = trend.length - 1; i >= 0; i--) {
      if (trend[i].date.isBefore(end)) return trend[i].kg;
    }
    return null;
  }

  /// Least-squares slope in kg per day.
  static double? slope(List<(double, double)> points) {
    if (points.length < 2) return null;
    final n = points.length.toDouble();
    final mx = points.fold(0.0, (s, p) => s + p.$1) / n;
    final my = points.fold(0.0, (s, p) => s + p.$2) / n;
    final sxx = points.fold(0.0, (s, p) => s + (p.$1 - mx) * (p.$1 - mx));
    if (sxx <= 0) return null;
    final sxy = points.fold(0.0, (s, p) => s + (p.$1 - mx) * (p.$2 - my));
    return sxy / sxx;
  }

  // Maintenance (TDEE)

  /// Starting estimate: Mifflin-St Jeor × activity. When a watch has supplied at least a week of total energy
  /// (resting + active), it's averaged in, because a wearable's guess about your own activity beats a category.
  static double startingTDEE({
    required Sex sex,
    required double weightKg,
    required double heightCm,
    required int age,
    required ActivityLevel activity,
    double? wearableDailyTotal,
  }) {
    final formula = bmr(sex, weightKg, heightCm, age) * activity.factor;
    if (wearableDailyTotal == null || wearableDailyTotal <= 1000) return formula;
    // Wrist devices tend to overestimate energy, so trust them a little less than face value.
    return (formula + wearableDailyTotal * 0.9) / 2;
  }

  /// Back-calculates maintenance from what you actually ate and what the trend did: if you averaged 2,000 kcal
  /// and lost 0.5 kg/week, you burned about 2,000 + 0.5 × 7,700 / 7 ≈ 2,550 kcal a day. Same idea as MacroFactor
  /// and The Hacker's Diet. Needs ≥ 10 logged days and ≥ 6 weigh-ins in the window, skips the plan's first week
  /// (water and glycogen), and moves the estimate only part of the way each week so one odd week can't swing it.
  static AdaptiveResult? adaptiveTDEE({
    required List<DayLog> days,
    required List<WeightPoint> weighIns,
    required double prior,
    required double bmr,
    required DateTime planStart,
    required DateTime through,
    int windowDays = 21,
  }) {
    final endDay = Day.start(through);
    final windowStartRaw = Day.add(-(windowDays - 1), endDay);
    final earliest = Day.add(7, Day.start(planStart));
    final windowStart = windowStartRaw.isAfter(earliest) ? windowStartRaw : earliest;
    final span = Day.between(windowStart, endDay) + 1;
    if (span < 14) return null;

    final windowEnd = Day.add(1, endDay);
    bool inWindow(DateTime d) => !d.isBefore(windowStart) && d.isBefore(windowEnd);
    final logged = days.where((d) => inWindow(d.date) && d.intake != null).map((d) => d.intake!).toList();
    final weights = weighIns.where((w) => inWindow(w.date)).toList();
    if (logged.length < 10 || weights.length < 6) return null;

    // A straight-line fit through the raw weigh-ins. Unlike the smoothed trend it doesn't lag behind a steady
    // loss, and with 6+ points the daily water noise mostly cancels out.
    final points = weights.map((w) => (w.date.difference(windowStart).inSeconds / 86400.0, w.kg)).toList();
    final perDay = slope(points);
    if (perDay == null) return null;

    final avgIntake = logged.reduce((a, b) => a + b) / logged.length;
    var observed = avgIntake - perDay * kcalPerKg;
    observed = observed.clamp(bmr * 1.0, bmr * 2.5);

    final coverage = logged.length / span;
    final step = 0.5 * coverage;
    return AdaptiveResult(prior + step * (observed - prior), observed, logged.length, perDay * 7);
  }

  // Targets

  static Targets targets({
    required Sex sex,
    required int age,
    required double heightCm,
    required double trendKg,
    required double goalKg,
    required Pace pace,
    required double tdee,
    required bool maintenanceBreak,
    double? baselineSteps,
  }) {
    final bmrValue = bmr(sex, trendKg, heightCm, age);
    final atGoal = trendKg <= goalKg + 0.3;
    final maintaining = atGoal || maintenanceBreak;
    final notes = <String>[];

    var deficit = 0.0;
    if (!maintaining) {
      final wanted = pace.fractionPerWeek * trendKg * kcalPerKg / 7;
      final cap = pace.maxDeficitShare * tdee;
      deficit = math.min(wanted, cap);
      if (wanted > cap) {
        notes.add('Your deficit is capped at ${(pace.maxDeficitShare * 100).toInt()} % of maintenance.');
      }
    }
    var calories = tdee - deficit;
    final floor = calorieFloor(sex).toDouble();
    if (calories < floor) {
      calories = floor;
      deficit = math.max(0, tdee - floor);
      notes.add('Calories are held at ${floor.toInt()}, the lowest intake advised without medical supervision.');
    }
    calories = (calories / 10).roundToDouble() * 10;
    if (atGoal) {
      notes.add("You're at your goal, so this is your maintenance target.");
    } else if (maintenanceBreak) {
      notes.add('Maintenance week: eat at maintenance, keep logging and lifting.');
    }

    // Protein: 1.6 g per kg of goal weight. That's the point where extra protein stops adding muscle in
    // resistance training (Morton 2018). During weight loss, intakes over 1.3 g/kg help keep muscle (Kokura 2024).
    // Goal weight keeps it sensible for larger bodies.
    var protein = 1.6 * goalKg;
    protein = math.min(protein, 0.4 * calories / 4);
    // Fat: about 30 % of calories, never under 0.6 g/kg of goal weight (hormones, vitamin absorption).
    final fat = math.max(0.30 * calories / 9, 0.6 * goalKg);
    final carbs = math.max(0.0, (calories - protein * 4 - fat * 9) / 4);
    // Fibre: 14 g per 1,000 kcal (Dietary Guidelines), at least 25 g. It's the most filling thing to add.
    final fiber = math.max(25.0, 14 * calories / 1000);

    // Steps: a bit above your current average, between 7,000 and 10,000. The drop in mortality levels off at
    // 6,000 to 8,000 a day for adults 60 and over and 8,000 to 10,000 for younger adults (Paluch 2022).
    var steps = 8000.0;
    if (baselineSteps != null && baselineSteps > 0) {
      steps = (((baselineSteps + 1000) / 500).roundToDouble() * 500).clamp(7000.0, 10000.0);
    }

    return Targets(
      calories: calories.toInt(),
      protein: protein.round(),
      fat: fat.round(),
      carbs: carbs.round(),
      fiber: fiber.round(),
      steps: steps.toInt(),
      tdee: tdee.round(),
      bmr: bmrValue.round(),
      deficit: deficit.round(),
      expectedLossPerWeekKg: deficit * 7 / kcalPerKg,
      maintaining: maintaining,
      notes: notes,
    );
  }

  // Safety

  static List<Warning> warnings({
    required int age,
    required double heightCm,
    required double weightKg,
    required double goalKg,
    required Screening screening,
  }) {
    final out = <Warning>[];
    final bmiNow = bmi(weightKg, heightCm);
    if (age < 18) {
      out.add(
        const Warning(
          WarningLevel.stop,
          'This program is built for adults. Teens should plan weight changes with a doctor, so targets are set to maintenance.',
        ),
      );
    }
    if (screening.pregnantOrBreastfeeding) {
      out.add(
        const Warning(
          WarningLevel.stop,
          "Dieting isn't recommended while pregnant or breastfeeding. Targets are set to maintenance; ask your doctor or midwife.",
        ),
      );
    }
    if (bmiNow < 18.5) {
      out.add(const Warning(WarningLevel.stop, "Your BMI is already under 18.5, so the app won't set a deficit."));
    }
    if (bmi(goalKg, heightCm) < 18.5) {
      out.add(
        Warning(
          WarningLevel.caution,
          'Your goal is below a BMI of 18.5. Pick a goal of at least ${weightForBmi(18.5, heightCm).round()} kg.',
        ),
      );
    }
    if (screening.eatingDisorderHistory) {
      out.add(
        const Warning(
          WarningLevel.caution,
          'With a history of disordered eating, calorie tracking can do harm. Please involve a clinician or dietitian.',
        ),
      );
    }
    if (screening.diabetesMedication) {
      out.add(
        const Warning(
          WarningLevel.caution,
          'Eating less can make insulin or sulfonylureas push blood sugar too low. Talk to your doctor before you start.',
        ),
      );
    }
    if (screening.kidneyDisease) {
      out.add(
        const Warning(
          WarningLevel.caution,
          'With kidney disease, ask your doctor before following the higher protein target.',
        ),
      );
    }
    if (screening.glp1Medication) {
      out.add(
        const Warning(
          WarningLevel.info,
          'In a large trial of a GLP-1 medicine, more than a third of the weight lost was lean mass, which includes muscle. Hitting protein and lifting twice a week matter even more.',
        ),
      );
    }
    return out;
  }

  /// Diet-only blocks: whether the program should hold intake at maintenance.
  static bool blocksDeficit(List<Warning> warnings) => warnings.any((w) => w.level == WarningLevel.stop);

  // Weekly review

  /// Plain-language feedback for the weekly check-in. The adaptive estimate does the calorie correction;
  /// these explain it and point at the habits that move results.
  static List<String> feedback({
    required WeekReview review,
    required Targets targets,
    required Pace pace,
    required int weeksInDeficit,
  }) {
    final out = <String>[];
    if (review.loggedDays < 5) {
      out.add(
        'You logged ${review.loggedDays} of 7 days. Aim for at least 5: the calorie adjustment only learns from logged days.',
      );
    }
    final f = review.changeFraction();
    if (f != null && !targets.maintaining) {
      final pct = -f * 100;
      if (pct > 1.5) {
        out.add(
          'Your trend dropped ${pct.toStringAsFixed(1)} % this week, faster than is good for keeping muscle. If it stays this fast, eat a little more.',
        );
      } else if (pct < pace.fractionPerWeek * 100 * 0.4 && review.loggedDays >= 5) {
        out.add(
          "Progress was slower than planned. Your maintenance estimate updates from this week's data, so the target adjusts automatically. Check that oils, sauces and drinks are logged.",
        );
      } else if (pct > 0) {
        out.add('Down ${pct.toStringAsFixed(2)} % this week, on track.');
      }
    }
    final p = review.avgProtein;
    if (p != null && p < targets.protein * 0.85) {
      out.add(
        'Protein averaged ${p.toInt()} g against ${targets.protein} g. Protein keeps muscle and keeps you full; add a lean source to each meal.',
      );
    }
    if (review.strengthSessions < 2) {
      final s = review.strengthSessions;
      out.add(
        'Lifting $s time${s == 1 ? '' : 's'} this week. Two full-body sessions are what protect muscle while you lose.',
      );
    }
    final steps = review.avgSteps;
    if (steps != null && steps < targets.steps * 0.85) {
      out.add(
        'Steps averaged ${Fmt.int_(steps.toInt())}, under your ${Fmt.int_(targets.steps)} goal. Walks after meals are an easy way to add them.',
      );
    }
    final sleep = review.avgSleepHours;
    if (sleep != null && sleep < 7) {
      out.add(
        'Sleep averaged ${sleep.toStringAsFixed(1)} h. Under 7 hours raises hunger and makes more of the loss come from muscle.',
      );
    }
    if (weeksInDeficit >= 12) {
      out.add(
        "You've been in a deficit for $weeksInDeficit weeks. Consider a 1 or 2 week maintenance break; it eases hunger and fatigue without losing progress.",
      );
    }
    if (out.isEmpty) out.add("Solid week. Keep doing what you're doing.");
    return out;
  }
}
