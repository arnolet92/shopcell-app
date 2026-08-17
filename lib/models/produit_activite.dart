/// Une ligne d'historique d'article (création ou modification), depuis
/// `gestion_produits` (voir `Mob/produit_activites`).
class GestionActivite {
  GestionActivite({
    required this.date,
    required this.designationOld,
    required this.designationNew,
    required this.prixOld,
    required this.prixNew,
    required this.isCreation,
  });

  final DateTime? date;
  final String? designationOld;
  final String? designationNew;
  final double prixOld;
  final double prixNew;
  final bool isCreation;

  factory GestionActivite.fromJson(Map<String, dynamic> json) {
    return GestionActivite(
      date: DateTime.tryParse(json['gestion_produits_at']?.toString() ?? ''),
      designationOld: json['designation_old']?.toString(),
      designationNew: json['designation_update']?.toString(),
      prixOld: double.tryParse('${json['prix_unitaire_old'] ?? 0}') ?? 0,
      prixNew: double.tryParse('${json['prix_unitaire_update'] ?? 0}') ?? 0,
      isCreation: json['type_gestion_produits'] == 'add',
    );
  }
}

/// Une vente de cet article, avec la référence de la facture (`client`
/// côté web = la transaction), pour ouvrir le lien du ticket/facture.
class VenteActivite {
  VenteActivite({required this.date, required this.qte, required this.prixVentes, required this.idClient, required this.numeroFacture});

  final DateTime? date;
  final double qte;
  final double prixVentes;
  final String? idClient;
  final String? numeroFacture;

  factory VenteActivite.fromJson(Map<String, dynamic> json) {
    return VenteActivite(
      date: DateTime.tryParse(json['ventes_at']?.toString() ?? ''),
      qte: double.tryParse('${json['qte'] ?? 0}') ?? 0,
      prixVentes: double.tryParse('${json['prix_ventes'] ?? 0}') ?? 0,
      idClient: json['id_client']?.toString(),
      numeroFacture: (json['numero_factures_client'] as String?)?.trim().isEmpty ?? true
          ? null
          : json['numero_factures_client'] as String?,
    );
  }
}

class ProduitActivites {
  ProduitActivites({required this.creations, required this.modifications, required this.ventes});

  final List<GestionActivite> creations;
  final List<GestionActivite> modifications;
  final List<VenteActivite> ventes;

  factory ProduitActivites.fromJson(Map<String, dynamic> json) {
    List<GestionActivite> parseGestion(String key) {
      final list = json[key];
      if (list is! List) return [];
      return list.whereType<Map>().map((e) => GestionActivite.fromJson(Map<String, dynamic>.from(e))).toList();
    }

    final ventesList = json['ventes'];
    return ProduitActivites(
      creations: parseGestion('creations'),
      modifications: parseGestion('modifications'),
      ventes: ventesList is List
          ? ventesList.whereType<Map>().map((e) => VenteActivite.fromJson(Map<String, dynamic>.from(e))).toList()
          : [],
    );
  }

  factory ProduitActivites.empty() => ProduitActivites(creations: [], modifications: [], ventes: []);
}
