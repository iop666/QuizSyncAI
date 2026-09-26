import 'package:crypto/crypto.dart';

/// sha256 hex（图片 `image_hash` 对**压缩后**字节计算，data-model.md images 表）。
String sha256Hex(List<int> bytes) => sha256.convert(bytes).toString();
