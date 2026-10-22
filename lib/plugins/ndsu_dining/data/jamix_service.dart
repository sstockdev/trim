import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../../domain/format.dart';
import '../../../domain/models.dart';
import 'jamix_script.dart';

class JamixError implements Exception {
  final String message;
  const JamixError(this.message);
  @override
  String toString() => message;
}

/// Reads NDSU Dining menus from usa.jamix.cloud. The site is a Vaadin app with no usable JSON API, so this loads
/// the real page in a headless web view and drives it with `jamixScript`. One job runs at a time, and the web view
/// switches to the job's hall when it needs to; jobs you're waiting on go ahead of background prefetching. On iOS the headless web view sits behind the
/// app's content in the key window (flutter_inappwebview does this), so WebKit doesn't throttle its timers.
/// The web view is kept between screens, so the Vaadin session survives closing and reopening the menu.
class JamixService {
  HeadlessInAppWebView? _headless;
  InAppWebViewController? _controller;

  /// The hall whose page is loaded or loading.
  DiningHall? _pageHall;
  bool _pageReady = false;
  final List<Completer<void>> _loadWaiters = [];

  bool _busy = false;

  /// Whether the job running now is background work that an urgent job may interrupt.
  bool _runningBackground = false;
  final List<({bool urgent, Completer<void> go})> _waiting = [];

  /// An urgent job is waiting for the background read. Kept here as well as in the page's `wl.abort`, because
  /// a background job that is loading a page has no `wl` yet to tell.
  bool _abortBackground = false;

  // Job queue

  Future<void> _acquire(bool urgent) async {
    if (!_busy) {
      _busy = true;
      return;
    }
    // A background station read stops after its current item (`wl.abort`) instead of finishing the station.
    if (urgent && _runningBackground) await abortBackground();
    final go = Completer<void>();
    if (urgent) {
      final at = _waiting.indexWhere((w) => !w.urgent);
      _waiting.insert(at < 0 ? _waiting.length : at, (urgent: true, go: go));
    } else {
      _waiting.add((urgent: false, go: go));
    }
    await go.future;
  }

  void _release() {
    if (_waiting.isEmpty) {
      _busy = false;
    } else {
      _waiting.removeAt(0).go.complete();
    }
  }

  /// Stops a running background station read after its current item.
  Future<void> abortBackground() async {
    if (!_runningBackground) return;
    _abortBackground = true;
    try {
      await _controller?.evaluateJavascript(source: 'wl.abort = true');
    } on Exception {
      // The page is gone; there's nothing left to stop.
    }
  }

  // Page

  /// Whether a finished load can be for the hall being loaded, so a page replaced by a hall switch is ignored.
  /// Only a different kitchen (`k`) rules it out, in case the site redirects to a URL without one.
  bool _isPageFor(WebUri? url) {
    final want = _pageHall;
    if (want == null) return false;
    final k = url?.queryParameters['k'];
    return k == null || k == Uri.parse(want.menuURL).queryParameters['k'];
  }

  Future<void> _ensurePage(DiningHall hall, {bool reload = false}) async {
    if (_headless == null) {
      _pageReady = false;
      final headless = HeadlessInAppWebView(
        initialSize: const Size(390, 844),
        initialSettings: InAppWebViewSettings(javaScriptEnabled: true, cacheEnabled: true),
        initialUserScripts: UnmodifiableListView([
          UserScript(source: jamixScript, injectionTime: UserScriptInjectionTime.AT_DOCUMENT_END),
        ]),
        onWebViewCreated: (c) => _controller = c,
        onLoadStop: (c, url) {
          if (_isPageFor(url)) _finishLoad(null);
        },
        onReceivedError: (c, request, error) {
          if ((request.isForMainFrame ?? true) && _isPageFor(request.url)) {
            _pageReady = false;
            _finishLoad(JamixError(error.description));
          }
        },
        onWebContentProcessDidTerminate: (c) {
          _pageReady = false;
          _pageHall = null;
          _finishLoad(const JamixError('The menu page stopped.'));
        },
      );
      _headless = headless;
      await headless.run();
      reload = true;
    }
    if (_pageReady && _pageHall == hall && !reload) return;
    _pageHall = hall;
    _pageReady = false;
    final loaded = Completer<void>();
    _loadWaiters.add(loaded);
    final c = _controller;
    if (c == null) throw const JamixError("The menu page didn't load.");
    await c.stopLoading();
    await c.loadUrl(
      urlRequest: URLRequest(
        url: WebUri(hall.menuURL),
        cachePolicy: URLRequestCachePolicy.RELOAD_IGNORING_LOCAL_CACHE_DATA,
        timeoutInterval: 20,
      ),
    );
    await loaded.future.timeout(const Duration(seconds: 25));
    // The page builds itself with script after load; the injected `wl` object is there once the document ends.
    for (var i = 0; i < 50; i++) {
      try {
        if (await c.evaluateJavascript(source: 'typeof window.wl') == 'object') {
          _pageReady = true;
          return;
        }
      } on Exception {
        // Not ready yet.
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    throw const JamixError("The menu page didn't load.");
  }

  void _finishLoad(Object? error) {
    final waiters = [..._loadWaiters];
    _loadWaiters.clear();
    for (final w in waiters) {
      if (w.isCompleted) continue;
      if (error != null) {
        w.completeError(error);
      } else {
        w.complete();
      }
    }
  }

  /// Runs one script call, reloading the page and retrying once if it fails (the Vaadin session expires after
  /// a while, and the page then needs a fresh load).
  Future<String> _call(String body, Map<String, dynamic> args, DiningHall hall, {required bool urgent}) async {
    final clock = Stopwatch()..start();
    await _acquire(urgent);
    final waited = clock.elapsedMilliseconds;
    _runningBackground = !urgent;
    try {
      Object? lastError;
      for (var attempt = 0; attempt < 2; attempt++) {
        try {
          await _ensurePage(hall, reload: attempt > 0);
          if (!urgent && _abortBackground) await _controller!.evaluateJavascript(source: 'wl.abort = true');
          final r = await _controller!.callAsyncJavaScript(functionBody: body, arguments: args);
          if (r?.error != null) throw JamixError(r!.error!);
          final out = r?.value;
          if (out is! String) throw const JamixError('The menu page returned nothing.');
          return out;
        } on Exception catch (e) {
          lastError = e;
        }
      }
      throw lastError ?? const JamixError('The menu page failed.');
    } finally {
      // In the device log (Console, or idevicesyslog), to see where a slow tap spends its time.
      debugPrint(
        'Trim: Jamix ${hall.name} ${urgent ? 'urgent' : 'background'} $args: '
        'waited ${waited}ms, ran ${clock.elapsedMilliseconds - waited}ms',
      );
      if (!urgent) _abortBackground = false;
      _runningBackground = false;
      _release();
    }
  }

  // API

  Future<MarketMenu> menu(DateTime day, DiningHall hall) async {
    final key = Day.key(day);
    final raw = await _call('return await wl.menu(iso)', {'iso': key}, hall, urgent: true);
    try {
      final r = jsonDecode(raw) as Map<String, dynamic>;
      final tabs = (r['menus'] as List<dynamic>).whereType<Map<String, dynamic>>().map((t) {
        final tab = MenuTab.fromJson(t);
        return MenuTab(tab.name, tab.stations.where((s) => s.items.isNotEmpty).toList());
      }).toList();
      return MarketMenu(day: key, hall: hall, label: r['date'] as String? ?? '', tabs: tabs, fetched: DateTime.now());
    } on Object {
      throw const JamixError("Couldn't read the menu.");
    }
  }

  /// Nutrition labels for the items at one station: just `only` when given (a tap, about one item's worth of
  /// clicks instead of the whole station), otherwise everything except `skip`. `complete` is false when an
  /// urgent job interrupted a background read.
  Future<({List<MarketItem> items, bool complete})> station(
    DiningHall hall, {
    required String day,
    required int tab,
    required int station,
    required String name,
    List<String>? only,
    List<String> skip = const [],
    bool urgent = true,
  }) async {
    final opts = <String, dynamic>{'skip': skip, 'background': !urgent, 'only': ?only};
    final raw = await _call(
      'return await wl.station(iso, tab, station, opts)',
      {
        'iso': day,
        'tab': tab,
        'station': station,
        'opts': opts,
      },
      hall,
      urgent: urgent,
    );
    final Map<String, dynamic> result;
    try {
      result = jsonDecode(raw) as Map<String, dynamic>;
    } on Object {
      throw const JamixError("Couldn't read the nutrition labels.");
    }
    final items = (result['items'] as List<dynamic>? ?? const []).whereType<Map<String, dynamic>>().map((m) {
      final facts = (m['facts'] as Map<String, dynamic>? ?? const {}).map((k, v) => MapEntry(k, '$v'));
      double f(String k) => number(facts[k]) ?? 0;
      final fibre = f('Fibre');
      final n = Nutrients(
        calories: f('Calories'),
        protein: f('Protein'),
        carbs: f('Total Carbohydrate'),
        fat: f('Total Fat'),
        fiber: fibre == 0 ? f('Fiber') : fibre,
        sugar: f('of which sugars'),
        sodium: f('Sodium'),
        saturatedFat: f('of which saturates'),
      );
      final portion = m['portion'] as String? ?? '';
      return MarketItem(
        name: m['name'] as String? ?? '',
        hall: hall,
        station: name,
        nutrients: n,
        portion: portion,
        portionGrams: grams(portion),
      );
    }).toList();
    return (items: items, complete: result['aborted'] != true);
  }

  static double? number(String? s) {
    if (s == null) return null;
    // "1,050 mg": commas between groups of three digits separate thousands.
    final thousands = RegExp(r'(?<![\d.,])\d{1,3}(?:,\d{3})+(?:\.\d+)?(?![\d,])').firstMatch(s);
    if (thousands != null) return double.tryParse(thousands[0]!.replaceAll(',', ''));
    // Otherwise a comma is a decimal point ("2,5 g").
    final m = RegExp(r'\d+(?:[.,]\d+)?').firstMatch(s);
    return m == null ? null : double.tryParse(m[0]!.replaceAll(',', '.'));
  }

  static double? grams(String portion) {
    final m = RegExp(r'\(\s*([\d.]+)\s*g\s*\)').firstMatch(portion);
    return m == null ? null : number(m[0]);
  }
}
