import 'package:flutter/material.dart';
import 'package:rivero/design_system/rivero_tokens.dart';

/// The one "add" button of the app. Every page that adds something (an
/// account, a debt, an autopay, a category...) uses this, so the plus is
/// always the same size and colour in the same place: the bottom-right
/// corner. Use it as a Scaffold's `floatingActionButton`.
class RiveroFab extends StatelessWidget {
  const RiveroFab({required this.tooltip, required this.onPressed, super.key});

  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => FloatingActionButton(
    heroTag: null, // several pages each have one
    tooltip: tooltip,
    onPressed: onPressed,
    backgroundColor: RiveroColors.accent,
    foregroundColor: RiveroColors.onAccent,
    elevation: 3,
    shape: const CircleBorder(),
    child: const Icon(Icons.add_rounded, size: 30),
  );
}
