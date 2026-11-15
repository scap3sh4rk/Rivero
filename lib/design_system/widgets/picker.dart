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

/// A real dropdown: a rounded menu opening right under the field it
/// belongs to, as wide as the field, never taller than [maxHeight] (it
/// scrolls) and kept inside the screen edges. Returns null if dismissed.
Future<PickerOption<T>?> showDropdown<T>(
  BuildContext fieldContext, {
  required List<PickerOption<T>> options,
  T? selected,
  double maxHeight = 320,
}) async {
  final box = fieldContext.findRenderObject()! as RenderBox;
  final overlay =
      Navigator.of(fieldContext).overlay!.context.findRenderObject()!
          as RenderBox;
  final topLeft = box.localToGlobal(Offset.zero, ancestor: overlay);
  final field = topLeft & box.size;
  // Values are positions in [options], so an option whose value is null is
  // still told apart from "dismissed".
  final i = await showMenu<int>(
    context: fieldContext,
    position: RelativeRect.fromLTRB(
      field.left,
      field.bottom + 4,
      overlay.size.width - field.right,
      overlay.size.height - field.bottom,
    ),
    constraints: BoxConstraints(
      minWidth: field.width,
      maxWidth: field.width,
      maxHeight: maxHeight,
    ),
    color: RiveroColors.surfaceElevated,
    shape: RoundedRectangleBorder(
      borderRadius: RiveroRadii.borderLg,
      side: BorderSide(color: RiveroColors.borderMedium),
    ),
    clipBehavior: Clip.antiAlias,
    items: [
      for (var k = 0; k < options.length; k++)
        PopupMenuItem<int>(
          key: ValueKey('pick-${options[k].label}'),
          value: k,
          child: Row(
            children: [
              if (options[k].leading != null) ...[
                options[k].leading!,
                const SizedBox(width: RiveroSpacing.sm),
              ],
              Expanded(
                child: Text(
                  options[k].label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: RiveroTypography.bodyLarge.copyWith(
                    color: options[k].value == selected
                        ? RiveroColors.accent
                        : null,
                  ),
                ),
              ),
              if (options[k].value == selected)
                Icon(Icons.check_rounded, color: RiveroColors.accent, size: 18),
            ],
          ),
        ),
    ],
  );
  return i == null ? null : options[i];
}

/// A form field that looks like the app's other inputs and opens a
/// dropdown under itself ([showDropdown]). Long labels are cut cleanly
/// instead of breaking layout.
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
    return Builder(
      builder: (fieldContext) => InkWell(
        borderRadius: RiveroRadii.borderLg,
        onTap: () async {
          final picked = await showDropdown<T>(
            fieldContext,
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
              Icon(
                Icons.expand_more_rounded,
                color: RiveroColors.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
