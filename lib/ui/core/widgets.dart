import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/format.dart';
import '../../domain/models.dart';
import '../../domain/plan.dart';
import 'theme.dart';

const appName = 'Trim';

/// A grouped block of rows with an optional header and footer, like an inset grouped list section on iOS.
class Section extends StatelessWidget {
  final Widget? header;
  final String? title;
  final Widget? footer;
  final String? footerText;
  final List<Widget> children;
  final EdgeInsets padding;

  const Section({
    super.key,
    this.header,
    this.title,
    this.footer,
    this.footerText,
    required this.children,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
  });

  @override
  Widget build(BuildContext context) {
    final rows = children.where((w) => w is! SizedBox || w.height != 0).toList();
    final head = header ?? (title == null ? null : Text(title!.toUpperCase()));
    final foot = footer ?? (footerText == null ? null : Text(footerText!));
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (head != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
              child: DefaultTextStyle.merge(
                style: context.text.labelMedium!.copyWith(color: context.secondaryText),
                child: head,
              ),
            ),
          if (rows.isNotEmpty)
            Material(
              color: context.colors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(12),
              clipBehavior: Clip.antiAlias,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < rows.length; i++) ...[
                    if (i > 0)
                      Divider(height: 1, indent: 16, color: context.colors.outlineVariant.withValues(alpha: .5)),
                    Padding(padding: padding, child: rows[i]),
                  ],
                ],
              ),
            ),
          if (foot != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
              child: DefaultTextStyle.merge(
                style: context.text.bodySmall!.copyWith(color: context.secondaryText),
                child: foot,
              ),
            ),
        ],
      ),
    );
  }
}

/// A full-width tappable row inside a Section.
class RowButton extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  const RowButton({super.key, required this.child, this.onTap});

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: child),
  );
}

/// "Label ............ value".
class KeyValue extends StatelessWidget {
  final String label;
  final String value;
  final bool bold;
  const KeyValue(this.label, this.value, {super.key, this.bold = false});

  @override
  Widget build(BuildContext context) {
    final w = bold ? FontWeight.w600 : FontWeight.normal;
    return Row(
      children: [
        Expanded(
          child: Text(label, style: TextStyle(fontWeight: w)),
        ),
        Text(
          value,
          style: TextStyle(
            fontWeight: w,
            color: bold ? null : context.secondaryText,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

class Card2 extends StatelessWidget {
  final List<Widget> children;
  const Card2({super.key, required this.children});

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: context.colors.surfaceContainerLow,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < children.length; i++) ...[if (i > 0) const SizedBox(height: 10), children[i]],
      ],
    ),
  );
}

/// A labelled bar for one nutrient or goal. Goes orange past the target when going over matters.
class GoalBar extends StatelessWidget {
  final String title;
  final double value;
  final double target;
  final String unit;
  final Color tint;

  /// Protein, fibre and steps are minimums; calories, fat and carbs are limits.
  final bool isMinimum;

  const GoalBar({
    super.key,
    required this.title,
    required this.value,
    required this.target,
    required this.unit,
    required this.tint,
    this.isMinimum = false,
  });

  @override
  Widget build(BuildContext context) {
    final f = target > 0 ? math.min(value / target, 1.0) : 0.0;
    final color = isMinimum
        ? (value >= target * 0.95 ? TrimColors.green : tint)
        : (value > target * 1.05 ? TrimColors.orange : tint);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
            ),
            Text(
              '${Fmt.int_(value.round())} / ${Fmt.int_(target.round())} $unit'.trimRight(),
              style: TextStyle(color: context.secondaryText, fontFeatures: const [FontFeature.tabularFigures()]),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(value: f, minHeight: 8, color: color, backgroundColor: context.fill),
        ),
      ],
    );
  }
}

class CalorieRing extends StatelessWidget {
  final double eaten;
  final double target;
  const CalorieRing({super.key, required this.eaten, required this.target});

  @override
  Widget build(BuildContext context) {
    final f = target > 0 ? eaten / target : 0.0;
    return SizedBox(
      width: 110,
      height: 110,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox.expand(
            child: CircularProgressIndicator(
              value: math.min(f, 1.0),
              strokeWidth: 12,
              strokeCap: StrokeCap.round,
              color: f > 1.05 ? TrimColors.orange : context.colors.primary,
              backgroundColor: context.fill,
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                Fmt.kcal((target - eaten).abs()),
                style: context.text.titleLarge!.copyWith(fontWeight: FontWeight.bold),
              ),
              Text(eaten <= target ? 'left' : 'over', style: TextStyle(fontSize: 12, color: context.secondaryText)),
            ],
          ),
        ],
      ),
    );
  }
}

/// 1 to 5 scale used for hunger, energy and how well the week went.
class RatingPicker extends StatelessWidget {
  final String title;
  final String low;
  final String high;
  final int? value;
  final ValueChanged<int?> onChanged;

  const RatingPicker({
    super.key,
    required this.title,
    required this.low,
    required this.high,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
        const SizedBox(height: 6),
        Row(
          children: [
            for (var n = 1; n <= 5; n++) ...[
              if (n > 1) const SizedBox(width: 8),
              Expanded(
                child: Material(
                  color: value == n ? context.colors.primary : context.fill,
                  borderRadius: BorderRadius.circular(8),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => onChanged(value == n ? null : n),
                    child: SizedBox(
                      height: 36,
                      child: Center(
                        child: Text(
                          '$n',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: value == n ? context.colors.onPrimary : null,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 4),
        DefaultTextStyle.merge(
          style: TextStyle(fontSize: 11, color: context.secondaryText),
          child: Row(children: [Text(low), const Spacer(), Text(high)]),
        ),
      ],
    );
  }
}

/// A number text field for an optional double. Commas work as decimal points.
class NumberField extends StatefulWidget {
  final String title;
  final double? value;
  final ValueChanged<double?> onChanged;
  final String unit;
  final TextAlign textAlign;
  final TextStyle? style;

  const NumberField({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    this.unit = '',
    this.textAlign = TextAlign.start,
    this.style,
  });

  @override
  State<NumberField> createState() => _NumberFieldState();
}

class _NumberFieldState extends State<NumberField> {
  late final TextEditingController _c;
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _c = TextEditingController(text: widget.value == null ? '' : Fmt.amount(widget.value!));
  }

  @override
  void didUpdateWidget(NumberField old) {
    super.didUpdateWidget(old);
    // Outside changes (a stepper, a unit switch) show up unless you're typing.
    if (!_focus.hasFocus && widget.value != _parse(_c.text)) {
      _c.text = widget.value == null ? '' : Fmt.amount(widget.value!);
    }
  }

  double? _parse(String s) => double.tryParse(s.replaceAll(',', '.'));

  @override
  void dispose() {
    _c.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
    controller: _c,
    focusNode: _focus,
    textAlign: widget.textAlign,
    style: widget.style,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    decoration: InputDecoration(
      hintText: widget.title,
      border: InputBorder.none,
      isDense: true,
      suffixText: widget.unit.isEmpty ? null : widget.unit,
    ),
    onChanged: (s) => widget.onChanged(_parse(s)),
  );
}

class WarningRow extends StatelessWidget {
  final Warning warning;
  const WarningRow(this.warning, {super.key});

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (warning.level) {
      WarningLevel.info => (Icons.info, TrimColors.blue),
      WarningLevel.caution => (Icons.warning_rounded, TrimColors.orange),
      WarningLevel.stop => (Icons.back_hand, TrimColors.red),
    };
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 10),
        Expanded(child: Text(warning.text)),
      ],
    );
  }
}

class MacroLine extends StatelessWidget {
  final Nutrients n;
  const MacroLine(this.n, {super.key});

  @override
  Widget build(BuildContext context) => Text(
    'P ${n.protein.round()} · C ${n.carbs.round()} · F ${n.fat.round()}',
    style: TextStyle(fontSize: 12, color: context.secondaryText, fontFeatures: const [FontFeature.tabularFigures()]),
  );
}

/// A row with a title, a detail line and a check mark when selected.
class ChoiceRow extends StatelessWidget {
  final String title;
  final String detail;
  final bool selected;
  final VoidCallback onTap;
  const ChoiceRow({super.key, required this.title, required this.detail, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => RowButton(
    onTap: onTap,
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title),
              const SizedBox(height: 3),
              Text(detail, style: TextStyle(fontSize: 13, color: context.secondaryText)),
            ],
          ),
        ),
        Icon(
          selected ? Icons.check_circle : Icons.circle_outlined,
          color: selected ? context.colors.primary : context.secondaryText,
        ),
      ],
    ),
  );
}

/// A labelled dropdown, the stand-in for a SwiftUI Picker row.
class PickerRow<T> extends StatelessWidget {
  final String label;
  final T value;
  final List<T> values;
  final String Function(T) title;
  final ValueChanged<T> onChanged;

  const PickerRow({
    super.key,
    required this.label,
    required this.value,
    required this.values,
    required this.title,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(child: Text(label)),
      DropdownButton<T>(
        value: value,
        underline: const SizedBox.shrink(),
        isDense: true,
        items: [for (final v in values) DropdownMenuItem(value: v, child: Text(title(v)))],
        onChanged: (v) {
          if (v is T) onChanged(v);
        },
      ),
    ],
  );
}

class SwitchRow extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  const SwitchRow(this.label, this.value, this.onChanged, {super.key});

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(child: Text(label)),
      Switch.adaptive(value: value, onChanged: onChanged),
    ],
  );
}

/// A small stat: value on top, caption below.
class Stat extends StatelessWidget {
  final String title;
  final String? value;
  const Stat(this.title, this.value, {super.key});

  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value ?? '-',
            style: const TextStyle(fontWeight: FontWeight.w600, fontFeatures: [FontFeature.tabularFigures()]),
          ),
        ),
        Text(title, style: TextStyle(fontSize: 12, color: context.secondaryText)),
      ],
    ),
  );
}

/// Brief confirmation after one-tap logging, with undo.
void showToast(BuildContext context, String text, {VoidCallback? onUndo}) {
  final m = ScaffoldMessenger.of(context);
  m.hideCurrentSnackBar();
  m.showSnackBar(
    SnackBar(
      content: Row(
        children: [
          const Icon(Icons.check_circle, color: TrimColors.green),
          const SizedBox(width: 10),
          Expanded(child: Text(text, maxLines: 2)),
        ],
      ),
      duration: const Duration(milliseconds: 3500),
      behavior: SnackBarBehavior.floating,
      action: onUndo == null ? null : SnackBarAction(label: 'Undo', onPressed: onUndo),
    ),
  );
}

/// Food photo thumbnail from a URL, with a plain placeholder.
class FoodThumb extends StatelessWidget {
  final String? url;
  final double size;
  const FoodThumb(this.url, {super.key, this.size = 36});

  @override
  Widget build(BuildContext context) {
    final u = url;
    if (u == null) return const SizedBox.shrink();
    return ClipRRect(
      borderRadius: BorderRadius.circular(size / 6),
      child: Image.network(
        u,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => Container(width: size, height: size, color: context.fill),
      ),
    );
  }
}

class Busy extends StatelessWidget {
  final double size;
  const Busy({super.key, this.size = 18});
  @override
  Widget build(BuildContext context) =>
      SizedBox(width: size, height: size, child: const CircularProgressIndicator(strokeWidth: 2));
}

/// A food in a list: optional photo, name, a detail line, and calories on the right.
class FoodRow extends StatelessWidget {
  const FoodRow({super.key, required this.name, required this.detail, this.kcal, this.photo, required this.onTap});

  final String name;
  final String detail;
  final double? kcal;
  final String? photo;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => RowButton(
    onTap: onTap,
    child: Row(
      children: [
        if (photo != null) ...[FoodThumb(photo), const SizedBox(width: 10)],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, maxLines: 2),
              Text(
                detail,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: context.secondaryText),
              ),
            ],
          ),
        ),
        if (kcal case final k?) Text(Fmt.kcal(k), style: TextStyle(color: context.secondaryText)),
      ],
    ),
  );
}

/// The red background shown while swiping a row away.
class DeleteBackground extends StatelessWidget {
  const DeleteBackground({super.key, this.label});

  /// Text instead of the trash icon.
  final String? label;

  @override
  Widget build(BuildContext context) => Container(
    color: TrimColors.red,
    alignment: Alignment.centerRight,
    padding: const EdgeInsets.only(right: 16),
    child: label == null
        ? const Icon(Icons.delete, color: Colors.white)
        : Text(label!, style: const TextStyle(color: Colors.white)),
  );
}
