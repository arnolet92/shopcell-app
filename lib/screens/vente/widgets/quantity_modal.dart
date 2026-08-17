import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme.dart';
import '../../../models/produit_model.dart';
import '../../../widgets/gradient_button.dart';
import '../../../widgets/produit_image.dart';

/// Modal affiché au tap sur un article de la grille Vente : nom de
/// l'article, quantité (1 par défaut, réglable), puis "Ajouter au panier".
Future<int?> showQuantityModal(BuildContext context, {required ProduitModel produit, required String? imageUrl}) {
  return showModalBottomSheet<int>(
    context: context,
    backgroundColor: AppColors.bgCard,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    builder: (context) => _QuantityModalContent(produit: produit, imageUrl: imageUrl),
  );
}

class _QuantityModalContent extends StatefulWidget {
  const _QuantityModalContent({required this.produit, required this.imageUrl});
  final ProduitModel produit;
  final String? imageUrl;

  @override
  State<_QuantityModalContent> createState() => _QuantityModalContentState();
}

class _QuantityModalContentState extends State<_QuantityModalContent> {
  int _qte = 1;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(4)),
              ),
            ),
            const SizedBox(height: 18),
            ProduitImage(url: widget.imageUrl, size: 72, radius: 16),
            const SizedBox(height: 12),
            Text(
              widget.produit.designation,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 4),
            Text(
              '${widget.produit.prixUnitaire.toStringAsFixed(0)} Ar',
              style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.green),
            ),
            const SizedBox(height: 22),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _StepButton(icon: Icons.remove_rounded, onTap: () => setState(() => _qte = _qte > 1 ? _qte - 1 : 1)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text('$_qte', style: GoogleFonts.inter(fontSize: 24, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                ),
                _StepButton(icon: Icons.add_rounded, onTap: () => setState(() => _qte++)),
              ],
            ),
            const SizedBox(height: 26),
            GradientButton(
              label: 'Ajouter au panier',
              icon: Icons.add_shopping_cart_rounded,
              onPressed: () => Navigator.of(context).pop(_qte),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.bgElevated,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Icon(icon, size: 20, color: AppColors.accentLight),
        ),
      ),
    );
  }
}
