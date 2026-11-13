import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:rivero/core/ingestion/ingestion_service.dart';
import 'package:rivero/core/ingestion/models/raw_notification.dart';

/// Android-only bridge to `RiveroNotificationListener` (no READ_SMS).
/// The native service queues notifications; [drain] feeds them to ingestion.
class NotificationBridge {
  NotificationBridge(this._ingestion);

  static const _channel = MethodChannel('rivero/notifications');
  final IngestionService _ingestion;

  static bool get supported => Platform.isAndroid;

  static Future<bool> isEnabled() async =>
      supported && (await _channel.invokeMethod<bool>('isEnabled') ?? false);

  static Future<void> openSettings() async {
    if (supported) await _channel.invokeMethod<void>('openSettings');
  }

  /// Pulls queued notifications and ingests them. Returns count processed.
  Future<int> drain() async {
    if (!supported) return 0;
    final json = await _channel.invokeMethod<String>('drain');
    return await ingestJson(json ?? '[]');
  }

  /// Parses the native queue payload; separated from [drain] for testing.
  Future<int> ingestJson(String json) async {
    final items = (jsonDecode(json) as List).cast<Map<String, dynamic>>();
    for (final m in items) {
      await _ingestion.processNotification(
        RawNotification(
          id: m['id'] as String,
          body: m['body'] as String,
          title: m['title'] as String?,
          packageName: m['package'] as String?,
          receivedAt: DateTime.fromMillisecondsSinceEpoch(m['time'] as int),
        ),
      );
    }
    return items.length;
  }
}
