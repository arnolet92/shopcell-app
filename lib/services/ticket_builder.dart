import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';

import '../models/produit_model.dart';
import 'cart_service.dart';

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
    required List<CartLine> lines,
    required double total,
    double? montantDonne,
    String? typePaiementLabel,
    String? clientName,
  }) async {
    final profile = await CapabilityProfile.load();
    final generator = Generator(PaperSize.mm58, profile);
    final now = DateTime.now();
    final bytes = <int>[];

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
    bytes.addAll(generator.text(
      '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year} '
      '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}',
    ));
    bytes.addAll(generator.text('Caissier : $cashierName'));
    if (clientName != null && clientName.trim().isNotEmpty) {
      bytes.addAll(generator.text('Client : $clientName'));
    }
    bytes.addAll(generator.hr());

    for (final line in lines) {
      bytes.addAll(generator.text(line.produit.designation, styles: const PosStyles(bold: true)));
      bytes.addAll(generator.row([
        PosColumn(text: '${line.qte} x ${_money(line.produit.prixUnitaire)}', width: 7),
        PosColumn(text: _money(line.total), width: 5, styles: const PosStyles(align: PosAlign.right)),
      ]));
    }

    bytes.addAll(generator.hr());
    bytes.addAll(generator.row([
      PosColumn(text: 'TOTAL', width: 6, styles: const PosStyles(bold: true)),
      PosColumn(text: _money(total), width: 6, styles: const PosStyles(align: PosAlign.right, bold: true)),
    ]));
    if (montantDonne != null) {
      bytes.addAll(generator.row([
        PosColumn(text: 'Montant donné', width: 6),
        PosColumn(text: _money(montantDonne), width: 6, styles: const PosStyles(align: PosAlign.right)),
      ]));
      bytes.addAll(generator.row([
        PosColumn(text: 'Monnaie', width: 6),
        PosColumn(text: _money(montantDonne - total), width: 6, styles: const PosStyles(align: PosAlign.right)),
      ]));
    }
    if (typePaiementLabel != null) {
      bytes.addAll(generator.text('Paiement : $typePaiementLabel'));
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
