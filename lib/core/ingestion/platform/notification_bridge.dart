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

  /// Process captures the moment the native listener queues them (while the
  /// app is open); otherwise they are drained on the next app resume.
  void listenForCaptures() {
    if (!supported) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'queued') await drain();
    });
  }

  /// A bank-style test message: Rs 1 debit, unique reference, and no
  /// "available balance" so it cannot overwrite the real balance.
  static String sampleMessage({required String mask, required DateTime now}) {
    final d = now.day.toString().padLeft(2, '0');
    final m = now.month.toString().padLeft(2, '0');
    final y = (now.year % 100).toString().padLeft(2, '0');
    final ref = (now.millisecondsSinceEpoch % 1000000000000).toString().padLeft(
      12,
      '0',
    );
    return 'Rs 1.00 debited from A/c XX$mask on $d-$m-$y to VPA '
        'rivero.test@ybl (UPI Ref No $ref). Rivero capture test.';
  }

  /// Posts a real system notification that the listener should capture.
  /// Returns `posted`, `no_access` (listener not granted) or `no_permission`.
  static Future<String> postTest({required String body}) async {
    if (!supported) return 'unsupported';
    return await _channel.invokeMethod<String>('postTest', {
          'title': 'Bank alert (test)',
          'body': body,
        }) ??
        'unsupported';
  }

  Future<void> _running = Future.value();

  /// Pulls queued notifications and ingests them. Returns count processed.
  /// Runs one at a time, so a wake-up and an app resume cannot interleave.
  Future<int> drain() {
    if (!supported) return Future.value(0);
    final run = _running.then((_) async {
      final json = await _channel.invokeMethod<String>('drain');
      return await ingestJson(json ?? '[]');
    });
    _running = run.then((_) {}, onError: (_) {});
    return run;
  }

  /// Tells the Android listener which UPI app is the user's main one (an
  /// empty or null package clears it).
  static Future<void> setPrimaryApp(String? package) async {
    if (!supported) return;
    try {
      await _channel.invokeMethod<void>('setPrimaryApp', {'package': package});
    } on MissingPluginException {
      // Not running on a device (tests).
    }
  }

  /// What the listener has seen since install: how many notifications it
  /// queued, skipped as not about money, or found without readable text,
  /// and the last app it heard from. Empty off-device.
  static Future<Map<String, dynamic>> diagnostics() async {
    if (!supported) return const {};
    try {
      final json = await _channel.invokeMethod<String>('diagnostics');
      return json == null
          ? const {}
          : (jsonDecode(json) as Map).cast<String, dynamic>();
    } on MissingPluginException {
      return const {};
    }
  }

  /// Empties the phone's capture queue ("Delete all data").
  static Future<void> clearQueue() async {
    if (!supported) return;
    try {
      await _channel.invokeMethod<void>('clearQueue');
    } on MissingPluginException {
      // Not running on a device (tests).
    }
  }

  /// Blocks screenshots and the recent-apps preview (Android), used while
  /// app lock is on so amounts never show outside the app.
  static Future<void> setSecure({required bool on}) async {
    if (!supported) return;
    try {
      await _channel.invokeMethod<void>('setSecure', {'on': on});
    } on MissingPluginException {
      // Not running on a device (tests).
    }
  }

  /// Parses the native queue payload; separated from [drain] for testing.
  Future<int> ingestJson(String json) async {
    final items = (jsonDecode(json) as List).cast<Map<String, dynamic>>();
    var processed = 0;
    for (final m in items) {
      // The native queue was already emptied, so one bad message must not
      // lose the ones behind it.
      try {
        await _ingestion.processNotification(
          RawNotification(
            id: m['id'] as String,
            body: m['body'] as String,
            title: m['title'] as String?,
            // In an SMS app the title is the sender ("VM-SBIUPI", "Mom").
            sender: m['title'] as String?,
            packageName: m['package'] as String?,
            receivedAt: DateTime.fromMillisecondsSinceEpoch(m['time'] as int),
          ),
        );
        processed++;
      } on Object {
        continue;
      }
    }
    return processed;
  }
}
