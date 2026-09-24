import 'dart:convert';

import '../core/api_client.dart';
import '../models/lookup_model.dart';
import '../models/payment_split.dart';
import '../models/personne_model.dart';
import '../models/produit_activite.dart';
import '../models/produit_model.dart';
import '../models/user_model.dart';
import 'cart_service.dart';

class SaleResult {
  SaleResult({required this.success, this.message, this.idClient, this.numeroFacture, this.dateFacture});
  final bool success;
  final String? message;
  final String? idClient;
  final String? numeroFacture;
  final String? dateFacture;
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
      'whatsapp2': field('whatsapp2'),
      'telephoneMobile': field('telephone_mobile'),
      'email': field('email'),
      'facebook': field('facebook'),
      'instagram': field('instagram'),
      'logo': field('logo'),
    };
  }

  Future<List<PersonneModel>> loadClients() async {
    final data = await ApiClient.instance.post('allpersonnes');
    if (data is! List) return [];
    return data.whereType<Map>().map((e) => PersonneModel.fromJson(Map<String, dynamic>.from(e))).toList();
  }

  /// Crée un nouveau client — nom, prénom, CIN et téléphone sont recueillis
  /// avant l'encaissement (voir `_AddClientDialog` dans `PaymentScreen`) pour
  /// pouvoir figurer sur le reçu A4 imprimé/partagé.
  Future<SaleResult> addClient(String nom, {String? prenom, String? cin, String? telephone}) async {
    final data = await ApiClient.instance.post('addpersonnes', fields: {
      'nom': nom,
      if (prenom != null && prenom.trim().isNotEmpty) 'prenom': prenom.trim(),
      if (cin != null && cin.trim().isNotEmpty) 'cin': cin.trim(),
      if (telephone != null && telephone.trim().isNotEmpty) 'telephone': telephone.trim(),
    });
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
              // Prix de vente de la ligne (modifiable depuis le panier via le
              // bouton "remise") — VenteMob::formatLstCmdArg() l'enregistre
              // tel quel dans ventes.prix_ventes, sans jamais toucher au
              // prix catalogue de l'article (produits.prix_unitaire).
              'prixProduit': l.prixVente,
              'isConsigne': 0,
              'prixBouteille': 0,
              'idAcompagner': '',
            })
        .toList();
  }

  /// "Encaisser" : paiement complet immédiat (`Mob/all_payed`), avec un ou
  /// plusieurs modes de paiement (`VenteMob::allpayed()` a été étendu côté
  /// serveur pour accepter un tableau de paiements plutôt qu'un seul).
  /// [isReservation] : bouton "Réserver" (voir CartScreen/PaymentScreen) —
  /// client obligatoire (vérifié par l'appelant), client.is_reservation=1
  /// côté serveur (VenteMob::addClient()), jusqu'au solde complet de la
  /// facture (voir ClientManage::payed() côté web, réutilisée par
  /// Mob::credit_pay()).
  Future<SaleResult> encaisser({
    required List<CartLine> lines,
    required UserModel user,
    required List<PaymentSplit> paiements,
    PersonneModel? client,
    String? reference,
    bool isReservation = false,
  }) async {
    if (lines.isEmpty) return SaleResult(success: false, message: 'Le panier est vide.');
    if (paiements.isEmpty) return SaleResult(success: false, message: 'Ajoutez au moins un mode de paiement.');
    if (isReservation && client == null) {
      return SaleResult(success: false, message: 'Les informations du client sont obligatoires pour une réservation.');
    }

    final fields = <String, String>{
      'cart': jsonEncode(_cartPayload(lines)),
      'user': jsonEncode(user.mobPayload),
      'paiements': jsonEncode(paiements.map((p) => p.toJson()).toList()),
      'is_reservation': isReservation ? '1' : '0',
    };
    if (client != null) fields['personne'] = jsonEncode({'id': client.id});
    if (reference != null && reference.trim().isNotEmpty) fields['reference'] = reference.trim();

    final data = await ApiClient.instance.post('all_payed', fields: fields);
    if (data is! Map) return SaleResult(success: false, message: 'Réponse du serveur invalide.');
    final error = data['error'] == true;
    return SaleResult(
      success: !error,
      message: data['msg']?.toString() ?? (error ? 'La vente a échoué.' : 'Vente encaissée avec succès.'),
      idClient: data['id_cmd']?.toString(),
      numeroFacture: data['numero_facture']?.toString(),
      dateFacture: data['date_facture']?.toString(),
    );
  }

  /// Historique d'un article (création, modifications, ventes + facture),
  /// pour l'écran ouvert depuis la recherche intelligente.
  Future<ProduitActivites> loadProduitActivites(String idProduits) async {
    final data = await ApiClient.instance.get('produit_activites', query: {'id_produits': idProduits});
    if (data is! Map) return ProduitActivites.empty();
    return ProduitActivites.fromJson(Map<String, dynamic>.from(data));
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
