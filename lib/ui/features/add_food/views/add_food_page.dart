import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../data/repositories/app_repository.dart';
import '../../../../data/services/usda_service.dart';
import '../../../../domain/format.dart';
import '../../../../domain/models.dart';
import '../../../../plugins/plugin.dart';
import '../../../../plugins/plugin_registry.dart';
import '../../../core/theme.dart';
import '../../../core/widgets.dart';
import '../view_models/add_food_view_model.dart';
import 'food_detail_page.dart';
import 'scan_page.dart';

/// Search and the other ways to add a food: favourites, recents, barcode, quick add and whatever plugins add.
class AddFoodPage extends StatelessWidget {
  const AddFoodPage({super.key, required this.day, required this.meal});
  final DateTime day;
  final Meal meal;

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create: (c) => AddFoodViewModel(
      usda: c.read<UsdaService>(),
      plugins: c.read<PluginRegistry>(),
      repository: c.read<AppRepository>(),
      meal: meal,
    ),
    child: _AddFoodView(day: day),
  );
}

class _AddFoodView extends StatefulWidget {
  const _AddFoodView({required this.day});
  final DateTime day;
  @override
  State<_AddFoodView> createState() => _AddFoodViewState();
}

class _AddFoodViewState extends State<_AddFoodView> {
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  void _push(Widget page) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<AddFoodViewModel>();
    final repository = context.watch<AppRepository>();
    return Scaffold(
      appBar: AppBar(
        leading: TextButton(onPressed: () => Navigator.pop(context), child: const Text('Done')),
        leadingWidth: 72,
        centerTitle: true,
        title: PopupMenuButton<Meal>(
          initialValue: vm.meal,
          onSelected: (m) => vm.meal = m,
          itemBuilder: (_) => [for (final m in Meal.values) PopupMenuItem(value: m, child: Text(m.title))],
          child: Row(mainAxisSize: MainAxisSize.min, children: [Text(vm.meal.title), const Icon(Icons.expand_more)]),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: SearchBar(
              controller: _query,
              hintText: vm.hint,
              leading: const Icon(Icons.search),
              elevation: const WidgetStatePropertyAll(0),
              textInputAction: TextInputAction.search,
              onChanged: vm.setQuery,
              onSubmitted: (_) {
                if (!vm.liveSearch) vm.search();
              },
              trailing: [
                if (vm.query.isNotEmpty)
                  IconButton(
                    tooltip: 'Clear',
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      _query.clear();
                      vm.setQuery('');
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.only(top: 12, bottom: 24),
        children: vm.query.isEmpty ? _start(repository, vm) : _results(repository, vm),
      ),
    );
  }

  List<Widget> _start(AppRepository repository, AddFoodViewModel vm) {
    final recents = repository.recents.where((s) => !s.favorite).take(25).toList();
    Widget link(IconData icon, String title, Widget page) => RowButton(
      onTap: () => _push(page),
      child: Row(
        children: [
          Icon(icon, color: context.colors.primary),
          const SizedBox(width: 12),
          Expanded(child: Text(title)),
          const Icon(Icons.chevron_right),
        ],
      ),
    );
    final day = widget.day, meal = vm.meal;
    return [
      Section(
        children: [
          for (final l in context.read<PluginRegistry>().addFoodLinks) link(l.icon, l.title, l.page(day, meal)),
          link(Icons.qr_code_scanner, 'Scan a barcode', ScanPage(day: day, meal: meal)),
          link(Icons.bolt, 'Quick add calories', QuickAddPage(day: day, meal: meal)),
        ],
      ),
      if (repository.favorites.isNotEmpty)
        Section(title: 'Favorites', children: [for (final s in repository.favorites) _savedRow(repository, vm, s)]),
      if (recents.isNotEmpty)
        Section(title: 'Recent', children: [for (final s in recents) _savedRow(repository, vm, s)]),
    ];
  }

  List<Widget> _results(AppRepository repository, AddFoodViewModel vm) {
    final yours = vm.yourFoods;
    final all = vm.group == null;
    return [
      if (vm.usesPlugin && vm.groups.length > 1)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: SegmentedButton<String?>(
            showSelectedIcon: false,
            segments: [
              const ButtonSegment(value: null, label: Text('All')),
              for (final g in vm.groups) ButtonSegment(value: g.title, label: Text(g.title)),
            ],
            selected: {vm.group},
            onSelectionChanged: (s) => vm.group = s.first,
          ),
        ),
      if (vm.error case final error?)
        Section(
          children: [Text(error, style: const TextStyle(color: TrimColors.orange))],
        ),
      if (yours.isNotEmpty && all)
        Section(title: 'Your foods', children: [for (final s in yours.take(5)) _savedRow(repository, vm, s)]),
      if (vm.usesPlugin) ...[
        for (final g in vm.groups)
          if ((all || g.title == vm.group) && g.hits.isNotEmpty)
            Section(title: g.title, children: [for (final h in all ? g.hits.take(g.preview) : g.hits) _hitRow(vm, h)]),
      ] else if (vm.usda.isNotEmpty)
        Section(
          title: 'USDA FoodData Central',
          footerText: vm.hasUsdaKey ? null : 'Add a USDA key in Settings to search as you type.',
          children: [
            for (final item in vm.usda)
              FoodRow(
                name: item.name,
                detail: [item.brand, 'per ${item.servings[0].name}'].whereType<String>().join(' · '),
                kcal: item.nutrients(0, item.servings[0].defaultAmount).calories,
                onTap: () => _push(FoodDetailPage.item(item, day: widget.day, meal: vm.meal)),
              ),
          ],
        ),
      if (vm.searching)
        const Padding(
          padding: EdgeInsets.all(16),
          child: Center(child: CircularProgressIndicator()),
        )
      else if (!vm.liveSearch && vm.usda.isEmpty && vm.error == null)
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text('Press Search to look this up.', style: TextStyle(color: context.secondaryText)),
        ),
    ];
  }

  Widget _savedRow(AppRepository repository, AddFoodViewModel vm, SavedFood s) {
    final detail = [
      s.item.brand,
      '${Fmt.amount(s.amount)} ${s.item.serving(s.serving).name}',
    ].whereType<String>().join(' · ');
    return Dismissible(
      key: ValueKey('saved-${s.id}'),
      direction: DismissDirection.endToStart,
      background: const DeleteBackground(label: 'Remove'),
      onDismissed: (_) => repository.forget(s),
      child: Row(
        children: [
          Expanded(
            child: FoodRow(
              name: s.item.name,
              detail: detail,
              kcal: s.item.nutrients(s.serving, s.amount).calories,
              photo: s.item.photoURL,
              onTap: () => _push(
                FoodDetailPage.item(s.item, serving: s.serving, amount: s.amount, day: widget.day, meal: vm.meal),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Log ${s.item.name}',
            icon: Icon(Icons.add_circle, color: context.colors.primary, size: 28),
            onPressed: () {
              final id = repository.log(s.item, serving: s.serving, amount: s.amount, meal: vm.meal, day: widget.day);
              showToast(context, 'Added ${s.item.name}', onUndo: () => repository.deleteEntry(id));
            },
          ),
        ],
      ),
    );
  }

  Widget _hitRow(AddFoodViewModel vm, SearchHit hit) => FoodRow(
    name: hit.name,
    detail: hit.detail,
    kcal: hit.calories,
    photo: hit.photo,
    onTap: () => _push(FoodDetailPage.load(() => vm.load(hit), day: widget.day, meal: vm.meal)),
  );
}

/// Quick add: calories and macros typed by hand. The form state is local to the screen.
class QuickAddPage extends StatefulWidget {
  const QuickAddPage({super.key, required this.day, required this.meal});
  final DateTime day;
  final Meal meal;
  @override
  State<QuickAddPage> createState() => _QuickAddPageState();
}

class _QuickAddPageState extends State<QuickAddPage> {
  late Meal _meal = widget.meal;
  final _name = TextEditingController();
  double? _kcal, _protein, _carbs, _fat, _fiber;
  bool _keep = false;

  double get _calories => _kcal ?? ((_protein ?? 0) * 4 + (_carbs ?? 0) * 4 + (_fat ?? 0) * 9);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _log() {
    final repository = context.read<AppRepository>();
    final n = Nutrients(
      calories: _calories,
      protein: _protein ?? 0,
      carbs: _carbs ?? 0,
      fat: _fat ?? 0,
      fiber: _fiber ?? 0,
    );
    final title = _name.text.trim();
    final item = FoodItem(
      name: title.isEmpty ? 'Quick add' : title,
      source: FoodSource.custom,
      externalID: _keep ? newId() : null,
      base: n,
      servings: const [Serving('serving', 1)],
    );
    repository.log(item, serving: 0, amount: 1, meal: _meal, day: widget.day);
    if (_keep) repository.toggleFavorite(item);
    closeToRoot(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Quick add')),
      body: ListView(
        padding: const EdgeInsets.only(top: 12, bottom: 24),
        children: [
          Section(
            footerText: _kcal == null && _calories > 0 ? '${Fmt.kcal(_calories)} kcal from the macros below.' : null,
            children: [
              TextField(
                controller: _name,
                decoration: const InputDecoration(hintText: 'Name (optional)', border: InputBorder.none, isDense: true),
              ),
              NumberField(title: 'Calories', value: _kcal, unit: 'kcal', onChanged: (v) => setState(() => _kcal = v)),
            ],
          ),
          Section(
            title: 'Macros (optional)',
            children: [
              NumberField(title: 'Protein', value: _protein, unit: 'g', onChanged: (v) => setState(() => _protein = v)),
              NumberField(title: 'Carbs', value: _carbs, unit: 'g', onChanged: (v) => setState(() => _carbs = v)),
              NumberField(title: 'Fat', value: _fat, unit: 'g', onChanged: (v) => setState(() => _fat = v)),
              NumberField(title: 'Fibre', value: _fiber, unit: 'g', onChanged: (v) => setState(() => _fiber = v)),
            ],
          ),
          Section(
            children: [
              SwitchRow('Save to my foods', _keep, (v) => setState(() => _keep = v)),
              PickerRow<Meal>(
                label: 'Meal',
                value: _meal,
                values: Meal.values,
                title: (m) => m.title,
                onChanged: (m) => setState(() => _meal = m),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: FilledButton(onPressed: _calories > 0 ? _log : null, child: Text('Log ${Fmt.kcal(_calories)} kcal')),
          ),
        ],
      ),
    );
  }
}
