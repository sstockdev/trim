import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/repositories/app_repository.dart';
import '../../../domain/format.dart';
import '../../../domain/models.dart';
import '../../../ui/core/theme.dart';
import '../../../ui/core/widgets.dart';
import '../data/jamix_service.dart';
import 'dining_menu_page.dart';

/// The Today tab's row of dining hall foods you log often. One tap logs it to the meal that fits the time.
class DiningUsuals extends StatelessWidget {
  const DiningUsuals({super.key, required this.jamix, required this.day});
  final JamixService jamix;
  final DateTime day;

  @override
  Widget build(BuildContext context) {
    final repository = context.watch<AppRepository>();
    final usuals = repository.marketUsuals();
    if (usuals.isEmpty) return const SizedBox.shrink();
    final isToday = Day.isToday(day);
    // Name the hall on each card once usuals come from more than one.
    final mixed = usuals.map((s) => s.item.source).toSet().length > 1;
    return Section(
      header: Row(
        children: [
          const Expanded(child: Text('DINING USUALS')),
          GestureDetector(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                fullscreenDialog: true,
                builder: (_) =>
                    DiningMenuPage(jamix: jamix, day: day, meal: isToday ? Meal.guess() : Meal.lunch, standalone: true),
              ),
            ),
            child: Text(
              'MENU',
              style: TextStyle(fontWeight: FontWeight.bold, color: context.colors.primary),
            ),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      children: [
        SizedBox(
          height: 74,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final s in usuals.take(12))
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Material(
                    color: context.fill,
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () {
                        final meal = isToday ? Meal.guess() : Meal.lunch;
                        final id = repository.log(s.item, serving: s.serving, amount: s.amount, meal: meal, day: day);
                        showToast(
                          context,
                          'Added ${s.item.name} to ${meal.title.toLowerCase()}',
                          onUndo: () => repository.deleteEntry(id),
                        );
                      },
                      child: Container(
                        width: 150,
                        padding: const EdgeInsets.all(10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              s.item.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
                            ),
                            const Spacer(),
                            Text(
                              [
                                '${Fmt.kcal(s.item.nutrients(s.serving, s.amount).calories)} kcal',
                                if (mixed) ?DiningHall.ofSource(s.item.source)?.shortTitle,
                              ].join(' · '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 12, color: context.secondaryText),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
