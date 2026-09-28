import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/color_extractor.dart';

/// Provider to extract colors from album art
final coverColorProvider = FutureProvider.family<PaletteColors, String?>((ref, imageUrl) async {
  if (imageUrl == null || imageUrl.isEmpty) {
    return const PaletteColors();
  }
  return ColorExtractor.extractPalette(imageUrl);
});
