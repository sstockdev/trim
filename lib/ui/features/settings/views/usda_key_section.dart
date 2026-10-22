import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../data/services/key_service.dart';
import '../../../../data/services/usda_service.dart';
import '../../../core/theme.dart';
import '../../../core/widgets.dart';
import '../view_models/usda_key_view_model.dart';

/// The USDA key field with a link to sign up, used in Settings and in onboarding.
class UsdaKeySection extends StatelessWidget {
  const UsdaKeySection({super.key, this.title});
  final String? title;

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create: (c) => UsdaKeyViewModel(keys: c.read<KeyService>(), usda: c.read<UsdaService>()),
    child: _UsdaKeyView(title: title),
  );
}

class _UsdaKeyView extends StatefulWidget {
  const _UsdaKeyView({this.title});
  final String? title;
  @override
  State<_UsdaKeyView> createState() => _UsdaKeyViewState();
}

class _UsdaKeyViewState extends State<_UsdaKeyView> {
  late final _key = TextEditingController(text: context.read<UsdaKeyViewModel>().saved);

  @override
  void dispose() {
    _key.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<UsdaKeyViewModel>();
    final changed = _key.text.trim() != vm.saved;
    return Section(
      title: widget.title,
      footerText: vm.hasKey ? null : 'Without a key, searches are limited.',
      children: [
        TextField(
          controller: _key,
          autocorrect: false,
          enableSuggestions: false,
          obscureText: !changed && vm.hasKey,
          decoration: const InputDecoration(hintText: 'USDA API key', border: InputBorder.none, isDense: true),
          onChanged: (_) => setState(() {}),
          onSubmitted: vm.save,
        ),
        if (changed)
          RowButton(
            onTap: vm.checking ? null : () => vm.save(_key.text),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _key.text.trim().isEmpty ? 'Remove key' : 'Save',
                    style: TextStyle(color: context.colors.primary),
                  ),
                ),
                if (vm.checking) const Busy(),
              ],
            ),
          ),
        if (vm.result case final r?)
          Text(r.message, style: TextStyle(fontSize: 13, color: r.ok ? TrimColors.green : TrimColors.orange)),
        RowButton(
          onTap: () => launchUrl(Uri.parse(UsdaService.signup), mode: LaunchMode.externalApplication),
          child: Text('Get a free key', style: TextStyle(color: context.colors.primary)),
        ),
      ],
    );
  }
}
