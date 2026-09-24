import 'dart:convert';

import '../core/api_client.dart';
import '../models/user_model.dart';

class CreditResult {
  CreditResult({required this.success, this.message});
  final bool success;
  final String? message;
}

/// Client ayant un solde impayé (`Mob/credit_clients`), miroir mobile de
/// `Clients/liste_client_credit`.
class CreditClient {
  CreditClient({
    required this.idPersonnes,
    required this.nomComplet,
    this.prenom,
    this.cin,
    this.telephone,
    this.adresse,
    this.email,
    required this.restant,
  });

  final String idPersonnes;
  final String nomComplet;
  /// Réservations uniquement (voir PaymentScreen) : prénom/CIN saisis à la
  /// création, réutilisés pour imprimer le reçu.
  final String? prenom;
  final String? cin;
  final String? telephone;
  final String? adresse;
  final String? email;
  final double restant;

  factory CreditClient.fromJson(Map<String, dynamic> j) {
    double d(dynamic v) => v == null ? 0 : (v is num ? v.toDouble() : double.tryParse('$v') ?? 0);
    String? s(dynamic v) {
      final t = v?.toString().trim();
      return (t == null || t.isEmpty) ? null : t;
    }

    return CreditClient(
      idPersonnes: '${j['id_personnes'] ?? ''}',
      nomComplet: s(j['nom_complet']) ?? 'Client',
      prenom: s(j['prenom_personnes']),
      cin: s(j['cin_personnes']),
      telephone: s(j['telephone']),
      adresse: s(j['adresse']),
      email: s(j['email']),
      restant: d(j['restant']),
    );
  }
}

/// Une facture à crédit non soldée de ce client.
class CreditFacture {
  CreditFacture({
    required this.idClient,
    this.numeroFacture,
    this.dateVentes,
    required this.montant,
    required this.donnee,
    required this.restant,
  });

  final String idClient;
  final String? numeroFacture;
  final String? dateVentes;
  final double montant;
  final double donnee;
  final double restant;

  factory CreditFacture.fromJson(Map<String, dynamic> j) {
    double d(dynamic v) => v == null ? 0 : (v is num ? v.toDouble() : double.tryParse('$v') ?? 0);
    return CreditFacture(
      idClient: '${j['id_client'] ?? ''}',
      numeroFacture: j['numero_facture']?.toString(),
      dateVentes: j['date_ventes']?.toString(),
      montant: d(j['montant']),
      donnee: d(j['donnee']),
      restant: d(j['restant']),
    );
  }
}

/// Un paiement déjà effectué par ce client, pour un type de paiement donné —
/// toutes ses factures confondues (voir Mob::credit_factures()).
class CreditPaiementLigne {
  CreditPaiementLigne({required this.nomTypePaiement, required this.donnee});
  final String nomTypePaiement;
  final double donnee;

  factory CreditPaiementLigne.fromJson(Map<String, dynamic> j) {
    double d(dynamic v) => v == null ? 0 : (v is num ? v.toDouble() : double.tryParse('$v') ?? 0);
    return CreditPaiementLigne(nomTypePaiement: j['nom_type_paiement']?.toString() ?? '-', donnee: d(j['donnee']));
  }
}

class CreditFacturesDetail {
  CreditFacturesDetail({
    required this.list,
    required this.restant,
    required this.donnee,
    required this.totalWithRemise,
    this.paiements = const [],
  });
  final List<CreditFacture> list;
  final double restant;
  final double donnee;
  final double totalWithRemise;
  /// Paiements déjà effectués, ventilés par type — écran "Réservations".
  final List<CreditPaiementLigne> paiements;
}

/// Paiement d'un crédit client (toutes ses factures impayées, réglées dans
/// l'ordre le plus ancien d'abord) — miroir mobile de
/// `Clients/layout_payementcredit` -> `ClientManage::payedClientCredit()`,
/// réutilisée telle quelle côté serveur (elle acceptait déjà un id_user
/// explicite en plus de la session, voir Mob::credit_pay()).
class CreditService {
  CreditService._();
  static final CreditService instance = CreditService._();

  Future<List<CreditClient>> loadClients() async {
    final data = await ApiClient.instance.post('credit_clients');
    if (data is! List) return [];
    return data.whereType<Map>().map((e) => CreditClient.fromJson(Map<String, dynamic>.from(e))).toList();
  }

  /// Miroir de loadClients(), mais pour les RÉSERVATIONS (client.is_reservation=1)
  /// — voir Mob::reservation_clients().
  Future<List<CreditClient>> loadReservationClients() async {
    final data = await ApiClient.instance.post('reservation_clients');
    if (data is! List) return [];
    return data.whereType<Map>().map((e) => CreditClient.fromJson(Map<String, dynamic>.from(e))).toList();
  }

  Future<CreditFacturesDetail> loadFactures(String idPersonnes) async {
    final data = await ApiClient.instance.post('credit_factures', fields: {'id_personnes': idPersonnes});
    if (data is! Map) return CreditFacturesDetail(list: [], restant: 0, donnee: 0, totalWithRemise: 0);
    double d(dynamic v) => v == null ? 0 : (v is num ? v.toDouble() : double.tryParse('$v') ?? 0);
    final list = (data['list'] is List)
        ? (data['list'] as List).whereType<Map>().map((e) => CreditFacture.fromJson(Map<String, dynamic>.from(e))).toList()
        : <CreditFacture>[];
    final paiements = (data['paiements'] is List)
        ? (data['paiements'] as List).whereType<Map>().map((e) => CreditPaiementLigne.fromJson(Map<String, dynamic>.from(e))).toList()
        : <CreditPaiementLigne>[];
    return CreditFacturesDetail(
      list: list,
      restant: d(data['restant']),
      donnee: d(data['donnee']),
      totalWithRemise: d(data['total_with_remise']),
      paiements: paiements,
    );
  }

  Future<CreditResult> payer({
    required String idPersonnes,
    required String idTypePaiement,
    required double sommeDonnee,
    required UserModel user,
  }) async {
    final data = await ApiClient.instance.post('credit_pay', fields: {
      'id_personnes': idPersonnes,
      'id_type_paiement': idTypePaiement,
      'somme_donnee': sommeDonnee.toString(),
      'user': jsonEncode(user.mobPayload),
    });
    if (data is! Map) return CreditResult(success: false, message: 'Réponse du serveur invalide.');
    final error = data['error'] == true;
    return CreditResult(
      success: !error,
      message: data['msg']?.toString() ?? (error ? 'Le paiement a échoué.' : 'Paiement enregistré avec succès.'),
    );
  }
}
