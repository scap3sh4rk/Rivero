import 'dart:async';

import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;

/// Stores the (already encrypted) backup in the app's hidden Drive folder.
/// Rivero can only see that folder, never the user's other files.
class DriveBackup {
  /// OAuth web client (Google Cloud > Clients). Not a secret.
  static const webClientId =
      '855959883374-041lgtda0bn6uk69rru8is2nkdopkd83.apps.googleusercontent.com';
  static const List<String> _scopes = [drive.DriveApi.driveAppdataScope];
  static const _fileName = 'rivero-backup.json';
  static const _previousName = 'rivero-backup-previous.json';

  static Future<void>? _init;

  Future<drive.DriveApi> _api() async {
    _init ??= GoogleSignIn.instance.initialize(serverClientId: webClientId);
    await _init;
    final auth = await GoogleSignIn.instance.authorizationClient
        .authorizeScopes(_scopes);
    return drive.DriveApi(auth.authClient(scopes: _scopes));
  }

  /// The Drive API only if the user already allowed it: never shows any
  /// screen (used by automatic backups). Null when sign-in is needed.
  Future<drive.DriveApi?> _silentApi() async {
    _init ??= GoogleSignIn.instance.initialize(serverClientId: webClientId);
    await _init;
    final auth = await GoogleSignIn.instance.authorizationClient
        .authorizationForScopes(_scopes);
    return auth == null
        ? null
        : drive.DriveApi(auth.authClient(scopes: _scopes));
  }

  Future<drive.File?> _existing(
    drive.DriveApi api, [
    String name = _fileName,
  ]) async {
    final list = await api.files.list(
      spaces: 'appDataFolder',
      q: "name = '$name'",
      $fields: 'files(id, modifiedTime)',
    );
    return list.files?.firstOrNull;
  }

  /// Uploads [bytes] as the latest backup; the one it replaces is kept as
  /// the previous backup (so one bad backup never wipes the last good one).
  Future<void> upload(List<int> bytes) async =>
      await _upload(await _api(), bytes);

  /// Like [upload], but only if Drive access was granted before. Returns
  /// false (nothing uploaded) when the user must sign in again.
  Future<bool> uploadSilently(List<int> bytes) async {
    final api = await _silentApi();
    if (api == null) return false;
    await _upload(api, bytes);
    return true;
  }

  Future<void> _upload(drive.DriveApi api, List<int> bytes) async {
    final existing = await _existing(api);
    if (existing?.id != null) {
      final old = await _existing(api, _previousName);
      if (old?.id != null) await api.files.delete(old!.id!);
      await api.files.copy(
        drive.File()
          ..name = _previousName
          ..parents = ['appDataFolder'],
        existing!.id!,
      );
    }
    final media = drive.Media(Stream.value(bytes), bytes.length);
    if (existing?.id != null) {
      await api.files.update(drive.File(), existing!.id!, uploadMedia: media);
    } else {
      await api.files.create(
        drive.File()
          ..name = _fileName
          ..parents = ['appDataFolder'],
        uploadMedia: media,
      );
    }
  }

  /// Downloads the last backup, or null if there is none.
  Future<({List<int> bytes, DateTime? at})?> download() async {
    final api = await _api();
    final existing = await _existing(api);
    if (existing?.id == null) return null;
    final media = await api.files.get(
      existing!.id!,
      downloadOptions: drive.DownloadOptions.fullMedia,
    ) as drive.Media;
    final bytes = <int>[];
    await media.stream.forEach(bytes.addAll);
    return (bytes: bytes, at: existing.modifiedTime);
  }
}
