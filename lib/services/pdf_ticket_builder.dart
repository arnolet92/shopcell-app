import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/receipt_line.dart';

/// Génère le reçu/bon de garantie A4 — calqué sur le modèle papier ShopCell
/// (voir capture fournie par l'utilisateur) : en-tête boutique + bloc
/// facture/client à droite, tableau article (modèle, n° série, capacité,
/// couleur, IMEI 1/2, défaut) avec quantité/prix/montant, puis les mentions
/// de garantie/exclusions/état de la batterie et les zones de signature.
/// Destiné aux imprimantes "bureautiques" (jet d'encre/laser, ex: Canon
/// G3800) pilotées via le système d'impression Android (`printing`), et non
/// en ESC/POS brut comme `TicketBuilder`.
class PdfTicketBuilder {
  static String _money(double v) => '${v.toStringAsFixed(0)} Ar';

  static const _labelStyle = pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold);
  static const _valueStyle = pw.TextStyle(fontSize: 9.5);

  static Future<pw.Document> buildSaleReceiptA4({
    required String shopName,
    String? shopAddress,
    String? shopLieu,
    String? shopNif,
    String? shopStat,
    String? shopPhone,
    String? shopEmail,
    String? logoUrl,
    required List<ReceiptLine> lines,
    required double total,
    String? numeroFacture,
    String? dateFacture,
    String? clientNom,
    String? clientTelephone,
    String? clientCin,
  }) async {
    final doc = pw.Document();

    pw.ImageProvider? logo;
    if (logoUrl != null && logoUrl.trim().isNotEmpty) {
      try {
        final res = await http.get(Uri.parse(logoUrl)).timeout(const Duration(seconds: 5));
        if (res.statusCode == 200) logo = pw.MemoryImage(res.bodyBytes);
      } catch (_) {
        // Pas grave : en-tête sans logo plutôt que de bloquer l'impression.
      }
    }

    final now = DateTime.now();
    final dateStr = dateFacture ??
        '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(26),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            _header(
              shopName: shopName,
              shopAddress: shopAddress,
              shopLieu: shopLieu,
              shopNif: shopNif,
              shopStat: shopStat,
              shopPhone: shopPhone,
              shopEmail: shopEmail,
              logo: logo,
              dateStr: dateStr,
              numeroFacture: numeroFacture,
              clientNom: clientNom,
              clientTelephone: clientTelephone,
              clientCin: clientCin,
            ),
            pw.SizedBox(height: 10),
            _articlesTable(lines: lines, total: total),
            pw.SizedBox(height: 10),
            _garantieEtSignature(),
          ],
        ),
      ),
    );

    return doc;
  }

  static pw.Widget _labelRow(String label, String? value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
      child: pw.Row(
        children: [
          pw.SizedBox(width: 90, child: pw.Text(label, style: _labelStyle)),
          pw.Text(':  ', style: _labelStyle),
          pw.Expanded(child: pw.Text(value ?? '', style: _valueStyle)),
        ],
      ),
    );
  }

  static pw.Widget _header({
    required String shopName,
    String? shopAddress,
    String? shopLieu,
    String? shopNif,
    String? shopStat,
    String? shopPhone,
    String? shopEmail,
    pw.ImageProvider? logo,
    required String dateStr,
    String? numeroFacture,
    String? clientNom,
    String? clientTelephone,
    String? clientCin,
  }) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        // Bloc boutique (logo + coordonnées)
        pw.Expanded(
          flex: 3,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  if (logo != null) ...[
                    pw.Container(width: 40, height: 40, child: pw.Image(logo)),
                    pw.SizedBox(width: 8),
                  ],
                  pw.Text(shopName, style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
                ],
              ),
              pw.SizedBox(height: 4),
              if (shopPhone != null && shopPhone.trim().isNotEmpty)
                pw.Text(shopPhone, style: const pw.TextStyle(fontSize: 9)),
              if (shopAddress != null && shopAddress.trim().isNotEmpty)
                pw.Text('Centre commercial : $shopAddress', style: const pw.TextStyle(fontSize: 9)),
              if (shopLieu != null && shopLieu.trim().isNotEmpty)
                pw.Text(shopLieu, style: const pw.TextStyle(fontSize: 9)),
              if (shopEmail != null && shopEmail.trim().isNotEmpty)
                pw.Text(shopEmail, style: const pw.TextStyle(fontSize: 9)),
              pw.SizedBox(height: 4),
              if (shopNif != null && shopNif.trim().isNotEmpty)
                pw.Text('NIF: $shopNif', style: const pw.TextStyle(fontSize: 8.5)),
              if (shopStat != null && shopStat.trim().isNotEmpty)
                pw.Text('STAT: $shopStat', style: const pw.TextStyle(fontSize: 8.5)),
            ],
          ),
        ),
        pw.SizedBox(width: 16),
        // Bloc facture/client
        pw.Expanded(
          flex: 2,
          child: pw.Container(
            padding: const pw.EdgeInsets.all(8),
            decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.6)),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                _labelRow('Date', dateStr),
                _labelRow('N° Facture', numeroFacture),
                _labelRow('Nom', clientNom),
                _labelRow('Prénom', null),
                _labelRow('N°CIN', clientCin),
                _labelRow('Téléphone', clientTelephone),
              ],
            ),
          ),
        ),
      ],
    );
  }

  static pw.Widget _articlesTable({required List<ReceiptLine> lines, required double total}) {
    pw.Widget cell(String text, {bool bold = false, pw.TextAlign align = pw.TextAlign.left}) => pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: pw.Text(text, style: pw.TextStyle(fontSize: 9.5, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal), textAlign: align),
        );

    final rows = <pw.TableRow>[
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColors.grey300),
        children: [
          cell('DESCRIPTION', bold: true),
          cell('Qté', bold: true, align: pw.TextAlign.center),
          cell('P.U', bold: true, align: pw.TextAlign.right),
          cell('MONTANT', bold: true, align: pw.TextAlign.right),
        ],
      ),
    ];

    for (final line in lines) {
      final champs = <String>[
        'Nom du Modèle     :  ${line.nomModel ?? ''}',
        'N° de SERIE       :  ${line.numSerie ?? ''}',
        'Capacité          :  ${line.nomMarque ?? ''}',
        'Couleur           :  ${line.nomTypePiece ?? ''}',
        'IMEI I            :  ${line.imei1 ?? ''}',
        'IMEI II           :  ${line.imei2 ?? ''}',
        'Défaut            :  ',
      ].join('\n');

      rows.add(pw.TableRow(
        children: [
          pw.Padding(padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4), child: pw.Text(champs, style: const pw.TextStyle(fontSize: 9))),
          cell(line.qte.toStringAsFixed(line.qte == line.qte.roundToDouble() ? 0 : 2), align: pw.TextAlign.center),
          cell(_money(line.prixUnitaire), align: pw.TextAlign.right),
          cell(_money(line.total), align: pw.TextAlign.right),
        ],
      ));
    }

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Table(
          border: pw.TableBorder.all(width: 0.6),
          columnWidths: const {
            0: pw.FlexColumnWidth(6),
            1: pw.FlexColumnWidth(1.2),
            2: pw.FlexColumnWidth(1.6),
            3: pw.FlexColumnWidth(1.8),
          },
          children: rows,
        ),
        pw.Container(
          alignment: pw.Alignment.centerRight,
          padding: const pw.EdgeInsets.only(top: 8, right: 4),
          child: pw.Row(
            mainAxisSize: pw.MainAxisSize.min,
            children: [
              pw.Text('TOTAL   ', style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: PdfColors.red)),
              pw.Text(_money(total), style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
            ],
          ),
        ),
      ],
    );
  }

  static pw.Widget _garantieEtSignature() {
    const small = pw.TextStyle(fontSize: 8);
    const smallBold = pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold);
    pw.Widget puce(String text, {pw.TextStyle style = small}) => pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 1.5),
          child: pw.Text('•  $text', style: style),
        );

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('Notre garantie par smartphone :', style: smallBold),
                  pw.SizedBox(height: 3),
                  puce('1 Ar à 1.000.000 Ar : 1 mois'),
                  puce('1.000.001 Ar à 2.500.000 Ar : 2 mois'),
                  puce('2.500.001 Ar à 4.000.000 Ar : 3 mois'),
                  puce('Plus de 4.000.000 Ar : 6 mois'),
                ],
              ),
            ),
            pw.SizedBox(width: 20),
            pw.Text('Signature ShopCell :', style: smallBold),
          ],
        ),
        pw.SizedBox(height: 10),
        pw.Text('Les exclusions de garantie :', style: smallBold),
        pw.SizedBox(height: 3),
        puce("Stickers arrachés et les accessoires"),
        puce("La modification ou la mise à jour du logiciel d'exploitation (iOS version)"),
        puce("La mauvaise entretien du produit et les dommages dus à une mauvaise utilisation"),
        puce("Le mobile modifié ou réparé par le client lui-même ou par une tierce personne"),
        puce("Dommage ou dysfonctionnement de l'écran"),
        puce("Les dommages dus à une cause extérieure : choc, dégâts des eaux, tension électrique"),
        pw.SizedBox(height: 6),
        pw.Text('nb : Veuillez tester et vérifier votre produit avant de partir', style: smallBold),
        pw.Text(
          "La garantie s'applique à la date d'achat, sous réserve que la panne soit couverte par la garantie. "
          "Tout retour de matériel sera diagnostiqué par notre technicien pour déterminer la cause ou la nature de la panne et réparer si possible.",
          style: small,
        ),
        pw.SizedBox(height: 8),
        pw.Text('État de la batterie :', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.red, decoration: pw.TextDecoration.underline)),
        pw.Text(
          "Pour un iPhone datant d'environ un an ou plus, il est fort probable que la capacité de la batterie soit moins de 90% voire même moins de 80%. "
          "Si elle affiche près de 100%, cela signifie qu'elle a été changée ou boostée (reconditionnée).",
          style: small,
        ),
        pw.Text("Cela ne veut pas dire que l'appareil est mauvais, mais c'est un détail important à connaître avant l'achat.", style: small),
        pw.SizedBox(height: 16),
        pw.Text('Signature du client suivi par (Lu et approuvé) :', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, decoration: pw.TextDecoration.underline)),
      ],
    );
  }
}
