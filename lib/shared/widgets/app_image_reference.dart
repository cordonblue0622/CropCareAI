import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/utils/image_reference.dart';

class AppImageReference extends StatelessWidget {
  final String imageRef;
  final BoxFit fit;
  final double? width;
  final double? height;
  final Widget? placeholder;
  final Widget? errorWidget;

  const AppImageReference({
    super.key,
    required this.imageRef,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.placeholder,
    this.errorWidget,
  });

  @override
  Widget build(BuildContext context) {
    final fallback = errorWidget ?? placeholder ?? const SizedBox.shrink();
    final inlineBytes = decodeInlineImageDataUrl(imageRef);
    if (inlineBytes != null) {
      return Image.memory(
        inlineBytes,
        width: width,
        height: height,
        fit: fit,
        errorBuilder: (_, __, ___) => fallback,
      );
    }

    if (isRemoteImageReference(imageRef)) {
      return CachedNetworkImage(
        imageUrl: imageRef,
        width: width,
        height: height,
        fit: fit,
        placeholder: (_, __) => placeholder ?? fallback,
        errorWidget: (_, __, ___) => fallback,
      );
    }

    return fallback;
  }
}
