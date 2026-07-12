import '../core/api_client.dart';
import '../models/lookup_model.dart';
import '../models/produit_model.dart';

/// Les 3 vues de la gestion d'article côté web : `Produit::lst()` (tous),
/// `Produit::lst_attente()` (articles en attente de validation),
/// `Produit::lst_vente()` (articles totalement épuisés).
enum ProduitVue { tous, attente, vente }

class SaveProduitResult {
  SaveProduitResult({required this.success, this.message, this.idProduits});
  final bool success;
  final String? message;
  final String? idProduits;
}

/// Écran "Gestion d'article" : consomme `Mob/produits_gestion` et
/// `Mob/produit_filters`, les équivalents JSON de
/// `Produit::lst()` / `Produit::recherche_prod_t()` côté web.
class ProduitService {
  ProduitService._();
  static final ProduitService instance = ProduitService._();

  Future<ProduitFilters> loadFilters() async {
    final data = await ApiClient.instance.post('produit_filters');
    if (data is! Map) return ProduitFilters.empty();
    return ProduitFilters.fromJson(Map<String, dynamic>.from(data));
  }

  Future<List<ProduitModel>> loadArticles({
    ProduitVue vue = ProduitVue.tous,
    String? recherche,
    String? idFamille,
    String? idMarque,
    String? idCouleur,
    String? idBatterie,
    String? idCarton,
    String? idDefaut,
  }) async {
    final fields = <String, String>{
      'vue': switch (vue) { ProduitVue.tous => 'tous', ProduitVue.attente => 'attente', ProduitVue.vente => 'vente' },
    };
    if (recherche != null && recherche.trim().isNotEmpty) fields['arg'] = recherche.trim();
    if (idFamille != null && idFamille.isNotEmpty) fields['id_sous_type_produit'] = idFamille;
    if (idMarque != null && idMarque.isNotEmpty) fields['id_marque'] = idMarque;
    if (idCouleur != null && idCouleur.isNotEmpty) fields['id_type_piece'] = idCouleur;
    if (idBatterie != null && idBatterie.isNotEmpty) fields['id_sous_categorie'] = idBatterie;
    if (idCarton != null && idCarton.isNotEmpty) fields['id_carton'] = idCarton;
    if (idDefaut != null && idDefaut.isNotEmpty) fields['id_defaut'] = idDefaut;

    final data = await ApiClient.instance.post('produits_gestion', fields: fields);
    if (data is! List) return [];
    return data
        .whereType<Map>()
        .map((e) => ProduitModel.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  /// Liste "prête à la vente" (`Mob/allprod`), utilisée par l'écran Vente.
  Future<List<ProduitModel>> loadProduitsVente({String? idFamille}) async {
    final fields = <String, String>{};
    if (idFamille != null && idFamille.isNotEmpty) fields['id_sous_type_produit'] = idFamille;
    final data = await ApiClient.instance.post('allprod', fields: fields);
    if (data is! List) return [];
    return data
        .whereType<Map>()
        .map((e) => ProduitModel.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  /// Carte designation -> photo, sur TOUS les articles (indépendamment du
  /// stock/disponibilité) — voir `Mob::images_par_designation()` côté
  /// serveur et le commentaire de `ProduitImageResolver`.
  Future<Map<String, String>> loadImagesParDesignation(String baseUrl) async {
    final data = await ApiClient.instance.post('images_par_designation');
    if (data is! List) return {};
    final base = baseUrl.replaceAll(RegExp(r'/+$'), '');
    final map = <String, String>{};
    for (final row in data.whereType<Map>()) {
      final designation = row['designation_produits']?.toString().trim();
      final id = row['id_produits']?.toString();
      final img = row['img_produit']?.toString().trim();
      if (designation == null || designation.isEmpty || id == null || img == null || img.isEmpty) continue;
      final key = designation.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
      map.putIfAbsent(key, () => '$base/uploads/photo/produit/$id/$img');
    }
    return map;
  }

  /// Création (idProduits null) ou modification (idProduits renseigné) d'un
  /// article — équivalent JSON de `Produit::add_prod()`/`update_lst()`.
  /// Les champs marque/couleur/batterie/carton/défaut/fournisseur/modèle/
  /// système/famille sont "trouvés ou créés" côté serveur à partir du texte
  /// envoyé (comme les `<input list="...">` du formulaire web) — pas besoin
  /// de résoudre un id côté mobile, un simple texte suffit.
  Future<SaveProduitResult> saveProduit({
    String? idProduits,
    required String designation,
    String? codeProduits,
    String? codeBar,
    String? numSerie,
    String? imei1,
    String? imei2,
    required double qteProduits,
    required double prixAchats,
    required double prixRevient,
    required double prixUnitaire,
    String? description,
    bool enAttente = false,
    String? datePeremption,
    String? famille,
    String? modele,
    String? marque,
    String? couleur,
    String? batterie,
    String? carton,
    String? defaut,
    String? fournisseur,
    String? systeme,
    String? idLieu,
    String? photoPath,
  }) async {
    final fields = <String, String>{
      'designation_produits': designation,
      'qte_produits': qteProduits.toString(),
      'prix_achats': prixAchats.toString(),
      'prix_revient_produits': prixRevient.toString(),
      'prix_unitaire': prixUnitaire.toString(),
      'produits_attente': enAttente ? '1' : '0',
    };
    if (idProduits != null) fields['id_produits'] = idProduits;
    if (codeProduits != null) fields['code_produits'] = codeProduits;
    if (codeBar != null) fields['codebar'] = codeBar;
    if (numSerie != null) fields['num_serie'] = numSerie;
    if (imei1 != null) fields['imei1'] = imei1;
    if (imei2 != null) fields['imei2'] = imei2;
    if (description != null) fields['description'] = description;
    if (datePeremption != null) fields['date_peremption_produits'] = datePeremption;
    if (famille != null) fields['type_produit_id'] = famille;
    if (modele != null) fields['produits_model_id'] = modele;
    if (marque != null) fields['produits_marque_id'] = marque;
    if (couleur != null) fields['produits_type_piece_id'] = couleur;
    if (batterie != null) fields['produits_sous_categorie_piece_id'] = batterie;
    if (carton != null) fields['produits_carton_id'] = carton;
    if (defaut != null) fields['produits_defaut_id'] = defaut;
    if (fournisseur != null) fields['produits_fournisseurs_id'] = fournisseur;
    if (systeme != null) fields['produits_systeme_id'] = systeme;
    if (idLieu != null) fields['produits_lieu_id'] = idLieu;

    final data = await ApiClient.instance.postMultipart(
      'save_produit',
      fields: fields,
      photoFieldName: photoPath != null ? 'photo' : null,
      photoPath: photoPath,
    );
    if (data is! Map) return SaveProduitResult(success: false, message: 'Réponse du serveur invalide.');
    final error = data['error'] == true;
    return SaveProduitResult(
      success: !error,
      message: data['msg']?.toString(),
      idProduits: data['id_produits']?.toString(),
    );
  }

  /// Valide un article en attente ou le remet en attente — équivalent de
  /// `Produit::valid()`/`metatt()`.
  Future<SaveProduitResult> validerAttente({required String idProduits, required bool valider}) async {
    final data = await ApiClient.instance.post('valider_attente', fields: {
      'id_produits': idProduits,
      'valide': valider ? '1' : '0',
    });
    if (data is! Map) return SaveProduitResult(success: false, message: 'Réponse du serveur invalide.');
    final error = data['error'] == true;
    return SaveProduitResult(success: !error, message: data['msg']?.toString());
  }
}
