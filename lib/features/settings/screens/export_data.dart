import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:rivero/core/export/data_export.dart';
import 'package:rivero/core/providers/app_providers.dart';
import 'package:rivero/design_system/rivero_tokens.dart';

/// Settings > Export data: everything as an Excel workbook or CSV files,
/// saved where the user chooses. Nothing is uploaded.
Future<void> exportData(BuildContext context, WidgetRef ref) async {
  final format = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: RiveroColors.surface,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            key: const ValueKey('export-xlsx'),
            leading: const Icon(Icons.grid_on_rounded),
            title: const Text('Excel workbook (.xlsx)'),
            subtitle: const Text(
              'Transactions, accounts, plan, owed and autopay, one sheet each',
            ),
            onTap: () => Navigator.pop(ctx, 'xlsx'),
          ),
          ListTile(
            key: const ValueKey('export-csv'),
            leading: const Icon(Icons.table_rows_outlined),
            title: const Text('CSV files (.zip)'),
            subtitle: const Text('The same data as plain CSV files'),
            onTap: () => Navigator.pop(ctx, 'csv'),
          ),
        ],
      ),
    ),
  );
  if (format == null) return;
  final export = DataExport(ref.read(databaseProvider));
  final stamp = DateFormat('yyyyMMdd-HHmm').format(DateTime.now());
  final bytes = format == 'xlsx' ? await export.xlsx() : await export.csvZip();
  final name = 'rivero-export-$stamp.${format == 'xlsx' ? 'xlsx' : 'zip'}';
  final saved = await FilePicker.saveFile(
    fileName: name,
    bytes: bytes,
    mimeType: format == 'xlsx'
        ? 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
        : 'application/zip',
  );
  if (saved != null && context.mounted) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('Saved $name')));
  }
}
