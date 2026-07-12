import 'package:flutter/material.dart';

import '../core/theme.dart';

/// Vignette photo d'un article, avec repli élégant sur une icône générique
/// si l'article n'a pas de photo ou que le chargement échoue.
class ProduitImage extends StatelessWidget {
  const ProduitImage({
    super.key,
    required this.url,
    this.size = 56,
    this.radius = 14,
    this.iconSize,
  });

  final String? url;
  final double size;
  final double radius;
  final double? iconSize;

  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: const Color(0xFF1A1D28),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: AppColors.borderAccent),
      ),
      child: Icon(Icons.smartphone_rounded, color: AppColors.green, size: iconSize ?? size * 0.46),
    );

    if (url == null) return fallback;

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Image.network(
        url!,
        width: size,
        height: size,
        fit: BoxFit.cover,
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return Container(
            width: size,
            height: size,
            color: const Color(0xFF1A1D28),
            child: const Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accentLight),
              ),
            ),
          );
        },
        errorBuilder: (context, error, stackTrace) => fallback,
      ),
    );
  }
}
