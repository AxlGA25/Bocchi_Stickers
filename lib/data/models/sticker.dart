class Sticker {
  final String id;
  final String sourcePath;
  final String? webpPath;
  final List<String> emojis;
  final String? originalPhotoPath;
  final bool isAnimated;

  const Sticker({
    required this.id,
    required this.sourcePath,
    this.webpPath,
    required this.emojis,
    this.originalPhotoPath,
    this.isAnimated = false,
  });

  Sticker copyWith({
    String? id,
    String? sourcePath,
    String? webpPath,
    List<String>? emojis,
    String? originalPhotoPath,
    bool? isAnimated,
  }) {
    return Sticker(
      id: id ?? this.id,
      sourcePath: sourcePath ?? this.sourcePath,
      webpPath: webpPath ?? this.webpPath,
      emojis: emojis ?? List<String>.from(this.emojis),
      originalPhotoPath: originalPhotoPath ?? this.originalPhotoPath,
      isAnimated: isAnimated ?? this.isAnimated,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'sourcePath': sourcePath,
      'webpPath': webpPath,
      'emojis': emojis,
      'originalPhotoPath': originalPhotoPath,
      'isAnimated': isAnimated,
    };
  }

  factory Sticker.fromJson(Map<String, dynamic> json) {
    return Sticker(
      id: json['id'] as String,
      sourcePath: json['sourcePath'] as String,
      webpPath: json['webpPath'] as String?,
      emojis: (json['emojis'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const ['😀'],
      originalPhotoPath: json['originalPhotoPath'] as String?,
      isAnimated: json['isAnimated'] as bool? ?? false,
    );
  }
}
