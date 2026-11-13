import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rivero/core/ingestion/models/raw_notification.dart';
import 'package:rivero/core/providers/app_providers.dart';
import 'package:rivero/design_system/rivero_tokens.dart';

/// Preset simulation bank SMS for interactive on-device testing.
class _SmsPreset {
  const _SmsPreset({
    required this.title,
    required this.sender,
    required this.body,
  });

  final String title;
  final String sender;
  final String body;
}

const _kSimulatedPresets = [
  _SmsPreset(
    title: 'HDFC UPI Debit (Starbucks)',
    sender: 'VK-HDFCBK',
    body:
        'Sent Rs.750.00 from HDFC Bank A/C **4012 to STARBUCKS on 13-Nov-26. '
        'Ref 431900123987. Bal Rs.149250.00.',
  ),
  _SmsPreset(
    title: 'ICICI Credit Card (Amazon)',
    sender: 'AD-ICICIB',
    body:
        'INR 2,999.00 spent on ICICI Bank Card 7102 at AMAZON INDIA on '
        '13-Nov-26. Avl Lmt INR 1,82,751.00.',
  ),
  _SmsPreset(
    title: 'PhonePe UPI Notification',
    sender: 'com.phonepe.app',
    body: 'Payment of ₹450 to Swiggy was successful.',
  ),
  _SmsPreset(
    title: 'ICICI Debit Card (BookMyShow)',
    sender: 'BP-ICICIB',
    body:
        'Acct XX8841 debited with INR 820.00 on 13-Nov-26. Info: BIL/ONL/BookMyShow. '
        'Bal: INR 47,430.00.',
  ),
  _SmsPreset(
    title: 'SBI Salary Credit',
    sender: 'VM-SBIBNK',
    body:
        'Dear Customer, Your A/C 9901 has a credit by transfer of '
        'Rs 1,50,000.00 on 13-Nov-26 by TECH CORP SALARY. Bal Rs 1,50,000.00.',
  ),
];

/// Bottom sheet allowing user to inject simulated bank notifications directly
/// into the live ingestion pipeline on a physical phone.
class SimulateSmsSheet extends ConsumerStatefulWidget {
  const SimulateSmsSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: RiveroColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => const SimulateSmsSheet(),
    );
  }

  @override
  ConsumerState<SimulateSmsSheet> createState() => _SimulateSmsSheetState();
}

class _SimulateSmsSheetState extends ConsumerState<SimulateSmsSheet> {
  late final TextEditingController _senderController;
  late final TextEditingController _bodyController;
  bool _isProcessing = false;
  String? _statusMessage;

  @override
  void initState() {
    super.initState();
    _senderController = TextEditingController(
      text: _kSimulatedPresets.first.sender,
    );
    _bodyController = TextEditingController(
      text: _kSimulatedPresets.first.body,
    );
  }

  @override
  void dispose() {
    _senderController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  void _applyPreset(_SmsPreset preset) {
    setState(() {
      _senderController.text = preset.sender;
      _bodyController.text = preset.body;
      _statusMessage = null;
    });
  }

  Future<void> _ingestNotification() async {
    final sender = _senderController.text.trim();
    final body = _bodyController.text.trim();
    if (sender.isEmpty || body.isEmpty) return;

    setState(() {
      _isProcessing = true;
      _statusMessage = null;
    });

    try {
      final ingestionService = ref.read(ingestionServiceProvider);
      final rawNotification = RawNotification(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        packageName: sender.contains('.')
            ? sender
            : 'com.google.android.apps.messaging',
        sender: sender,
        body: body,
        receivedAt: DateTime.now(),
      );

      final result = await ingestionService.processNotification(
        rawNotification,
      );

      if (mounted) {
        setState(() {
          _isProcessing = false;
          _statusMessage =
              'Success: ${result.status.name} (${result.parsedTransaction?.merchant ?? "Processed"})';
        });
        // Auto-close sheet after 1.2s to show success
        await Future<void>.delayed(const Duration(milliseconds: 1200));
        if (mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      }
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _statusMessage = 'Error: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: RiveroSpacing.lg,
        right: RiveroSpacing.lg,
        top: RiveroSpacing.xl,
        bottom: MediaQuery.of(context).viewInsets.bottom + RiveroSpacing.xl,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Sheet Drag Handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: RiveroColors.borderHighlight,
                  borderRadius: RiveroRadii.borderFull,
                ),
              ),
            ),
            const SizedBox(height: RiveroSpacing.lg),

            // Sheet Title
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Simulate Bank Notification',
                  style: RiveroTypography.titleLarge,
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            Text(
              'Test live parsing & deduplication without physical SMS.',
              style: RiveroTypography.bodySmall,
            ),
            const SizedBox(height: RiveroSpacing.md),

            // Presets Horizontal Chips
            Text(
              'QUICK PRESETS',
              style: RiveroTypography.labelSmall.copyWith(
                color: RiveroColors.textMuted,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: RiveroSpacing.xs),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _kSimulatedPresets.map((preset) {
                  return Padding(
                    padding: const EdgeInsets.only(right: RiveroSpacing.sm),
                    child: ActionChip(
                      label: Text(preset.title),
                      backgroundColor: RiveroColors.surfaceInteractive,
                      labelStyle: RiveroTypography.bodySmall.copyWith(
                        color: RiveroColors.textPrimary,
                        fontSize: 12,
                      ),
                      onPressed: () => _applyPreset(preset),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: RiveroSpacing.md),

            // Sender Header Field
            Text(
              'SENDER / TRAI HEADER',
              style: RiveroTypography.labelSmall.copyWith(
                color: RiveroColors.textMuted,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: RiveroSpacing.xs),
            TextField(
              controller: _senderController,
              style: RiveroTypography.monoMedium,
              decoration: InputDecoration(
                filled: true,
                fillColor: RiveroColors.surfaceInteractive,
                hintText: 'e.g. VK-HDFCBK or AD-ICICIB',
                border: const OutlineInputBorder(
                  borderRadius: RiveroRadii.borderMd,
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: RiveroSpacing.md,
                  vertical: RiveroSpacing.sm,
                ),
              ),
            ),
            const SizedBox(height: RiveroSpacing.md),

            // Body Field
            Text(
              'NOTIFICATION CONTENT',
              style: RiveroTypography.labelSmall.copyWith(
                color: RiveroColors.textMuted,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: RiveroSpacing.xs),
            TextField(
              controller: _bodyController,
              maxLines: 3,
              style: RiveroTypography.bodyMedium.copyWith(
                color: RiveroColors.textPrimary,
              ),
              decoration: InputDecoration(
                filled: true,
                fillColor: RiveroColors.surfaceInteractive,
                hintText: 'Sent Rs.500 to Merchant on 13-Nov-26...',
                border: const OutlineInputBorder(
                  borderRadius: RiveroRadii.borderMd,
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.all(RiveroSpacing.md),
              ),
            ),
            const SizedBox(height: RiveroSpacing.lg),

            if (_statusMessage != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(RiveroSpacing.sm),
                decoration: BoxDecoration(
                  color: _statusMessage!.startsWith('Success')
                      ? RiveroColors.investmentAccent.withValues(alpha: 0.15)
                      : RiveroColors.danger.withValues(alpha: 0.15),
                  borderRadius: RiveroRadii.borderSm,
                ),
                child: Text(
                  _statusMessage!,
                  style: RiveroTypography.bodySmall.copyWith(
                    color: _statusMessage!.startsWith('Success')
                        ? RiveroColors.investmentAccent
                        : RiveroColors.danger,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: RiveroSpacing.md),
            ],

            // Submit Button
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: _isProcessing ? null : _ingestNotification,
                icon: _isProcessing
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: RiveroColors.textPrimary,
                        ),
                      )
                    : const Icon(Icons.flash_on, size: 20),
                label: Text(
                  _isProcessing
                      ? 'Ingesting...'
                      : 'Ingest & Process Notification',
                  style: RiveroTypography.labelLarge,
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: RiveroColors.expenseAccent,
                  foregroundColor: RiveroColors.textPrimary,
                  shape: const RoundedRectangleBorder(
                    borderRadius: RiveroRadii.borderMd,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
