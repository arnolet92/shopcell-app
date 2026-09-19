import 'package:flutter/widgets.dart';

import '../models/receipt_line.dart';
import '../models/user_model.dart';
import '../widgets/client_info_dialog.dart';
import 'receipt_print_service.dart';

/// Impression (ticket thermique / A4 / partage PDF) d'un échange archivé, à
/// partir de sa ligne JSON (`Mob/echange_historique`, ou une ligne "Échange"
/// de `Mob/factures_payees` — mêmes champs old_*/new_*). Partagé entre
/// l'historique d'échange et la liste des factures payées, pour que les deux
/// impriment exactement le même document.
///
/// La ligne principale est l'article REMIS au client (sortie du stock) ;
/// l'article RETOURNÉ (repris) figure en bas sous "Article retourné".
/// Retourne le message à afficher (vide si tout va bien).
Future<String> printEchangeFromJson(
  BuildContext context,
  Map<String, dynamic> j, {
  required UserModel user,
  String? numeroFacture,
}) async {
  String? s(dynamic v) {
    final t = v?.toString().trim();
    return (t == null || t.isEmpty) ? null : t;
  }

  double d(dynamic v) => v == null ? 0 : (v is num ? v.toDouble() : double.tryParse('$v') ?? 0);

  final prixAjoute = d(j['prix_ajoute']);
  final newPrixUnitaire = d(j['new_prix_unitaire']);
  final prixUnitaireTicket = prixAjoute != 0 ? prixAjoute : newPrixUnitaire;

  final lines = [
    ReceiptLine(
      designation: s(j['new_designation']) ?? 'Article',
      qte: 1,
      prixUnitaire: prixUnitaireTicket,
      total: prixUnitaireTicket,
      numSerie: s(j['new_num_serie']),
      imei1: s(j['new_imei1']),
      imei2: s(j['new_imei2']),
      nomModel: s(j['new_nom_model']),
      nomMarque: s(j['new_nom_marque']),
    ),
  ];
  final articleRetourne = ReceiptLine(
    designation: s(j['old_designation']) ?? 'Article',
    qte: 1,
    prixUnitaire: 0,
    total: 0,
    numSerie: s(j['old_num_serie']),
    imei1: s(j['old_imei1']),
    imei2: s(j['old_imei2']),
    nomModel: s(j['old_nom_model']),
    nomMarque: s(j['old_nom_marque']),
  );

  final clientInfo = await showClientInfoDialog(
    context,
    initialNom: s(j['client_nom_complet']),
    initialPrenom: s(j['client_prenom']),
    initialTelephone: s(j['client_telephone']),
    initialCin: s(j['client_cin']),
  );
  if (!context.mounted) return '';

  return ReceiptPrintService.instance.offerPrint(
    context,
    lines: lines,
    total: prixUnitaireTicket,
    cashierName: user.nomComplet,
    clientName: clientInfo?.nom,
    clientPrenom: clientInfo?.prenom,
    clientTelephone: clientInfo?.telephone,
    clientCin: clientInfo?.cin,
    numeroFacture: numeroFacture,
    dateFacture: s(j['echange_at_raw']) ?? s(j['echange_at']),
    isEchange: true,
    articleRetourne: articleRetourne,
  );
}
