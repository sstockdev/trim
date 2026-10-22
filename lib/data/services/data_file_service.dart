import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../../domain/models.dart';

/// The result of reading trim.json at launch.
class LoadedData {
  final AppData data;

  /// Set when trim.json couldn't be read: the name of the copy kept next to it.
  final String? unreadableBackup;

  /// True when the unreadable file couldn't be copied aside, so saving would destroy the only copy.
  final bool saveBlocked;

  const LoadedData(this.data, {this.unreadableBackup, this.saveBlocked = false});
}

/// Reads and writes trim.json in the app's Documents folder (visible in the iOS Files app).
class DataFileService {
  DataFileService({Future<Directory> Function()? directory})
    : _directory = directory ?? getApplicationDocumentsDirectory;

  final Future<Directory> Function() _directory;
  File? _file;

  Future<File> _target() async => _file ??= File('${(await _directory()).path}/trim.json');

  Future<LoadedData> load() async {
    final file = await _target();
    if (!await file.exists()) return LoadedData(AppData());
    final raw = await file.readAsBytes();
    try {
      // Years of logging make a big file, so it's parsed off the UI isolate.
      return LoadedData(await compute(_decode, raw));
    } on Object {
      // Keep the unreadable file instead of overwriting it with an empty one.
      final name = 'trim-unreadable-${DateTime.now().millisecondsSinceEpoch ~/ 1000}.json';
      try {
        await File('${file.parent.path}/$name').writeAsBytes(raw);
        return LoadedData(AppData(), unreadableBackup: name);
      } on Object {
        return LoadedData(AppData(), unreadableBackup: 'trim.json', saveBlocked: true);
      }
    }
  }

  static AppData _decode(Uint8List raw) => AppData.fromJson(jsonDecode(utf8.decode(raw)));

  /// Written to a temporary file and renamed, so a crash mid-write can't leave half a file.
  void save(AppData data) {
    final file = _file;
    if (file == null) return;
    try {
      final tmp = File('${file.path}.tmp');
      tmp.writeAsStringSync(jsonEncode(data.toJson()), flush: true);
      tmp.renameSync(file.path);
    } on FileSystemException catch (e) {
      debugPrint('Trim: save failed: $e');
    }
  }
}
