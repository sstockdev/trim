import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// API keys for USDA and for plugins, kept in the iOS Keychain or the Android Keystore rather than in trim.json.
/// They're read once at launch so screens can check them synchronously.
class KeyService {
  KeyService({this._storage = const FlutterSecureStorage()});

  static const usda = 'usda.key';

  final FlutterSecureStorage _storage;
  final Map<String, String> _values = {};

  /// Reads [usda] and the given plugin keys.
  Future<void> load(Iterable<String> pluginKeys) async {
    for (final k in {usda, ...pluginKeys}) {
      try {
        final v = await _storage.read(key: k);
        if (v != null && v.isNotEmpty) _values[k] = v;
      } on Exception {
        // A storage error leaves that key unset, the same as never having entered it.
      }
    }
  }

  String? get(String key) => _values[key];

  Future<void> set(String key, String? value) async {
    final v = value?.trim() ?? '';
    if (v.isEmpty) {
      _values.remove(key);
      await _storage.delete(key: key);
    } else {
      _values[key] = v;
      await _storage.write(key: key, value: v);
    }
  }
}
