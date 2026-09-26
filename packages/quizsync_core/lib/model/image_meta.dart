/// 图片元数据（文件本体单独存放，`data-model.md` images 表）。
class ImageMeta {
  /// sha256(压缩后字节)。
  final String hash;
  final int size;
  final String mime;
  final int? width;
  final int? height;

  /// 本机文件路径；该端没有文件时为 null（可后台补传）。
  final String? localPath;
  final int createdAt;
  final String uploadedBy;

  const ImageMeta({
    required this.hash,
    required this.size,
    required this.mime,
    this.width,
    this.height,
    this.localPath,
    required this.createdAt,
    required this.uploadedBy,
  });

  ImageMeta copyWith({String? localPath, int? width, int? height}) => ImageMeta(
        hash: hash,
        size: size,
        mime: mime,
        width: width ?? this.width,
        height: height ?? this.height,
        localPath: localPath ?? this.localPath,
        createdAt: createdAt,
        uploadedBy: uploadedBy,
      );

  Map<String, dynamic> toJson() => {
        'hash': hash,
        'size': size,
        'mime': mime,
        'width': width,
        'height': height,
        'local_path': localPath,
        'created_at': createdAt,
        'uploaded_by': uploadedBy,
      };

  factory ImageMeta.fromJson(Map<String, dynamic> json) => ImageMeta(
        hash: json['hash'].toString(),
        size: (json['size'] as num?)?.toInt() ?? 0,
        mime: json['mime']?.toString() ?? 'image/jpeg',
        width: (json['width'] as num?)?.toInt(),
        height: (json['height'] as num?)?.toInt(),
        localPath: json['local_path']?.toString(),
        createdAt: (json['created_at'] as num?)?.toInt() ?? 0,
        uploadedBy: json['uploaded_by']?.toString() ?? '',
      );

  @override
  String toString() => 'ImageMeta($hash ${size}B)';
}
