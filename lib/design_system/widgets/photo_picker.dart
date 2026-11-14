import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:rivero/design_system/rivero_tokens.dart';

/// Lets the user take a photo or pick one; returns a temporary file path.
Future<String?> pickPhoto(BuildContext context) async {
  final source = await showModalBottomSheet<ImageSource>(
    context: context,
    backgroundColor: RiveroColors.surface,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('Take a photo'),
            onTap: () => Navigator.pop(ctx, ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Choose from gallery'),
            onTap: () => Navigator.pop(ctx, ImageSource.gallery),
          ),
        ],
      ),
    ),
  );
  if (source == null) return null;
  final file = await ImagePicker().pickImage(
    source: source,
    maxWidth: 2000,
    imageQuality: 85,
  );
  return file?.path;
}

/// Full-screen, zoomable view of a stored photo.
Future<void> showPhoto(BuildContext context, String path) => showDialog<void>(
  context: context,
  builder: (ctx) => Dialog.fullscreen(
    backgroundColor: Colors.black,
    child: Stack(
      children: [
        Center(child: InteractiveViewer(child: Image.file(File(path)))),
        SafeArea(
          child: IconButton(
            onPressed: () => Navigator.pop(ctx),
            icon: const Icon(Icons.close_rounded, color: Colors.white),
          ),
        ),
      ],
    ),
  ),
);
