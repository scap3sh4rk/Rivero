import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Photos the user attaches (account pictures, bill photos), copied into the
/// app's private storage so they survive the gallery file being deleted.
// ponytail: files are app-private but not encrypted like the database;
// encrypt them if photos of bills are considered sensitive.
abstract final class MediaStore {
  static const accountImages = 'account_images';
  static const bills = 'bills';

  /// For tests.
  static Directory? rootOverride;

  static Future<Directory> _dir(String folder) async {
    final root = rootOverride ?? await getApplicationDocumentsDirectory();
    return await Directory(p.join(root.path, folder)).create(recursive: true);
  }

  /// Copies [sourcePath] to `<folder>/<name>.<ext>` and returns the new path.
  static Future<String> keep(
    String sourcePath, {
    required String folder,
    required String name,
  }) async {
    final dir = await _dir(folder);
    final ext = p.extension(sourcePath).isEmpty
        ? '.jpg'
        : p.extension(sourcePath);
    // A fresh name each time so image caches never show a stale picture.
    final target = p.join(
      dir.path,
      '$name-${DateTime.now().millisecondsSinceEpoch}$ext',
    );
    return (await File(sourcePath).copy(target)).path;
  }

  static Future<void> remove(String? path) async {
    if (path == null) return;
    final f = File(path);
    if (f.existsSync()) await f.delete();
  }

  /// Deletes every stored photo (used by "Delete all data").
  static Future<void> wipe() async {
    for (final folder in [accountImages, bills]) {
      final d = await _dir(folder);
      if (d.existsSync()) await d.delete(recursive: true);
    }
  }
}
