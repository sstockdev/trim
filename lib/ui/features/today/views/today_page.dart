import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../../domain/format.dart';
import '../../../../data/services/health_service.dart';
import '../../../../domain/models.dart';
import '../../../../domain/plan.dart';
import '../../../../data/repositories/app_repository.dart';
import '../../../../plugins/plugin_registry.dart';
import '../../add_food/views/add_food_page.dart';
import '../../check_in/views/check_in_page.dart';
import '../../../core/theme.dart';
import '../../../core/widgets.dart';
import '../../add_food/views/food_detail_page.dart';

class TodayPage extends StatefulWidget {
  const TodayPage({super.key});
  @override
  State<TodayPage> createState() => _TodayPageState();
}

class _TodayPageState extends State<TodayPage> {
  DateTime _day = Day.start(DateTime.now());

  bool get _isToday => Day.isToday(_day);

  String get _title {
    if (_isToday) return 'Today';
    if (Day.between(_day, DateTime.now()) == 1) return 'Yesterday';
    return DateFormat('EEE, MMM d').format(_day);
  }

  void _add(Meal meal) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => AddFoodPage(day: _day, meal: meal),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final repository = context.watch<AppRepository>();
    return Scaffold(
      appBar: AppBar(
        title: Text(_title),
        leadingWidth: 104,
        leading: Row(
          children: [
            IconButton(icon: const Icon(Icons.chevron_left), onPressed: () => setState(() => _day = Day.add(-1, _day))),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              onPressed: _isToday ? null : () => setState(() => _day = Day.add(1, _day)),
            ),
          ],
        ),
        actions: [
          if (!_isToday)
            TextButton(onPressed: () => setState(() => _day = Day.start(DateTime.now())), child: const Text('Today')),
          IconButton(icon: const Icon(Icons.add), onPressed: () => _add(_isToday ? Meal.guess() : Meal.snack)),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => repository.syncHealth(days: 7),
        child: ListView(
          padding: const EdgeInsets.only(top: 8, bottom: 24),
          children: [
            _summary(repository),
            _alerts(repository),
            _weight(repository),
            for (final p in context.watch<PluginRegistry>().active) ?p.todaySection(context, _day),
            for (final m in Meal.values) _meal(repository, m),
            _activity(repository),
            _daySection(repository),
          ],
        ),
      ),
    );
  }

  Widget _summary(AppRepository repository) {
    final t = repository.targets;
    final n = repository.totals(_day);
    final cal = repository.calorieTarget(_day);
    return Section(
      children: [
        Row(
          children: [
            CalorieRing(eaten: n.calories, target: cal.total.toDouble()),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${Fmt.kcal(n.calories)} of ${Fmt.int_(cal.total)} kcal',
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                  ),
                  if (cal.bonus > 0)
                    Text(
                      'Includes +${cal.bonus} for extra activity',
                      style: TextStyle(fontSize: 12, color: context.secondaryText),
                    ),
                  if (t.maintaining)
                    const Text(
                      'Maintenance',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: TrimColors.green),
                    ),
                  const SizedBox(height: 4),
                  MacroLine(n),
                ],
              ),
            ),
          ],
        ),
        GoalBar(
          title: 'Protein',
          value: n.protein,
          target: t.protein.toDouble(),
          unit: 'g',
          tint: TrimColors.red,
          isMinimum: true,
        ),
        GoalBar(
          title: 'Fibre',
          value: n.fiber,
          target: t.fiber.toDouble(),
          unit: 'g',
          tint: TrimColors.green,
          isMinimum: true,
        ),
        GoalBar(title: 'Carbs', value: n.carbs, target: t.carbs.toDouble(), unit: 'g', tint: TrimColors.blue),
        GoalBar(title: 'Fat', value: n.fat, target: t.fat.toDouble(), unit: 'g', tint: TrimColors.yellow),
      ],
    );
  }

  Widget _alerts(AppRepository repository) {
    final alerts = [...repository.warnings.where((w) => w.level != WarningLevel.info), ...repository.trendAlerts];
    if (alerts.isEmpty && !repository.checkInDue) return const SizedBox.shrink();
    return Section(
      children: [
        for (final a in alerts) WarningRow(a),
        if (repository.checkInDue)
          RowButton(
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const CheckInPage())),
            child: Row(
              children: [
                Icon(Icons.checklist, color: context.colors.primary),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text('Your weekly check-in is ready', style: TextStyle(fontWeight: FontWeight.w500)),
                ),
                const Icon(Icons.chevron_right),
              ],
            ),
          ),
      ],
    );
  }

  Widget _weight(AppRepository repository) {
    final metric = repository.profile.metric;
    final w = repository.weight(_day);
    final trend = Plan.trendValue(_day, repository.trend);
    return Section(
      children: [
        RowButton(
          onTap: () => showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            useSafeArea: true,
            builder: (_) => ChangeNotifierProvider.value(
              value: repository,
              child: WeighInSheet(day: _day),
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.monitor_weight_outlined, color: context.colors.primary),
              const SizedBox(width: 10),
              Expanded(
                child: w != null
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            Fmt.weight(w.kg, metric),
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                          ),
                          Text(
                            w.fromHealth ? 'From ${HealthService.name}' : 'Weigh-in',
                            style: TextStyle(fontSize: 12, color: context.secondaryText),
                          ),
                        ],
                      )
                    : Text(_isToday ? "Log this morning's weight" : 'Log weight'),
              ),
              if (trend != null)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(Fmt.weight(trend, metric)),
                    Text('trend', style: TextStyle(fontSize: 12, color: context.secondaryText)),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _meal(AppRepository repository, Meal meal) {
    final entries = repository.entries(_day).where((e) => e.meal == meal).toList();
    final kcal = entries.fold(0.0, (s, e) => s + e.nutrients.calories);
    return Section(
      header: Row(
        children: [
          Expanded(child: Text(meal.title.toUpperCase())),
          if (kcal > 0) Text('${Fmt.kcal(kcal)} KCAL'),
          PopupMenuButton<int>(
            padding: EdgeInsets.zero,
            iconSize: 18,
            icon: const Icon(Icons.more_horiz),
            itemBuilder: (_) => const [PopupMenuItem(value: 0, child: Text('Copy from yesterday'))],
            onSelected: (_) => repository.copyMeal(meal, Day.add(-1, _day), _day),
          ),
        ],
      ),
      children: [
        for (final e in entries)
          Dismissible(
            key: ValueKey(e.id),
            direction: DismissDirection.endToStart,
            background: const DeleteBackground(),
            onDismissed: (_) => repository.deleteEntry(e.id),
            child: RowButton(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => FoodDetailPage.entry(e),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(e.item.name, maxLines: 2),
                        Text(
                          [e.amountText, e.item.brand].whereType<String>().join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: context.secondaryText),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(Fmt.kcal(e.nutrients.calories)),
                      Text(
                        '${e.nutrients.protein.round()} g P',
                        style: TextStyle(fontSize: 12, color: context.secondaryText),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        RowButton(
          onTap: () => _add(meal),
          child: Row(
            children: [
              Icon(Icons.add_circle_outline, size: 20, color: context.colors.primary),
              const SizedBox(width: 8),
              Text('Add food', style: TextStyle(color: context.colors.primary)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _activity(AppRepository repository) {
    final t = repository.targets;
    final a = repository.activity(_day);
    return Section(
      title: 'Activity',
      children: [
        if (!repository.profile.useHealth)
          Text(
            'Connect ${HealthService.name} in Settings.',
            style: TextStyle(color: context.secondaryText),
          )
        else if (a != null) ...[
          GoalBar(
            title: 'Steps',
            value: a.steps ?? 0,
            target: t.steps.toDouble(),
            unit: '',
            tint: TrimColors.teal,
            isMinimum: true,
          ),
          Row(
            children: [
              Stat('Active', a.activeKcal == null ? null : '${Fmt.kcal(a.activeKcal!)} kcal'),
              Stat('Sleep', a.sleepHours == null ? null : '${a.sleepHours!.toStringAsFixed(1)} h'),
              Stat('Resting HR', a.restingHR == null ? null : '${a.restingHR!.toInt()} bpm'),
            ],
          ),
          if (a.workouts.isNotEmpty)
            Row(
              children: [
                const Icon(Icons.fitness_center, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text(a.workouts.join(', '))),
              ],
            ),
        ] else
          Text('No activity yet. Pull down to sync.', style: TextStyle(color: context.secondaryText)),
      ],
    );
  }

  Widget _daySection(AppRepository repository) {
    final note = repository.note(_day);
    return Section(
      title: 'How today went',
      footerText:
          "Mark a day incomplete if you couldn't log everything, so it doesn't throw off your maintenance estimate. Auto counts days with at least ${AppRepository.minimumCountedKcal.toInt()} kcal logged.",
      children: [
        RatingPicker(
          title: 'Hunger',
          low: 'Not hungry',
          high: 'Very hungry',
          value: note.hunger,
          onChanged: (v) => repository.setNote(_day, (n) => n.hunger = v),
        ),
        RatingPicker(
          title: 'Energy',
          low: 'Drained',
          high: 'Great',
          value: note.energy,
          onChanged: (v) => repository.setNote(_day, (n) => n.energy = v),
        ),
        Row(
          children: [
            Expanded(child: Text('Water: ${note.water} glass${note.water == 1 ? '' : 'es'}')),
            IconButton(
              icon: const Icon(Icons.remove),
              onPressed: note.water <= 0 ? null : () => repository.setNote(_day, (n) => n.water -= 1),
            ),
            IconButton(
              icon: const Icon(Icons.add),
              onPressed: note.water >= 20 ? null : () => repository.setNote(_day, (n) => n.water += 1),
            ),
          ],
        ),
        Row(
          children: [
            const Expanded(child: Text('Food log')),
            SegmentedButton<int>(
              showSelectedIcon: false,
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
              segments: const [
                ButtonSegment(value: 0, label: Text('Auto')),
                ButtonSegment(value: 1, label: Text('Complete')),
                ButtonSegment(value: 2, label: Text('Incomplete')),
              ],
              selected: {note.complete == null ? 0 : (note.complete! ? 1 : 2)},
              onSelectionChanged: (s) => repository.setNote(
                _day,
                (n) => n.complete = switch (s.first) {
                  1 => true,
                  2 => false,
                  _ => null,
                },
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class WeighInSheet extends StatefulWidget {
  final DateTime day;
  const WeighInSheet({super.key, required this.day});
  @override
  State<WeighInSheet> createState() => _WeighInSheetState();
}

class _WeighInSheetState extends State<WeighInSheet> {
  double? _value;

  /// The day's existing weigh-in as shown in the field, so saving without changing it doesn't log it again.
  double? _prefilled;
  double? _waist;
  late DateTime _date;

  @override
  void initState() {
    super.initState();
    final repository = context.read<AppRepository>();
    final day = widget.day;
    _date = Day.isToday(day) ? DateTime.now() : DateTime(day.year, day.month, day.day, 7);
    // Only the day's own weigh-in is filled in: a weight carried over from another day would be saved
    // as a new weigh-in when only a waist is entered.
    final w = repository.weight(day);
    _value = w == null ? null : Fmt.round1(Fmt.weightValue(w.kg, repository.profile.metric));
    _prefilled = _value;
  }

  void _save() {
    final repository = context.read<AppRepository>();
    final metric = repository.profile.metric;
    final v = _value;
    if (v != null && v > 0 && (v != _prefilled || !Day.same(_date, widget.day))) {
      final kg = Fmt.kgFromDisplay(v, metric);
      repository.recordWeighIn(kg, _date);
    }
    final w = _waist;
    if (w != null && w > 0) repository.addWaist(metric ? w : w * 2.54, _date);
    Navigator.pop(context);
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (d == null || !mounted) return;
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_date));
    final picked = DateTime(d.year, d.month, d.day, t?.hour ?? _date.hour, t?.minute ?? _date.minute);
    setState(() => _date = picked.isAfter(DateTime.now()) ? DateTime.now() : picked);
  }

  @override
  Widget build(BuildContext context) {
    final repository = context.watch<AppRepository>();
    final metric = repository.profile.metric;
    final existing = repository.weight(widget.day);
    final last = repository.weightsSorted.lastOrNull;
    final canSave = (_value ?? 0) > 0 || (_waist ?? 0) > 0;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                const Expanded(
                  child: Text(
                    'Weigh-in',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                TextButton(onPressed: canSave ? _save : null, child: const Text('Save')),
              ],
            ),
            const SizedBox(height: 8),
            Section(
              footerText: 'Weigh in each morning before eating.',
              children: [
                NumberField(
                  title: 'Weight',
                  value: _value,
                  unit: Fmt.weightUnit(metric),
                  onChanged: (v) => setState(() => _value = v),
                ),
                RowButton(
                  onTap: _pickDate,
                  child: KeyValue('When', DateFormat('MMM d, y, h:mm a').format(_date)),
                ),
                if (existing == null && last != null)
                  Text(
                    'Last weigh-in: ${Fmt.weight(last.kg, metric)}, ${DateFormat.yMMMd().format(last.date)}',
                    style: TextStyle(fontSize: 12, color: context.secondaryText),
                  ),
              ],
            ),
            Section(
              children: [
                NumberField(
                  title: 'Waist (optional)',
                  value: _waist,
                  unit: metric ? 'cm' : 'in',
                  onChanged: (v) => setState(() => _waist = v),
                ),
              ],
            ),
            if (existing != null)
              Section(
                children: [
                  RowButton(
                    onTap: () {
                      repository.deleteWeight(existing);
                      Navigator.pop(context);
                    },
                    child: const Text('Delete this weigh-in', style: TextStyle(color: TrimColors.red)),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
