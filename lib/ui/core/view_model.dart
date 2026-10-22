import 'package:flutter/foundation.dart';

/// Base class for screen ViewModels. Network and web-view work can finish after its screen has closed, so
/// notifications after [dispose] are dropped instead of throwing.
abstract class ViewModel extends ChangeNotifier {
  bool _disposed = false;

  bool get isDisposed => _disposed;

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
