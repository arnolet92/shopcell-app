/// Élément générique pour les listes de filtres (famille, marque, couleur,
/// batterie, carton, défaut) renvoyées par `Mob/produit_filters`.
class LookupItem {
  LookupItem({required this.id, required this.label});

  final String id;
  final String label;

  factory LookupItem.from(Map<String, dynamic> json, {required String idKey, required String labelKey}) {
    return LookupItem(id: '${json[idKey] ?? ''}', label: '${json[labelKey] ?? ''}');
  }
}

class ProduitFilters {
  ProduitFilters({
    required this.familles,
    required this.marques,
    required this.couleurs,
    required this.batteries,
    required this.cartons,
    required this.defauts,
    required this.fournisseurs,
    required this.modeles,
    required this.systemes,
    required this.lieux,
  });

  final List<LookupItem> familles;
  final List<LookupItem> marques;
  final List<LookupItem> couleurs;
  final List<LookupItem> batteries;
  final List<LookupItem> cartons;
  final List<LookupItem> defauts;
  // Listes complémentaires pour le formulaire de création/modification d'article.
  final List<LookupItem> fournisseurs;
  final List<LookupItem> modeles;
  final List<LookupItem> systemes;
  final List<LookupItem> lieux;

  factory ProduitFilters.fromJson(Map<String, dynamic> json) {
    List<LookupItem> parse(String key, String idKey, String labelKey) {
      final list = json[key];
      if (list is! List) return [];
      return list
          .whereType<Map<String, dynamic>>()
          .map((e) => LookupItem.from(e, idKey: idKey, labelKey: labelKey))
          .toList();
    }

    return ProduitFilters(
      familles: parse('souscat', 'id_sous_type_produit', 'nom_sous_type'),
      marques: parse('marques', 'id_marque', 'nom_marque'),
      couleurs: parse('type_pieces', 'id_type_piece', 'nom_type_piece'),
      batteries: parse('sous_categorie_pieces', 'id_sous_categorie', 'nom_sous_categorie_piece'),
      cartons: parse('carton_', 'id_carton', 'nom_carton'),
      defauts: parse('defaut_', 'id_defaut', 'nom_defaut'),
      fournisseurs: parse('fournisseurs', 'id_fournisseurs', 'nom_frns'),
      modeles: parse('models', 'id_model', 'nom_model'),
      systemes: parse('systemes', 'id_systeme', 'nom_systeme'),
      lieux: parse('lieux', 'id_lieu', 'nom_lieu'),
    );
  }

  factory ProduitFilters.empty() => ProduitFilters(
        familles: [],
        marques: [],
        couleurs: [],
        batteries: [],
        cartons: [],
        defauts: [],
        fournisseurs: [],
        modeles: [],
        systemes: [],
        lieux: [],
      );
}
