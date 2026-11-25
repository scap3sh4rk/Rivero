import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:rivero/core/backup/auto_backup.dart';
import 'package:rivero/core/backup/backup_codec.dart';
import 'package:rivero/core/backup/drive_backup.dart';
import 'package:rivero/core/providers/app_providers.dart';
import 'package:rivero/design_system/rivero_tokens.dart';
import 'package:rivero/design_system/widgets/rivero_app_bar.dart';

/// Back up to Google Drive (or a file), and restore. Always encrypted with
/// a passphrase chosen here (kept in secure storage only for automatic backups).
class BackupScreen extends ConsumerStatefulWidget {
  const BackupScreen({super.key});

  static Future<void> open(BuildContext context) =>
      Navigator.of(context)
          .push(MaterialPageRoute<void>(builder: (_) => const BackupScreen()));

  @override
  ConsumerState<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends ConsumerState<BackupScreen> {
  static const _codec = BackupCodec();
  bool _busy = false;
  String? _status;

  void _say(String text) {
    if (!mounted) return;
    setState(() => _status = text);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  BackupFrequency _freq = BackupFrequency.off;
  DateTime? _last;

  @override
  void initState() {
    super.initState();
    _loadAuto();
  }

  Future<void> _loadAuto() async {
    final auto = AutoBackup(ref.read(databaseProvider));
    final f = await auto.frequency();
    final last = await auto.lastBackup();
    if (mounted) {
      setState(() {
        _freq = f;
        _last = last;
      });
    }
  }

  String _autoLabel() {
    final when = _last == null
        ? 'never backed up'
        : 'last backup ${DateFormat('d MMM, h:mm a').format(_last!)}';
    return switch (_freq) {
      BackupFrequency.off => 'Off · $when',
      BackupFrequency.daily => 'Every day · $when',
      BackupFrequency.weekly => 'Every week · $when',
    };
  }

  /// Off, daily or weekly. Turning it on asks for the passphrase once (kept
  /// in the phone's keystore) and makes the first backup now, which also
  /// signs in to Google so later backups need no screen at all.
  Future<void> _chooseAuto() async {
    final picked = await showModalBottomSheet<BackupFrequency>(
      context: context,
      backgroundColor: RiveroColors.surface,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final f in BackupFrequency.values)
              ListTile(
                title: Text(switch (f) {
                  BackupFrequency.off => 'Off',
                  BackupFrequency.daily => 'Every day',
                  BackupFrequency.weekly => 'Every week',
                }),
                trailing: f == _freq ? const Icon(Icons.check_rounded) : null,
                onTap: () => Navigator.pop(ctx, f),
              ),
          ],
        ),
      ),
    );
    if (picked == null) return;
    final auto = AutoBackup(ref.read(databaseProvider));
    if (picked == BackupFrequency.off) {
      await auto.configure(picked);
      await _loadAuto();
      _say('Automatic backup is off');
      return;
    }
    final pass = await _askPassphrase(confirm: true, kept: true);
    if (pass == null) return;
    final data = await BackupCodec.export(ref.read(databaseProvider));
    await DriveBackup().upload(await _codec.encrypt(data, pass));
    await auto.configure(picked, passphrase: pass);
    await auto.markBackedUp(DateTime.now());
    await _loadAuto();
    _say('Backed up now; the next ones happen by themselves');
  }

  /// [kept]: automatic backups keep the passphrase on this phone (in its
  /// secure storage) so they can run by themselves; say so.
  Future<String?> _askPassphrase({required bool confirm, bool kept = false}) {
    final a = TextEditingController();
    final b = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) {
          final ok = a.text.length >= 8 && (!confirm || a.text == b.text);
          return AlertDialog(
            title: Text(confirm ? 'Choose a passphrase' : 'Backup passphrase'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (confirm)
                  Text(
                    kept
                        ? 'It encrypts every backup. Rivero keeps it in this '
                              "phone's secure storage so backups run by "
                              'themselves; it is never uploaded. Write it '
                              'down: without it a backup cannot be opened.'
                        : 'It encrypts the backup. Rivero does not keep it: '
                              'if it is lost, the backup cannot be opened.',
                  ),
                const SizedBox(height: RiveroSpacing.md),
                TextField(
                  key: const ValueKey('passphrase'),
                  controller: a,
                  obscureText: true,
                  autofocus: true,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    hintText: 'At least 8 characters',
                  ),
                ),
                if (confirm) ...[
                  const SizedBox(height: RiveroSpacing.sm),
                  TextField(
                    key: const ValueKey('passphrase-again'),
                    controller: b,
                    obscureText: true,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      hintText: 'Type it again',
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: ok ? () => Navigator.pop(ctx, a.text) : null,
                child: const Text('Continue'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<List<int>?> _encryptedBackup() async {
    final pass = await _askPassphrase(confirm: true);
    if (pass == null) return null;
    final data = await BackupCodec.export(ref.read(databaseProvider));
    return await _codec.encrypt(data, pass);
  }

  Future<void> _restoreFrom(List<int> bytes) async {
    final pass = await _askPassphrase(confirm: false);
    if (pass == null || !mounted) return;
    final data = await _codec.decrypt(bytes, pass);
    if (!mounted) return;
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Replace everything with this backup?'),
        content: const Text('Data on this phone is replaced by the backup.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );
    if (go != true) return;
    await BackupCodec.restore(ref.read(databaseProvider), data);
    await ref.read(settingsSyncProvider).load();
    _say('Restored');
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } on BackupException catch (e) {
      _say(e.message);
    } on Object catch (e) {
      _say(friendlyBackupError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final drive = DriveBackup();
    return Scaffold(
      backgroundColor: RiveroColors.background,
      appBar: RiveroAppBar(
        showEye: false, // the hide-amounts eye is for money pages
        title: 'Backup',
        showProfile: false,
        leading: BackButton(onPressed: () => Navigator.of(context).pop()),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: RiveroSpacing.sm),
        children: [
          Padding(
            padding: const EdgeInsets.all(RiveroSpacing.md),
            child: Text(
              'Backups are encrypted on this phone with your passphrase before '
              'they are saved. Google Drive keeps them in a hidden app folder.',
              style: RiveroTypography.bodySmall,
            ),
          ),
          if (_busy) const LinearProgressIndicator(),
          ListTile(
            key: const ValueKey('auto-backup'),
            leading: const Icon(Icons.schedule_rounded),
            title: const Text('Automatic backup to Google Drive'),
            subtitle: Text(_autoLabel()),
            onTap: () => _run(_chooseAuto),
          ),
          ListTile(
            leading: const Icon(Icons.cloud_upload_outlined),
            title: const Text('Back up to Google Drive'),
            subtitle: _status == null ? null : Text(_status!),
            onTap: () => _run(() async {
              final bytes = await _encryptedBackup();
              if (bytes == null) return;
              await drive.upload(bytes);
              await AutoBackup(ref.read(databaseProvider))
                  .markBackedUp(DateTime.now());
              _say(
                'Backed up ${DateFormat('d MMM, h:mm a').format(DateTime.now())}',
              );
            }),
          ),
          ListTile(
            leading: const Icon(Icons.cloud_download_outlined),
            title: const Text('Restore from Google Drive'),
            onTap: () => _run(() async {
              final found = await drive.download();
              if (found == null) return _say('No backup found in your Drive');
              await _restoreFrom(found.bytes);
            }),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.save_alt_rounded),
            title: const Text('Save a backup file'),
            subtitle: const Text('Keep it anywhere: USB, another cloud'),
            onTap: () => _run(() async {
              final bytes = await _encryptedBackup();
              if (bytes == null) return;
              final name =
                  'rivero-${DateFormat('yyyyMMdd-HHmm').format(DateTime.now())}.json';
              final saved = await FilePicker.saveFile(
                fileName: name,
                bytes: Uint8List.fromList(bytes),
                mimeType: 'application/json',
              );
              if (saved != null) {
                await AutoBackup(ref.read(databaseProvider))
                    .markBackedUp(DateTime.now());
                _say('Saved $name');
              }
            }),
          ),
          ListTile(
            leading: const Icon(Icons.restore_rounded),
            title: const Text('Restore from a file'),
            onTap: () => _run(() async {
              final picked = await FilePicker.pickFiles();
              final path = picked.firstOrNull?.path;
              if (path == null) return;
              await _restoreFrom(await File(path).readAsBytes());
            }),
          ),
        ],
      ),
    );
  }
}
