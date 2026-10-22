import 'package:intl/intl.dart';

import '../../../../data/repositories/app_repository.dart';
import '../../../../domain/format.dart';
import '../../../../domain/models.dart';
import '../../../../domain/plan.dart';
import '../../../core/view_model.dart';

/// The weekly check-in: the answers being filled in, then the saved result with feedback.
class CheckInViewModel extends ViewModel {
  CheckInViewModel({required this._repository});

  final AppRepository _repository;

  double? waist;
  int? hunger, energy, adherence;
  String note = '';
  bool takeBreak = false;

  /// The check-in just saved, shown until the user taps Done.
  CheckIn? result;

  void set(void Function(CheckInViewModel vm) change) {
    change(this);
    notifyListeners();
  }

  void done() => set((vm) => vm.result = null);

  /// Saves the check-in, updates maintenance when it's due, and writes the feedback.
  void finish() {
    final repo = _repository;
    final review = repo.weekReview();
    final metric = repo.profile.metric;
    final c = CheckIn(
      trendStartKg: review.trendStart,
      trendEndKg: review.trendEnd,
      loggedDays: review.loggedDays,
      avgCalories: review.avgCalories,
      avgProtein: review.avgProtein,
      avgSteps: review.avgSteps,
      strengthSessions: review.strengthSessions,
      cardioMinutes: review.cardioMinutes,
      avgSleep: review.avgSleepHours,
      hunger: hunger,
      energy: energy,
      adherence: adherence,
      note: note,
    );
    final w = waist;
    if (w != null && w > 0) {
      final cm = metric ? w : w * 2.54;
      c.waistCm = cm;
      repo.addWaist(cm);
    }

    final targetsBefore = repo.targets;
    c.maintenanceBefore = repo.profile.maintenance;
    final recent = repo.maintenanceUpdatedRecently;
    final adaptive = repo.updateMaintenanceIfDue();
    c.maintenanceAfter = repo.profile.maintenance;
    if (takeBreak) repo.data.profile.maintenanceBreakUntil = Day.add(7, Day.start(DateTime.now()));
    final t = repo.targets;
    c.calorieTarget = t.calories;

    final feedback = Plan.feedback(
      review: review,
      targets: targetsBefore,
      pace: repo.profile.pace,
      weeksInDeficit: repo.weeksInDeficit,
    );
    if (adaptive != null) {
      final change = t.calories - targetsBefore.calories;
      if (change.abs() >= 20) {
        feedback.add(
          'Based on your last ${adaptive.loggedDays} logged days and weight trend, your maintenance is about ${Fmt.kcal(adaptive.observed)} kcal. Your target moves ${change > 0 ? 'up' : 'down'} ${change.abs()} kcal to ${Fmt.int_(t.calories)}.',
        );
      } else {
        feedback.add('Your data matches the current estimate; your target stays at ${Fmt.int_(t.calories)} kcal.');
      }
    } else if (recent) {
      feedback.add(
        'Your maintenance estimate was updated in the last week, so it stays at ${Fmt.kcal(repo.profile.maintenance)} kcal until next week.',
      );
    } else if (Day.between(repo.profile.planStart, DateTime.now()) < 21) {
      feedback.add(
        "Your maintenance estimate starts learning from your data after about three weeks of logging and weigh-ins. The first week's drop is mostly water, so it's left out.",
      );
    } else {
      feedback.add(
        'Not enough logged days or weigh-ins in the last three weeks to update your maintenance estimate. Log at least 10 days and weigh in 6 or more times.',
      );
    }
    if ((hunger ?? 0) >= 4) {
      feedback.add(
        'High hunger: lean on protein, high-fibre vegetables, fruit and soups for volume, and check your sleep. If it lasts, a maintenance week or the gentle pace can help.',
      );
    }
    if (takeBreak) {
      feedback.add(
        'Maintenance week on: eat about ${Fmt.int_(t.calories)} kcal until ${DateFormat.yMMMd().format(Day.add(7, DateTime.now()))}.',
      );
    }
    c.feedback = feedback;
    repo.data.checkIns.add(c);
    repo.changed();

    result = c;
    waist = null;
    hunger = energy = adherence = null;
    note = '';
    takeBreak = false;
    notifyListeners();
  }
}
