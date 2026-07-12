import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme.dart';
import '../../../models/lookup_model.dart';
import '../../../widgets/inline_field.dart';

class FilterSelection {
  const FilterSelection({
    this.familleId,
    this.marqueId,
    this.couleurId,
    this.batterieId,
    this.cartonId,
    this.defautId,
  });

  final String? familleId;
  final String? marqueId;
  final String? couleurId;
  final String? batterieId;
  final String? cartonId;
  final String? defautId;

  bool get isEmpty =>
      familleId == null && marqueId == null && couleurId == null && batterieId == null && cartonId == null && defautId == null;

  FilterSelection copyWith({
    String? Function()? familleId,
    String? Function()? marqueId,
    String? Function()? couleurId,
    String? Function()? batterieId,
    String? Function()? cartonId,
    String? Function()? defautId,
  }) {
    return FilterSelection(
      familleId: familleId != null ? familleId() : this.familleId,
      marqueId: marqueId != null ? marqueId() : this.marqueId,
      couleurId: couleurId != null ? couleurId() : this.couleurId,
      batterieId: batterieId != null ? batterieId() : this.batterieId,
      cartonId: cartonId != null ? cartonId() : this.cartonId,
      defautId: defautId != null ? defautId() : this.defautId,
    );
  }

  static const empty = FilterSelection();
}

/// Barre de recherche + filtres, miroir de `.filter-bar` sur `Produit/lst` :
/// champ de recherche en ligne (sans cadre) + sélecteurs (famille, capacité,
/// couleur, batterie, carton, défaut) ouvrant chacun une liste de choix.
class ProduitFilterBar extends StatelessWidget {
  const ProduitFilterBar({
    super.key,
    required this.searchController,
    required this.onSearchChanged,
    required this.filters,
    required this.selection,
    required this.onSelectionChanged,
  });

  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final ProduitFilters filters;
  final FilterSelection selection;
  final ValueChanged<FilterSelection> onSelectionChanged;

  void _openPicker(
    BuildContext context, {
    required String title,
    required List<LookupItem> items,
    required String? currentId,
    required void Function(String?) onPicked,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(4))),
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(title, style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                ),
              ),
              const SizedBox(height: 8),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    ListTile(
                      title: Text('Toutes / Tous', style: GoogleFonts.inter(color: AppColors.textSecondary, fontSize: 14)),
                      trailing: currentId == null ? const Icon(Icons.check_rounded, color: AppColors.accentLight) : null,
                      onTap: () {
                        onPicked(null);
                        Navigator.of(context).pop();
                      },
                    ),
                    for (final item in items)
                      ListTile(
                        title: Text(item.label, style: GoogleFonts.inter(color: AppColors.textPrimary, fontSize: 14)),
                        trailing: currentId == item.id ? const Icon(Icons.check_rounded, color: AppColors.accentLight) : null,
                        onTap: () {
                          onPicked(item.id);
                          Navigator.of(context).pop();
                        },
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    String labelFor(List<LookupItem> items, String? id, String fallback) {
      if (id == null) return fallback;
      return items.firstWhere((e) => e.id == id, orElse: () => LookupItem(id: id, label: fallback)).label;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: InlineSearchField(
            controller: searchController,
            hint: 'Rechercher par nom, code ou n° série...',
            onChanged: onSearchChanged,
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 36,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              _FilterChip(
                icon: Icons.layers_rounded,
                label: labelFor(filters.familles, selection.familleId, 'Famille'),
                active: selection.familleId != null,
                onTap: () => _openPicker(
                  context,
                  title: 'Famille',
                  items: filters.familles,
                  currentId: selection.familleId,
                  onPicked: (id) => onSelectionChanged(selection.copyWith(familleId: () => id)),
                ),
              ),
              const SizedBox(width: 8),
              _FilterChip(
                icon: Icons.memory_rounded,
                label: labelFor(filters.marques, selection.marqueId, 'Capacité'),
                active: selection.marqueId != null,
                onTap: () => _openPicker(
                  context,
                  title: 'Capacité',
                  items: filters.marques,
                  currentId: selection.marqueId,
                  onPicked: (id) => onSelectionChanged(selection.copyWith(marqueId: () => id)),
                ),
              ),
              const SizedBox(width: 8),
              _FilterChip(
                icon: Icons.palette_rounded,
                label: labelFor(filters.couleurs, selection.couleurId, 'Couleur'),
                active: selection.couleurId != null,
                onTap: () => _openPicker(
                  context,
                  title: 'Couleur',
                  items: filters.couleurs,
                  currentId: selection.couleurId,
                  onPicked: (id) => onSelectionChanged(selection.copyWith(couleurId: () => id)),
                ),
              ),
              const SizedBox(width: 8),
              _FilterChip(
                icon: Icons.battery_full_rounded,
                label: labelFor(filters.batteries, selection.batterieId, 'Batterie'),
                active: selection.batterieId != null,
                onTap: () => _openPicker(
                  context,
                  title: 'Batterie',
                  items: filters.batteries,
                  currentId: selection.batterieId,
                  onPicked: (id) => onSelectionChanged(selection.copyWith(batterieId: () => id)),
                ),
              ),
              const SizedBox(width: 8),
              _FilterChip(
                icon: Icons.inventory_rounded,
                label: labelFor(filters.cartons, selection.cartonId, 'Carton'),
                active: selection.cartonId != null,
                onTap: () => _openPicker(
                  context,
                  title: 'Carton',
                  items: filters.cartons,
                  currentId: selection.cartonId,
                  onPicked: (id) => onSelectionChanged(selection.copyWith(cartonId: () => id)),
                ),
              ),
              const SizedBox(width: 8),
              _FilterChip(
                icon: Icons.report_gmailerrorred_rounded,
                label: labelFor(filters.defauts, selection.defautId, 'Défaut'),
                active: selection.defautId != null,
                onTap: () => _openPicker(
                  context,
                  title: 'Défaut',
                  items: filters.defauts,
                  currentId: selection.defautId,
                  onPicked: (id) => onSelectionChanged(selection.copyWith(defautId: () => id)),
                ),
              ),
              if (!selection.isEmpty) ...[
                const SizedBox(width: 8),
                _FilterChip(
                  icon: Icons.close_rounded,
                  label: 'Réinitialiser',
                  active: false,
                  danger: true,
                  onTap: () => onSelectionChanged(FilterSelection.empty),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final bool active;
  final bool danger;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = danger ? AppColors.red : (active ? AppColors.accentLight : AppColors.textSecondary);
    return Material(
      color: active ? AppColors.accentGlow : Colors.transparent,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: active ? AppColors.borderAccent : AppColors.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 13, color: color),
              const SizedBox(width: 6),
              Text(label, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
            ],
          ),
        ),
      ),
    );
  }
}
