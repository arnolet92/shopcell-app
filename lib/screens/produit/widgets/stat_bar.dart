import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme.dart';

/// Bandeau de statistiques globales, équivalent de `.global-stats-bar`
/// dans tabproduit2.php (nombre d'articles, valeur du stock, valeur d'achat).
class StatBar extends StatelessWidget {
  const StatBar({
    super.key,
    required this.nbArticles,
    required this.valeurStock,
    required this.valeurAchat,
  });

  final int nbArticles;
  final double valeurStock;
  final double valeurAchat;

  String _fmt(double v) {
    final s = v.round().toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(' ');
      buf.write(s[i]);
    }
    return buf.toString();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          _StatChip(icon: Icons.inventory_2_rounded, color: AppColors.accentLight, label: 'ARTICLES', value: '$nbArticles'),
          const SizedBox(width: 10),
          _StatChip(icon: Icons.stacked_line_chart_rounded, color: AppColors.green, label: 'VALEUR STOCK', value: '${_fmt(valeurStock)} Ar'),
          const SizedBox(width: 10),
          _StatChip(icon: Icons.shopping_bag_rounded, color: AppColors.blue, label: "VALEUR D'ACHAT", value: '${_fmt(valeurAchat)} Ar'),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({required this.icon, required this.color, required this.label, required this.value});

  final IconData icon;
  final Color color;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 168,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.bgCard, AppColors.bgElevated],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(9)),
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: GoogleFonts.inter(fontSize: 9.5, letterSpacing: 0.4, fontWeight: FontWeight.w600, color: AppColors.textMuted)),
                Text(value, style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w700, color: AppColors.textPrimary), overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
