import 'package:flutter/material.dart';
import 'package:rivero/design_system/rivero_tokens.dart';

/// One choice in a [PickerField] / [showPicker] list.
class PickerOption<T> {
  const PickerOption(this.value, this.label, {this.leading});
  final T value;
  final String label;
  final Widget? leading;
}

/// The one way the app asks "pick one of these": a rounded bottom sheet
/// with the current choice ticked. Returns null if dismissed.
Future<PickerOption<T>?> showPicker<T>(
  BuildContext context, {
  required String title,
  required List<PickerOption<T>> options,
  T? selected,
}) {
  return showModalBottomSheet<PickerOption<T>>(
    context: context,
    isScrollControlled: true,
    backgroundColor: RiveroColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (ctx) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(ctx).height * 0.7,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                RiveroSpacing.xl,
                RiveroSpacing.xl,
                RiveroSpacing.xl,
                RiveroSpacing.sm,
              ),
              child: Text(title, style: RiveroTypography.titleLarge),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(
                  RiveroSpacing.sm,
                  0,
                  RiveroSpacing.sm,
                  RiveroSpacing.lg,
                ),
                children: [
                  for (final o in options)
                    ListTile(
                      key: ValueKey('pick-${o.label}'),
                      leading: o.leading,
                      title: Text(
                        o.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: o.value == selected
                          ? Icon(
                              Icons.check_rounded,
                              color: RiveroColors.accent,
                            )
                          : null,
                      selected: o.value == selected,
                      selectedColor: RiveroColors.textPrimary,
                      selectedTileColor: RiveroColors.accent.withValues(
                        alpha: 0.12,
                      ),
                      onTap: () => Navigator.pop(ctx, o),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// A form field that looks like the app's other inputs and opens
/// [showPicker]. Long labels are cut cleanly instead of breaking layout.
class PickerField<T> extends StatelessWidget {
  const PickerField({
    required this.label,
    required this.options,
    required this.value,
    required this.onChanged,
    super.key,
  });

  final String label;
  final List<PickerOption<T>> options;
  final T? value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final current = options.where((o) => o.value == value).firstOrNull;
    return InkWell(
      borderRadius: RiveroRadii.borderLg,
      onTap: () async {
        final picked = await showPicker<T>(
          context,
          title: label,
          options: options,
          selected: value,
        );
        if (picked != null) onChanged(picked.value);
      },
      child: InputDecorator(
        decoration: InputDecoration(labelText: label),
        child: Row(
          children: [
            if (current?.leading != null) ...[
              current!.leading!,
              const SizedBox(width: RiveroSpacing.sm),
            ],
            Expanded(
              child: Text(
                current?.label ?? 'Choose',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: RiveroTypography.bodyLarge,
              ),
            ),
            Icon(Icons.expand_more_rounded, color: RiveroColors.textSecondary),
          ],
        ),
      ),
    );
  }
}
