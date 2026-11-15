import '../../core/constants.dart';
import 'sticker.dart';

class StickerPack {
  final String id;
  final String name;
  final String publisher;
  final String? trayImagePath;
  final int imageDataVersion;
  final bool isAnimatedPack;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<Sticker> stickers;

  const StickerPack({
    required this.id,
    required this.name,
    required this.publisher,
    this.trayImagePath,
    this.imageDataVersion = 1,
    this.isAnimatedPack = false,
    required this.createdAt,
    required this.updatedAt,
    this.stickers = const [],
  });

  String get whatsappIdentifier => '${id}_v$imageDataVersion';

  bool get isReady =>
      stickers.length >= AppConstants.minStickersPerPack &&
      stickers.length <= AppConstants.maxStickersPerPack;

  StickerPack copyWith({
    String? id,
    String? name,
    String? publisher,
    String? trayImagePath,
    int? imageDataVersion,
    bool? isAnimatedPack,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<Sticker>? stickers,
  }) {
    return StickerPack(
      id: id ?? this.id,
      name: name ?? this.name,
      publisher: publisher ?? this.publisher,
      trayImagePath: trayImagePath ?? this.trayImagePath,
      imageDataVersion: imageDataVersion ?? this.imageDataVersion,
      isAnimatedPack: isAnimatedPack ?? this.isAnimatedPack,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      stickers: stickers ?? List<Sticker>.from(this.stickers),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'publisher': publisher,
      'trayImagePath': trayImagePath,
      'imageDataVersion': imageDataVersion,
      'isAnimatedPack': isAnimatedPack,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'stickers': stickers.map((s) => s.toJson()).toList(),
    };
  }

  factory StickerPack.fromJson(Map<String, dynamic> json) {
    return StickerPack(
      id: json['id'] as String,
      name: json['name'] as String,
      publisher: json['publisher'] as String,
      trayImagePath: json['trayImagePath'] as String?,
      imageDataVersion: (json['imageDataVersion'] as num?)?.toInt() ?? 1,
      isAnimatedPack: json['isAnimatedPack'] as bool? ?? false,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.now(),
      stickers: (json['stickers'] as List<dynamic>?)
              ?.map((s) => Sticker.fromJson(s as Map<String, dynamic>))
              .toList() ??
          const [],
    );
  }
}
