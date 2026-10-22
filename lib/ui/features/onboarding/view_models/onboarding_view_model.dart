import 'dart:math' as math;

import '../../../../data/repositories/app_repository.dart';
import '../../../../domain/format.dart';
import '../../../../domain/models.dart';
import '../../../../domain/plan.dart';
import '../../../core/view_model.dart';

/// First run: the answers collected step by step, the draft targets, and saving the plan.
class OnboardingViewModel extends ViewModel {
  OnboardingViewModel({required this._repository});

  final AppRepository _repository;

  static const lastStep = 8;

  int step = 0;
  final Profile p = Profile();
  double? weight, goal, waist;
  int feet = 5, inches = 10;
  double? cm = 178;
  double? wearableBurn;
  bool connecting = false;
  String? healthError;

  /// Applies a change to the answers and redraws.
  void set(void Function() change) {
    change();
    notifyListeners();
  }

  double get heightCm => p.metric ? (cm ?? 0) : (feet * 12 + inches) * 2.54;
  double? get weightKg => weight == null ? null : Fmt.kgFromDisplay(weight!, p.metric);
  double? get goalKg => goal == null ? null : Fmt.kgFromDisplay(goal!, p.metric);

  bool get canContinue {
    switch (step) {
      case 1:
        return heightCm > 120 && heightCm < 230;
      case 2:
        final (w, g) = (weightKg, goalKg);
        if (w == null || g == null) return false;
        return w > 35 && w < 300 && g > 35 && g <= w;
      default:
        return true;
    }
  }

  void next() => set(() => step++);
  void back() => set(() => step--);

  void inchUp() => set(() {
    if (inches == 11) {
      inches = 0;
      feet++;
    } else {
      inches++;
    }
  });

  void inchDown() => set(() {
    if (inches > 0) {
      inches--;
    } else if (feet > 4) {
      inches = 11;
      feet--;
    }
  });

  /// "About 0.7 kg a week now; goal in about 30 weeks." Empty until weight and goal are set.
  String timeline(Pace pace) {
    final w = weightKg, g = goalKg;
    if (w == null || g == null || w <= g) return '';
    // Weeks to goal when each week loses pace × current weight.
    final weeks = math.log(g / w) / math.log(1 - pace.fractionPerWeek);
    return '\nAbout ${Fmt.weight(w * pace.fractionPerWeek, p.metric)} a week now; goal in about ${weeks.round()} weeks.';
  }

  /// Asks for Health access and reads the recent total burn that your watch or phone recorded, for the starting
  /// estimate.
  Future<void> connectHealth() async {
    set(() => connecting = true);
    await _repository.connectHealth();
    final ok = _repository.profile.useHealth;
    final burn = ok ? await _repository.averageTotalBurn() : null;
    set(() {
      p.useHealth = ok;
      healthError = _repository.healthError;
      wearableBurn = burn;
      connecting = false;
    });
  }

  double get _startingTDEE => Plan.startingTDEE(
    sex: p.sex,
    weightKg: weightKg ?? p.startWeightKg,
    heightCm: heightCm,
    age: p.age,
    activity: p.activity,
    wearableDailyTotal: wearableBurn,
  );

  (Targets, List<Warning>) get draft {
    final w = weightKg ?? p.startWeightKg;
    final g = goalKg ?? w;
    final warnings = Plan.warnings(age: p.age, heightCm: heightCm, weightKg: w, goalKg: g, screening: p.screening);
    final t = Plan.targets(
      sex: p.sex,
      age: p.age,
      heightCm: heightCm,
      trendKg: w,
      goalKg: g,
      pace: p.pace,
      tdee: _startingTDEE,
      maintenanceBreak: Plan.blocksDeficit(warnings),
    );
    return (t, warnings);
  }

  /// Saves the profile and the first weigh-in, which ends onboarding.
  void finish() {
    final w = weightKg, g = goalKg;
    if (w == null || g == null) return;
    p
      ..heightCm = heightCm
      ..startWeightKg = w
      ..goalKg = g
      ..planStart = Day.start(DateTime.now())
      ..maintenance = _startingTDEE
      ..maintenanceUpdated = null;
    final repo = _repository;
    repo.data.profile = p.copy();
    repo.recordWeighIn(w, DateTime.now());
    if (waist case final wst?) repo.addWaist(p.metric ? wst : wst * 2.54);
    repo.update((d) => d.onboarded = true);
    repo.saveNow();
    repo.syncHealth();
  }
}
