import 'package:flutter/material.dart';
import 'package:pdf/widgets.dart' as pw;

import '../core/api_client.dart';
import '../core/theme.dart';
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
    String? clientTelephone,
    String? clientCin,
    List<PaymentSplit>? paiements,
    String? numeroFacture,
    String? dateFacture,
  }) async {
    final ticketCfg = await PrinterService.instance.config;
    final hasTicket = ticketCfg?.isConfigured ?? false;
    final hasA4 = await PrinterService.instance.isA4Enabled;
    if (!hasTicket && !hasA4) return '';
    if (!context.mounted) return '';

    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.bgCard,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (_) => PrintChoiceSheet(hasTicket: hasTicket, hasA4: hasA4),
    );
    if (choice == null || choice == 'none') return '';

    if (choice == 'ticket') {
      return _printTicket(lines: lines, total: total, cashierName: cashierName, clientName: clientName, paiements: paiements);
    }

    final doc = await _buildA4Doc(
      lines: lines,
      total: total,
      numeroFacture: numeroFacture,
      dateFacture: dateFacture,
      clientNom: clientName,
      clientTelephone: clientTelephone,
      clientCin: clientCin,
    );
    if (choice == 'a4_share') {
      final result = await PrinterService.instance.sharePdf(doc, filename: 'facture_${numeroFacture ?? ''}.pdf');
      return result.success ? '(PDF partagé.)' : (result.message ?? '');
    }
    final result = await PrinterService.instance.printPdf(doc, docName: 'Ticket');
    return result.success ? '(Document A4 envoyé.)' : '(Impression échouée : ${result.message ?? ''})';
  }

  Future<String> _printTicket({
    required List<ReceiptLine> lines,
    required double total,
    String? cashierName,
    String? clientName,
    List<PaymentSplit>? paiements,
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
    String? clientTelephone,
    String? clientCin,
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
      shopEmail: shopInfo['email'],
      logoUrl: logoUrl,
      lines: lines,
      total: total,
      numeroFacture: numeroFacture,
      dateFacture: dateFacture,
      clientNom: clientNom,
      clientTelephone: clientTelephone,
      clientCin: clientCin,
    );
  }
}
