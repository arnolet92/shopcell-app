import 'package:flutter/material.dart';
import 'package:pdf/widgets.dart' as pw;

import '../core/api_client.dart';
import '../models/payment_split.dart';
import '../models/receipt_line.dart';
import '../widgets/print_choice_sheet.dart';
import 'pdf_ticket_builder.dart';
import 'printer_service.dart';
import 'ticket_builder.dart';
import 'vente_service.dart';

/// Orchestration partagée de l'impression d'un reçu (ticket ESC/POS ou PDF
/// A4) — propose le choix parmi les moyens configurés (voir
/// `PrinterSettingsScreen`), puis génère et envoie le document. Utilisé par
/// l'écran d'encaissement (`PaymentScreen`) et par le détail d'une facture
/// déjà payée (`FactureDetailScreen`, réimpression) : "même système que la
/// vente".
class ReceiptPrintService {
  ReceiptPrintService._();
  static final ReceiptPrintService instance = ReceiptPrintService._();

  /// Retourne un message court à afficher (snackbar), ou une chaîne vide si
  /// rien n'a été imprimé (aucun moyen configuré, ou "Ne pas imprimer").
  Future<String> offerPrint(
    BuildContext context, {
    required List<ReceiptLine> lines,
    required double total,
    String? cashierName,
    String? clientName,
    String? clientPrenom,
    String? clientTelephone,
    String? clientCin,
    List<PaymentSplit>? paiements,
    String? numeroFacture,
    String? dateFacture,
    /// Réimpression d'une facture déjà payée : ajoute le filigrane
    /// "FACTURE COPIE" sur le PDF A4 (sans effet sur le ticket thermique).
    bool isCopie = false,
    /// Ticket d'un échange : filigrane "Échange" sur le PDF A4.
    bool isEchange = false,
    /// Devis non fiscal (bouton "Proforma" de l'encaissement vente/échange) :
    /// même contenu, filigrane "PROFORMA" (PDF A4) ou mention "PROFORMA"
    /// (ticket thermique) à la place du filigrane normal.
    bool isProforma = false,
    /// Échange uniquement : l'article repris au client (retourné en stock),
    /// affiché à part en bas du PDF A4 — la ligne principale (`lines`)
    /// montre l'article remis au client (sortie du stock).
    ReceiptLine? articleRetourne,
    /// Bouton "Réserver" : filigrane "Reçue" + pied de page "reçu de
    /// réservation" (récapitulatif du paiement + conditions de réservation)
    /// à la place du pied de page facture habituel — voir PdfTicketBuilder.
    bool isReservation = false,
  }) async {
    final ticketCfg = await PrinterService.instance.config;
    final hasTicket = ticketCfg?.isConfigured ?? false;
    final hasA4 = await PrinterService.instance.isA4Enabled;
    // On ne coupe plus court quand rien n'est configuré : l'option "Ticket
    // thermique" est toujours proposée (au tap, message vers Paramètres).
    if (!context.mounted) return '';

    final choice = await showPrintChoiceSheet(context, hasTicket: hasTicket, hasA4: hasA4);
    if (choice == null || choice == 'none') return '';

    // La fermeture du bottom sheet (route pop) doit être totalement retombée
    // avant de déclencher une action native (intent de partage/impression
    // Android) : sur certains appareils, lancer l'intent trop tôt pendant la
    // transition de fermeture le fait échouer silencieusement (l'appel
    // renvoie quand même un succès côté plugin).
    await Future.delayed(const Duration(milliseconds: 300));

    if (choice == 'ticket') {
      return _printTicket(
        lines: lines,
        total: total,
        cashierName: cashierName,
        clientName: clientName,
        clientPrenom: clientPrenom,
        clientTelephone: clientTelephone,
        paiements: paiements,
        numeroFacture: numeroFacture,
        dateFacture: dateFacture,
        isProforma: isProforma,
      );
    }

    try {
      final doc = await _buildA4Doc(
        lines: lines,
        total: total,
        numeroFacture: numeroFacture,
        dateFacture: dateFacture,
        clientNom: clientName,
        clientPrenom: clientPrenom,
        clientTelephone: clientTelephone,
        clientCin: clientCin,
        isCopie: isCopie,
        isEchange: isEchange,
        isProforma: isProforma,
        articleRetourne: articleRetourne,
        isReservation: isReservation,
        paiements: paiements,
      );
      if (choice == 'a4_share') {
        final result = await PrinterService.instance.sharePdf(doc, filename: 'facture_${numeroFacture ?? ''}.pdf');
        return result.success ? '(PDF partagé.)' : (result.message ?? '(Partage du PDF impossible.)');
      }
      final result = await PrinterService.instance.printPdf(doc, docName: 'Ticket');
      return result.success ? '(Document A4 envoyé.)' : '(Impression échouée : ${result.message ?? ''})';
    } catch (e) {
      return '(Impression A4 impossible : $e)';
    }
  }

  Future<String> _printTicket({
    required List<ReceiptLine> lines,
    required double total,
    String? cashierName,
    String? clientName,
    String? clientPrenom,
    String? clientTelephone,
    List<PaymentSplit>? paiements,
    String? numeroFacture,
    String? dateFacture,
    bool isProforma = false,
  }) async {
    try {
      final shopInfo = await VenteService.instance.loadShopInfo();
      final bytes = await TicketBuilder.buildSaleReceipt(
        shopName: shopInfo['appellation']?.isNotEmpty == true ? shopInfo['appellation']! : 'ShopCell',
        shopAddress: shopInfo['adresse'],
        shopLieu: shopInfo['lieu'],
        shopNif: shopInfo['nif'],
        shopStat: shopInfo['stat'],
        shopRcs: shopInfo['rcs'],
        shopPhone: shopInfo['telephone'],
        shopEmail: shopInfo['email'],
        cashierName: cashierName ?? '-',
        lines: lines,
        total: total,
        paiements: paiements,
        clientName: clientName,
        clientPrenom: clientPrenom,
        clientTelephone: clientTelephone,
        numeroFacture: numeroFacture,
        dateFacture: dateFacture,
        isProforma: isProforma,
      );
      final result = await PrinterService.instance.printBytes(bytes);
      return result.success ? '(Ticket imprimé.)' : '(Impression échouée : ${result.message ?? 'imprimante non configurée'})';
    } catch (_) {
      return '(Impression du ticket impossible.)';
    }
  }

  Future<pw.Document> _buildA4Doc({
    required List<ReceiptLine> lines,
    required double total,
    String? numeroFacture,
    String? dateFacture,
    String? clientNom,
    String? clientPrenom,
    String? clientTelephone,
    String? clientCin,
    bool isCopie = false,
    bool isEchange = false,
    bool isProforma = false,
    ReceiptLine? articleRetourne,
    bool isReservation = false,
    List<PaymentSplit>? paiements,
  }) async {
    final shopInfo = await VenteService.instance.loadShopInfo();
    final baseUrl = await ApiClient.instance.baseUrl;
    final logo = shopInfo['logo'];
    final logoUrl = (baseUrl != null && logo != null) ? '${baseUrl.replaceAll(RegExp(r'/+$'), '')}/uploads/logo/$logo' : null;
    return PdfTicketBuilder.buildSaleReceiptA4(
      shopName: shopInfo['appellation']?.isNotEmpty == true ? shopInfo['appellation']! : 'ShopCell',
      shopAddress: shopInfo['adresse'],
      shopLieu: shopInfo['lieu'],
      shopNif: shopInfo['nif'],
      shopStat: shopInfo['stat'],
      shopPhone: shopInfo['telephone'],
      shopPhone2: shopInfo['whatsapp2'],
      shopPhoneMobile: shopInfo['telephoneMobile'],
      shopEmail: shopInfo['email'],
      shopFacebook: shopInfo['facebook'],
      shopInstagram: shopInfo['instagram'],
      logoUrl: logoUrl,
      lines: lines,
      total: total,
      numeroFacture: numeroFacture,
      dateFacture: dateFacture,
      clientNom: clientNom,
      clientPrenom: clientPrenom,
      clientTelephone: clientTelephone,
      clientCin: clientCin,
      isCopie: isCopie,
      isEchange: isEchange,
      isProforma: isProforma,
      articleRetourne: articleRetourne,
      isReservation: isReservation,
      paiements: paiements,
    );
  }
}
