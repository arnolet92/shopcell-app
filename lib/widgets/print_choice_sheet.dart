import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/theme.dart';

/// Choix du format d'impression (ticket thermique / A4 / partage PDF) — ne
/// montre que les moyens réellement configurés (voir `PrinterSettingsScreen`).
/// Partagé entre l'écran de paiement (`PaymentScreen`) et le détail d'une
/// facture déjà payée (`FactureDetailScreen`) : "même système que la vente".
///
/// Présenté via `DraggableScrollableSheet` (voir showPrintChoiceSheet
/// ci-dessous) plutôt qu'un simple Column dimensionné à son contenu : sur un
/// petit téléphone, ce dernier pouvait pousser "Ne pas imprimer" hors champ.
/// Ici la feuille occupe délibérément une bonne partie de l'écran dès
/// l'ouverture, et reste redimensionnable/défilante en secours.
class PrintChoiceSheet extends StatelessWidget {
  const PrintChoiceSheet({super.key, required this.hasTicket, required this.hasA4, this.scrollController});

  /// Une imprimante ticket est enregistrée dans les paramètres. L'option
  /// "Ticket thermique" reste proposée même si `hasTicket` est faux (au tap,
  /// un message renvoie vers Paramètres > Imprimante) — demandé pour que le
  /// choix ticket soit toujours visible.
  final bool hasTicket;
  final bool hasA4;
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        controller: scrollController,
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(4)),
              ),
            ),
            const SizedBox(height: 20),
            Text('Imprimer ?', style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
            const SizedBox(height: 20),
            _PrintChoiceTile(
              icon: Icons.receipt_long_rounded,
              label: hasTicket ? 'Ticket thermique' : 'Ticket thermique (imprimante non configurée)',
              onTap: () => Navigator.of(context).pop('ticket'),
            ),
            if (hasA4) ...[
              const SizedBox(height: 14),
              _PrintChoiceTile(
                icon: Icons.description_rounded,
                label: 'Format A4 (feuille)',
                onTap: () => Navigator.of(context).pop('a4'),
              ),
              const SizedBox(height: 14),
              _PrintChoiceTile(
                icon: Icons.share_rounded,
                label: 'Partager le PDF (autre application)',
                onTap: () => Navigator.of(context).pop('a4_share'),
              ),
            ],
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => Navigator.of(context).pop('none'),
                style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                child: const Text('Ne pas imprimer', style: TextStyle(color: AppColors.textSecondary)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Affiche [PrintChoiceSheet] dans un `DraggableScrollableSheet` deux fois
/// plus haut qu'avant par défaut (55% de l'écran, extensible jusqu'à 90%,
/// réductible jusqu'à 35%) : une hauteur délibérément généreuse, pas
/// seulement calée sur le contenu, pour que rien ne soit hors champ même sur
/// un petit téléphone.
Future<String?> showPrintChoiceSheet(BuildContext context, {required bool hasTicket, required bool hasA4}) {
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: AppColors.bgCard,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    builder: (_) => DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.35,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) => PrintChoiceSheet(hasTicket: hasTicket, hasA4: hasA4, scrollController: scrollController),
    ),
  );
}

class _PrintChoiceTile extends StatelessWidget {
  const _PrintChoiceTile({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.bgElevated,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
          child: Row(
            children: [
              Icon(icon, size: 21, color: AppColors.accentLight),
              const SizedBox(width: 14),
              Expanded(child: Text(label, style: GoogleFonts.inter(fontSize: 14.5, fontWeight: FontWeight.w600, color: AppColors.textPrimary))),
              const Icon(Icons.chevron_right_rounded, size: 19, color: AppColors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}
