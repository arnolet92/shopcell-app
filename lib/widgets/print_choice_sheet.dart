import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/theme.dart';

/// Choix du format d'impression (ticket thermique / A4 / partage PDF) — ne
/// montre que les moyens réellement configurés (voir `PrinterSettingsScreen`).
/// Partagé entre l'écran de paiement (`PaymentScreen`) et le détail d'une
/// facture déjà payée (`FactureDetailScreen`) : "même système que la vente".
class PrintChoiceSheet extends StatelessWidget {
  const PrintChoiceSheet({super.key, required this.hasTicket, required this.hasA4});

  /// Une imprimante ticket est enregistrée dans les paramètres. L'option
  /// "Ticket thermique" reste proposée même si `hasTicket` est faux (au tap,
  /// un message renvoie vers Paramètres > Imprimante) — demandé pour que le
  /// choix ticket soit toujours visible.
  final bool hasTicket;
  final bool hasA4;

  @override
  Widget build(BuildContext context) {
    // Hauteur généreuse (jusqu'à 80% de l'écran) + défilement interne : sur
    // un petit téléphone, avec isScrollControlled ce sheet se dimensionne
    // sinon strictement à son contenu et pouvait pousser "Ne pas imprimer"
    // hors champ sans le moindre indice qu'il fallait défiler.
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(4)),
                ),
              ),
              const SizedBox(height: 18),
              Text('Imprimer ?', style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
              const SizedBox(height: 18),
              _PrintChoiceTile(
                icon: Icons.receipt_long_rounded,
                label: hasTicket ? 'Ticket thermique' : 'Ticket thermique (imprimante non configurée)',
                onTap: () => Navigator.of(context).pop('ticket'),
              ),
              if (hasA4) ...[
                const SizedBox(height: 12),
                _PrintChoiceTile(
                  icon: Icons.description_rounded,
                  label: 'Format A4 (feuille)',
                  onTap: () => Navigator.of(context).pop('a4'),
                ),
                const SizedBox(height: 12),
                _PrintChoiceTile(
                  icon: Icons.share_rounded,
                  label: 'Partager le PDF (autre application)',
                  onTap: () => Navigator.of(context).pop('a4_share'),
                ),
              ],
              const SizedBox(height: 14),
              TextButton(
                onPressed: () => Navigator.of(context).pop('none'),
                child: const Text('Ne pas imprimer', style: TextStyle(color: AppColors.textSecondary)),
              ),
            ],
          ),
        ),
      ),
    );
  }
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
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 17),
          child: Row(
            children: [
              Icon(icon, size: 20, color: AppColors.accentLight),
              const SizedBox(width: 12),
              Expanded(child: Text(label, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary))),
              const Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}
