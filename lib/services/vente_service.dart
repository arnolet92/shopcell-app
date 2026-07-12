import 'dart:convert';

import '../core/api_client.dart';
import '../models/lookup_model.dart';
import '../models/personne_model.dart';
import '../models/produit_model.dart';
import '../models/user_model.dart';
import 'cart_service.dart';

class SaleResult {
  SaleResult({required this.success, this.message});
  final bool success;
  final String? message;
}

/// Orchestration de la vente côté mobile, sur le même principe que l'écran
/// web `Vente/commande_direct` (panier -> client optionnel -> "Encaisser"
/// ou "En attente"), mais via les routes `Mob/*` déjà prévues côté serveur
/// pour un client mobile (`application/core/VenteMob.php`).
class VenteService {
  VenteService._();
  static final VenteService instance = VenteService._();

  /// Infos boutique (`information_interne`, via `Mob/monsession`), pour
  /// l'en-tête du ticket imprimé après encaissement — mêmes champs et même
  /// ordre que `application/views/ticket/_entete.php` côté web (appellation,
  /// adresse, lieu, nif, stat, rcs, telephone, email).
  Future<Map<String, String?>> loadShopInfo() async {
    final data = await ApiClient.instance.post('monsession');
    if (data is! Map) return {};
    final info = data['information_iterne'];
    if (info is! Map) return {};
    String? field(String key) {
      final v = info[key]?.toString().trim();
      return (v == null || v.isEmpty) ? null : v;
    }

    return {
      'appellation': field('appellation'),
      'adresse': field('adresse'),
      'lieu': field('lieu'),
      'nif': field('nif'),
      'stat': field('stat'),
      'rcs': field('rcs'),
      'telephone': field('telephone'),
      'email': field('email'),
    };
  }

  Future<List<PersonneModel>> loadClients() async {
    final data = await ApiClient.instance.post('allpersonnes');
    if (data is! List) return [];
    return data.whereType<Map>().map((e) => PersonneModel.fromJson(Map<String, dynamic>.from(e))).toList();
  }

  Future<SaleResult> addClient(String nom) async {
    final data = await ApiClient.instance.post('addpersonnes', fields: {'nom': nom});
    if (data is! Map) return SaleResult(success: false, message: 'Réponse invalide.');
    final error = data['error'] == true;
    return SaleResult(success: !error, message: data['msg']?.toString());
  }

  Future<List<LookupItem>> loadTypesPaiement() async {
    final data = await ApiClient.instance.post('alltypepaiement');
    if (data is! List) return [];
    return data
        .whereType<Map>()
        .map((e) => LookupItem.from(Map<String, dynamic>.from(e), idKey: 'id_type_paiement', labelKey: 'nom_type_paiement'))
        .toList();
  }

  /// Recherche un article par id (scan QR = id_produits), pour la vente par
  /// scan côté mobile.
  Future<ProduitModel?> findProduitById(String idProduits) async {
    final data = await ApiClient.instance.get('produit_by_id', query: {'id_produits': idProduits});
    if (data is! Map) return null;
    return ProduitModel.fromJson(Map<String, dynamic>.from(data));
  }

  List<Map<String, dynamic>> _cartPayload(List<CartLine> lines) {
    return lines
        .map((l) => {
              'idProduit': l.produit.idProduits,
              'qteProduit': l.qte,
              'prixProduit': l.produit.prixUnitaire,
              'isConsigne': 0,
              'prixBouteille': 0,
              'idAcompagner': '',
            })
        .toList();
  }

  /// "Encaisser" : paiement complet immédiat (`Mob/all_payed`).
  Future<SaleResult> encaisser({
    required List<CartLine> lines,
    required UserModel user,
    PersonneModel? client,
    String? idTypePaiement,
    double? sommeDonnee,
  }) async {
    if (lines.isEmpty) return SaleResult(success: false, message: 'Le panier est vide.');

    final fields = <String, String>{
      'cart': jsonEncode(_cartPayload(lines)),
      'user': jsonEncode(user.mobPayload),
    };
    if (client != null) fields['personne'] = jsonEncode({'id': client.id});
    if (idTypePaiement != null) fields['id_type_paiement'] = idTypePaiement;
    if (sommeDonnee != null) fields['somme_donnee'] = sommeDonnee.toStringAsFixed(0);

    final data = await ApiClient.instance.post('all_payed', fields: fields);
    if (data is! Map) return SaleResult(success: false, message: 'Réponse du serveur invalide.');
    final error = data['error'] == true;
    return SaleResult(
      success: !error,
      message: data['msg']?.toString() ?? (error ? 'La vente a échoué.' : 'Vente encaissée avec succès.'),
    );
  }

  /// "En attente" : commande enregistrée non payée (`Mob/all_data`), qui
  /// exige côté serveur soit un client, soit une référence/table.
  Future<SaleResult> mettreEnAttente({
    required List<CartLine> lines,
    required UserModel user,
    PersonneModel? client,
    String? reference,
  }) async {
    if (lines.isEmpty) return SaleResult(success: false, message: 'Le panier est vide.');
    if (client == null && (reference == null || reference.trim().isEmpty)) {
      return SaleResult(success: false, message: "Choisissez un client ou indiquez une référence.");
    }

    final fields = <String, String>{
      'cart': jsonEncode(_cartPayload(lines)),
      'user': jsonEncode(user.mobPayload),
    };
    if (client != null) fields['personne'] = jsonEncode({'id': client.id});
    if (reference != null && reference.trim().isNotEmpty) fields['reference'] = reference.trim();

    final data = await ApiClient.instance.post('all_data', fields: fields);
    if (data is! Map) return SaleResult(success: false, message: 'Réponse du serveur invalide.');
    final error = data['error'] == true;
    return SaleResult(
      success: !error,
      message: data['msg']?.toString() ?? (error ? 'Échec de la mise en attente.' : 'Commande mise en attente.'),
    );
  }
}
