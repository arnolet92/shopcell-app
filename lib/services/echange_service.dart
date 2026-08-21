import 'dart:convert';

import '../core/api_client.dart';
import '../models/payment_split.dart';
import '../models/produit_model.dart';
import '../models/user_model.dart';

class EchangeResult {
  EchangeResult({required this.success, this.message});
  final bool success;
  final String? message;
}

/// Ligne vendue trouvée par la recherche (point de départ d'un échange).
class VenteLigne {
  VenteLigne({
    required this.idVentes,
    required this.clientId,
    required this.designation,
    required this.numeroFacture,
    required this.qte,
    required this.prixVentes,
    required this.numSerie,
    required this.imei1,
    required this.imei2,
    required this.nomModel,
    required this.nomMarque,
    required this.nomLieu,
  });

  final String idVentes;
  final String clientId;
  final String designation;
  final String? numeroFacture;
  final double qte;
  final double prixVentes;
  final String? numSerie;
  final String? imei1;
  final String? imei2;
  final String? nomModel;
  final String? nomMarque;
  final String? nomLieu;

  factory VenteLigne.fromJson(Map<String, dynamic> j) {
    double d(dynamic v) => v == null ? 0 : (v is num ? v.toDouble() : double.tryParse('$v') ?? 0);
    String? s(dynamic v) {
      final t = v?.toString().trim();
      return (t == null || t.isEmpty) ? null : t;
    }

    return VenteLigne(
      idVentes: '${j['id_ventes'] ?? ''}',
      clientId: '${j['client_id'] ?? ''}',
      designation: s(j['designation_produits']) ?? 'Article',
      numeroFacture: s(j['numero_factures_client']),
      qte: d(j['qte']),
      prixVentes: d(j['prix_ventes']),
      numSerie: s(j['num_serie']),
      imei1: s(j['imei1']),
      imei2: s(j['imei2']),
      nomModel: s(j['nom_model']),
      nomMarque: s(j['nom_marque']),
      nomLieu: s(j['nom_lieu']),
    );
  }
}

/// Récapitulatif dynamique renvoyé par `Mob/echange_recap`, autoritaire
/// côté serveur (même formule que `EchangeManagement::recap()` côté web).
class EchangeRecap {
  EchangeRecap({
    required this.error,
    this.message,
    this.oldDesignation,
    this.newDesignation,
    this.prixAjoute = 0,
    this.montantFinal = 0,
    this.totalApres = 0,
    this.dejaPaye = 0,
    this.reste = 0,
    this.rendu = 0,
    this.personnesId,
  });

  final bool error;
  final String? message;
  final String? oldDesignation;
  final String? newDesignation;
  final double prixAjoute;
  final double montantFinal;
  final double totalApres;
  final double dejaPaye;
  final double reste;
  final double rendu;
  final String? personnesId;

  factory EchangeRecap.fromJson(Map<String, dynamic> j) {
    double d(dynamic v) => v == null ? 0 : (v is num ? v.toDouble() : double.tryParse('$v') ?? 0);
    if (j['error'] == true) {
      return EchangeRecap(error: true, message: j['msg']?.toString());
    }
    return EchangeRecap(
      error: false,
      oldDesignation: j['old_designation']?.toString(),
      newDesignation: j['new_designation']?.toString(),
      prixAjoute: d(j['prix_ajoute']),
      montantFinal: d(j['montant_final']),
      totalApres: d(j['total_apres']),
      dejaPaye: d(j['deja_paye']),
      reste: d(j['reste']),
      rendu: d(j['rendu']),
      personnesId: j['personnes_id']?.toString(),
    );
  }
}

/// Échange d'un article déjà vendu contre un article en stock, en réglant
/// la différence de prix — miroir mobile de `Echange/index` (web). Contrairement
/// à la version web (qui accumule les paiements du supplément dans la
/// session PHP au fil des clics), le mobile construit la liste complète des
/// paiements localement puis l'envoie en un seul appel `valider()` — cohérent
/// avec le principe des routes `Mob/*` (aucune session, chaque appel se
/// suffit à lui-même) et avec la manière dont l'écran "Encaisser" gère déjà
/// le paiement scindé d'une vente normale.
class EchangeService {
  EchangeService._();
  static final EchangeService instance = EchangeService._();

  Future<List<VenteLigne>> searchVentes(String arg) async {
    if (arg.trim().isEmpty) return [];
    final data = await ApiClient.instance.post('echange_search_ventes', fields: {'arg': arg});
    if (data is! List) return [];
    return data.whereType<Map>().map((e) => VenteLigne.fromJson(Map<String, dynamic>.from(e))).toList();
  }

  /// Détail brut (facture + lignes) : exposé tel quel en Map, l'écran de
  /// détail ne s'intéresse qu'à quelques champs (entête.numero_facture,
  /// entete.nom_complet, total_avant_remise, deja_paye).
  Future<Map<String, dynamic>?> factureDetail(String idVentes) async {
    final data = await ApiClient.instance.post('echange_facture_detail', fields: {'id_ventes': idVentes});
    if (data is! Map) return null;
    if (data['error'] == true) return null;
    return Map<String, dynamic>.from(data);
  }

  Future<List<ProduitModel>> searchNewProduit(String arg) async {
    if (arg.trim().isEmpty) return [];
    final data = await ApiClient.instance.post('echange_search_produit', fields: {'arg': arg});
    if (data is! List) return [];
    return data.whereType<Map>().map((e) => ProduitModel.fromJson(Map<String, dynamic>.from(e))).toList();
  }

  Future<EchangeRecap> recap({required String idVentes, required String newProduitsId, double? prixAjoute}) async {
    final fields = <String, String>{'id_ventes': idVentes, 'new_produits_id': newProduitsId};
    if (prixAjoute != null) fields['prix_ajoute'] = prixAjoute.toString();
    final data = await ApiClient.instance.post('echange_recap', fields: fields);
    if (data is! Map) return EchangeRecap(error: true, message: 'Réponse du serveur invalide.');
    return EchangeRecap.fromJson(Map<String, dynamic>.from(data));
  }

  Future<EchangeResult> valider({
    required String idVentes,
    required String newProduitsId,
    required double prixAjoute,
    required bool isDefaut,
    String? motifReparation,
    required UserModel user,
    required List<PaymentSplit> paiements,
  }) async {
    if (isDefaut && (motifReparation == null || motifReparation.trim().isEmpty)) {
      return EchangeResult(success: false, message: 'Le motif de réparation est obligatoire pour un article retourné avec défaut.');
    }
    final fields = <String, String>{
      'id_ventes': idVentes,
      'new_produits_id': newProduitsId,
      'prix_ajoute': prixAjoute.toString(),
      'isdefaut': isDefaut ? '1' : '0',
      'user': jsonEncode(user.mobPayload),
      'paiements': jsonEncode(paiements.map((p) => p.toJson()).toList()),
    };
    if (motifReparation != null && motifReparation.trim().isNotEmpty) {
      fields['motif_reparation'] = motifReparation.trim();
    }
    final data = await ApiClient.instance.post('echange_valider', fields: fields);
    if (data is! Map) return EchangeResult(success: false, message: 'Réponse du serveur invalide.');
    final error = data['error'] == true;
    return EchangeResult(
      success: !error,
      message: data['msg']?.toString() ?? (error ? "L'échange a échoué." : 'Échange validé avec succès.'),
    );
  }
}
