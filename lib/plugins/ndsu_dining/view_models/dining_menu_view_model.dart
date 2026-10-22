import 'dart:async';

import '../../../data/repositories/app_repository.dart';
import '../../../domain/format.dart';
import '../../../domain/models.dart';
import '../../../ui/core/view_model.dart';
import '../data/jamix_service.dart';

/// The day's menu at an NDSU dining hall. The hall picker remembers the last hall. Labels seen before are cached;
/// the rest of the open tab's labels load in the background, so most items log in one tap.
class DiningMenuViewModel extends ViewModel {
  DiningMenuViewModel({
    required this._jamix,
    required this._repository,
    required this.day,
    required this.meal,
  });

  final JamixService _jamix;
  final AppRepository _repository;
  final DateTime day;
  final Meal meal;

  MarketMenu? menu;
  int tab = 0;
  bool loading = false;
  String? error;
  String filter = '';

  /// Items whose labels are being read after a tap.
  final Set<({String name, DiningHall hall})> _opening = {};

  /// The item tapped last. Only it opens when its label arrives; earlier taps just cache theirs.
  ({String name, DiningHall hall})? _lastTap;
  bool prefetching = false;

  /// Reads queued or running per station, by `MarketMenu.stationKey`. A tap and the background prefetch can both
  /// be reading the same station, so this counts rather than flags.
  final Map<String, int> _stationReads = {};

  /// Bumped to cancel the running prefetch loop.
  int _generation = 0;

  DiningHall get hall => _repository.data.diningHall;

  bool isLoading(String stationKey) => (_stationReads[stationKey] ?? 0) > 0;

  bool isOpening(String name) => _opening.contains((name: name, hall: hall));

  void setFilter(String f) {
    filter = f;
    notifyListeners();
  }

  /// Switches to another hall and starts over, with its own tab for the time of day.
  void selectHall(DiningHall h) {
    if (h == hall) return;
    _repository.update((d) => d.diningHall = h);
    cancelPrefetch();
    menu = null;
    error = null;
    loading = false;
    // Labels still loading at the old hall aren't shown here, and none of them should open.
    _opening.clear();
    _lastTap = null;
    notifyListeners();
    unawaited(loadMenu(force: false));
  }

  bool onMenu(String name) {
    final key = MarketItem.normalized(name);
    return menu?.tabs.any(
          (t) => t.stations.any((s) => s.items.any((i) => MarketItem.normalized(i.name) == key)),
        ) ??
        false;
  }

  Future<void> loadMenu({required bool force}) async {
    final want = hall;
    final cached = _repository.data.menus[MarketMenu.key(Day.key(day), want)];
    if (!force && cached != null && DateTime.now().difference(cached.fetched).inHours < 6) {
      _show(cached);
      return;
    }
    if (menu == null && cached != null) _show(cached);
    loading = true;
    notifyListeners();
    try {
      final fresh = await _jamix.menu(day, want);
      _repository.saveMenu(fresh);
      // A load for a hall you've since switched away from leaves the screen (and `loading`) to the new one.
      if (want != hall) return;
      error = null;
      if (!isDisposed) _show(fresh);
    } on Exception catch (e) {
      if (want == hall) error = "Couldn't load the menu: $e";
    } finally {
      if (want == hall) {
        loading = false;
        notifyListeners();
      }
    }
  }

  void _show(MarketMenu m) {
    final first = menu == null;
    menu = m;
    if (first || tab >= m.tabs.length) {
      tab = Day.isToday(day) ? m.tabIndex(Meal.guess()) : m.tabIndex(meal);
    }
    notifyListeners();
    prefetch();
  }

  void selectTab(int i) {
    tab = i;
    notifyListeners();
    prefetch();
  }

  /// Reads the label for a tapped item if it isn't cached. Returns the label, or null with [error] set. Also null
  /// when the hall changed or another item was tapped while the label loaded.
  Future<MarketItem?> open(int stationIndex, Station station, String name) async {
    final m = menu;
    if (m == null) return null;
    final mine = (name: name, hall: m.hall);
    _lastTap = mine;
    if (_repository.marketItem(name, m.hall) == null) {
      // Already loading from an earlier tap, which opens it now that it's the last one.
      if (!_opening.add(mine)) return null;
      notifyListeners();
      try {
        // Just this item; the background prefetch fills in the rest of the station afterwards.
        final r = await _read(m, tab, stationIndex, station, only: [name], urgent: true);
        _repository.saveMarket(r.items, m.hall, menuNames: [name]);
      } on Exception catch (e) {
        if (_lastTap == mine) error = '$e';
        return null;
      } finally {
        _opening.remove(mine);
        notifyListeners();
      }
      if (_lastTap != mine) return null;
    }
    _lastTap = null;
    if (m.hall != hall) return null;
    final item = _repository.marketItem(name, m.hall);
    if (item == null) {
      error = "${m.hall.title} doesn't list nutrition for $name.";
      notifyListeners();
    }
    return item;
  }

  Future<({List<MarketItem> items, bool complete})> _read(
    MarketMenu m,
    int t,
    int i,
    Station st, {
    List<String>? only,
    List<String> skip = const [],
    required bool urgent,
  }) async {
    final key = MarketMenu.stationKey(m.hall, m.day, t, i);
    _stationReads[key] = (_stationReads[key] ?? 0) + 1;
    notifyListeners();
    try {
      return await _jamix.station(
        m.hall,
        day: m.day,
        tab: t,
        station: i,
        name: st.name,
        only: only,
        skip: skip,
        urgent: urgent,
      );
    } finally {
      final left = (_stationReads[key] ?? 1) - 1;
      if (left > 0) {
        _stationReads[key] = left;
      } else {
        _stationReads.remove(key);
      }
      notifyListeners();
    }
  }

  /// Reads the labels for the open tab's stations in the background, skipping stations whose items are all
  /// cached, so tapping an item is usually instant. Starting again cancels the previous run.
  void prefetch() {
    final m = menu;
    final gen = ++_generation;
    if (m == null || tab >= m.tabs.length) return;
    final t = tab;
    unawaited(() async {
      prefetching = true;
      notifyListeners();
      try {
        final stations = m.tabs[t].stations;
        for (var i = 0; i < stations.length; i++) {
          final st = stations[i];
          // An interrupted station picks up where it stopped once the tap is served.
          for (var round = 0; round < 20; round++) {
            if (gen != _generation) return;
            final cached = [
              for (final it in st.items)
                if (_repository.marketItem(it.name, m.hall) != null) it.name,
            ];
            if (cached.length == st.items.length) break;
            if (isLoading(MarketMenu.stationKey(m.hall, m.day, t, i))) break;
            final ({List<MarketItem> items, bool complete}) r;
            try {
              r = await _read(m, t, i, st, skip: cached, urgent: false);
            } on Exception {
              break;
            }
            _repository.saveMarket(r.items, m.hall, menuNames: [for (final it in st.items) it.name]);
            if (r.complete) break;
          }
        }
      } finally {
        if (gen == _generation) {
          prefetching = false;
          notifyListeners();
        }
      }
    }());
  }

  /// Stops background label reads. A station read in progress stops after its current item.
  void cancelPrefetch() {
    _generation++;
    prefetching = false;
    unawaited(_jamix.abortBackground());
  }

  @override
  void dispose() {
    cancelPrefetch();
    super.dispose();
  }
}
