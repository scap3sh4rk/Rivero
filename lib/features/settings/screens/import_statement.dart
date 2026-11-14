import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:rivero/core/import/statement_importer.dart';
import 'package:rivero/core/import/statement_parser.dart';
import 'package:rivero/core/providers/app_providers.dart';

/// Experimental: pick an account and a CSV statement, preview, import.
Future<void> importStatement(BuildContext context, WidgetRef ref) async {
  void say(String text) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));

  final accounts = ref.read(activePhysicalAccountsProvider).value ?? const [];
  if (accounts.isEmpty) return say('Add an account first.');
  final accountId = await showDialog<String>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: const Text('Which account is this statement for?'),
      children: [
        for (final a in accounts)
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, a.id),
            child: Text(a.name),
          ),
      ],
    ),
  );
  if (accountId == null || !context.mounted) return;

  final files = await FilePicker.pickFiles(
    type: FileType.custom,
    allowedExtensions: const ['csv'],
  );
  final path = files.firstOrNull?.path;
  if (path == null || !context.mounted) return;

  final rows = parseStatementCsv(await File(path).readAsString());
  if (!context.mounted) return;
  if (rows.isEmpty) {
    return say(
      'Could not find transactions in that file. Export it as CSV with '
      'date, description and debit/credit (or amount) columns.',
    );
  }
  final dates = rows.map((r) => r.date).toList()..sort();
  final fmt = DateFormat('d MMM y');
  final go = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Import ${rows.length} transactions?'),
      content: Text(
        '${fmt.format(dates.first)} – ${fmt.format(dates.last)}.\n'
        'Your current balance is not changed; entries already in Rivero '
        'are skipped.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Import'),
        ),
      ],
    ),
  );
  if (go != true) return;
  final result = await StatementImporter(ref.read(databaseProvider))
      .importRows(accountId, rows);
  if (context.mounted) {
    say(
      'Imported ${result.added}'
      '${result.skipped > 0 ? ', skipped ${result.skipped} already here' : ''}.',
    );
  }
}
