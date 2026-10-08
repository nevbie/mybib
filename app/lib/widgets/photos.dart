import 'dart:convert';
import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';

final _picker = ImagePicker();

/// Take or pick a photo, downscaled to [maxEdge] px as JPEG. Null when cancelled.
Future<Uint8List?> pickPhoto({required bool camera, required double maxEdge, int quality = 85}) async {
  final f = await _picker.pickImage(source: camera ? ImageSource.camera : ImageSource.gallery, maxWidth: maxEdge, maxHeight: maxEdge, imageQuality: quality);
  return f?.readAsBytes();
}

/// Several gallery photos at once (shelf recognition).
Future<List<Uint8List>> pickPhotos({required double maxEdge, int quality = 88}) async {
  final fs = await _picker.pickMultiImage(maxWidth: maxEdge, maxHeight: maxEdge, imageQuality: quality);
  return [for (final f in fs) await f.readAsBytes()];
}

/// Small cover thumbnail kept with the item (≈ 20–40 KB), as data URL like the web app.
Future<String?> pickCoverPhoto({required bool camera}) async {
  final b = await pickPhoto(camera: camera, maxEdge: 480, quality: 80);
  return b == null ? null : 'data:image/jpeg;base64,${base64Encode(b)}';
}
