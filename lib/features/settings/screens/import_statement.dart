import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:rivero/core/import/statement_importer.dart';
import 'package:rivero/core/import/statement_parser.dart';
import 'package:rivero/core/import/statement_text_parser.dart';
import 'package:rivero/core/ingestion/platform/notification_bridge.dart';
import 'package:rivero/core/providers/app_providers.dart';
import 'package:rivero/core/utils/currency_formatter.dart';
import 'package:rivero/design_system/rivero_tokens.dart';

/// Pick an account and a PDF (Android) or CSV statement, preview, import.
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

  final pdf = NotificationBridge.supported; // read on the phone (Android)
  final files = await FilePicker.pickFiles(
    type: FileType.custom,
    allowedExtensions: [if (pdf) 'pdf', 'csv'],
  );
  final path = files.firstOrNull?.path;
  if (path == null || !context.mounted) return;

  final List<StatementRow> rows;
  if (path.toLowerCase().endsWith('.pdf')) {
    final text = await _pdfText(context, path);
    if (text == null || !context.mounted) return;
    rows = parseStatementText(text.split(RegExp(r'\r?\n')));
  } else {
    rows = parseStatementCsv(await File(path).readAsString());
  }
  if (!context.mounted) return;
  if (rows.isEmpty) {
    return say(
      'Could not find transactions in that file. A PDF needs one line per '
      'entry with a date and an amount; a CSV needs date, description and '
      'debit/credit (or amount) columns.',
    );
  }
  final dates = rows.map((r) => r.date).toList()..sort();
  final fmt = DateFormat('d MMM y');
  final go = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Import ${rows.length} transactions?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${fmt.format(dates.first)} – ${fmt.format(dates.last)}.\n'
              'Your current balance is not changed; entries already in '
              'Rivero are skipped.',
            ),
            const SizedBox(height: 12),
            // A preview, so a misread statement is caught before import.
            for (final r in rows.take(6))
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '${DateFormat('d MMM').format(r.date)} · '
                  '${r.amountMinorUnits < 0 ? '−' : '+'}'
                  '${CurrencyFormatter.format(r.amountMinorUnits.abs())} · '
                  '${r.description}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            if (rows.length > 6) Text('and ${rows.length - 6} more'),
          ],
        ),
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

/// The PDF's text; asks for the password if it has one (used once, never
/// saved). Null if the user cancels or the file cannot be read.
Future<String?> _pdfText(BuildContext context, String path) async {
  String? password;
  while (true) {
    final r = await NotificationBridge.pdfText(path, password: password);
    if (r.text != null) return r.text;
    if (!context.mounted) return null;
    if (r.error != 'password') {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Could not read that PDF.')));
      return null;
    }
    final c = TextEditingController();
    password = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(password == null ? 'PDF password' : 'Wrong password'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Banks often protect statements with a password (like part of '
              'your name and date of birth). It is used once to open the '
              'file and is not saved.',
            ),
            const SizedBox(height: RiveroSpacing.field),
            TextField(
              key: const ValueKey('pdf-password'),
              controller: c,
              obscureText: true,
              autofocus: true,
              onSubmitted: (v) => Navigator.pop(ctx, v),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, c.text),
            child: const Text('Open'),
          ),
        ],
      ),
    );
    // ponytail: not disposed here, the dialog may still be animating out
    // and use it; it holds no listeners afterwards and is collected.
    if (password == null || password.isEmpty) return null;
  }
}
