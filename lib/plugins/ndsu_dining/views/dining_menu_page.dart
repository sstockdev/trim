import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/repositories/app_repository.dart';
import '../../../domain/format.dart';
import '../../../domain/models.dart';
import '../../../ui/core/theme.dart';
import '../../../ui/core/widgets.dart';
import '../../../ui/features/add_food/views/food_detail_page.dart';
import '../data/jamix_service.dart';
import '../view_models/dining_menu_view_model.dart';

/// Today's menu at an NDSU dining hall, opened at the meal that fits the time of day.
class DiningMenuPage extends StatelessWidget {
  const DiningMenuPage({
    super.key,
    required this.jamix,
    required this.day,
    required this.meal,
    this.standalone = false,
  });
  final JamixService jamix;
  final DateTime day;
  final Meal meal;

  /// Opened straight from the Today tab rather than from Add food, so it needs its own close button.
  final bool standalone;

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create: (c) =>
        DiningMenuViewModel(jamix: jamix, repository: c.read<AppRepository>(), day: day, meal: meal)
          ..loadMenu(force: false),
    child: _DiningMenuView(standalone: standalone),
  );
}

class _DiningMenuView extends StatelessWidget {
  const _DiningMenuView({required this.standalone});
  final bool standalone;

  Future<void> _openItem(BuildContext context, DiningMenuViewModel vm, int index, Station st, String name) async {
    final item = await vm.open(index, st, name);
    if (item == null || !context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => FoodDetailPage.item(item.foodItem, day: vm.day, meal: vm.meal),
      ),
    );
    // Back from the food's page: restart the prefetch with what's cached now.
    vm.prefetch();
  }

  void _log(BuildContext context, DiningMenuViewModel vm, FoodItem item, int serving, double amount) {
    final repository = context.read<AppRepository>();
    final id = repository.log(item, serving: serving, amount: amount, meal: vm.meal, day: vm.day);
    showToast(
      context,
      'Added ${item.name} to ${vm.meal.title.toLowerCase()}',
      onUndo: () => repository.deleteEntry(id),
    );
  }

  Widget _addButton(BuildContext context, DiningMenuViewModel vm, FoodItem item, int serving, double amount) =>
      IconButton(
        tooltip: 'Log ${item.name}',
        icon: Icon(Icons.add_circle, color: context.colors.primary, size: 28),
        onPressed: () => _log(context, vm, item, serving, amount),
      );

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<DiningMenuViewModel>();
    final repository = context.watch<AppRepository>();
    final menu = vm.menu;
    final usuals = repository.marketUsuals(vm.hall);
    return Scaffold(
      appBar: AppBar(
        title: Text(vm.hall.title),
        leading: standalone
            ? IconButton(tooltip: 'Close', icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context))
            : null,
        actions: [if (vm.prefetching) const Padding(padding: EdgeInsets.all(16), child: Busy())],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: SearchBar(
              hintText: 'Find on the menu',
              leading: const Icon(Icons.search),
              elevation: const WidgetStatePropertyAll(0),
              onChanged: vm.setFilter,
            ),
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () => vm.loadMenu(force: true),
        child: ListView(
          padding: const EdgeInsets.only(top: 12, bottom: 24),
          children: [
            _hallPicker(vm),
            if (vm.filter.isEmpty && usuals.isNotEmpty) _usuals(context, vm, usuals),
            if (menu != null) ...[
              if (menu.tabs.length > 1) _tabPicker(vm, menu),
              if (vm.tab < menu.tabs.length)
                for (var i = 0; i < menu.tabs[vm.tab].stations.length; i++)
                  _station(context, vm, repository, menu, i, menu.tabs[vm.tab].stations[i]),
              if (menu.tabs.every((t) => t.stations.isEmpty))
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text('Nothing is on the menu for this day.', style: TextStyle(color: context.secondaryText)),
                ),
            ] else if (vm.loading)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Column(children: [CircularProgressIndicator(), SizedBox(height: 8), Text('Loading the menu…')]),
              ),
            if (vm.error case final error?)
              Section(
                children: [
                  Text(error, style: const TextStyle(color: TrimColors.orange)),
                  RowButton(
                    onTap: () => vm.loadMenu(force: true),
                    child: Text('Try again', style: TextStyle(color: context.colors.primary)),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _hallPicker(DiningMenuViewModel vm) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
    child: SegmentedButton<DiningHall>(
      segments: [for (final h in DiningHall.values) ButtonSegment(value: h, label: Text(h.shortTitle))],
      selected: {vm.hall},
      showSelectedIcon: false,
      onSelectionChanged: (s) => vm.selectHall(s.first),
    ),
  );

  Widget _usuals(BuildContext context, DiningMenuViewModel vm, List<SavedFood> usuals) => Section(
    title: 'Your usuals',
    children: [
      for (final s in usuals.take(8))
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s.item.name),
                  Row(
                    children: [
                      Text(
                        '${Fmt.kcal(s.item.nutrients(s.serving, s.amount).calories)} kcal',
                        style: TextStyle(fontSize: 12, color: context.secondaryText),
                      ),
                      if (vm.onMenu(s.item.name)) ...[
                        const SizedBox(width: 6),
                        const Text('On the menu', style: TextStyle(fontSize: 12, color: TrimColors.green)),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            _addButton(context, vm, s.item, s.serving, s.amount),
          ],
        ),
    ],
  );

  Widget _tabPicker(DiningMenuViewModel vm, MarketMenu menu) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < menu.tabs.length; i++)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(menu.tabs[i].name),
                selected: vm.tab == i,
                showCheckmark: false,
                onSelected: (_) => vm.selectTab(i),
              ),
            ),
        ],
      ),
    ),
  );

  Widget _station(
    BuildContext context,
    DiningMenuViewModel vm,
    AppRepository repository,
    MarketMenu menu,
    int index,
    Station st,
  ) {
    final f = vm.filter.toLowerCase();
    final items = st.items.where((i) => f.isEmpty || i.name.toLowerCase().contains(f)).toList();
    if (items.isEmpty) return const SizedBox.shrink();
    return Section(
      header: Row(
        children: [
          Expanded(child: Text(st.name.toUpperCase())),
          if (vm.isLoading(MarketMenu.stationKey(menu.hall, menu.day, vm.tab, index))) const Busy(size: 12),
        ],
      ),
      children: [
        for (final it in items) _item(context, vm, repository.marketItem(it.name, menu.hall), index, st, it),
      ],
    );
  }

  Widget _item(BuildContext context, DiningMenuViewModel vm, MarketItem? cached, int index, Station st, MenuItem it) {
    final opening = vm.isOpening(it.name);
    final caption = switch (cached) {
      final c? => '${Fmt.kcal(c.nutrients.calories)} kcal · ${c.nutrients.protein.round()} g protein',
      null when opening => 'Loading nutrition…',
      null => 'Tap for nutrition',
    };
    return Row(
      children: [
        Expanded(
          child: RowButton(
            onTap: () => _openItem(context, vm, index, st, it.name),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(it.name),
                Text(caption, style: TextStyle(fontSize: 12, color: context.secondaryText)),
                if (it.diets.isNotEmpty)
                  Text(it.diets, style: TextStyle(fontSize: 11, color: context.secondaryText.withValues(alpha: .7))),
              ],
            ),
          ),
        ),
        if (cached != null)
          _addButton(context, vm, cached.foodItem, 0, 1)
        else if (opening)
          const Padding(padding: EdgeInsets.all(12), child: Busy()),
      ],
    );
  }
}
