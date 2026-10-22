import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../../domain/format.dart';
import '../../../../domain/plan.dart';
import '../../../../data/repositories/app_repository.dart';
import '../../../core/theme.dart';
import '../../../core/widgets.dart';

enum _Range {
  month('1M', 30),
  quarter('3M', 91),
  half('6M', 182),
  year('1Y', 365),
  all('All', null);

  final String label;
  final int? days;
  const _Range(this.label, this.days);
}

class TrendsPage extends StatefulWidget {
  const TrendsPage({super.key});
  @override
  State<TrendsPage> createState() => _TrendsPageState();
}

class _TrendsPageState extends State<TrendsPage> {
  _Range _range = _Range.month;

  DateTime _start(AppRepository repository) {
    final d = _range.days;
    if (d != null) return Day.add(-(d - 1), Day.start(DateTime.now()));
    final first = repository.weightsSorted.firstOrNull?.date ?? DateTime.now();
    final plan = repository.profile.planStart;
    return Day.start(first.isBefore(plan) ? first : plan);
  }

  List<DateTime> _days(DateTime start) {
    final n = math.max(1, Day.between(start, DateTime.now()) + 1);
    return [for (var i = 0; i < n; i++) Day.add(i, start)];
  }

  @override
  Widget build(BuildContext context) {
    final repository = context.watch<AppRepository>();
    final start = _start(repository);
    final days = _days(start);
    final cards = <Widget>[
      _weightCard(repository, start),
      _caloriesCard(repository, start, days),
      _proteinCard(repository, start, days),
      if (repository.profile.useHealth) ...[_stepsCard(repository, start, days), _sleepCard(repository, start, days)],
      if (repository.data.waists.isNotEmpty) _waistCard(repository),
      _maintenanceCard(repository),
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('Trends')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SegmentedButton<_Range>(
            showSelectedIcon: false,
            segments: [for (final r in _Range.values) ButtonSegment(value: r, label: Text(r.label))],
            selected: {_range},
            onSelectionChanged: (s) => setState(() => _range = s.first),
          ),
          for (final c in cards) ...[const SizedBox(height: 14), c],
        ],
      ),
    );
  }

  // Chart plumbing: x is days since `start`.

  double _x(DateTime start, DateTime d) => d.difference(start).inSeconds / 86400.0;

  FlTitlesData _titles(DateTime start, double maxX) {
    final step = math.max(1.0, (maxX / 4).ceilToDouble());
    return FlTitlesData(
      topTitles: const AxisTitles(),
      rightTitles: const AxisTitles(),
      leftTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 44,
          getTitlesWidget: (v, meta) => SideTitleWidget(
            meta: meta,
            child: Text(meta.formattedValue, style: TextStyle(fontSize: 10, color: context.secondaryText)),
          ),
        ),
      ),
      bottomTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          interval: step,
          reservedSize: 22,
          getTitlesWidget: (v, meta) => SideTitleWidget(
            meta: meta,
            child: Text(
              DateFormat('M/d').format(Day.add(v.round(), start)),
              style: TextStyle(fontSize: 10, color: context.secondaryText),
            ),
          ),
        ),
      ),
    );
  }

  HorizontalLine _rule(double y, Color color) => HorizontalLine(y: y, color: color, strokeWidth: 1, dashArray: [4, 4]);

  Widget _bars(
    DateTime start,
    List<(DateTime, double)> points,
    Color Function(double) color,
    double rule, {
    double height = 130,
  }) {
    final maxX = math.max(1.0, Day.between(start, DateTime.now()).toDouble());
    final maxY = [rule, ...points.map((p) => p.$2)].reduce(math.max) * 1.1;
    final width = math.max(2.0, math.min(10.0, 260 / (maxX + 1)));
    return SizedBox(
      height: height,
      child: BarChart(
        BarChartData(
          minY: 0,
          maxY: maxY <= 0 ? 1 : maxY,
          alignment: BarChartAlignment.spaceBetween,
          barGroups: [
            for (final p in points)
              BarChartGroupData(
                x: Day.between(start, p.$1),
                barRods: [
                  BarChartRodData(toY: p.$2, color: color(p.$2), width: width, borderRadius: BorderRadius.circular(2)),
                ],
              ),
          ],
          extraLinesData: ExtraLinesData(horizontalLines: [_rule(rule, context.secondaryText)]),
          titlesData: _titles(start, maxX),
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          barTouchData: BarTouchData(enabled: false),
        ),
      ),
    );
  }

  Widget _line(List<(double, double)> points, {double height = 110, DateTime? start}) {
    final ys = points.map((p) => p.$2);
    final lo = ys.reduce(math.min), hi = ys.reduce(math.max);
    final pad = math.max(1.0, (hi - lo) * 0.1);
    return SizedBox(
      height: height,
      child: LineChart(
        LineChartData(
          minY: lo - pad,
          maxY: hi + pad,
          lineBarsData: [
            LineChartBarData(
              spots: [for (final p in points) FlSpot(p.$1, p.$2)],
              color: context.colors.primary,
              barWidth: 2,
              dotData: const FlDotData(show: true),
            ),
          ],
          titlesData: start == null
              ? const FlTitlesData(
                  topTitles: AxisTitles(),
                  rightTitles: AxisTitles(),
                  bottomTitles: AxisTitles(),
                  leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 44)),
                )
              : _titles(start, points.last.$1),
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          lineTouchData: const LineTouchData(enabled: false),
        ),
      ),
    );
  }

  Widget _header(String title, [String? caption, Color? captionColor]) => Row(
    children: [
      Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 17)),
      const Spacer(),
      if (caption != null) Text(caption, style: TextStyle(fontSize: 12, color: captionColor ?? context.secondaryText)),
    ],
  );

  // Weight

  Widget _weightCard(AppRepository repository, DateTime start) {
    final metric = repository.profile.metric;
    final weights = repository.weightsSorted.where((w) => !w.date.isBefore(start)).toList();
    final trend = repository.trend.where((t) => !t.date.isBefore(start)).toList();
    final goal = Fmt.weightValue(repository.profile.goalKg, metric);
    if (weights.isEmpty) {
      return Card2(
        children: [
          _header('Weight'),
          Text('Weigh in on the Today tab to see your trend.', style: TextStyle(color: context.secondaryText)),
        ],
      );
    }
    final values = [...weights.map((w) => Fmt.weightValue(w.kg, metric)), goal];
    final maxX = math.max(1.0, Day.between(start, DateTime.now()).toDouble());
    return Card2(
      children: [
        _header('Weight'),
        _weightStats(repository, start),
        SizedBox(
          height: 200,
          child: LineChart(
            LineChartData(
              minX: 0,
              maxX: maxX,
              minY: values.reduce(math.min) - 1,
              maxY: values.reduce(math.max) + 1,
              lineBarsData: [
                LineChartBarData(
                  spots: [for (final w in weights) FlSpot(_x(start, w.date), Fmt.weightValue(w.kg, metric))],
                  barWidth: 0,
                  color: Colors.transparent,
                  dotData: FlDotData(
                    show: true,
                    getDotPainter: (s, p, b, i) =>
                        FlDotCirclePainter(radius: 2.5, color: Colors.grey.withValues(alpha: .5), strokeWidth: 0),
                  ),
                ),
                LineChartBarData(
                  spots: [for (final t in trend) FlSpot(_x(start, t.date), Fmt.weightValue(t.kg, metric))],
                  isCurved: true,
                  preventCurveOverShooting: true,
                  color: context.colors.primary,
                  barWidth: 2,
                  dotData: const FlDotData(show: false),
                ),
              ],
              extraLinesData: ExtraLinesData(horizontalLines: [_rule(goal, TrimColors.green.withValues(alpha: .6))]),
              titlesData: _titles(start, maxX),
              gridData: const FlGridData(show: false),
              borderData: FlBorderData(show: false),
              lineTouchData: const LineTouchData(enabled: false),
            ),
          ),
        ),
      ],
    );
  }

  Widget _weightStats(AppRepository repository, DateTime start) {
    final metric = repository.profile.metric;
    final line = repository.trend;
    final now = line.lastOrNull?.kg;
    final then = Plan.trendValue(start, line) ?? line.firstOrNull?.kg;
    final fourWeeksAgo = Plan.trendValue(Day.add(-28, DateTime.now()), line);
    final rate = now != null && fourWeeksAgo != null ? (fourWeeksAgo - now) / 4 : null;
    final toGo = now == null ? null : now - repository.profile.goalKg;
    String? eta() {
      if (toGo == null) return null;
      if (toGo <= 0.3) return 'Reached';
      if (rate == null || rate <= 0.05) return Fmt.weight(toGo, metric);
      return '~${(toGo / rate).ceil()} wk';
    }

    return Row(
      children: [
        Stat('Trend', now == null ? null : Fmt.weight(now, metric)),
        Stat('Change', now != null && then != null ? Fmt.signedWeight(now - then, metric) : null),
        Stat('Per week', rate == null ? null : Fmt.signedWeight(-rate, metric)),
        Stat('To goal', eta()),
      ],
    );
  }

  // Food

  Widget _caloriesCard(AppRepository repository, DateTime start, List<DateTime> days) {
    final counted = [
      for (final d in days)
        if (repository.countedIntake(d) case final k?) (d, k),
    ];
    final target = repository.targets.calories.toDouble();
    final avg = counted.isEmpty ? null : counted.fold(0.0, (s, p) => s + p.$2) / counted.length;
    return Card2(
      children: [
        _header('Calories', avg == null ? null : 'avg ${Fmt.kcal(avg)} · ${counted.length} days logged'),
        _bars(
          start,
          counted,
          (k) => k > target * 1.05 ? TrimColors.orange : context.colors.primary,
          target,
          height: 150,
        ),
      ],
    );
  }

  Widget _proteinCard(AppRepository repository, DateTime start, List<DateTime> days) {
    final points = [
      for (final d in days)
        if (repository.countedIntake(d) != null) (d, repository.totals(d).protein),
    ];
    final target = repository.targets.protein.toDouble();
    final hit = points.where((p) => p.$2 >= target * 0.9).length;
    return Card2(
      children: [
        _header('Protein', points.isEmpty ? null : 'target hit $hit of ${points.length} days'),
        _bars(
          start,
          points,
          (g) => g >= target * 0.9 ? TrimColors.green : TrimColors.red.withValues(alpha: .7),
          target,
        ),
      ],
    );
  }

  // Activity

  Widget _stepsCard(AppRepository repository, DateTime start, List<DateTime> days) {
    final points = [
      for (final d in days)
        if (repository.activity(d)?.steps case final s?) (d, s),
    ];
    final target = repository.targets.steps.toDouble();
    final avg = points.isEmpty ? null : points.fold(0.0, (s, p) => s + p.$2) / points.length;
    final strength = days.fold(0, (s, d) => s + (repository.activity(d)?.strengthSessions ?? 0));
    final weeks = math.max(1.0, days.length / 7);
    return Card2(
      children: [
        _header(
          'Steps',
          avg == null ? null : 'avg ${Fmt.int_(avg.toInt())} · lifting ${(strength / weeks).toStringAsFixed(1)}/wk',
        ),
        _bars(start, points, (s) => s >= target ? TrimColors.teal : TrimColors.teal.withValues(alpha: .45), target),
      ],
    );
  }

  Widget _sleepCard(AppRepository repository, DateTime start, List<DateTime> days) {
    final points = [
      for (final d in days)
        if (repository.activity(d)?.sleepHours case final h?) (d, h),
    ];
    final avg = points.isEmpty ? null : points.fold(0.0, (s, p) => s + p.$2) / points.length;
    return Card2(
      children: [
        _header('Sleep', avg == null ? null : 'avg ${avg.toStringAsFixed(1)} h'),
        _bars(
          start,
          points,
          (h) => h >= 7 ? TrimColors.indigo : TrimColors.indigo.withValues(alpha: .45),
          7,
          height: 110,
        ),
      ],
    );
  }

  // Body and program

  Widget _waistCard(AppRepository repository) {
    final metric = repository.profile.metric;
    final waists = [...repository.data.waists]..sort((a, b) => a.date.compareTo(b.date));
    final latest = waists.last;
    final ratio = latest.cm / repository.profile.heightCm;
    final first = Day.start(waists.first.date);
    return Card2(
      children: [
        _header('Waist', 'waist ÷ height ${ratio.toStringAsFixed(2)}', ratio < 0.5 ? TrimColors.green : null),
        if (waists.length > 1)
          _line([for (final w in waists) (_x(first, w.date), metric ? w.cm : w.cm / 2.54)], start: first)
        else
          Text(Fmt.length(latest.cm, metric), style: const TextStyle(fontSize: 20)),
        Text(
          'Under 0.5 is the healthy range (NICE). Measure at your weekly check-in.',
          style: TextStyle(fontSize: 12, color: context.secondaryText),
        ),
      ],
    );
  }

  Widget _maintenanceCard(AppRepository repository) {
    final history = ([
      ...repository.data.checkIns,
    ]..sort((a, b) => a.date.compareTo(b.date))).where((c) => c.maintenanceAfter != null).toList();
    final first = history.isEmpty ? DateTime.now() : Day.start(history.first.date);
    return Card2(
      children: [
        _header('Maintenance estimate'),
        Text('${Fmt.kcal(repository.profile.maintenance)} kcal', style: const TextStyle(fontSize: 15)),
        if (history.length > 1)
          _line([for (final c in history) (_x(first, c.date), c.maintenanceAfter!)], start: first),
        Text(
          repository.profile.maintenanceUpdated == null
              ? 'Based on the formula until about three weeks of logging and weigh-ins, then learned from your data.'
              : 'Learned from your logging and weight trend; it updates each week.',
          style: TextStyle(fontSize: 12, color: context.secondaryText),
        ),
      ],
    );
  }
}
