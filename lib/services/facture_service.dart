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
  /// (revalidé côté serveur, voir Mob::cancel_addition()).
  Future<FactureActionResult> cancelArticle({required String idVentes, required String role}) async {
    final data = await ApiClient.instance.post('cancel_addition', fields: {
      'id_ventes': idVentes,
      'role': role,
    });
    if (data is! Map) return FactureActionResult(success: false, message: 'Réponse du serveur invalide.');
    final success = data['success'] == true;
    return FactureActionResult(success: success, message: data['message']?.toString());
  }
}

class FactureActionResult {
  FactureActionResult({required this.success, this.message});
  final bool success;
  final String? message;
}
