import 'package:flutter/material.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';

import 'identity_avatar_image.dart';

enum AveraPhotoAction { takePhoto, uploadPhoto, viewPhoto, removePhoto }

Future<AveraPhotoAction?> showAveraPhotoActionSheet({
  required BuildContext context,
  required String subjectName,
  required bool hasPhoto,
  bool canChangePhoto = true,
  bool canRemovePhoto = false,
}) => showModalBottomSheet<AveraPhotoAction>(
  context: context,
  useSafeArea: true,
  showDragHandle: true,
  builder: (sheetContext) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: Text(
            '$subjectName photo',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(sheetContext).textTheme.titleLarge,
          ),
        ),
        if (canChangePhoto) ...[
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('Take photo'),
            onTap: () =>
                Navigator.pop(sheetContext, AveraPhotoAction.takePhoto),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Upload photo'),
            onTap: () =>
                Navigator.pop(sheetContext, AveraPhotoAction.uploadPhoto),
          ),
        ],
        ListTile(
          enabled: hasPhoto,
          leading: const Icon(Icons.visibility_outlined),
          title: const Text('View photo'),
          subtitle: hasPhoto ? null : const Text('No photo added yet'),
          onTap: hasPhoto
              ? () => Navigator.pop(sheetContext, AveraPhotoAction.viewPhoto)
              : null,
        ),
        if (canRemovePhoto && hasPhoto)
          ListTile(
            leading: Icon(
              Icons.delete_outline_rounded,
              color: Theme.of(sheetContext).colorScheme.error,
            ),
            title: Text(
              'Remove photo',
              style: TextStyle(color: Theme.of(sheetContext).colorScheme.error),
            ),
            onTap: () =>
                Navigator.pop(sheetContext, AveraPhotoAction.removePhoto),
          ),
      ],
    ),
  ),
);

Future<XFile?> pickAndCropAveraPhoto(AveraPhotoAction action) async {
  final source = switch (action) {
    AveraPhotoAction.takePhoto => ImageSource.camera,
    AveraPhotoAction.uploadPhoto => ImageSource.gallery,
    _ => null,
  };
  if (source == null) return null;
  final selected = await ImagePicker().pickImage(
    source: source,
    maxWidth: 1024,
    maxHeight: 1024,
    imageQuality: 88,
  );
  if (selected == null) return null;
  final cropped = await ImageCropper().cropImage(
    sourcePath: selected.path,
    compressFormat: ImageCompressFormat.jpg,
    compressQuality: 84,
    maxWidth: 512,
    maxHeight: 512,
    aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
  );
  return cropped == null ? null : XFile(cropped.path);
}

Future<void> showAveraPhotoViewer({
  required BuildContext context,
  required String subjectName,
  required String photoReference,
}) async {
  final image = photoReference.startsWith('http')
      ? NetworkImage(photoReference) as ImageProvider<Object>
      : localIdentityImage(photoReference);
  if (image == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('This photo is not available right now.')),
    );
    return;
  }
  await Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (viewerContext) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          foregroundColor: Colors.white,
          backgroundColor: Colors.black,
          title: Text('$subjectName photo'),
        ),
        body: Center(
          child: InteractiveViewer(
            minScale: .8,
            maxScale: 4,
            child: Image(
              image: image,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'This photo is not available right now.',
                  style: TextStyle(color: Colors.white),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
