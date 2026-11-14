// Cells are chosen per row (a ternary reads clearer than if-elements here),
// and the workbook XML is built from fixed fragments with no spaces between.
// ignore_for_file: prefer_if_elements_to_conditional_expressions, missing_whitespace_between_adjacent_strings
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:drift/drift.dart' show OrderingTerm;
import 'package:intl/intl.dart';
import 'package:rivero/core/database/database.dart';
import 'package:rivero/core/dues/dues_service.dart';

/// One table of exported data: a header row and string cells.
class ExportSheet {
  const ExportSheet(this.name, this.header, this.rows);

  final String name;
  final List<String> header;
  final List<List<String>> rows;
}

/// Takes the user's data out of Rivero as CSV or an Excel workbook, so it is
/// never locked in. Nothing is uploaded: the caller saves or shares the bytes.
/// Amounts are written from integer paise as exact rupee decimals ("450.50").
class DataExport {
  const DataExport(this.db);

  final RiveroDatabase db;

  /// 12345 -> "123.45", -5 -> "-0.05". Exact; no floating point.
  static String rupees(int minor) {
    final neg = minor < 0;
    final v = minor.abs();
    final s = '${v ~/ 100}.${(v % 100).toString().padLeft(2, '0')}';
    return neg ? '-$s' : s;
  }

  static final _date = DateFormat('yyyy-MM-dd HH:mm');

  Future<List<ExportSheet>> sheets() async {
    final accounts = await db.select(db.physicalAccounts).get();
    final name = {for (final a in accounts) a.id: a.name};
    final txns = await (db.select(
      db.transactions,
    )..orderBy([(t) => OrderingTerm.desc(t.transactionTimestamp)])).get();
    final buckets = await db.select(db.allocationBuckets).get();
    final dues = await db.select(db.dues).get();
    final mandates = await db.select(db.mandates).get();

    return [
      ExportSheet(
        'Transactions',
        const [
          'Date',
          'Account',
          'Amount (INR)',
          'Direction',
          'Type',
          'State',
          'Merchant',
          'Category',
          'Note',
          'Reference',
        ],
        [
          for (final t in txns)
            [
              _date.format(t.transactionTimestamp),
              name[t.physicalAccountId] ?? t.physicalAccountId,
              rupees(t.amountMinorUnits.abs()),
              t.amountMinorUnits < 0 ? 'out' : 'in',
              t.transactionType.name,
              t.transactionState.name,
              t.merchant,
              t.category,
              t.userNotes ?? '',
              t.referenceNumber ?? '',
            ],
        ],
      ),
      ExportSheet(
        'Accounts',
        const [
          'Name',
          'Bank',
          'Last digits',
          'Type',
          'Balance (INR)',
          'Is card/loan',
          'Credit limit (INR)',
          'Active',
        ],
        [
          for (final a in accounts)
            [
              a.name,
              a.institution,
              a.accountMask,
              a.accountType,
              rupees(a.balanceMinorUnits),
              a.isLiability ? 'yes' : 'no',
              rupees(a.creditLimitMinorUnits),
              a.isActive ? 'yes' : 'no',
            ],
        ],
      ),
      ExportSheet(
        'Plan',
        const [
          'Category',
          'Role',
          'Planned (INR)',
          'Carried over (INR)',
          'Spent/paid (INR)',
        ],
        [
          for (final b in buckets)
            [
              b.name,
              b.role.name,
              rupees(b.allocatedMinorUnits),
              rupees(b.carryOverMinorUnits),
              rupees(b.spentMinorUnits),
            ],
        ],
      ),
      ExportSheet(
        'Owed',
        const [
          'Person',
          'Kind',
          'Amount (INR)',
          'Settled so far (INR)',
          'Outstanding (INR)',
          'Status',
          'Date',
          'Pay back by',
          'Note',
        ],
        [
          for (final d in dues)
            [
              d.person,
              d.kind.name,
              rupees(d.amountMinorUnits),
              rupees(d.receivedMinorUnits),
              rupees(DuesService(db).outstandingOf(d)),
              d.status.name,
              _date.format(d.createdAt),
              d.dueDate == null ? '' : _date.format(d.dueDate!),
              d.note ?? '',
            ],
        ],
      ),
      ExportSheet(
        'Autopay',
        const [
          'Payee',
          'Amount (INR)',
          'Up to (INR)',
          'Frequency',
          'Next date',
          'Status',
          'Account',
        ],
        [
          for (final m in mandates)
            [
              m.payee,
              rupees(m.amountMinorUnits),
              m.maxCapMinorUnits == null ? '' : rupees(m.maxCapMinorUnits!),
              m.frequency.name,
              m.nextExecutionDate == null
                  ? ''
                  : _date.format(m.nextExecutionDate!),
              m.status.name,
              name[m.physicalAccountId] ?? m.physicalAccountId,
            ],
        ],
      ),
    ];
  }

  // ---- CSV -----------------------------------------------------------------

  static String _csvCell(String v) {
    final needs =
        v.contains(',') ||
        v.contains('"') ||
        v.contains('\n') ||
        v.contains('\r');
    // A leading = + - @ would run as a formula in spreadsheets: neutralise.
    final safe = v.isNotEmpty && '=+-@'.contains(v[0]) && !_isNumber(v)
        ? "'$v"
        : v;
    return needs || safe != v ? '"${safe.replaceAll('"', '""')}"' : v;
  }

  static bool _isNumber(String v) => RegExp(r'^-?\d+(\.\d+)?$').hasMatch(v);

  static String csv(ExportSheet sheet) {
    final b = StringBuffer()..writeln(sheet.header.map(_csvCell).join(','));
    for (final r in sheet.rows) {
      b.writeln(r.map(_csvCell).join(','));
    }
    return b.toString();
  }

  /// Every sheet as its own CSV inside a .zip ("transactions.csv"...).
  Future<Uint8List> csvZip() async {
    final archive = Archive();
    for (final s in await sheets()) {
      final bytes = utf8.encode('﻿${csv(s)}'); // BOM: Excel reads UTF-8
      archive.addFile(
        ArchiveFile('${s.name.toLowerCase()}.csv', bytes.length, bytes),
      );
    }
    return Uint8List.fromList(ZipEncoder().encode(archive));
  }

  // ---- Excel (.xlsx) -----------------------------------------------------

  static String _xml(String v) => v
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      // Control characters are not allowed in XML.
      .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '');

  static String _col(int i) {
    var n = i + 1;
    var s = '';
    while (n > 0) {
      final r = (n - 1) % 26;
      s = String.fromCharCode(65 + r) + s;
      n = (n - 1) ~/ 26;
    }
    return s;
  }

  static String _sheetXml(ExportSheet s) {
    final b = StringBuffer(
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
      '<sheetData>',
    );
    final all = [s.header, ...s.rows];
    for (var r = 0; r < all.length; r++) {
      b.write('<row r="${r + 1}">');
      for (var c = 0; c < all[r].length; c++) {
        final v = all[r][c];
        final ref = '${_col(c)}${r + 1}';
        // Amount columns become real numbers so totals work in Excel.
        if (r > 0 && _isNumber(v) && s.header[c].contains('(INR)')) {
          b.write('<c r="$ref"><v>$v</v></c>');
        } else {
          b.write(
            '<c r="$ref" t="inlineStr"><is><t xml:space="preserve">'
            '${_xml(v)}</t></is></c>',
          );
        }
      }
      b.write('</row>');
    }
    b.write('</sheetData></worksheet>');
    return b.toString();
  }

  Future<Uint8List> xlsx() async {
    final list = await sheets();
    final archive = Archive();
    void add(String path, String content) {
      final bytes = utf8.encode(content);
      archive.addFile(ArchiveFile(path, bytes.length, bytes));
    }

    add(
      '[Content_Types].xml',
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
          '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
          '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
          '<Default Extension="xml" ContentType="application/xml"/>'
          '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
          '${[for (var i = 0; i < list.length; i++) '<Override PartName="/xl/worksheets/sheet${i + 1}.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'].join()}'
          '</Types>',
    );
    add(
      '_rels/.rels',
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
          '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
          '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>'
          '</Relationships>',
    );
    add(
      'xl/workbook.xml',
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
          '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
          'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets>'
          '${[for (var i = 0; i < list.length; i++) '<sheet name="${_xml(list[i].name)}" sheetId="${i + 1}" r:id="rId${i + 1}"/>'].join()}'
          '</sheets></workbook>',
    );
    add(
      'xl/_rels/workbook.xml.rels',
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
          '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
          '${[for (var i = 0; i < list.length; i++) '<Relationship Id="rId${i + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet${i + 1}.xml"/>'].join()}'
          '</Relationships>',
    );
    for (var i = 0; i < list.length; i++) {
      add('xl/worksheets/sheet${i + 1}.xml', _sheetXml(list[i]));
    }
    return Uint8List.fromList(ZipEncoder().encode(archive));
  }
}
