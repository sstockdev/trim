import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../data/repositories/app_repository.dart';
import '../../../../data/services/health_service.dart';
import '../../../core/widgets.dart';
import '../../check_in/views/check_in_page.dart';
import '../../onboarding/views/onboarding_page.dart';
import '../../settings/views/settings_page.dart';
import '../../today/views/today_page.dart';
import '../../trends/views/trends_page.dart';

/// Onboarding until it's done, then the four tabs. Syncs Health whenever the app comes to the foreground.
class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  int _tab = 0;
  late final AppRepository _repository = context.read<AppRepository>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showUnreadable();
      _refresh();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _refresh();
      case AppLifecycleState.inactive || AppLifecycleState.paused:
        _repository.saveNow();
      default:
        break;
    }
  }

  Future<void> _refresh() async {
    if (!_repository.data.onboarded) return;
    await _repository.syncHealth();
    // Normally the estimate updates at the weekly check-in; this keeps it learning if check-ins get skipped.
    if (_repository.daysSinceCheckIn >= 10) _repository.updateMaintenanceIfDue();
  }

  void _showUnreadable() {
    final name = _repository.unreadableBackup;
    if (name == null) return;
    final where = HealthService.isIOS ? 'Files, On My iPhone, $appName' : 'the app data folder';
    showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text("Couldn't read your saved data"),
        content: Text(
          _repository.saveBlocked
              ? "trim.json couldn't be read or copied, so $appName won't save anything this session and the file is left as it was. It's in $where."
              : '$appName started fresh. Your old data is kept as $name in $where, so it can be recovered.',
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('OK'))],
      ),
    ).then((_) => _repository.dismissUnreadable());
  }

  @override
  Widget build(BuildContext context) {
    final onboarded = context.select<AppRepository, bool>((r) => r.data.onboarded);
    final checkInDue = context.select<AppRepository, bool>((r) => r.checkInDue);
    if (!onboarded) return const OnboardingPage();
    return Scaffold(
      body: IndexedStack(
        index: _tab,
        children: const [
          TodayPage(),
          TrendsPage(),
          CheckInPage(),
          SettingsPage(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: [
          const NavigationDestination(icon: Icon(Icons.restaurant), label: 'Today'),
          const NavigationDestination(icon: Icon(Icons.show_chart), label: 'Trends'),
          NavigationDestination(
            icon: Badge(isLabelVisible: checkInDue, label: const Text('1'), child: const Icon(Icons.checklist)),
            label: 'Check-in',
          ),
          const NavigationDestination(icon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
    );
  }
}
