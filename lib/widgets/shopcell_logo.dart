import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/theme.dart';

/// Marque ShopCell réutilisée sur le splash, le login et le sidebar :
/// un badge dégradé avec une icône de téléphone, et un wordmark "Shop/Cell".
class ShopCellMark extends StatelessWidget {
  const ShopCellMark({super.key, this.size = 64, this.radius});

  final double size;
  final double? radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: AppColors.accentGradient,
        borderRadius: BorderRadius.circular(radius ?? size * 0.28),
        boxShadow: [
          BoxShadow(
            color: AppColors.accent.withValues(alpha: 0.45),
            blurRadius: size * 0.35,
            offset: Offset(0, size * 0.12),
          ),
        ],
      ),
      child: Icon(Icons.smartphone_rounded, color: Colors.white, size: size * 0.52),
    );
  }
}

class ShopCellWordmark extends StatelessWidget {
  const ShopCellWordmark({super.key, this.fontSize = 28, this.color});

  final double fontSize;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final baseColor = color ?? AppColors.textPrimary;
    return RichText(
      text: TextSpan(
        style: GoogleFonts.inter(
          fontSize: fontSize,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.5,
          color: baseColor,
        ),
        children: [
          const TextSpan(text: 'Shop'),
          TextSpan(text: 'Cell', style: TextStyle(color: AppColors.accentLight)),
        ],
      ),
    );
  }
}
