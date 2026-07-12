import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/theme.dart';
import '../../../models/produit_model.dart';
import '../../../services/printer_service.dart';
import '../../../services/ticket_builder.dart';
import '../../../widgets/gradient_button.dart';
import '../../../widgets/produit_image.dart';

String _fmtMoney(double v) {
  final s = v.round().toString();
  final buf = StringBuffer();
  for (int i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(' ');
    buf.write(s[i]);
  }
  return '${buf.toString()} Ar';
}

/// Fiche détaillée d'un article — même niveau de détail que la fiche
/// article côté web (prix, marge, attributs marque/couleur/batterie/carton/
/// défaut/lieu, fournisseur, description), utilisée à la fois depuis
/// "Gestion d'article" et depuis "Vente".
Future<void> showProduitDetailSheet(
  BuildContext context, {
  required ProduitModel produit,
  required String? baseUrl,
  String? imageUrlOverride,
  VoidCallback? onAddToCart,
  bool showPrintQr = false,
}) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: AppColors.bgCard,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    builder: (context) => _ProduitDetailContent(
      produit: produit,
      baseUrl: baseUrl,
      imageUrlOverride: imageUrlOverride,
      onAddToCart: onAddToCart,
      showPrintQr: showPrintQr,
    ),
  );
}

class _ProduitDetailContent extends StatelessWidget {
  const _ProduitDetailContent({
    required this.produit,
    required this.baseUrl,
    this.imageUrlOverride,
    this.onAddToCart,
    this.showPrintQr = false,
  });

  final ProduitModel produit;
  final String? baseUrl;
  final String? imageUrlOverride;
  final VoidCallback? onAddToCart;
  final bool showPrintQr;

  @override
  Widget build(BuildContext context) {
    final imageUrl = imageUrlOverride ?? (baseUrl != null ? produit.imageUrl(baseUrl!) : null);

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return SafeArea(
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(4)),
                ),
              ),
              const SizedBox(height: 18),
              Center(child: ProduitImage(url: imageUrl, size: 128, radius: 22, iconSize: 56)),
              const SizedBox(height: 16),
              Text(
                produit.designation,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(fontSize: 19, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
              ),
              const SizedBox(height: 4),
              if (produit.codeProduits != null || produit.numSerie != null)
                Center(
                  child: Text(
                    [if (produit.codeProduits != null) 'Code: ${produit.codeProduits}', if (produit.numSerie != null) 'S/N: ${produit.numSerie}']
                        .join('  ·  '),
                    style: GoogleFonts.inter(fontSize: 12, color: AppColors.textMuted),
                  ),
                ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: _PriceTile(label: 'Prix de vente', value: _fmtMoney(produit.prixUnitaire), color: AppColors.green),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _PriceTile(label: "Prix d'achat", value: _fmtMoney(produit.prixAchats), color: AppColors.blue),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _PriceTile(label: 'Prix de revient', value: _fmtMoney(produit.prixRevient), color: AppColors.yellow),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _PriceTile(
                      label: 'Stock disponible',
                      value: produit.totalStock.toStringAsFixed(0),
                      color: produit.totalStock > 0 ? AppColors.accentLight : AppColors.red,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              Text('Caractéristiques', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (produit.nomSousType != null) _AttrChip(icon: Icons.layers_rounded, label: produit.nomSousType!),
                  if (produit.nomModel != null) _AttrChip(icon: Icons.phone_android_rounded, label: produit.nomModel!),
                  if (produit.nomSysteme != null) _AttrChip(icon: Icons.settings_suggest_rounded, label: produit.nomSysteme!),
                  if (produit.nomMarque != null) _AttrChip(icon: Icons.memory_rounded, label: produit.nomMarque!),
                  if (produit.nomTypePiece != null) _AttrChip(icon: Icons.palette_rounded, label: produit.nomTypePiece!),
                  if (produit.nomSousCategoriePiece != null) _AttrChip(icon: Icons.battery_full_rounded, label: produit.nomSousCategoriePiece!),
                  if (produit.nomCarton != null) _AttrChip(icon: Icons.inventory_rounded, label: produit.nomCarton!),
                  if (produit.nomDefaut != null) _AttrChip(icon: Icons.report_gmailerrorred_rounded, label: produit.nomDefaut!),
                  if (produit.nomLieu != null) _AttrChip(icon: Icons.place_rounded, label: produit.nomLieu!),
                  if (produit.nomFrns != null) _AttrChip(icon: Icons.local_shipping_rounded, label: produit.nomFrns!),
                  if (produit.imei1 != null) _AttrChip(icon: Icons.fingerprint_rounded, label: 'IMEI1: ${produit.imei1}'),
                  if (produit.imei2 != null) _AttrChip(icon: Icons.fingerprint_rounded, label: 'IMEI2: ${produit.imei2}'),
                ],
              ),
              if (produit.description != null && produit.description!.trim().isNotEmpty) ...[
                const SizedBox(height: 22),
                Text('Description', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
                const SizedBox(height: 8),
                Text(produit.description!, style: GoogleFonts.inter(fontSize: 13.5, color: AppColors.textPrimary, height: 1.4)),
              ],
              if (showPrintQr) ...[
                const SizedBox(height: 22),
                Text('QR code article', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
                const SizedBox(height: 12),
                _PrintQrSection(produit: produit),
              ],
              if (onAddToCart != null) ...[
                const SizedBox(height: 26),
                GradientButton(
                  label: 'Ajouter au panier',
                  icon: Icons.add_shopping_cart_rounded,
                  onPressed: () {
                    onAddToCart!();
                    Navigator.of(context).pop();
                  },
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _PriceTile extends StatelessWidget {
  const _PriceTile({required this.label, required this.value, required this.color});
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: GoogleFonts.inter(fontSize: 10.5, color: AppColors.textMuted, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(value, style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w800, color: color)),
        ],
      ),
    );
  }
}

/// Aperçu à l'écran (QR = id_produits, comme "Vente par scan QR") + bouton
/// d'impression réelle sur l'imprimante ticket configurée
/// (`PrinterSettingsScreen`), en WiFi ou Bluetooth.
class _PrintQrSection extends StatefulWidget {
  const _PrintQrSection({required this.produit});
  final ProduitModel produit;

  @override
  State<_PrintQrSection> createState() => _PrintQrSectionState();
}

class _PrintQrSectionState extends State<_PrintQrSection> {
  bool _printing = false;

  Future<void> _print() async {
    setState(() => _printing = true);
    final bytes = await TicketBuilder.buildArticleQrLabel(widget.produit);
    final result = await PrinterService.instance.printBytes(bytes);
    if (!mounted) return;
    setState(() => _printing = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(result.success ? 'QR envoyé à l\'imprimante.' : (result.message ?? "Échec de l'impression."))),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
          child: QrImageView(data: widget.produit.idProduits, size: 140, backgroundColor: Colors.white),
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _printing ? null : _print,
            icon: _printing
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accentLight))
                : const Icon(Icons.print_rounded, size: 18, color: AppColors.accentLight),
            label: const Text('Imprimer le QR code', style: TextStyle(color: AppColors.accentLight)),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: AppColors.borderAccent),
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ),
      ],
    );
  }
}

class _AttrChip extends StatelessWidget {
  const _AttrChip({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.accentGlow,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: AppColors.accentLight),
          const SizedBox(width: 6),
          Text(label, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
        ],
      ),
    );
  }
}
