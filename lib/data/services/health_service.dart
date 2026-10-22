import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:health/health.dart';

import '../../domain/format.dart';
import '../../domain/models.dart';

/// A weigh-in found in Health.
class HealthWeight {
  final DateTime date;
  final double kg;
  const HealthWeight(this.date, this.kg);
}

/// What one sync read: activity by day key, and weigh-ins written by other apps (smart scales).
class HealthSnapshot {
  final Map<String, DayActivity> activity;
  final List<HealthWeight> weights;
  const HealthSnapshot(this.activity, this.weights);
}

class HealthException implements Exception {
  final String message;
  const HealthException(this.message);
  @override
  String toString() => message;
}

/// Activity, sleep and weight from Apple Health (iOS) or Health Connect (Android), through the health plugin.
/// The service only reads and writes Health; `AppRepository.syncHealth` applies what it reads.
class HealthService {
  HealthService({Health? health}) : _health = health ?? Health();

  static bool get isIOS => !kIsWeb && Platform.isIOS;
  static String get name => isIOS ? 'Apple Health' : 'Health Connect';

  final Health _health;
  bool _configured = false;

  static const _strengthTypes = {
    HealthWorkoutActivityType.TRADITIONAL_STRENGTH_TRAINING,
    HealthWorkoutActivityType.FUNCTIONAL_STRENGTH_TRAINING,
    HealthWorkoutActivityType.STRENGTH_TRAINING,
    HealthWorkoutActivityType.WEIGHTLIFTING,
    HealthWorkoutActivityType.CORE_TRAINING,
    HealthWorkoutActivityType.CROSS_TRAINING,
  };

  static List<HealthDataType> get _sleepTypes => isIOS
      ? const [
          HealthDataType.SLEEP_ASLEEP,
          HealthDataType.SLEEP_LIGHT,
          HealthDataType.SLEEP_DEEP,
          HealthDataType.SLEEP_REM,
        ]
      : const [
          HealthDataType.SLEEP_ASLEEP,
          HealthDataType.SLEEP_LIGHT,
          HealthDataType.SLEEP_DEEP,
          HealthDataType.SLEEP_REM,
          HealthDataType.SLEEP_SESSION,
        ];

  /// Resting energy: HealthKit has basal energy samples; Health Connect has total calories, and resting is
  /// total minus active.
  static HealthDataType get _restingSource =>
      isIOS ? HealthDataType.BASAL_ENERGY_BURNED : HealthDataType.TOTAL_CALORIES_BURNED;

  static List<HealthDataType> get _readTypes => [
    HealthDataType.STEPS,
    HealthDataType.ACTIVE_ENERGY_BURNED,
    _restingSource,
    HealthDataType.WEIGHT,
    HealthDataType.RESTING_HEART_RATE,
    HealthDataType.WORKOUT,
    ..._sleepTypes,
  ];

  Future<void> _configure() async {
    if (_configured) return;
    await _health.configure();
    _configured = true;
  }

  Future<bool> get available async {
    if (kIsWeb) return false;
    if (isIOS) return true;
    try {
      await _configure();
      return await _health.getHealthConnectSdkStatus() == HealthConnectSdkStatus.sdkAvailable;
    } on Exception {
      return false;
    }
  }

  /// Asks for access. Throws [HealthException] with a message for the user when it can't be granted.
  Future<void> requestAccess() async {
    await _configure();
    if (!await available) {
      if (!isIOS) await _health.installHealthConnect();
      throw const HealthException(
        "Health Connect isn't available on this phone. Install or update it from the Play Store, then try again.",
      );
    }
    final types = _readTypes;
    final access = [
      for (final t in types) t == HealthDataType.WEIGHT ? HealthDataAccess.READ_WRITE : HealthDataAccess.READ,
    ];
    final ok = await _health.requestAuthorization(types, permissions: access);
    // Apple Health never says whether read access was granted, so on iOS a "no" only means the sheet failed.
    if (!ok && !isIOS) throw HealthException('Access to $name was not granted.');
  }

  Future<List<HealthDataPoint>> _read(List<HealthDataType> types, DateTime from, DateTime to) async {
    try {
      final points = await _health.getHealthDataFromTypes(types: types, startTime: from, endTime: to);
      return _health.removeDuplicates(points);
    } on Exception catch (e) {
      debugPrint('Trim: reading $types failed: $e');
      return [];
    }
  }

  static double? _num(HealthDataPoint p) {
    final v = p.value;
    return v is NumericHealthValue ? v.numericValue.toDouble() : null;
  }

  /// Daily totals of a cumulative type. A watch and a phone can both record the same walk, so each day takes
  /// the source with the biggest total rather than adding sources together.
  static Map<String, double> _dailyTotals(List<HealthDataPoint> points) {
    final bySource = <String, Map<String, double>>{};
    for (final p in points) {
      final v = _num(p);
      if (v == null) continue;
      final day = Day.key(p.dateFrom);
      final m = bySource.putIfAbsent(day, () => {});
      m[p.sourceId] = (m[p.sourceId] ?? 0) + v;
    }
    return bySource.map((day, m) => MapEntry(day, m.values.reduce(math.max)));
  }

  /// Reads the last `days` days. Apple Health doesn't say whether read access was granted, so a day with nothing
  /// simply comes back empty.
  Future<HealthSnapshot> fetch({int days = 28}) async {
    await _configure();
    final end = DateTime.now();
    final start = Day.add(-(days - 1), Day.start(end));

    final steps = <String, double>{};
    for (var i = 0; i < days; i++) {
      final d = Day.add(i, start);
      // The platform's own daily total, which already removes overlap between sources.
      try {
        final s = await _health.getTotalStepsInInterval(d, Day.add(1, d));
        if (s != null && s > 0) steps[Day.key(d)] = s.toDouble();
      } on Exception catch (e) {
        debugPrint('Trim: steps for ${Day.key(d)} failed: $e');
      }
    }
    final active = _dailyTotals(await _read([HealthDataType.ACTIVE_ENERGY_BURNED], start, end));
    final restingRaw = _dailyTotals(await _read([_restingSource], start, end));
    final resting = isIOS
        ? restingRaw
        : {
            for (final e in restingRaw.entries)
              if (e.value - (active[e.key] ?? 0) > 0) e.key: e.value - (active[e.key] ?? 0),
          };
    final hr = _dailyAverages(await _read([HealthDataType.RESTING_HEART_RATE], start, end));
    final sleep = _sleepByDay(await _read(_sleepTypes, Day.add(-1, start), end));
    final workouts = _workoutsByDay(await _read([HealthDataType.WORKOUT], start, end));

    final activity = <String, DayActivity>{};
    for (var i = 0; i < days; i++) {
      final key = Day.key(Day.add(i, start));
      final list = workouts[key] ?? const <_Workout>[];
      activity[key] = DayActivity(
        steps: steps[key],
        activeKcal: active[key],
        restingKcal: resting[key],
        restingHR: hr[key],
        sleepHours: sleep[key],
        workouts: list.map((w) => w.name).toList(),
        strengthSessions: list.where((w) => w.strength).length,
        strengthMinutes: list.where((w) => w.strength).fold(0.0, (s, w) => s + w.minutes),
        cardioMinutes: list.where((w) => !w.strength).fold(0.0, (s, w) => s + w.minutes),
      );
    }
    final weights = [
      for (final p in await _read([HealthDataType.WEIGHT], Day.add(-90, end), end))
        // Skip the ones this app wrote.
        if (!p.sourceId.toLowerCase().startsWith('com.sstock.trim'))
          if (_num(p) case final kg?) HealthWeight(p.dateFrom, kg),
    ]..sort((a, b) => a.date.compareTo(b.date));
    return HealthSnapshot(activity, weights);
  }

  static Map<String, double> _dailyAverages(List<HealthDataPoint> points) {
    final sums = <String, (double, int)>{};
    for (final p in points) {
      final v = _num(p);
      if (v == null) continue;
      final key = Day.key(p.dateFrom);
      final (s, n) = sums[key] ?? (0.0, 0);
      sums[key] = (s + v, n + 1);
    }
    return sums.map((k, v) => MapEntry(k, v.$1 / v.$2));
  }

  /// Sleep is credited to the day you wake up. Overlapping samples from several sources (watch and phone) or
  /// stages inside a session are merged so time isn't counted twice.
  static Map<String, double> _sleepByDay(List<HealthDataPoint> points) {
    final byDay = <String, List<(DateTime, DateTime)>>{};
    for (final p in points) {
      byDay.putIfAbsent(Day.key(p.dateTo), () => []).add((p.dateFrom, p.dateTo));
    }
    final out = <String, double>{};
    byDay.forEach((day, spans) {
      spans.sort((a, b) => a.$1.compareTo(b.$1));
      var total = Duration.zero;
      DateTime? cursor;
      for (final (a, b) in spans) {
        final start = cursor != null && cursor.isAfter(a) ? cursor : a;
        if (b.isAfter(start)) total += b.difference(start);
        if (cursor == null || b.isAfter(cursor)) cursor = b;
      }
      final hours = total.inSeconds / 3600;
      if (hours > 0.5) out[day] = hours;
    });
    return out;
  }

  static Map<String, List<_Workout>> _workoutsByDay(List<HealthDataPoint> points) {
    final out = <String, List<_Workout>>{};
    for (final p in points) {
      final v = p.value;
      if (v is! WorkoutHealthValue) continue;
      final type = v.workoutActivityType;
      out
          .putIfAbsent(Day.key(p.dateFrom), () => [])
          .add(
            _Workout(
              _workoutName(type),
              p.dateTo.difference(p.dateFrom).inSeconds / 60,
              _strengthTypes.contains(type),
            ),
          );
    }
    return out;
  }

  /// Average total burn (resting + active) over the last couple of weeks, for the starting estimate.
  Future<double?> averageTotalBurn({int days = 14}) async {
    try {
      await _configure();
      final end = Day.start(DateTime.now());
      final start = Day.add(-days, end);
      final active = _dailyTotals(await _read([HealthDataType.ACTIVE_ENERGY_BURNED], start, end));
      final rest = _dailyTotals(await _read([_restingSource], start, end));
      final totals = [
        for (final e in rest.entries)
          if (active[e.key] case final a?) isIOS ? e.value + a : e.value,
      ].where((t) => t > 1000).toList();
      if (totals.length < 7) return null;
      return totals.reduce((a, b) => a + b) / totals.length;
    } on Exception {
      return null;
    }
  }

  Future<void> saveWeight(double kg, DateTime date) async {
    await _configure();
    await _health.writeHealthData(value: kg, type: HealthDataType.WEIGHT, startTime: date, endTime: date);
  }

  static String _workoutName(HealthWorkoutActivityType t) => switch (t) {
    HealthWorkoutActivityType.RUNNING || HealthWorkoutActivityType.RUNNING_TREADMILL => 'Run',
    HealthWorkoutActivityType.WALKING => 'Walk',
    HealthWorkoutActivityType.HIKING => 'Hike',
    HealthWorkoutActivityType.BIKING || HealthWorkoutActivityType.BIKING_STATIONARY => 'Ride',
    HealthWorkoutActivityType.SWIMMING ||
    HealthWorkoutActivityType.SWIMMING_OPEN_WATER ||
    HealthWorkoutActivityType.SWIMMING_POOL => 'Swim',
    HealthWorkoutActivityType.ROWING || HealthWorkoutActivityType.ROWING_MACHINE => 'Row',
    HealthWorkoutActivityType.ELLIPTICAL => 'Elliptical',
    HealthWorkoutActivityType.STAIR_CLIMBING || HealthWorkoutActivityType.STAIRS => 'Stairs',
    HealthWorkoutActivityType.TRADITIONAL_STRENGTH_TRAINING ||
    HealthWorkoutActivityType.FUNCTIONAL_STRENGTH_TRAINING ||
    HealthWorkoutActivityType.STRENGTH_TRAINING ||
    HealthWorkoutActivityType.WEIGHTLIFTING => 'Strength',
    HealthWorkoutActivityType.CORE_TRAINING => 'Core',
    HealthWorkoutActivityType.CROSS_TRAINING => 'Cross training',
    HealthWorkoutActivityType.HIGH_INTENSITY_INTERVAL_TRAINING => 'HIIT',
    HealthWorkoutActivityType.YOGA => 'Yoga',
    HealthWorkoutActivityType.PILATES => 'Pilates',
    HealthWorkoutActivityType.BASKETBALL => 'Basketball',
    HealthWorkoutActivityType.SOCCER => 'Soccer',
    HealthWorkoutActivityType.TENNIS => 'Tennis',
    HealthWorkoutActivityType.GOLF => 'Golf',
    _ => 'Workout',
  };
}

class _Workout {
  final String name;
  final double minutes;
  final bool strength;
  const _Workout(this.name, this.minutes, this.strength);
}
