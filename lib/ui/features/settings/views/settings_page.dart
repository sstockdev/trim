import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../domain/format.dart';
import '../../../../data/services/health_service.dart';
import '../../../../domain/models.dart';
import '../../../../domain/plan.dart';
import '../../../../data/repositories/app_repository.dart';
import '../../../../plugins/plugin_registry.dart';
import '../../../core/theme.dart';
import '../../../core/widgets.dart';
import 'guide_page.dart';
import 'plugins_page.dart';
import 'usda_key_section.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _syncing = false;

  @override
  Widget build(BuildContext context) {
    final repository = context.watch<AppRepository>();
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.only(top: 12, bottom: 24),
        children: [
          _program(repository),
          _profile(repository),
          _safety(repository),
          _healthSection(repository),
          const UsdaKeySection(title: 'Food search'),
          _plugins(),
          _data(repository),
        ],
      ),
    );
  }

  Widget _program(AppRepository repository) {
    final t = repository.targets;
    final p = repository.profile;
    return Section(
      title: 'Program',
      footerText: 'When on, you get half of any active calories above a normal day.',
      children: [
        RowButton(
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const GuidePage())),
          child: Row(
            children: [
              Icon(Icons.menu_book, color: context.colors.primary),
              const SizedBox(width: 12),
              const Expanded(child: Text('How the program works')),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
        KeyValue('Maintenance estimate', '${Fmt.kcal(p.maintenance)} kcal'),
        KeyValue('Daily target', '${Fmt.int_(t.calories)} kcal · ${t.protein} g protein'),
        PickerRow<Pace>(
          label: 'Pace',
          value: p.pace,
          values: Pace.values,
          title: (v) => v.title,
          onChanged: (v) => repository.update((d) => d.profile.pace = v),
        ),
        SwitchRow(
          'Eat back some exercise calories',
          p.eatBackExercise,
          (v) => repository.update((d) => d.profile.eatBackExercise = v),
        ),
        RowButton(
          onTap: () => repository.update(
            (d) => d.profile.maintenanceBreakUntil = repository.onMaintenanceBreak
                ? null
                : Day.add(7, Day.start(DateTime.now())),
          ),
          child: Text(
            repository.onMaintenanceBreak ? 'End maintenance week' : 'Start a maintenance week',
            style: TextStyle(color: context.colors.primary),
          ),
        ),
        RowButton(
          onTap: () => repository.update((d) {
            d.profile.maintenance = Plan.startingTDEE(
              sex: p.sex,
              weightKg: repository.trendKg,
              heightCm: p.heightCm,
              age: p.age,
              activity: p.activity,
            );
            d.profile.maintenanceUpdated = null;
          }),
          child: Text('Reset estimate to the formula', style: TextStyle(color: context.colors.primary)),
        ),
      ],
    );
  }

  Widget _profile(AppRepository repository) {
    final p = repository.profile;
    final metric = p.metric;
    return Section(
      title: 'Profile',
      children: [
        Row(
          children: [
            const Expanded(child: Text('Units')),
            SegmentedButton<bool>(
              showSelectedIcon: false,
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
              segments: const [
                ButtonSegment(value: false, label: Text('lb / in')),
                ButtonSegment(value: true, label: Text('kg / cm')),
              ],
              selected: {metric},
              onSelectionChanged: (s) => repository.update((d) => d.profile.metric = s.first),
            ),
          ],
        ),
        Row(
          children: [
            const Expanded(child: Text('Goal weight')),
            SizedBox(
              width: 120,
              child: NumberField(
                key: ValueKey('goal-$metric'),
                title: 'Goal',
                value: Fmt.round1(Fmt.weightValue(p.goalKg, metric)),
                unit: Fmt.weightUnit(metric),
                textAlign: TextAlign.end,
                onChanged: (v) {
                  if (v != null && v > 30) repository.update((d) => d.profile.goalKg = Fmt.kgFromDisplay(v, metric));
                },
              ),
            ),
          ],
        ),
        Row(
          children: [
            const Expanded(child: Text('Height')),
            SizedBox(
              width: 120,
              child: NumberField(
                key: ValueKey('height-$metric'),
                title: 'Height',
                value: Fmt.round1(metric ? p.heightCm : p.heightCm / 2.54),
                unit: metric ? 'cm' : 'in',
                textAlign: TextAlign.end,
                onChanged: (v) {
                  if (v == null) return;
                  final cm = metric ? v : v * 2.54;
                  if (cm > 120 && cm < 230) repository.update((d) => d.profile.heightCm = cm);
                },
              ),
            ),
          ],
        ),
        PickerRow<Sex>(
          label: 'Sex',
          value: p.sex,
          values: Sex.values,
          title: (v) => v.title,
          onChanged: (v) => repository.update((d) => d.profile.sex = v),
        ),
        RowButton(
          onTap: () async {
            final d = await showDatePicker(
              context: context,
              initialDate: p.birthDate,
              firstDate: DateTime(1900),
              lastDate: DateTime.now(),
            );
            if (d != null) repository.update((x) => x.profile.birthDate = d);
          },
          child: KeyValue('Birthday', DateFormat.yMMMd().format(p.birthDate)),
        ),
        PickerRow<ActivityLevel>(
          label: 'Activity (first weeks)',
          value: p.activity,
          values: ActivityLevel.values,
          title: (v) => v.title,
          onChanged: (v) => repository.update((d) => d.profile.activity = v),
        ),
        PickerRow<StrengthExperience>(
          label: 'Strength training',
          value: p.strength,
          values: StrengthExperience.values,
          title: (v) => v.title,
          onChanged: (v) => repository.update((d) => d.profile.strength = v),
        ),
        PickerRow<DietStyle>(
          label: 'Eating style',
          value: p.diet,
          values: DietStyle.values,
          title: (v) => v.title,
          onChanged: (v) => repository.update((d) => d.profile.diet = v),
        ),
      ],
    );
  }

  Widget _safety(AppRepository repository) {
    final s = repository.profile.screening;
    void set(void Function(Screening s) f) => repository.update((d) => f(d.profile.screening));
    return Section(
      title: 'Health check',
      children: [
        SwitchRow(
          'Pregnant or breastfeeding',
          s.pregnantOrBreastfeeding,
          (v) => set((x) => x.pregnantOrBreastfeeding = v),
        ),
        SwitchRow(
          'History of an eating disorder',
          s.eatingDisorderHistory,
          (v) => set((x) => x.eatingDisorderHistory = v),
        ),
        SwitchRow('Insulin or sulfonylureas', s.diabetesMedication, (v) => set((x) => x.diabetesMedication = v)),
        SwitchRow('GLP-1 medicine', s.glp1Medication, (v) => set((x) => x.glp1Medication = v)),
        SwitchRow('Kidney disease', s.kidneyDisease, (v) => set((x) => x.kidneyDisease = v)),
        for (final w in repository.warnings) WarningRow(w),
      ],
    );
  }

  Widget _healthSection(AppRepository repository) {
    final p = repository.profile;
    final name = HealthService.name;
    return Section(
      title: name,
      footerText: HealthService.isIOS
          ? 'Missing data? Check Health, Sharing, Apps, $appName.'
          : 'Missing data? Check Health Connect, App permissions, $appName.',
      children: [
        SwitchRow('Use $name', p.useHealth, (on) => on ? repository.connectHealth() : repository.disconnectHealth()),
        if (p.useHealth) ...[
          SwitchRow(
            'Save weigh-ins to $name',
            p.writeWeightToHealth,
            (v) => repository.update((d) => d.profile.writeWeightToHealth = v),
          ),
          RowButton(
            onTap: _syncing
                ? null
                : () async {
                    setState(() => _syncing = true);
                    await repository.syncHealth(days: 60);
                    if (mounted) setState(() => _syncing = false);
                  },
            child: Row(
              children: [
                Expanded(
                  child: Text('Sync now', style: TextStyle(color: context.colors.primary)),
                ),
                if (_syncing)
                  const Busy()
                else if (repository.healthLastSync case final t?)
                  Text(DateFormat.jm().format(t), style: TextStyle(color: context.secondaryText)),
              ],
            ),
          ),
        ],
        if (repository.healthError case final e?)
          Text(e, style: const TextStyle(fontSize: 13, color: TrimColors.orange)),
      ],
    );
  }

  Widget _plugins() {
    final registry = context.watch<PluginRegistry>();
    return Section(
      title: 'Plugins',
      children: [
        for (final p in registry.installed) PluginRow(p),
        RowButton(
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const PluginsPage())),
          child: Row(
            children: [
              Icon(Icons.extension_outlined, color: context.colors.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  registry.installed.isEmpty ? 'Browse plugins' : 'All plugins',
                  style: TextStyle(color: context.colors.primary),
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ],
    );
  }

  Widget _data(AppRepository repository) => Section(
    title: 'Data',
    footerText: HealthService.isIOS
        ? 'Stored on this phone in trim.json (Files, On My iPhone, $appName).'
        : 'Stored on this phone. Export CSV for a copy.',
    children: [
      RowButton(
        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const WeightHistoryPage())),
        child: const Row(
          children: [
            Expanded(child: Text('Weigh-ins')),
            Icon(Icons.chevron_right),
          ],
        ),
      ),
      RowButton(
        onTap: () async {
          final file = await repository.csvExport();
          await SharePlus.instance.share(ShareParams(files: [XFile(file.path)]));
        },
        child: Text('Export CSV', style: TextStyle(color: context.colors.primary)),
      ),
      RowButton(
        onTap: () async {
          final ok = await showDialog<bool>(
            context: context,
            builder: (c) => AlertDialog(
              title: const Text('Erase all logs, weigh-ins and settings?'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
                TextButton(
                  onPressed: () => Navigator.pop(c, true),
                  child: const Text('Erase everything', style: TextStyle(color: TrimColors.red)),
                ),
              ],
            ),
          );
          if (ok == true) repository.resetAll();
        },
        child: const Text('Erase everything', style: TextStyle(color: TrimColors.red)),
      ),
    ],
  );
}

class WeightHistoryPage extends StatelessWidget {
  const WeightHistoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    final repository = context.watch<AppRepository>();
    final metric = repository.profile.metric;
    final line = repository.trend;
    final list = repository.weightsSorted.reversed.toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Weigh-ins')),
      body: ListView(
        padding: const EdgeInsets.only(top: 12, bottom: 24),
        children: [
          Section(
            children: [
              for (final w in list)
                Dismissible(
                  key: ValueKey(w.id),
                  direction: DismissDirection.endToStart,
                  background: const DeleteBackground(),
                  onDismissed: (_) => repository.deleteWeight(w),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(DateFormat.yMMMd().add_jm().format(w.date)),
                            if (w.fromHealth)
                              Text(HealthService.name, style: TextStyle(fontSize: 12, color: context.secondaryText)),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(Fmt.weight(w.kg, metric)),
                          if (Plan.trendValue(w.date, line) case final t?)
                            Text(
                              'trend ${Fmt.weight(t, metric)}',
                              style: TextStyle(fontSize: 12, color: context.secondaryText),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
