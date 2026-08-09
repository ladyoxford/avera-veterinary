import 'dart:io';

import 'package:flutter/widgets.dart';

ImageProvider<Object>? localIdentityImage(String path) {
  final file = File(path);
  return file.existsSync() ? FileImage(file) : null;
}
