import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';

import '../models/payment_split.dart';
import '../models/produit_model.dart';
import '../models/receipt_line.dart';

/// Génère les tickets ESC/POS (reçu de vente, étiquette QR article) envoyés
/// à `PrinterService`. Papier 58mm par défaut (le format le plus courant
/// pour les petites imprimantes portables WiFi/Bluetooth).
class TicketBuilder {
  static String _money(double v) => '${v.toStringAsFixed(0)} Ar';

  static Future<List<int>> buildSaleReceipt({
    required String shopName,
    String? shopAddress,
    String? shopLieu,
    String? shopNif,
    String? shopStat,
    String? shopRcs,
    String? shopPhone,
    String? shopEmail,
    required String cashierName,
    required List<ReceiptLine> lines,
    required double total,
    List<PaymentSplit>? paiements,
    String? clientName,
    String? clientPrenom,
    String? clientTelephone,
    String? numeroFacture,
    String? dateFacture,
    /// Devis non fiscal (bouton "Proforma") : bandeau "*** PROFORMA ***" en
    /// tête de ticket — pas de filigrane possible en ESC/POS brut.
    bool isProforma = false,
  }) async {
    final profile = await CapabilityProfile.load();
    final generator = Generator(PaperSize.mm58, profile);
    final now = DateTime.now();
    final dateStr = dateFacture ??
        '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year} '
            '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    final bytes = <int>[];

    if (isProforma) {
      bytes.addAll(generator.text('*** PROFORMA ***', styles: const PosStyles(align: PosAlign.center, bold: true)));
    }
    bytes.addAll(generator.text(
      shopName,
      styles: const PosStyles(align: PosAlign.center, bold: true, height: PosTextSize.size2, width: PosTextSize.size2),
    ));
    // Même ordre que application/views/ticket/_entete.php côté web :
    // adresse, lieu, nif, stat, rcs, telephone, email.
    for (final line in [shopAddress, shopLieu, shopNif, shopStat, shopRcs, shopPhone, shopEmail]) {
      if (line != null && line.trim().isNotEmpty) {
        bytes.addAll(generator.text(line, styles: const PosStyles(align: PosAlign.center)));
      }
    }
    bytes.addAll(generator.hr());
    if (numeroFacture != null && numeroFacture.trim().isNotEmpty) {
      bytes.addAll(generator.text('Facture N° : $numeroFacture', styles: const PosStyles(bold: true)));
    }
    bytes.addAll(generator.text(dateStr));
    bytes.addAll(generator.text('Caissier : $cashierName'));
    final clientComplet = [clientName, clientPrenom].where((s) => s != null && s.trim().isNotEmpty).join(' ');
    if (clientComplet.isNotEmpty) {
      bytes.addAll(generator.text('Client : $clientComplet'));
    }
    if (clientTelephone != null && clientTelephone.trim().isNotEmpty) {
      bytes.addAll(generator.text('Tél : $clientTelephone'));
    }
    bytes.addAll(generator.hr());

    for (final line in lines) {
      bytes.addAll(generator.text(line.designation, styles: const PosStyles(bold: true)));
      bytes.addAll(generator.row([
        PosColumn(text: '${line.qte.toStringAsFixed(line.qte == line.qte.roundToDouble() ? 0 : 2)} x ${_money(line.prixUnitaire)}', width: 7),
        PosColumn(text: _money(line.total), width: 5, styles: const PosStyles(align: PosAlign.right)),
      ]));
    }

    bytes.addAll(generator.hr());
    bytes.addAll(generator.row([
      PosColumn(text: 'TOTAL', width: 6, styles: const PosStyles(bold: true)),
      PosColumn(text: _money(total), width: 6, styles: const PosStyles(align: PosAlign.right, bold: true)),
    ]));
    if (paiements != null && paiements.isNotEmpty) {
      final montantDonne = paiements.fold(0.0, (sum, p) => sum + p.montant);
      for (final p in paiements) {
        bytes.addAll(generator.row([
          PosColumn(text: 'Paiement (${p.typeLabel})', width: 7),
          PosColumn(text: _money(p.montant), width: 5, styles: const PosStyles(align: PosAlign.right)),
        ]));
      }
      bytes.addAll(generator.row([
        PosColumn(text: 'Montant donné', width: 6),
        PosColumn(text: _money(montantDonne), width: 6, styles: const PosStyles(align: PosAlign.right)),
      ]));
      // "Rendu" si le client a payé plus que le total (monnaie à lui rendre),
      // "Reste à payer" s'il a payé moins (crédit) — jamais les deux, et
      // jamais un montant négatif affiché comme si c'était de la monnaie.
      final diff = montantDonne - total;
      if (diff > 0.01) {
        bytes.addAll(generator.row([
          PosColumn(text: 'Rendu', width: 6, styles: const PosStyles(bold: true)),
          PosColumn(text: _money(diff), width: 6, styles: const PosStyles(align: PosAlign.right, bold: true)),
        ]));
      } else if (diff < -0.01) {
        bytes.addAll(generator.row([
          PosColumn(text: 'Reste à payer', width: 6, styles: const PosStyles(bold: true)),
          PosColumn(text: _money(-diff), width: 6, styles: const PosStyles(align: PosAlign.right, bold: true)),
        ]));
      }
    }

    bytes.addAll(generator.feed(1));
    bytes.addAll(generator.text('Merci de votre achat !', styles: const PosStyles(align: PosAlign.center, bold: true)));
    bytes.addAll(generator.feed(2));
    bytes.addAll(generator.cut());
    return bytes;
  }

  /// Étiquette QR d'un article : le QR encode `id_produits`, le même
  /// principe que l'écran "Vente par scan QR" côté mobile.
  static Future<List<int>> buildArticleQrLabel(ProduitModel produit) async {
    final profile = await CapabilityProfile.load();
    final generator = Generator(PaperSize.mm58, profile);
    final bytes = <int>[];

    bytes.addAll(generator.text(produit.designation, styles: const PosStyles(align: PosAlign.center, bold: true)));
    if (produit.numSerie != null) {
      bytes.addAll(generator.text('S/N: ${produit.numSerie}', styles: const PosStyles(align: PosAlign.center)));
    }
    bytes.addAll(generator.feed(1));
    bytes.addAll(generator.qrcode(produit.idProduits, size: QRSize.size6));
    bytes.addAll(generator.feed(1));
    bytes.addAll(generator.text('ID: ${produit.idProduits}', styles: const PosStyles(align: PosAlign.center)));
    bytes.addAll(generator.text(_money(produit.prixUnitaire), styles: const PosStyles(align: PosAlign.center, bold: true)));
    bytes.addAll(generator.feed(2));
    bytes.addAll(generator.cut());
    return bytes;
  }
}
