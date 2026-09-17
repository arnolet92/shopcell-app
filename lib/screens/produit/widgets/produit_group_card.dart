import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme.dart';
import '../../../models/produit_model.dart';
import '../../../widgets/produit_image.dart';
import 'produit_detail_sheet.dart';

/// Beaucoup d'unités d'un même modèle n'ont pas leur propre photo ; on
/// réutilise celle de la première unité du groupe qui en a une, comme le
/// fait `tabproduit2.php` côté web (`$images_par_designation`). Le groupe
/// visible peut lui-même ne contenir aucune unité avec photo (stock filtré),
/// d'où le repli sur la carte globale non filtrée `imagesParDesignation`
/// (voir `ProduitService.loadImagesParDesignation`).
String? _groupImageUrl(ProduitGroup group, String baseUrl, Map<String, String> imagesParDesignation) {
  for (final p in group.items) {
    final url = p.imageUrl(baseUrl);
    if (url != null) return url;
  }
  final key = group.designation.toLowerCase().trim().replaceAll(RegExp(r'\s+'), ' ');
  return imagesParDesignation[key];
}

/// Carte de regroupement par désignation, équivalent de `.designation-header`
/// + ventilation "capacité"/"lieu" dans tabproduit2.php.
class ProduitGroupCard extends StatefulWidget {
  const ProduitGroupCard({
    super.key,
    required this.group,
    required this.baseUrl,
    this.imagesParDesignation = const {},
    this.showValiderAction = false,
    this.restrictedInfo = false,
    this.isAchatConfirmeVue = false,
    this.isAchatAttenteVue = false,
    this.showMettreEnAchatAction = false,
    this.isPatron = false,
    this.onEdit,
    this.onValider,
    this.onMiseEnReparation,
    this.onTerminerReparation,
    this.onAddToCart,
    this.onTapUnit,
    this.onRemettreEnStock,
    this.onEntrerEnStockAchat,
    this.onConfirmerAchat,
    this.onMettreEnAchat,
    this.selectionMode = false,
    this.selectedIds = const {},
    this.onCheckChanged,
    this.startExpanded = false,
  });

  final ProduitGroup group;
  final String? baseUrl;
  final Map<String, String> imagesParDesignation;
  final bool showValiderAction;
  /// Comptes hors patron/gérant/magasinier : n'affiche que prix de vente,
  /// modèle, n° de série, IMEI et batterie (masque achat/revient, capacité,
  /// couleur, carton, défaut, stockage, fournisseur, description).
  final bool restrictedInfo;
  /// Onglet "Achat confirmé" (Produit::lst_achat_confirme) : affiche le
  /// bouton "Entrer en stock" au lieu de "Mise en réparation".
  final bool isAchatConfirmeVue;
  /// Onglet "Achat en attente" (Produit::lst_achat_attente) : affiche le
  /// bouton "Confirmer l'achat" (patron uniquement) au lieu de "Mise en
  /// réparation".
  final bool isAchatAttenteVue;
  /// Onglet "En attente" (Produit::lst_attente), patron uniquement : affiche
  /// en plus le bouton "Mettre en achat".
  final bool showMettreEnAchatAction;
  final bool isPatron;
  final void Function(ProduitModel produit, String? imageUrl)? onEdit;
  final void Function(ProduitModel produit)? onValider;
  final void Function(ProduitModel produit)? onMiseEnReparation;
  final void Function(ProduitModel produit)? onTerminerReparation;
  /// Onglet "Après échange" : remet l'article dans le circuit normal
  /// (produit_apres_echange = 0).
  final void Function(ProduitModel produit)? onRemettreEnStock;
  /// Ajout rapide au ticket (panier de vente) depuis "Gestion d'article" —
  /// même principe que le bouton "ajoutez au ticket" de `tabproduit2.php`
  /// côté web (quantité 1, ajout immédiat).
  final void Function(ProduitModel produit)? onAddToCart;
  /// Si renseigné, remplace le comportement par défaut (fiche détaillée) au
  /// tap sur une unité — utilisé par la recherche intelligente pour ouvrir
  /// l'historique de l'article au lieu de la fiche produit.
  final void Function(ProduitModel produit, String? imageUrl)? onTapUnit;
  final void Function(ProduitModel produit)? onEntrerEnStockAchat;
  final void Function(ProduitModel produit)? onConfirmerAchat;
  final void Function(ProduitModel produit)? onMettreEnAchat;
  /// Sélection multiple (onglet "Achat confirmé") : affiche une case à
  /// cocher sur chaque unité "en achat confirmé", sur toutes les vues
  /// (tous/sans bulk/un classeur nommé), pour pouvoir réorganiser un article
  /// déjà rangé vers un autre bulk.
  final bool selectionMode;
  final Set<String> selectedIds;
  final void Function(String idProduits, bool checked)? onCheckChanged;
  /// Groupe déjà déplié à l'ouverture (onglet "Achat confirmé" : le détail
  /// doit être visible par défaut pour que les cases à cocher soient
  /// immédiatement accessibles, sans devoir déplier chaque groupe).
  final bool startExpanded;

  @override
  State<ProduitGroupCard> createState() => _ProduitGroupCardState();
}

class _ProduitGroupCardState extends State<ProduitGroupCard> {
  late bool _expanded = widget.startExpanded;

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
    final group = widget.group;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF10131C), AppColors.bgElevated],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderAccent),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: 3,
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [AppColors.accent, AppColors.green],
                ),
              ),
            ),
          ),
          InkWell(
            onTap: () {
              if (widget.onTapUnit != null && group.items.length == 1) {
                final imageUrl = widget.baseUrl != null ? _groupImageUrl(group, widget.baseUrl!, widget.imagesParDesignation) : null;
                widget.onTapUnit!(group.items.first, imageUrl);
                return;
              }
              setState(() => _expanded = !_expanded);
            },
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ProduitImage(
                        url: widget.baseUrl != null ? _groupImageUrl(group, widget.baseUrl!, widget.imagesParDesignation) : null,
                        size: 56,
                        radius: 12,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              group.designation,
                              style: GoogleFonts.inter(
                                fontSize: 15.5,
                                fontWeight: FontWeight.w800,
                                color: AppColors.textPrimary,
                                letterSpacing: -0.2,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              children: [
                                _Badge(
                                  label: '${group.totalStock.toStringAsFixed(0)} en stock',
                                  color: group.totalStock > 0 ? AppColors.green : AppColors.red,
                                ),
                                _Badge(
                                  label: '${group.items.length} unité(s)',
                                  color: AppColors.blue,
                                ),
                                if (!widget.restrictedInfo)
                                  _Badge(
                                    label: '${_fmt(group.totalAchat)} Ar',
                                    color: AppColors.yellow,
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        _expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                        color: AppColors.textMuted,
                      ),
                    ],
                  ),
                  if (!widget.restrictedInfo && (group.stockByCapacity.isNotEmpty || group.stockByLocation.isNotEmpty)) ...[
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        ...group.stockByCapacity.entries.map(
                          (e) => _DimChip(icon: Icons.memory_rounded, label: '${e.key} · ${e.value.toStringAsFixed(0)}'),
                        ),
                        ...group.stockByLocation.entries.map(
                          (e) => _DimChip(icon: Icons.place_rounded, label: '${e.key} · ${e.value.toStringAsFixed(0)}'),
                        ),
                      ],
                    ),
                  ],
                  if (_expanded) ...[
                    const SizedBox(height: 12),
                    const Divider(color: AppColors.border, height: 1),
                    const SizedBox(height: 8),
                    ...group.items.map((p) => _UnitRow(
                          produit: p,
                          fmt: _fmt,
                          baseUrl: widget.baseUrl,
                          fallbackImageUrl:
                              widget.baseUrl != null ? _groupImageUrl(group, widget.baseUrl!, widget.imagesParDesignation) : null,
                          showValiderAction: widget.showValiderAction,
                          restrictedInfo: widget.restrictedInfo,
                          isAchatConfirmeVue: widget.isAchatConfirmeVue,
                          isAchatAttenteVue: widget.isAchatAttenteVue,
                          showMettreEnAchatAction: widget.showMettreEnAchatAction,
                          isPatron: widget.isPatron,
                          onEdit: widget.onEdit,
                          onValider: widget.onValider,
                          onMiseEnReparation: widget.onMiseEnReparation,
                          onTerminerReparation: widget.onTerminerReparation,
                          onAddToCart: widget.onAddToCart,
                          onTapUnit: widget.onTapUnit,
                          onRemettreEnStock: widget.onRemettreEnStock,
                          onEntrerEnStockAchat: widget.onEntrerEnStockAchat,
                          onConfirmerAchat: widget.onConfirmerAchat,
                          onMettreEnAchat: widget.onMettreEnAchat,
                          selectionMode: widget.selectionMode,
                          checked: widget.selectedIds.contains(p.idProduits),
                          onCheckChanged: widget.onCheckChanged == null ? null : (v) => widget.onCheckChanged!(p.idProduits, v),
                        )),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label, style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w700, color: color)),
    );
  }
}

class _DimChip extends StatelessWidget {
  const _DimChip({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: AppColors.textMuted),
          const SizedBox(width: 5),
          Text(label, style: GoogleFonts.inter(fontSize: 10.5, color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}

/// Ligne d'unité individuelle (numéro de série, prix, emplacement) — pas de
/// cadre, séparation fine, en ligne comme demandé pour tous les champs.
/// Un tap ouvre la fiche détaillée de cette unité.
class _UnitRow extends StatelessWidget {
  const _UnitRow({
    required this.produit,
    required this.fmt,
    required this.baseUrl,
    required this.fallbackImageUrl,
    this.showValiderAction = false,
    this.restrictedInfo = false,
    this.isAchatConfirmeVue = false,
    this.isAchatAttenteVue = false,
    this.showMettreEnAchatAction = false,
    this.isPatron = false,
    this.onEdit,
    this.onValider,
    this.onMiseEnReparation,
    this.onTerminerReparation,
    this.onAddToCart,
    this.onTapUnit,
    this.onRemettreEnStock,
    this.onEntrerEnStockAchat,
    this.onConfirmerAchat,
    this.onMettreEnAchat,
    this.selectionMode = false,
    this.checked = false,
    this.onCheckChanged,
  });
  final ProduitModel produit;
  final String Function(double) fmt;
  final String? baseUrl;
  final String? fallbackImageUrl;
  final bool showValiderAction;
  final bool restrictedInfo;
  final bool isAchatConfirmeVue;
  final bool isAchatAttenteVue;
  final bool showMettreEnAchatAction;
  final bool isPatron;
  final void Function(ProduitModel produit, String? imageUrl)? onEdit;
  final void Function(ProduitModel produit)? onValider;
  final void Function(ProduitModel produit)? onMiseEnReparation;
  final void Function(ProduitModel produit)? onTerminerReparation;
  final void Function(ProduitModel produit)? onAddToCart;
  final void Function(ProduitModel produit, String? imageUrl)? onTapUnit;
  final void Function(ProduitModel produit)? onRemettreEnStock;
  final void Function(ProduitModel produit)? onEntrerEnStockAchat;
  final void Function(ProduitModel produit)? onConfirmerAchat;
  final void Function(ProduitModel produit)? onMettreEnAchat;
  final bool selectionMode;
  final bool checked;
  final ValueChanged<bool>? onCheckChanged;

  @override
  Widget build(BuildContext context) {
    final resolvedImage = baseUrl != null ? produit.imageUrl(baseUrl!) ?? fallbackImageUrl : null;

    return InkWell(
      onTap: onTapUnit != null
          ? () => onTapUnit!(produit, resolvedImage)
          : () => showProduitDetailSheet(
                context,
                produit: produit,
                baseUrl: baseUrl,
                imageUrlOverride: resolvedImage,
                showPrintQr: true,
                restrictedInfo: restrictedInfo,
              ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (selectionMode && produit.isAchat && !produit.achatAttente) ...[
                  // GestureDetector "vide" : absorbe le tap pour qu'il ne se
                  // propage pas à l'InkWell parent (qui ouvrirait la fiche
                  // détaillée au lieu de simplement cocher la case).
                  GestureDetector(
                    onTap: () {},
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: Checkbox(
                        value: checked,
                        activeColor: AppColors.green,
                        onChanged: onCheckChanged == null ? null : (v) => onCheckChanged!(v ?? false),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                const Icon(Icons.subdirectory_arrow_right_rounded, size: 14, color: AppColors.textMuted),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    produit.numSerie ?? produit.codeProduits ?? 'Réf. ${produit.idProduits}',
                    style: GoogleFonts.inter(fontSize: 12.5, color: AppColors.textSecondary),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (produit.produitApresEchange)
                  const Padding(
                    padding: EdgeInsets.only(right: 6),
                    child: Icon(Icons.undo_rounded, size: 14, color: Color(0xFF8B5CF6)),
                  ),
                if (produit.isReparationProduits)
                  const Padding(
                    padding: EdgeInsets.only(right: 6),
                    child: Icon(Icons.build_circle_rounded, size: 14, color: AppColors.orange),
                  ),
                if (produit.isAchat)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Icon(
                      produit.achatAttente ? Icons.hourglass_bottom_rounded : Icons.check_circle_rounded,
                      size: 14,
                      color: produit.achatAttente ? AppColors.orange : AppColors.green,
                    ),
                  ),
                Text(
                  '${fmt(produit.prixUnitaire)} Ar',
                  style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                ),
                if (produit.produitApresEchange && onRemettreEnStock != null)
                  IconButton(
                    icon: const Icon(Icons.undo_rounded, size: 18, color: Color(0xFF8B5CF6)),
                    tooltip: 'Remettre en stock',
                    onPressed: () => onRemettreEnStock!(produit),
                  )
                else if (isAchatConfirmeVue && onEntrerEnStockAchat != null)
                  IconButton(
                    icon: const Icon(Icons.move_to_inbox_rounded, size: 18, color: AppColors.green),
                    tooltip: 'Entrer en stock',
                    onPressed: () => onEntrerEnStockAchat!(produit),
                  )
                else if (isAchatAttenteVue && isPatron && onConfirmerAchat != null)
                  IconButton(
                    icon: const Icon(Icons.check_circle_outline_rounded, size: 18, color: AppColors.green),
                    tooltip: "Confirmer l'achat",
                    onPressed: () => onConfirmerAchat!(produit),
                  )
                else if (showValiderAction && onValider != null) ...[
                  IconButton(
                    icon: const Icon(Icons.check_circle_outline_rounded, size: 18, color: AppColors.green),
                    tooltip: 'Valider',
                    onPressed: () => onValider!(produit),
                  ),
                  if (showMettreEnAchatAction && onMettreEnAchat != null)
                    IconButton(
                      icon: const Icon(Icons.shopping_bag_rounded, size: 17, color: AppColors.accentLight),
                      tooltip: 'Mettre en achat',
                      onPressed: () => onMettreEnAchat!(produit),
                    ),
                ] else ...[
                  if (onAddToCart != null && produit.totalStock > 0 && !produit.isReparationProduits && !produit.produitApresEchange && !produit.isAchat)
                    IconButton(
                      icon: const Icon(Icons.add_shopping_cart_rounded, size: 17, color: AppColors.green),
                      tooltip: 'Ajouter au ticket',
                      onPressed: () => onAddToCart!(produit),
                    ),
                  if (onMiseEnReparation != null || onTerminerReparation != null)
                    IconButton(
                      icon: Icon(
                        produit.isReparationProduits ? Icons.build_circle_rounded : Icons.build_outlined,
                        size: 17,
                        color: produit.isReparationProduits ? AppColors.orange : AppColors.textMuted,
                      ),
                      tooltip: produit.isReparationProduits ? 'Terminer la réparation' : 'Mise en réparation',
                      onPressed: produit.isReparationProduits
                          ? (onTerminerReparation != null ? () => onTerminerReparation!(produit) : null)
                          : (onMiseEnReparation != null ? () => onMiseEnReparation!(produit) : null),
                    ),
                  if (onEdit != null)
                    IconButton(
                      icon: const Icon(Icons.edit_rounded, size: 16, color: AppColors.textMuted),
                      tooltip: 'Modifier',
                      onPressed: () => onEdit!(produit, resolvedImage),
                    )
                  else if (onMiseEnReparation == null && onTerminerReparation == null)
                    const Padding(
                      padding: EdgeInsets.only(left: 6),
                      child: Icon(Icons.chevron_right_rounded, size: 16, color: AppColors.textMuted),
                    ),
                ],
              ],
            ),
            if (produit.isReparationProduits && (produit.motifReparationProduits ?? '').trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 22, top: 2),
                child: Text(
                  'Motif : ${produit.motifReparationProduits}',
                  style: GoogleFonts.inter(fontSize: 11, color: AppColors.orange, fontStyle: FontStyle.italic),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            if (produit.isAchat && (produit.bulk ?? '').trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 22, top: 2),
                child: Text(
                  'Bulk : ${produit.bulk}',
                  style: GoogleFonts.inter(fontSize: 11, color: AppColors.accentLight, fontStyle: FontStyle.italic),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
