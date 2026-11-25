import 'package:flutter/material.dart';
import 'package:rivero/design_system/rivero_tokens.dart';

/// A name field that suggests people already in the log while you type, so
/// one person's entries (on different days) stay under one name.
class PersonField extends StatefulWidget {
  const PersonField({
    required this.controller,
    required this.people,
    this.decoration = const InputDecoration(),
    super.key,
  });

  final TextEditingController controller;

  /// Names to suggest (see `DuesService.knownPeople`).
  final List<String> people;
  final InputDecoration decoration;

  @override
  State<PersonField> createState() => _PersonFieldState();
}

class _PersonFieldState extends State<PersonField> {
  final _focus = FocusNode();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final people = widget.people;
    return RawAutocomplete<String>(
      textEditingController: controller,
      focusNode: _focus,
      optionsBuilder: (v) {
        final q = v.text.trim().toLowerCase();
        if (q.isEmpty) return const Iterable<String>.empty();
        return people.where(
          (p) => p.toLowerCase().contains(q) && p.toLowerCase() != q,
        );
      },
      fieldViewBuilder: (context, c, f, _) => TextField(
        controller: c,
        focusNode: f,
        textCapitalization: TextCapitalization.words,
        decoration: widget.decoration,
      ),
      optionsViewBuilder: (context, onSelected, options) => Align(
        alignment: Alignment.topLeft,
        child: Material(
          color: RiveroColors.surfaceElevated,
          elevation: 4,
          borderRadius: RiveroRadii.borderMd,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 180, maxWidth: 280),
            child: ListView(
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              children: [
                for (final o in options)
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.person_outline_rounded, size: 18),
                    title: Text(o),
                    onTap: () => onSelected(o),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
