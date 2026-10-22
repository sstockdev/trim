import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../../data/repositories/app_repository.dart';
import '../../../../domain/format.dart';
import '../../../../domain/models.dart';
import '../../../core/theme.dart';
import '../../../core/widgets.dart';
import '../view_models/check_in_view_model.dart';

/// The weekly review: what happened over the last seven days, a few questions, then updated targets.
class CheckInPage extends StatelessWidget {
  const CheckInPage({super.key});

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create: (c) => CheckInViewModel(repository: c.read<AppRepository>()),
    child: const _CheckInView(),
  );
}

class _CheckInView extends StatefulWidget {
  const _CheckInView();
  @override
  State<_CheckInView> createState() => _CheckInViewState();
}

class _CheckInViewState extends State<_CheckInView> {
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<CheckInViewModel>();
    final repository = context.watch<AppRepository>();
    final result = vm.result;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Weekly check-in'),
        actions: [if (result != null) TextButton(onPressed: vm.done, child: const Text('Done'))],
      ),
      body: ListView(
        padding: const EdgeInsets.only(top: 12, bottom: 24),
        children: result != null
            ? CheckInResult.sections(context, repository, result, current: true)
            : _review(context, vm, repository),
      ),
    );
  }

  List<Widget> _review(BuildContext context, CheckInViewModel vm, AppRepository repository) {
    final r = repository.weekReview();
    final t = repository.targets;
    final metric = repository.profile.metric;
    return [
      Section(
        title: 'Last 7 days',
        footerText: repository.checkInDue ? null : 'Next check-in in ${7 - repository.daysSinceCheckIn} days.',
        children: [
          KeyValue('Trend', r.changeKg == null ? '-' : Fmt.signedWeight(r.changeKg!, metric)),
          KeyValue('Days fully logged', '${r.loggedDays} of 7'),
          KeyValue(
            'Average calories',
            r.avgCalories == null ? '-' : '${Fmt.kcal(r.avgCalories!)} / ${Fmt.int_(t.calories)}',
          ),
          KeyValue('Protein target hit', '${r.proteinDays} of ${r.loggedDays} days'),
          if (repository.profile.useHealth) ...[
            KeyValue('Average steps', r.avgSteps == null ? '-' : Fmt.int_(r.avgSteps!.toInt())),
            KeyValue('Strength sessions', '${r.strengthSessions}'),
            KeyValue('Cardio', '${r.cardioMinutes.toInt()} min'),
            KeyValue('Average sleep', r.avgSleepHours == null ? '-' : '${r.avgSleepHours!.toStringAsFixed(1)} h'),
          ],
        ],
      ),
      Section(
        footerText: 'At belly-button level, after breathing out.',
        children: [
          NumberField(
            title: 'Waist',
            value: vm.waist,
            unit: metric ? 'cm' : 'in',
            onChanged: (v) => vm.set((m) => m.waist = v),
          ),
        ],
      ),
      Section(
        children: [
          RatingPicker(
            title: 'Hunger this week',
            low: 'Rarely hungry',
            high: 'Always hungry',
            value: vm.hunger,
            onChanged: (v) => vm.set((m) => m.hunger = v),
          ),
          RatingPicker(
            title: 'Energy this week',
            low: 'Drained',
            high: 'Great',
            value: vm.energy,
            onChanged: (v) => vm.set((m) => m.energy = v),
          ),
          RatingPicker(
            title: 'Sticking to the plan',
            low: 'Hard',
            high: 'Easy',
            value: vm.adherence,
            onChanged: (v) => vm.set((m) => m.adherence = v),
          ),
          TextField(
            controller: _note,
            minLines: 1,
            maxLines: 5,
            onChanged: (v) => vm.note = v,
            decoration: const InputDecoration(hintText: 'Notes (optional)', border: InputBorder.none, isDense: true),
          ),
        ],
      ),
      Section(
        footerText: repository.weeksInDeficit >= 8
            ? '${repository.weeksInDeficit} weeks in a deficit. A break now eases hunger.'
            : 'Eat at maintenance for a week.',
        children: [SwitchRow('Take a maintenance week', vm.takeBreak, (v) => vm.set((m) => m.takeBreak = v))],
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: FilledButton(
          onPressed: () {
            vm.finish();
            _note.clear();
          },
          child: const Text('Finish check-in'),
        ),
      ),
      if (repository.data.checkIns.isNotEmpty) _history(context, repository),
    ];
  }

  Widget _history(BuildContext context, AppRepository repository) {
    final list = [...repository.data.checkIns]..sort((a, b) => b.date.compareTo(a.date));
    return Section(
      title: 'Past check-ins',
      children: [
        for (final c in list)
          RowButton(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (ctx) => Scaffold(
                  appBar: AppBar(title: Text(DateFormat.yMMMd().format(c.date))),
                  body: ListView(
                    padding: const EdgeInsets.only(top: 12, bottom: 24),
                    children: CheckInResult.sections(ctx, repository, c, current: false),
                  ),
                ),
              ),
            ),
            child: Row(
              children: [
                Expanded(child: Text(DateFormat.yMMMd().format(c.date))),
                if ((c.trendStartKg, c.trendEndKg) case (final a?, final b?))
                  Text(
                    Fmt.signedWeight(b - a, repository.profile.metric),
                    style: TextStyle(color: context.secondaryText),
                  ),
                const Icon(Icons.chevron_right),
              ],
            ),
          ),
      ],
    );
  }
}

/// A saved check-in: feedback, the targets it set, and notes.
abstract final class CheckInResult {
  static List<Widget> sections(BuildContext context, AppRepository repository, CheckIn c, {required bool current}) {
    final before = c.maintenanceBefore, after = c.maintenanceAfter;
    return [
      Section(title: 'Feedback', children: [for (final f in c.feedback) Text(f)]),
      Section(
        title: 'Targets',
        children: [
          if (before != null && after != null)
            KeyValue(
              'Maintenance estimate',
              (after - before).abs() < 1 ? '${Fmt.kcal(after)} kcal' : '${Fmt.kcal(before)} → ${Fmt.kcal(after)} kcal',
            ),
          if (c.calorieTarget case final cal?) KeyValue('Daily calories', '${Fmt.int_(cal)} kcal'),
          if (current) ...[
            KeyValue('Protein', '${repository.targets.protein} g'),
            KeyValue('Steps', Fmt.int_(repository.targets.steps)),
          ],
        ],
      ),
      if (c.note.isNotEmpty) Section(title: 'Notes', children: [Text(c.note)]),
    ];
  }
}
