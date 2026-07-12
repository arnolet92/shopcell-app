/// Reflète une ligne renvoyée par `Mob/produits_gestion` (ou `Mob/allprod`),
/// équivalent JSON de application/models/Produits.php::select_func().
///
/// Chaque ligne représente une unité physique (souvent identifiée par un
/// numéro de série / IMEI) ; l'écran "Gestion d'article" les regroupe par
/// désignation, à l'identique de la vue web `tabproduit2.php`.
class ProduitModel {
  ProduitModel({
    required this.idProduits,
    required this.designation,
    required this.codeProduits,
    required this.codeBarProduits,
    required this.numSerie,
    required this.imei1,
    required this.imei2,
    required this.qteProduits,
    required this.prixUnitaire,
    required this.prixAchats,
    required this.prixRevient,
    required this.totalStock,
    required this.description,
    required this.nomMarque,
    required this.nomTypePiece,
    required this.nomSousCategoriePiece,
    required this.nomCarton,
    required this.nomDefaut,
    required this.nomLieu,
    required this.nomFrns,
    required this.nomModel,
    required this.nomSysteme,
    required this.nomSousType,
    required this.imgProduit,
  });

  final String idProduits;
  final String designation;
  final String? codeProduits;
  final String? codeBarProduits;
  final String? numSerie;
  final String? imei1;
  final String? imei2;
  final double qteProduits;
  final double prixUnitaire;
  final double prixAchats;
  final double prixRevient;
  final double totalStock;
  final String? description;
  final String? nomMarque; // "Capacité"
  final String? nomTypePiece; // "Couleur"
  final String? nomSousCategoriePiece; // "Batterie"
  final String? nomCarton;
  final String? nomDefaut;
  final String? nomLieu;
  final String? nomFrns; // Fournisseur
  final String? nomModel; // "Modèle"
  final String? nomSysteme; // "Système"
  final String? nomSousType; // Famille
  final String? imgProduit;

  /// URL réelle de la photo, sur le même principe que
  /// `Media::get_url_file($id, $img, 'photo', 'produit', false)` côté web :
  /// `<base>/uploads/photo/produit/<id_produits>/<img_produit>`.
  String? imageUrl(String baseUrl) {
    if (imgProduit == null) return null;
    final base = baseUrl.replaceAll(RegExp(r'/+$'), '');
    return '$base/uploads/photo/produit/$idProduits/$imgProduit';
  }

  static double _d(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse('$v') ?? 0;
  }

  static String? _s(dynamic v) {
    if (v == null) return null;
    final s = '$v'.trim();
    return s.isEmpty ? null : s;
  }

  factory ProduitModel.fromJson(Map<String, dynamic> json) {
    return ProduitModel(
      idProduits: '${json['id_produits'] ?? ''}',
      designation: _s(json['designation_produits']) ?? 'Sans désignation',
      codeProduits: _s(json['code_produits']),
      codeBarProduits: _s(json['code_bar_produits']),
      numSerie: _s(json['num_serie']),
      imei1: _s(json['imei1']),
      imei2: _s(json['imei2']),
      qteProduits: _d(json['qte_produits']),
      prixUnitaire: _d(json['prix_unitaire']),
      prixAchats: _d(json['prix_achats']),
      prixRevient: _d(json['prix_revient_produits']),
      totalStock: _d(json['total_stock']),
      description: _s(json['description']),
      nomMarque: _s(json['nom_marque']),
      nomTypePiece: _s(json['nom_type_piece']),
      nomSousCategoriePiece: _s(json['nom_sous_categorie_piece']),
      nomCarton: _s(json['nom_carton']),
      nomDefaut: _s(json['nom_defaut']),
      nomLieu: _s(json['nom_lieu']),
      nomFrns: _s(json['nom_frns']),
      nomModel: _s(json['nom_model']),
      nomSysteme: _s(json['nom_systeme']),
      nomSousType: _s(json['nom_sous_type']),
      imgProduit: _s(json['img_produit']),
    );
  }

  static String _normalize(String designation) =>
      designation.toLowerCase().trim().replaceAll(RegExp(r'\s+'), ' ');
}

/// Reproduit `$images_par_designation` de `allproduct.php`/`tabproduit2.php` :
/// beaucoup d'unités partagent la même désignation (même modèle de
/// téléphone) mais une seule a une photo — on la réutilise pour toutes les
/// unités de ce modèle plutôt que de n'afficher une image que pour l'unité
/// qui la possède réellement.
///
/// La liste chargée à l'écran (Vente/Gestion) est déjà filtrée par stock
/// (`qte_produits>0`, `isvendable=1`...), donc l'unité qui porte la photo
/// d'un modèle peut très bien être absente de cette liste. On complète donc
/// toujours avec la carte globale non filtrée renvoyée par
/// `Mob/images_par_designation` (voir `ProduitService.loadImagesParDesignation`),
/// qui est prioritaire sur ce qui a pu être trouvé localement.
class ProduitImageResolver {
  ProduitImageResolver(List<ProduitModel> produits, String? baseUrl) {
    if (baseUrl == null) return;
    for (final p in produits) {
      final url = p.imageUrl(baseUrl);
      if (url == null) continue;
      _byDesignation.putIfAbsent(ProduitModel._normalize(p.designation), () => url);
    }
  }

  final Map<String, String> _byDesignation = {};

  void seedGlobalMap(Map<String, String> globalMap) {
    _byDesignation.addAll(globalMap);
  }

  String? resolve(ProduitModel produit, String? baseUrl) {
    if (baseUrl == null) return null;
    return produit.imageUrl(baseUrl) ?? _byDesignation[ProduitModel._normalize(produit.designation)];
  }
}

/// Groupe de produits partageant la même désignation normalisée
/// (même principe que `$groupedProducts` dans tabproduit2.php).
class ProduitGroup {
  ProduitGroup({required this.designation, required this.items});

  final String designation;
  final List<ProduitModel> items;

  double get totalStock => items.fold(0.0, (sum, p) => sum + p.totalStock);
  double get totalAchat =>
      items.fold(0.0, (sum, p) => sum + (p.totalStock * p.prixAchats));

  /// Ventilation du stock par "capacité" (marque), comme `$stockByCapacity`.
  Map<String, double> get stockByCapacity {
    final map = <String, double>{};
    for (final p in items) {
      final key = p.nomMarque;
      if (key == null) continue;
      map[key] = (map[key] ?? 0) + p.totalStock;
    }
    return map;
  }

  /// Ventilation du stock par lieu de stockage, comme `$stockByLocation`.
  Map<String, double> get stockByLocation {
    final map = <String, double>{};
    for (final p in items) {
      final key = p.nomLieu;
      if (key == null) continue;
      map[key] = (map[key] ?? 0) + p.totalStock;
    }
    return map;
  }

  static List<ProduitGroup> groupBy(List<ProduitModel> produits) {
    final map = <String, List<ProduitModel>>{};
    for (final p in produits) {
      final key = p.designation.toLowerCase().trim().replaceAll(RegExp(r'\s+'), ' ');
      map.putIfAbsent(key, () => []).add(p);
    }
    final groups = map.entries
        .map((e) => ProduitGroup(designation: e.value.first.designation, items: e.value))
        .toList();
    groups.sort((a, b) => a.designation.toLowerCase().compareTo(b.designation.toLowerCase()));
    return groups;
  }
}
