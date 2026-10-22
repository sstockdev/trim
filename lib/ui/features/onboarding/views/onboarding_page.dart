import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../../data/repositories/app_repository.dart';
import '../../../../data/services/health_service.dart';
import '../../../../domain/format.dart';
import '../../../../domain/models.dart';
import '../../../../domain/plan.dart';
import '../../../core/theme.dart';
import '../../../core/widgets.dart';
import '../../settings/views/usda_key_section.dart';
import '../view_models/onboarding_view_model.dart';

/// First run: the measurements and answers the program needs.
class OnboardingPage extends StatelessWidget {
  const OnboardingPage({super.key});

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create: (c) => OnboardingViewModel(repository: c.read<AppRepository>()),
    child: const _OnboardingView(),
  );
}

class _OnboardingView extends StatelessWidget {
  const _OnboardingView();

  static List<String> get _titles => [
    'Welcome',
    'About you',
    'Weight and goal',
    'Activity',
    'Pace',
    'Health check',
    HealthService.name,
    'Food search',
    'Your plan',
  ];

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<OnboardingViewModel>();
    final v = _Steps(context, vm);
    final last = vm.step == OnboardingViewModel.lastStep;
    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[vm.step]),
        leading: vm.step > 0 ? TextButton(onPressed: vm.back, child: const Text('Back')) : null,
        leadingWidth: 72,
      ),
      body: ListView(padding: const EdgeInsets.only(top: 12, bottom: 24), children: v.content()),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: vm.canContinue ? (last ? vm.finish : vm.next) : null,
            child: Text(last ? 'Start' : 'Continue'),
          ),
        ),
      ),
    );
  }
}

/// The content of each step.
class _Steps {
  _Steps(this.context, this.vm);
  final BuildContext context;
  final OnboardingViewModel vm;

  List<Widget> content() => switch (vm.step) {
    0 => _welcome(),
    1 => _aboutYou(),
    2 => _weightGoal(),
    3 => _activity(),
    4 => _pace(),
    5 => _safety(),
    6 => _health(),
    7 => _food(),
    _ => _summary(),
  };

  Widget _bullet(IconData icon, String text) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, color: context.colors.primary, size: 20),
      const SizedBox(width: 10),
      Expanded(child: Text(text)),
    ],
  );

  List<Widget> _welcome() => [
    Section(
      footerText: 'Not medical advice. If you have a medical condition, ask your doctor first.',
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '$appName sets a calorie and protein target from evidence-based formulas, then learns your real metabolism from what you log and how your weight trends.',
            ),
            const SizedBox(height: 14),
            _bullet(
              Icons.restaurant,
              'Log what you eat.',
            ),
            const SizedBox(height: 10),
            _bullet(Icons.monitor_weight_outlined, 'Weigh in each morning.'),
            const SizedBox(height: 10),
            _bullet(Icons.checklist, 'Check in weekly. Targets adjust to your progress.'),
            const SizedBox(height: 10),
            _bullet(
              Icons.directions_walk,
              'Activity and sleep come from ${HealthService.name}.',
            ),
          ],
        ),
      ],
    ),
  ];

  List<Widget> _aboutYou() => [
    Section(
      children: [
        SegmentedButton<bool>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: false, label: Text('lb / in')),
            ButtonSegment(value: true, label: Text('kg / cm')),
          ],
          selected: {vm.p.metric},
          onSelectionChanged: (s) => vm.set(() => vm.p.metric = s.first),
        ),
      ],
    ),
    Section(
      footerText: 'Used to estimate the calories you burn at rest.',
      children: [
        PickerRow<Sex>(
          label: 'Sex',
          value: vm.p.sex,
          values: Sex.values,
          title: (v) => v.title,
          onChanged: (v) => vm.set(() => vm.p.sex = v),
        ),
        RowButton(
          onTap: () async {
            final d = await showDatePicker(
              context: context,
              initialDate: vm.p.birthDate,
              firstDate: DateTime(1900),
              lastDate: DateTime.now(),
            );
            if (d != null) vm.set(() => vm.p.birthDate = d);
          },
          child: KeyValue('Birthday', DateFormat.yMMMd().format(vm.p.birthDate)),
        ),
        if (vm.p.metric)
          NumberField(title: 'Height', value: vm.cm, unit: 'cm', onChanged: (v) => vm.set(() => vm.cm = v))
        else
          Row(
            children: [
              Expanded(child: Text('Height: $vm.feet′ $vm.inches″')),
              IconButton(tooltip: 'Shorter', icon: const Icon(Icons.remove), onPressed: vm.inchDown),
              IconButton(tooltip: 'Taller', icon: const Icon(Icons.add), onPressed: vm.inchUp),
            ],
          ),
      ],
    ),
  ];

  List<Widget> _weightGoal() {
    final w = vm.weightKg;
    final h = vm.heightCm;
    String? footer;
    if (w != null && h > 0) {
      final low = Plan.weightForBmi(18.5, h), high = Plan.weightForBmi(24.9, h);
      footer =
          'BMI ${Plan.bmi(w, h).toStringAsFixed(1)}. A healthy range for your height is ${Fmt.weight(low, vm.p.metric, digits: 0)} to ${Fmt.weight(high, vm.p.metric, digits: 0)}.';
    }
    final unit = Fmt.weightUnit(vm.p.metric);
    return [
      Section(
        footerText: footer,
        children: [
          NumberField(
            title: 'Current weight',
            value: vm.weight,
            unit: unit,
            onChanged: (v) => vm.set(() => vm.weight = v),
          ),
          NumberField(title: 'Goal weight', value: vm.goal, unit: unit, onChanged: (v) => vm.set(() => vm.goal = v)),
        ],
      ),
      Section(
        footerText: 'At belly-button level, after breathing out.',
        children: [
          NumberField(
            title: 'Waist (optional)',
            value: vm.waist,
            unit: vm.p.metric ? 'cm' : 'in',
            onChanged: (v) => vm.set(() => vm.waist = v),
          ),
        ],
      ),
    ];
  }

  List<Widget> _activity() => [
    Section(
      title: 'A normal week',
      footerText: 'Only used for the first few weeks.',
      children: [
        for (final level in ActivityLevel.values)
          ChoiceRow(
            title: level.title,
            detail: level.detail,
            selected: vm.p.activity == level,
            onTap: () => vm.set(() => vm.p.activity = level),
          ),
      ],
    ),
    Section(
      title: 'Strength training',
      children: [
        PickerRow<StrengthExperience>(
          label: 'Experience',
          value: vm.p.strength,
          values: StrengthExperience.values,
          title: (v) => v.title,
          onChanged: (v) => vm.set(() => vm.p.strength = v),
        ),
      ],
    ),
  ];

  List<Widget> _pace() => [
    Section(
      footerText: 'Loss slows as you get lighter. That keeps muscle.',
      children: [
        for (final pace in Pace.values)
          ChoiceRow(
            title: pace.title,
            detail: pace.detail + vm.timeline(pace),
            selected: vm.p.pace == pace,
            onTap: () => vm.set(() => vm.p.pace = pace),
          ),
      ],
    ),
  ];

  List<Widget> _safety() {
    final s = vm.p.screening;
    return [
      Section(
        footerText: 'Some of these hold you at maintenance.',
        children: [
          SwitchRow(
            'Pregnant or breastfeeding',
            s.pregnantOrBreastfeeding,
            (v) => vm.set(() => s.pregnantOrBreastfeeding = v),
          ),
          SwitchRow(
            'History of an eating disorder',
            s.eatingDisorderHistory,
            (v) => vm.set(() => s.eatingDisorderHistory = v),
          ),
          SwitchRow(
            'Insulin or sulfonylureas for diabetes',
            s.diabetesMedication,
            (v) => vm.set(() => s.diabetesMedication = v),
          ),
          SwitchRow(
            'GLP-1 medicine (Wegovy, Zepbound, …)',
            s.glp1Medication,
            (v) => vm.set(() => s.glp1Medication = v),
          ),
          SwitchRow('Kidney disease', s.kidneyDisease, (v) => vm.set(() => s.kidneyDisease = v)),
        ],
      ),
      Section(
        title: 'Diet',
        children: [
          PickerRow<DietStyle>(
            label: 'Eating style',
            value: vm.p.diet,
            values: DietStyle.values,
            title: (v) => v.title,
            onChanged: (v) => vm.set(() => vm.p.diet = v),
          ),
        ],
      ),
    ];
  }

  List<Widget> _health() {
    final name = HealthService.name;
    return [
      Section(
        children: [
          Text('Reads steps, calories, workouts, sleep and weight from $name.'),
          RowButton(
            onTap: vm.connecting ? null : vm.connectHealth,
            child: Row(
              children: [
                const Icon(Icons.favorite, color: TrimColors.red),
                const SizedBox(width: 10),
                Expanded(child: Text(vm.p.useHealth ? 'Connected' : 'Connect $name')),
                if (vm.connecting) const Busy(),
              ],
            ),
          ),
          if (vm.healthError case final e?) Text(e, style: const TextStyle(fontSize: 13, color: TrimColors.orange)),
          if (vm.wearableBurn != null)
            Text(
              'You burn about ${Fmt.kcal(vm.wearableBurn!)} kcal a day.',
              style: TextStyle(fontSize: 13, color: context.secondaryText),
            ),
        ],
      ),
    ];
  }

  List<Widget> _food() => [
    const UsdaKeySection(),
    Section(
      children: [
        Text('Add more food sources later in Settings, Plugins.', style: TextStyle(color: context.secondaryText)),
      ],
    ),
  ];

  List<Widget> _summary() {
    final (t, warnings) = vm.draft;
    return [
      if (warnings.isNotEmpty) Section(children: [for (final w in warnings) WarningRow(w)]),
      Section(
        title: 'Daily targets',
        footerText:
            'Maintenance ${Fmt.int_(t.tdee)} kcal, minus ${t.deficit}. About ${Fmt.weight(t.expectedLossPerWeekKg, vm.p.metric)} a week.',
        children: [
          KeyValue('Calories', '${Fmt.int_(t.calories)} kcal'),
          KeyValue('Protein', '${t.protein} g'),
          KeyValue('Fat', '${t.fat} g'),
          KeyValue('Carbs', '${t.carbs} g'),
          KeyValue('Fibre', '${t.fiber}+ g'),
          KeyValue('Steps', '${Fmt.int_(t.steps)}+ a day'),
          const KeyValue('Strength training', '2 or 3 times a week'),
          const KeyValue('Sleep', '7 to 9 hours'),
        ],
      ),
      if (t.notes.isNotEmpty)
        Section(children: [for (final n in t.notes) Text(n, style: const TextStyle(fontSize: 13))]),
    ];
  }
}
