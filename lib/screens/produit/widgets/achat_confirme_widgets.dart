import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme.dart';

const String kBulkSansBulk = '__sans_bulk__';
const String kBulkTous = '__tous__';

String _fmtNombre(double v) {
  final s = v.round().toString();
  final buf = StringBuffer();
  for (int i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(' ');
    buf.write(s[i]);
  }
  return buf.toString();
}

/// Titre affiché en haut de la page "Achat confirmé" selon le menu choisi
/// dans le tiroir de gauche : "Sans bulk", "Afficher tout" ou le nom du bulk.
String titreBulkFiltre(String filtre) {
  if (filtre == kBulkSansBulk) return 'Sans bulk';
  if (filtre == kBulkTous) return 'Afficher tout';
  return filtre;
}

/// En-tête de la page "Achat confirmé" : bouton qui ouvre le tiroir des bulks
/// (fermé par défaut) + titre du menu choisi et nombre d'articles affichés.
class AchatConfirmeHeader extends StatelessWidget {
  const AchatConfirmeHeader({super.key, required this.titre, required this.sousTitre, required this.onMenu});

  final String titre;
  final String sousTitre;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      child: Row(
        children: [
          Material(
            color: AppColors.accentGlow,
            borderRadius: BorderRadius.circular(13),
            child: InkWell(
              borderRadius: BorderRadius.circular(13),
              onTap: onMenu,
              child: Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(color: AppColors.borderAccent),
                ),
                child: const Icon(Icons.folder_open_rounded, size: 22, color: AppColors.accentLight),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titre,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(fontSize: 21, fontWeight: FontWeight.w800, color: AppColors.textPrimary, letterSpacing: -0.3),
                ),
                const SizedBox(height: 2),
                Text(sousTitre, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.textMuted)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Tiroir de gauche de la page "Achat confirmé" : "Sans bulk", "Afficher
/// tout", puis un menu par bulk existant (avec renommage pour patron/gérant).
/// Remplace la barre de chips horizontale — fermé par défaut, s'ouvre avec
/// l'icône dossier de [AchatConfirmeHeader].
class AchatBulkDrawer extends StatelessWidget {
  const AchatBulkDrawer({
    super.key,
    required this.filtreActif,
    required this.totalCount,
    required this.sansBulkCount,
    required this.bulkCounts,
    required this.bulkNames,
    required this.onChanged,
    this.canRename = false,
    this.onRename,
  });

  final String filtreActif;
  final int totalCount;
  final int sansBulkCount;
  final Map<String, int> bulkCounts;
  final List<String> bulkNames;
  final ValueChanged<String> onChanged;
  final bool canRename;
  final ValueChanged<String>? onRename;

  @override
  Widget build(BuildContext context) {
    void choisir(String key) {
      Navigator.of(context).pop();
      onChanged(key);
    }

    return Drawer(
      backgroundColor: AppColors.bgCard,
      width: 300,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 14),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(color: AppColors.accentGlow, borderRadius: BorderRadius.circular(12)),
                    child: const Icon(Icons.check_circle_rounded, size: 20, color: AppColors.accentLight),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Achat confirmé', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                        Text('Classeurs (bulks)', style: GoogleFonts.inter(fontSize: 11.5, color: AppColors.textMuted)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: AppColors.border),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 14, 12, 20),
                children: [
                  _DrawerItem(
                    icon: Icons.help_outline_rounded,
                    label: 'Les articles sans bulk',
                    count: sansBulkCount,
                    selected: filtreActif == kBulkSansBulk,
                    onTap: () => choisir(kBulkSansBulk),
                  ),
                  _DrawerItem(
                    icon: Icons.layers_rounded,
                    label: 'Afficher tout',
                    count: totalCount,
                    selected: filtreActif == kBulkTous,
                    onTap: () => choisir(kBulkTous),
                  ),
                  if (bulkNames.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(10, 18, 10, 8),
                      child: Text(
                        'BULKS',
                        style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: AppColors.textMuted),
                      ),
                    ),
                    for (final name in bulkNames)
                      _DrawerItem(
                        icon: Icons.folder_rounded,
                        label: name,
                        count: bulkCounts[name] ?? 0,
                        selected: filtreActif == name,
                        onTap: () => choisir(name),
                        onRename: canRename
                            ? () {
                                Navigator.of(context).pop();
                                onRename?.call(name);
                              }
                            : null,
                      ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DrawerItem extends StatelessWidget {
  const _DrawerItem({
    required this.icon,
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
    this.onRename,
  });

  final IconData icon;
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onRename;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(13),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              gradient: selected ? const LinearGradient(colors: [AppColors.accent, AppColors.green]) : null,
              color: selected ? null : AppColors.bgElevated,
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: selected ? Colors.transparent : AppColors.border),
              boxShadow: selected ? [BoxShadow(color: AppColors.accent.withValues(alpha: 0.3), blurRadius: 12, offset: const Offset(0, 4))] : null,
            ),
            child: Row(
              children: [
                Icon(icon, size: 17, color: selected ? Colors.white : AppColors.textSecondary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w700, color: selected ? Colors.white : AppColors.textPrimary),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: selected ? Colors.white.withValues(alpha: 0.25) : Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Text(
                    '$count',
                    style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w800, color: selected ? Colors.white : AppColors.textSecondary),
                  ),
                ),
                if (onRename != null) ...[
                  const SizedBox(width: 4),
                  InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: onRename,
                    child: Padding(
                      padding: const EdgeInsets.all(5),
                      child: Icon(Icons.edit_rounded, size: 15, color: selected ? Colors.white.withValues(alpha: 0.9) : AppColors.textSecondary),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Pied de page de "Achat confirmé" : articles / valeur stock / valeur
/// d'achat du menu affiché (auparavant en en-tête de page). Comptes sans
/// accès complet : seulement le nombre d'articles (les valeurs dérivent des
/// prix d'achat/vente).
class AchatFooterBar extends StatelessWidget {
  const AchatFooterBar({
    super.key,
    required this.nbArticles,
    required this.valeurStock,
    required this.valeurAchat,
    this.restrictedInfo = false,
  });

  final int nbArticles;
  final double valeurStock;
  final double valeurAchat;
  final bool restrictedInfo;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.bgCard,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
          child: Row(
            children: [
              _FooterStat(icon: Icons.inventory_2_rounded, color: AppColors.accentLight, label: 'ARTICLES', value: '$nbArticles'),
              if (!restrictedInfo) ...[
                const _FooterDivider(),
                _FooterStat(icon: Icons.stacked_line_chart_rounded, color: AppColors.green, label: 'VALEUR STOCK', value: '${_fmtNombre(valeurStock)} Ar'),
                const _FooterDivider(),
                _FooterStat(icon: Icons.shopping_bag_rounded, color: AppColors.blue, label: "VALEUR D'ACHAT", value: '${_fmtNombre(valeurAchat)} Ar'),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _FooterDivider extends StatelessWidget {
  const _FooterDivider();

  @override
  Widget build(BuildContext context) => Container(width: 1, height: 30, color: AppColors.border);
}

class _FooterStat extends StatelessWidget {
  const _FooterStat({required this.icon, required this.color, required this.label, required this.value});

  final IconData icon;
  final Color color;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 11, color: color),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(fontSize: 9, letterSpacing: 0.4, fontWeight: FontWeight.w700, color: AppColors.textMuted),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 3),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(value, style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
            ),
          ],
        ),
      ),
    );
  }
}
