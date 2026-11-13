import 'package:flutter/foundation.dart';
import 'package:rivero/core/domain/transaction_enums.dart';

/// Represents an incoming unparsed financial notification or message event.
@immutable
class RawNotification {
  const RawNotification({
    required this.id,
    required this.body,
    required this.receivedAt,
    this.sender,
    this.title,
    this.packageName,
    this.channel = IngestionChannel.notificationAndroid,
  });

  /// Unique identifier for this ingestion event.
  final String id;

  /// Raw body text received from the notification or message.
  final String body;

  /// Timestamp when the notification was delivered by the operating system.
  final DateTime receivedAt;

  /// Sender header or address (e.g. "VK-HDFCBK", "AD-ICICIB").
  final String? sender;

  /// Notification title (if applicable, e.g. "Payment Successful").
  final String? title;

  /// Originating Android app package name (e.g. "com.phonepe.app").
  final String? packageName;

  /// Channel through which the raw notification was captured.
  final IngestionChannel channel;

  RawNotification copyWith({
    String? id,
    String? body,
    DateTime? receivedAt,
    String? sender,
    String? title,
    String? packageName,
    IngestionChannel? channel,
  }) {
    return RawNotification(
      id: id ?? this.id,
      body: body ?? this.body,
      receivedAt: receivedAt ?? this.receivedAt,
      sender: sender ?? this.sender,
      title: title ?? this.title,
      packageName: packageName ?? this.packageName,
      channel: channel ?? this.channel,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RawNotification &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          body == other.body &&
          receivedAt == other.receivedAt &&
          sender == other.sender &&
          title == other.title &&
          packageName == other.packageName &&
          channel == other.channel;

  @override
  int get hashCode =>
      Object.hash(id, body, receivedAt, sender, title, packageName, channel);

  @override
  String toString() {
    return 'RawNotification(id: $id, sender: $sender, package: $packageName, '
        'channel: $channel, time: $receivedAt)';
  }
}
