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
    this.newPrixUnitaire = 0,
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
  /// "Prix de vente" du produit qui sort de stock — modifiable, par défaut
  /// son prix catalogue.
  final double newPrixUnitaire;
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
      newPrixUnitaire: d(j['new_prix_unitaire']),
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
/// Un échange archivé (`Mob/echange_historique`) — pour l'historique et la
/// ré-impression du ticket d'échange.
class EchangeHistoItem {
  EchangeHistoItem({
    required this.idEchange,
    required this.numeroFacture,
    required this.dateGest,
    required this.dateRaw,
    required this.oldDesignation,
    required this.newDesignation,
    required this.prixAjoute,
    required this.montantFinal,
    required this.isAnnule,
    required this.raw,
  });

  final String idEchange;
  final String numeroFacture;
  final String dateGest;
  final String? dateRaw;
  final String oldDesignation;
  final String newDesignation;
  final double prixAjoute;
  final double montantFinal;
  final bool isAnnule;

  /// Ligne JSON brute — sert directement à construire le ticket d'échange
  /// (voir `EchangeHistoriqueScreen`), sans second aller-retour serveur.
  final Map<String, dynamic> raw;

  static double _d(dynamic v) => v == null ? 0 : (v is num ? v.toDouble() : double.tryParse('$v') ?? 0);
  static String? _s(dynamic v) {
    final t = v?.toString().trim();
    return (t == null || t.isEmpty) ? null : t;
  }

  factory EchangeHistoItem.fromJson(Map<String, dynamic> j) {
    return EchangeHistoItem(
      idEchange: '${j['id_echange'] ?? ''}',
      numeroFacture: _s(j['numero_factures_client']) ?? _s(j['numero_facture_echange']) ?? 'F/${j['client_id'] ?? ''}',
      dateGest: _s(j['date_echange_gest']) ?? '',
      dateRaw: _s(j['echange_at_raw']) ?? _s(j['echange_at']),
      oldDesignation: _s(j['old_designation']) ?? '-',
      newDesignation: _s(j['new_designation']) ?? '-',
      prixAjoute: _d(j['prix_ajoute']),
      montantFinal: _d(j['montant_final']),
      isAnnule: '${j['isannule'] ?? '0'}' == '1',
      raw: j,
    );
  }
}

/// Un échange "en réservation" (`Mob/echange_reservation_list`) : le
/// supplément n'est payé que partiellement — aucun mouvement de stock n'a
/// encore eu lieu, les deux articles sont juste verrouillés côté serveur
/// jusqu'à validation ou annulation. Miroir mobile de l'onglet web
/// "Échanges en réservation" (`Echange::reservation_pending()`).
class EchangeReservationItem {
  EchangeReservationItem({
    required this.idEchangeReservation,
    required this.clientNomComplet,
    required this.clientPrenom,
    required this.clientCin,
    required this.clientTelephone,
    required this.oldDesignation,
    required this.oldNumSerie,
    required this.oldImei1,
    required this.oldImei2,
    required this.newDesignation,
    required this.newNumSerie,
    required this.newImei1,
    required this.newImei2,
    required this.montantFinal,
    required this.prixAjoute,
    required this.paye,
    required this.reste,
    required this.reservationAt,
    required this.numeroFacture,
  });

  final String idEchangeReservation;
  final String? clientNomComplet;
  final String? clientPrenom;
  final String? clientCin;
  final String? clientTelephone;
  final String oldDesignation;
  final String? oldNumSerie;
  final String? oldImei1;
  final String? oldImei2;
  final String newDesignation;
  final String? newNumSerie;
  final String? newImei1;
  final String? newImei2;
  final double montantFinal;
  final double prixAjoute;
  final double paye;
  final double reste;
  final String? reservationAt;
  final String? numeroFacture;

  factory EchangeReservationItem.fromJson(Map<String, dynamic> j) {
    double d(dynamic v) => v == null ? 0 : (v is num ? v.toDouble() : double.tryParse('$v') ?? 0);
    String? s(dynamic v) {
      final t = v?.toString().trim();
      return (t == null || t.isEmpty) ? null : t;
    }

    return EchangeReservationItem(
      idEchangeReservation: '${j['id_echange_reservation'] ?? ''}',
      clientNomComplet: s(j['client_nom_complet']),
      clientPrenom: s(j['client_prenom']),
      clientCin: s(j['client_cin']),
      clientTelephone: s(j['client_telephone']),
      oldDesignation: s(j['old_designation']) ?? '-',
      oldNumSerie: s(j['old_num_serie']),
      oldImei1: s(j['old_imei1']),
      oldImei2: s(j['old_imei2']),
      newDesignation: s(j['new_designation']) ?? '-',
      newNumSerie: s(j['new_num_serie']),
      newImei1: s(j['new_imei1']),
      newImei2: s(j['new_imei2']),
      montantFinal: d(j['montant_final']),
      prixAjoute: d(j['prix_ajoute']),
      paye: d(j['paye']),
      reste: d(j['reste']),
      reservationAt: s(j['reservation_at']),
      numeroFacture: s(j['numero_facture_echange']),
    );
  }
}

class EchangeService {
  EchangeService._();
  static final EchangeService instance = EchangeService._();

  /// Historique des échanges archivés sur une période.
  Future<List<EchangeHistoItem>> historique({String? arg, String? date1, String? date2}) async {
    final data = await ApiClient.instance.post('echange_historique', fields: {
      if (arg != null && arg.trim().isNotEmpty) 'arg': arg.trim(),
      if (date1 != null && date1.isNotEmpty) 'date1': date1,
      if (date2 != null && date2.isNotEmpty) 'date2': date2,
    });
    if (data is! List) return [];
    return data.whereType<Map>().map((e) => EchangeHistoItem.fromJson(Map<String, dynamic>.from(e))).toList();
  }

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

  /// [prixVente] : "prix de vente" (modifiable) du produit qui sort de
  /// stock — par défaut son prix catalogue si non fourni. "Prix ajouté"
  /// n'est plus un paramètre : il est recalculé côté serveur.
  /// [prixActuelRepris] : "Prix actuel" (modifiable), valeur de reprise de
  /// l'article RETOURNÉ — par défaut le prix auquel il a été vendu à
  /// l'origine si non fourni.
  /// [nonUpgrade] : force le prix ajouté à 0 côté serveur, quel que soit
  /// le prix affiché (article repris de valeur équivalente).
  Future<EchangeRecap> recap({
    required String idVentes,
    required String newProduitsId,
    double? prixVente,
    double? prixActuelRepris,
    bool nonUpgrade = false,
  }) async {
    final fields = <String, String>{'id_ventes': idVentes, 'new_produits_id': newProduitsId, 'non_upgrade': nonUpgrade ? '1' : '0'};
    if (prixVente != null) fields['prix_vente'] = prixVente.toString();
    if (prixActuelRepris != null) fields['prix_actuel_repris'] = prixActuelRepris.toString();
    final data = await ApiClient.instance.post('echange_recap', fields: fields);
    if (data is! Map) return EchangeRecap(error: true, message: 'Réponse du serveur invalide.');
    return EchangeRecap.fromJson(Map<String, dynamic>.from(data));
  }

  Future<EchangeResult> valider({
    required String idVentes,
    required String newProduitsId,
    required double prixVente,
    double? prixActuelRepris,
    required bool isDefaut,
    String? motifReparation,
    String? batterie,
    required UserModel user,
    required List<PaymentSplit> paiements,
    bool nonUpgrade = false,
  }) async {
    if (isDefaut && (motifReparation == null || motifReparation.trim().isEmpty)) {
      return EchangeResult(success: false, message: 'Le motif de réparation est obligatoire pour un article retourné avec défaut.');
    }
    final fields = <String, String>{
      'id_ventes': idVentes,
      'new_produits_id': newProduitsId,
      'prix_vente': prixVente.toString(),
      'isdefaut': isDefaut ? '1' : '0',
      'non_upgrade': nonUpgrade ? '1' : '0',
      'user': jsonEncode(user.mobPayload),
      'paiements': jsonEncode(paiements.map((p) => p.toJson()).toList()),
    };
    if (prixActuelRepris != null) fields['prix_actuel_repris'] = prixActuelRepris.toString();
    if (motifReparation != null && motifReparation.trim().isNotEmpty) {
      fields['motif_reparation'] = motifReparation.trim();
    }
    if (batterie != null && batterie.trim().isNotEmpty) {
      fields['batterie'] = batterie.trim();
    }
    final data = await ApiClient.instance.post('echange_valider', fields: fields);
    if (data is! Map) return EchangeResult(success: false, message: 'Réponse du serveur invalide.');
    final error = data['error'] == true;
    return EchangeResult(
      success: !error,
      message: data['msg']?.toString() ?? (error ? "L'échange a échoué." : 'Échange validé avec succès.'),
    );
  }

  /// "Article vendu ultérieurement" : autocomplétion des désignations déjà
  /// connues dans `produits`, pour aider à saisir le nom de l'article repris
  /// (jamais vendu via ce logiciel, donc introuvable par `searchVentes`).
  Future<List<String>> searchDesignations(String arg) async {
    if (arg.trim().isEmpty) return [];
    final data = await ApiClient.instance.post('echange_search_designations', fields: {'arg': arg});
    if (data is! List) return [];
    return data.whereType<Map>().map((e) => e['designation_produits']?.toString() ?? '').where((s) => s.isNotEmpty).toList();
  }

  Future<EchangeRecap> recapUlterieur({
    required String designation,
    required double prixActuelRepris,
    required String newProduitsId,
    double? prixVente,
    bool nonUpgrade = false,
  }) async {
    final fields = <String, String>{
      'designation': designation,
      'prix_actuel_repris': prixActuelRepris.toString(),
      'new_produits_id': newProduitsId,
      'non_upgrade': nonUpgrade ? '1' : '0',
    };
    if (prixVente != null) fields['prix_vente'] = prixVente.toString();
    final data = await ApiClient.instance.post('echange_ulterieur_recap', fields: fields);
    if (data is! Map) return EchangeRecap(error: true, message: 'Réponse du serveur invalide.');
    return EchangeRecap.fromJson(Map<String, dynamic>.from(data));
  }

  Future<EchangeResult> validerUlterieur({
    required String designation,
    required double prixActuelRepris,
    required String newProduitsId,
    required double prixVente,
    required bool isDefaut,
    String? motifReparation,
    String? batterie,
    required UserModel user,
    bool nonUpgrade = false,
  }) async {
    if (isDefaut && (motifReparation == null || motifReparation.trim().isEmpty)) {
      return EchangeResult(success: false, message: 'Le motif de réparation est obligatoire pour un article retourné avec défaut.');
    }
    final fields = <String, String>{
      'designation': designation,
      'prix_actuel_repris': prixActuelRepris.toString(),
      'new_produits_id': newProduitsId,
      'prix_vente': prixVente.toString(),
      'isdefaut': isDefaut ? '1' : '0',
      'non_upgrade': nonUpgrade ? '1' : '0',
      'user': jsonEncode(user.mobPayload),
    };
    if (motifReparation != null && motifReparation.trim().isNotEmpty) {
      fields['motif_reparation'] = motifReparation.trim();
    }
    if (batterie != null && batterie.trim().isNotEmpty) {
      fields['batterie'] = batterie.trim();
    }
    final data = await ApiClient.instance.post('echange_ulterieur_valider', fields: fields);
    if (data is! Map) return EchangeResult(success: false, message: 'Réponse du serveur invalide.');
    final error = data['error'] == true;
    return EchangeResult(
      success: !error,
      message: data['msg']?.toString() ?? (error ? "L'échange a échoué." : 'Échange validé avec succès.'),
    );
  }

  /// "Réservez l'échange" : même principe que valider(), mais quand le
  /// supplément n'est payé que partiellement — aucun mouvement de stock,
  /// coordonnées client obligatoires (nom/prénom/téléphone/CIN).
  Future<EchangeResult> reserver({
    required String idVentes,
    required String newProduitsId,
    required double prixVente,
    double? prixActuelRepris,
    required bool isDefaut,
    String? motifReparation,
    String? batterie,
    required UserModel user,
    required List<PaymentSplit> paiements,
    bool nonUpgrade = false,
    required String nomComplet,
    required String prenom,
    required String telephone,
    required String cin,
  }) async {
    if (isDefaut && (motifReparation == null || motifReparation.trim().isEmpty)) {
      return EchangeResult(success: false, message: 'Le motif de réparation est obligatoire pour un article retourné avec défaut.');
    }
    if (nomComplet.trim().isEmpty) {
      return EchangeResult(success: false, message: 'Le nom du client est obligatoire pour réserver cet échange.');
    }
    final fields = <String, String>{
      'id_ventes': idVentes,
      'new_produits_id': newProduitsId,
      'prix_vente': prixVente.toString(),
      'isdefaut': isDefaut ? '1' : '0',
      'non_upgrade': nonUpgrade ? '1' : '0',
      'user': jsonEncode(user.mobPayload),
      'paiements': jsonEncode(paiements.map((p) => p.toJson()).toList()),
      'nom_complet': nomComplet.trim(),
      'prenom_personnes': prenom.trim(),
      'telephone': telephone.trim(),
      'cin_personnes': cin.trim(),
    };
    if (prixActuelRepris != null) fields['prix_actuel_repris'] = prixActuelRepris.toString();
    if (motifReparation != null && motifReparation.trim().isNotEmpty) {
      fields['motif_reparation'] = motifReparation.trim();
    }
    if (batterie != null && batterie.trim().isNotEmpty) {
      fields['batterie'] = batterie.trim();
    }
    final data = await ApiClient.instance.post('echange_reserver', fields: fields);
    if (data is! Map) return EchangeResult(success: false, message: 'Réponse du serveur invalide.');
    final error = data['error'] == true;
    return EchangeResult(
      success: !error,
      message: data['msg']?.toString() ?? (error ? "La réservation a échoué." : 'Échange réservé avec succès.'),
    );
  }

  /// Liste des échanges en réservation (ni validés, ni annulés) — écran
  /// mobile "Échanges en réservation".
  Future<List<EchangeReservationItem>> loadPendingReservations({String? arg}) async {
    final data = await ApiClient.instance.post('echange_reservation_list', fields: {
      if (arg != null && arg.trim().isNotEmpty) 'arg': arg.trim(),
    });
    if (data is! List) return [];
    return data.whereType<Map>().map((e) => EchangeReservationItem.fromJson(Map<String, dynamic>.from(e))).toList();
  }

  /// Ajoute un paiement à une réservation déjà créée, sans la valider.
  Future<EchangeResult> payerReservation({
    required String idEchangeReservation,
    required double somme,
    required String idTypePaiement,
    required UserModel user,
  }) async {
    final data = await ApiClient.instance.post('echange_payer_reservation', fields: {
      'id_echange_reservation': idEchangeReservation,
      'somme_donnee': somme.toString(),
      'id_type_paiement': idTypePaiement,
      'user': jsonEncode(user.mobPayload),
    });
    if (data is! Map) return EchangeResult(success: false, message: 'Réponse du serveur invalide.');
    final error = data['error'] == true;
    return EchangeResult(
      success: !error,
      message: data['msg']?.toString() ?? (error ? 'Le paiement a échoué.' : 'Paiement enregistré avec succès.'),
    );
  }

  /// Validation d'une réservation (reste à 0) : mêmes mouvements de stock
  /// que valider(), déclenchés à partir des données figées à la réservation.
  Future<EchangeResult> validerReservation({
    required String idEchangeReservation,
    required UserModel user,
  }) async {
    final data = await ApiClient.instance.post('echange_valider_reservation', fields: {
      'id_echange_reservation': idEchangeReservation,
      'user': jsonEncode(user.mobPayload),
    });
    if (data is! Map) return EchangeResult(success: false, message: 'Réponse du serveur invalide.');
    final error = data['error'] == true;
    return EchangeResult(
      success: !error,
      message: data['msg']?.toString() ?? (error ? "L'échange a échoué." : 'Échange validé avec succès.'),
    );
  }

  /// Annulation d'une réservation (avant validation) : aucun mouvement de
  /// stock à défaire, déverrouille juste les deux articles.
  Future<EchangeResult> annulerReservation({
    required String idEchangeReservation,
    required UserModel user,
  }) async {
    final data = await ApiClient.instance.post('echange_annuler_reservation', fields: {
      'id_echange_reservation': idEchangeReservation,
      'user': jsonEncode(user.mobPayload),
    });
    if (data is! Map) return EchangeResult(success: false, message: 'Réponse du serveur invalide.');
    final error = data['error'] == true;
    return EchangeResult(
      success: !error,
      message: data['msg']?.toString() ?? (error ? "L'annulation a échoué." : 'Réservation annulée.'),
    );
  }
}
