double _d(dynamic v) => v == null ? 0 : (v is num ? v.toDouble() : double.tryParse('$v') ?? 0);
String? _s(dynamic v) {
  final t = v?.toString().trim();
  return (t == null || t.isEmpty) ? null : t;
}

/// Une ligne de la liste "Factures payées" ou "Factures annulées"
/// (`Mob/factures_payees` / `Mob/factures_annulees`) — un client = une
/// carte, même principe que `tab_payed.php`/`tab_cancel.php` côté web.
class FactureListItem {
  FactureListItem({
    required this.idClient,
    required this.numeroFacture,
    this.referenceClient,
    this.nomComplet,
    this.telephone,
    this.nomVisiteur,
    this.prenomVisiteur,
    this.telephoneVisiteur,
    this.caissierPseudo,
    required this.montant,
    this.articlesApercu,
    this.dateReference,
  });

  final String idClient;
  final String numeroFacture;
  final String? referenceClient;
  final String? nomComplet;
  final String? telephone;
  final String? nomVisiteur;
  final String? prenomVisiteur;
  final String? telephoneVisiteur;
  final String? caissierPseudo;
  final double montant;
  final String? articlesApercu;
  /// "Date de paiement" (factures payées) ou "Date d'annulation" (factures
  /// annulées) selon l'endpoint d'origine — même champ, libellé différent
  /// choisi par l'écran appelant.
  final String? dateReference;

  /// Nom à afficher : client enregistré, sinon visiteur de passage — même
  /// repli que `tab_payed.php`/`tab_cancel.php` (`is_null(personnes_id)`).
  String get nomAffiche {
    final complet = _s(nomComplet);
    if (complet != null) return complet;
    final visiteur = [_s(nomVisiteur), _s(prenomVisiteur)].whereType<String>().join(' ').trim();
    return visiteur.isNotEmpty ? visiteur : 'Client';
  }

  String get contactAffiche => _s(telephone) ?? _s(telephoneVisiteur) ?? '-';

  factory FactureListItem.fromJson(Map<String, dynamic> j, {required String dateField}) {
    return FactureListItem(
      idClient: '${j['id_client'] ?? ''}',
      numeroFacture: _s(j['numero_facture']) ?? '-',
      referenceClient: _s(j['reference_client']),
      nomComplet: _s(j['nom_complet']),
      telephone: _s(j['telephone']),
      nomVisiteur: _s(j['nom_visiteur']),
      prenomVisiteur: _s(j['prenom_visiteur']),
      telephoneVisiteur: _s(j['telephone_visiteur']),
      caissierPseudo: _s(j['caissier_pseudo']),
      montant: _d(j['montant']),
      articlesApercu: _s(j['articles_apercu']),
      dateReference: _s(j[dateField]),
    );
  }
}

/// Un article (actif, offert ou annulé) dans le détail d'une facture
/// (`Mob/facture_detail`) — mêmes champs que les cartes de
/// `_facture_detail_row.php`/`_facture_detail_row_cancel.php` côté web.
class FactureDetailArticle {
  FactureDetailArticle({
    required this.designation,
    required this.qte,
    this.numSerie,
    this.imei1,
    this.imei2,
    this.nomModel,
    this.nomLieu,
    this.accompagnement,
    this.prixUnitaire,
    this.montant,
    this.motif,
    this.dateAnnulation,
  });

  final String designation;
  final double qte;
  final String? numSerie;
  final String? imei1;
  final String? imei2;
  final String? nomModel;
  final String? nomLieu;
  final String? accompagnement;
  final double? prixUnitaire;
  final double? montant;
  final String? motif;
  final String? dateAnnulation;

  factory FactureDetailArticle.fromActifJson(Map<String, dynamic> j) => FactureDetailArticle(
        designation: _s(j['designation_unite']) ?? _s(j['designation_produits']) ?? 'Article',
        qte: _d(j['qte']),
        numSerie: _s(j['num_serie']),
        imei1: _s(j['imei1']),
        imei2: _s(j['imei2']),
        nomModel: _s(j['nom_model']),
        nomLieu: _s(j['nom_lieu']),
        accompagnement: _s(j['accompagnement']),
        prixUnitaire: _d(j['prix_ventes']),
        montant: _d(j['total_recette']),
      );

  factory FactureDetailArticle.fromAnnuleJson(Map<String, dynamic> j) => FactureDetailArticle(
        designation: _s(j['designation_produits']) ?? 'Article',
        qte: _d(j['qte_tracage']),
        numSerie: _s(j['num_serie']),
        imei1: _s(j['imei1']),
        imei2: _s(j['imei2']),
        motif: _s(j['motif_trace']),
        dateAnnulation: _s(j['tracage_at']),
      );
}

class FacturePaiementLigne {
  FacturePaiementLigne({required this.nomTypePaiement, required this.montant});
  final String nomTypePaiement;
  final double montant;

  factory FacturePaiementLigne.fromJson(Map<String, dynamic> j) => FacturePaiementLigne(
        nomTypePaiement: _s(j['nom_type_paiement']) ?? '-',
        montant: _d(j['donnee']),
      );
}

/// Détail complet d'une facture (`Mob/facture_detail`) — articles
/// actifs/offerts/annulés + paiements + totaux, même contenu que le
/// panneau "Plus d'information" côté web (`FactureManage::getFactureDetail()`).
class FactureDetail {
  FactureDetail({
    required this.actifs,
    required this.offerts,
    required this.annules,
    required this.paiements,
    required this.totalWithRemise,
    required this.donnee,
    required this.restant,
    required this.rendu,
  });

  final List<FactureDetailArticle> actifs;
  final List<FactureDetailArticle> offerts;
  final List<FactureDetailArticle> annules;
  final List<FacturePaiementLigne> paiements;
  final double totalWithRemise;
  final double donnee;
  final double restant;
  final double rendu;

  factory FactureDetail.fromJson(Map<String, dynamic> j) {
    List<FactureDetailArticle> actifsList(String key) {
      final raw = j[key];
      if (raw is! List) return [];
      return raw.whereType<Map>().map((e) => FactureDetailArticle.fromActifJson(Map<String, dynamic>.from(e))).toList();
    }

    final annulesRaw = j['list_annule'];
    final annules = annulesRaw is List
        ? annulesRaw.whereType<Map>().map((e) => FactureDetailArticle.fromAnnuleJson(Map<String, dynamic>.from(e))).toList()
        : <FactureDetailArticle>[];

    final paiementsRaw = j['info_paiement'];
    final paiements = paiementsRaw is List
        ? paiementsRaw.whereType<Map>().map((e) => FacturePaiementLigne.fromJson(Map<String, dynamic>.from(e))).toList()
        : <FacturePaiementLigne>[];

    return FactureDetail(
      actifs: actifsList('list'),
      offerts: actifsList('list_offert'),
      annules: annules,
      paiements: paiements,
      totalWithRemise: _d(j['total_with_remise']),
      donnee: _d(j['donnee']),
      restant: _d(j['restant']),
      rendu: _d(j['rendu']),
    );
  }

  factory FactureDetail.empty() => FactureDetail(
        actifs: [], offerts: [], annules: [], paiements: [],
        totalWithRemise: 0, donnee: 0, restant: 0, rendu: 0,
      );
}
