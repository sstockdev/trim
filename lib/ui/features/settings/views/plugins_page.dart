import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../plugins/plugin.dart';
import '../../../../plugins/plugin_registry.dart';
import '../../../core/theme.dart';
import '../../../core/widgets.dart';

/// One plugin in a list: icon, name, and whether it's installed or still needs its keys.
class PluginRow extends StatelessWidget {
  const PluginRow(this.plugin, {super.key});
  final TrimPlugin plugin;

  @override
  Widget build(BuildContext context) {
    final registry = context.watch<PluginRegistry>();
    final status = !registry.isInstalled(plugin)
        ? null
        : plugin.configured
        ? 'Installed'
        : 'Needs setup';
    return RowButton(
      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => PluginPage(plugin: plugin))),
      child: Row(
        children: [
          Icon(plugin.icon, color: context.colors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(plugin.title),
                Text(plugin.summary, style: TextStyle(fontSize: 12, color: context.secondaryText)),
              ],
            ),
          ),
          if (status != null)
            Text(
              status,
              style: TextStyle(fontSize: 13, color: plugin.configured ? context.secondaryText : TrimColors.orange),
            ),
          const Icon(Icons.chevron_right),
        ],
      ),
    );
  }
}

/// Every plugin the app has, installed or not.
class PluginsPage extends StatelessWidget {
  const PluginsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final registry = context.watch<PluginRegistry>();
    return Scaffold(
      appBar: AppBar(title: const Text('Plugins')),
      body: ListView(
        padding: const EdgeInsets.only(top: 12, bottom: 24),
        children: [
          Section(
            children: [for (final p in registry.all) PluginRow(p)],
          ),
        ],
      ),
    );
  }
}

/// A plugin's description, its settings, and the install or remove button.
class PluginPage extends StatefulWidget {
  const PluginPage({super.key, required this.plugin});
  final TrimPlugin plugin;
  @override
  State<PluginPage> createState() => _PluginPageState();
}

class _PluginPageState extends State<PluginPage> {
  late final _fields = {
    for (final f in widget.plugin.fields) f.key: TextEditingController(text: widget.plugin.keys.get(f.key) ?? ''),
  };

  @override
  void dispose() {
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _remove(PluginRegistry registry) async {
    final p = widget.plugin;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Remove ${p.title}?'),
        content: Text(
          p.fields.isEmpty ? 'Your logged food stays.' : 'Its keys are deleted. Your logged food stays.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Remove', style: TextStyle(color: TrimColors.red)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await registry.uninstall(p);
    for (final c in _fields.values) {
      c.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final registry = context.watch<PluginRegistry>();
    final p = widget.plugin;
    final installed = registry.isInstalled(p);
    return Scaffold(
      appBar: AppBar(title: Text(p.title)),
      body: ListView(
        padding: const EdgeInsets.only(top: 12, bottom: 24),
        children: [
          Section(
            children: [
              Row(
                children: [
                  Icon(p.icon, size: 36, color: context.colors.primary),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(p.title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
              Text(p.about),
            ],
          ),
          if (installed && p.fields.isNotEmpty)
            Section(
              title: 'Setup',
              footerText: p.configured ? null : 'Required to use ${p.title}.',
              children: [
                for (final f in p.fields)
                  TextField(
                    controller: _fields[f.key],
                    obscureText: f.secret,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: InputDecoration(
                      labelText: f.required ? f.label : '${f.label} (optional)',
                      border: InputBorder.none,
                      isDense: true,
                    ),
                    onChanged: (v) => registry.setField(p, f, v),
                  ),
                if (p.signup case final s?)
                  RowButton(
                    onTap: () => launchUrl(Uri.parse(s.url), mode: LaunchMode.externalApplication),
                    child: Text(s.title, style: TextStyle(color: context.colors.primary)),
                  ),
              ],
            ),
          if (installed && p.configured)
            if (p.settingsRows(context) case final rows when rows.isNotEmpty) Section(children: rows),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: installed
                ? OutlinedButton(
                    onPressed: () => _remove(registry),
                    child: const Text('Remove', style: TextStyle(color: TrimColors.red)),
                  )
                : FilledButton(onPressed: () => registry.install(p), child: const Text('Install')),
          ),
        ],
      ),
    );
  }
}
