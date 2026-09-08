import '../core/api_client.dart';
import '../models/facture_model.dart';

/// Factures payées/annulées (`Mob/factures_payees`, `Mob/factures_annulees`,
/// `Mob/facture_detail`) — miroir mobile de `Facture::liste_Factures_Payer`/
/// `liste_Factures_cancel` côté web (voir FactureManage::searchFacturesPayees()/
/// searchFacturesAnnulees()/getFactureDetail(), réutilisées telles quelles).
class FactureService {
  FactureService._();
  static final FactureService instance = FactureService._();

  Future<List<FactureListItem>> loadPayees({String? arg, String? date1, String? date2}) async {
    final data = await ApiClient.instance.post('factures_payees', fields: {
      if (arg != null && arg.trim().isNotEmpty) 'arg': arg.trim(),
      if (date1 != null && date1.isNotEmpty) 'date1': date1,
      if (date2 != null && date2.isNotEmpty) 'date2': date2,
    });
    if (data is! List) return [];
    return data.whereType<Map>().map((e) => FactureListItem.fromJson(Map<String, dynamic>.from(e), dateField: 'dernier_paiement')).toList();
  }

  Future<List<FactureListItem>> loadAnnulees({String? arg, String? date1, String? date2}) async {
    final data = await ApiClient.instance.post('factures_annulees', fields: {
      if (arg != null && arg.trim().isNotEmpty) 'arg': arg.trim(),
      if (date1 != null && date1.isNotEmpty) 'date1': date1,
      if (date2 != null && date2.isNotEmpty) 'date2': date2,
    });
    if (data is! List) return [];
    return data.whereType<Map>().map((e) => FactureListItem.fromJson(Map<String, dynamic>.from(e), dateField: 'date_annulation')).toList();
  }

  Future<FactureDetail> loadDetail(String idClient) async {
    final data = await ApiClient.instance.post('facture_detail', fields: {'id_client': idClient});
    if (data is! Map) return FactureDetail.empty();
    return FactureDetail.fromJson(Map<String, dynamic>.from(data));
  }

  /// Miroir mobile de `Vente/cancel_addition` — réservé patron/gerant
  /// (revalidé côté serveur, voir Mob::cancel_addition()). `motif` alimente
  /// `tracage.motif_trace` (affiché "Défaut" sur les factures annulées) et,
  /// si `mettreEnReparation` est vrai, flague aussi l'article en réparation
  /// (`produits.isreparation_produits`/`motif_reparation_produits`).
  Future<FactureActionResult> cancelArticle({
    required String idVentes,
    required String role,
    String? motif,
    bool mettreEnReparation = false,
  }) async {
    final data = await ApiClient.instance.post('cancel_addition', fields: {
      'id_ventes': idVentes,
      'role': role,
      if (motif != null && motif.trim().isNotEmpty) 'motif': motif.trim(),
      if (mettreEnReparation) 'mettre_en_reparation': '1',
    });
    if (data is! Map) return FactureActionResult(success: false, message: 'Réponse du serveur invalide.');
    final success = data['success'] == true;
    return FactureActionResult(success: success, message: data['message']?.toString());
  }

  /// Modifie le client rattaché à une facture payée (nom/prénom/téléphone/
  /// CIN), ou lui en rattache un nouveau — depuis l'écran "Factures payées",
  /// avant impression (voir Mob::update_client_facture()).
  Future<FactureActionResult> updateClientFacture({
    required String idClient,
    required String nom,
    String? prenom,
    String? telephone,
    String? cin,
    bool nouveau = false,
  }) async {
    final data = await ApiClient.instance.post('update_client_facture', fields: {
      'id_client': idClient,
      'nom': nom,
      if (prenom != null && prenom.trim().isNotEmpty) 'prenom': prenom.trim(),
      if (telephone != null && telephone.trim().isNotEmpty) 'telephone': telephone.trim(),
      if (cin != null && cin.trim().isNotEmpty) 'cin': cin.trim(),
      if (nouveau) 'nouveau': '1',
    });
    if (data is! Map) return FactureActionResult(success: false, message: 'Réponse du serveur invalide.');
    final error = data['error'] == true;
    return FactureActionResult(success: !error, message: data['msg']?.toString());
  }
}

class FactureActionResult {
  FactureActionResult({required this.success, this.message});
  final bool success;
  final String? message;
}
