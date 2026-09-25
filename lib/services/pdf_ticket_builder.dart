import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/payment_split.dart';
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
  static String _money(double v) {
    final s = v.round().toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(' ');
      buf.write(s[i]);
    }
    return '${buf.toString()} Ar';
  }

  static String _p2(int n) => n.toString().padLeft(2, '0');

  /// `dateFacture` vient du serveur sous forme de datetime SQL brut
  /// ("2026-09-08 14:23:00") — on le reformate systématiquement en
  /// jour-mois-année plutôt que de l'afficher tel quel.
  static String _formatDateDMY(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      final now = DateTime.now();
      return '${_p2(now.day)}-${_p2(now.month)}-${now.year}';
    }
    final dt = DateTime.tryParse(raw.trim());
    if (dt == null) return raw.trim();
    return '${_p2(dt.day)}-${_p2(dt.month)}-${dt.year}';
  }

  static const _labelStyle = pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold);
  static const _valueStyle = pw.TextStyle(fontSize: 9.5);

  static Future<pw.Document> buildSaleReceiptA4({
    required String shopName,
    String? shopAddress,
    String? shopLieu,
    String? shopNif,
    String? shopStat,
    String? shopPhone,
    String? shopPhone2,
    String? shopPhoneMobile,
    String? shopEmail,
    String? shopFacebook,
    String? shopInstagram,
    String? logoUrl,
    required List<ReceiptLine> lines,
    required double total,
    String? numeroFacture,
    String? dateFacture,
    String? clientNom,
    String? clientPrenom,
    String? clientTelephone,
    String? clientCin,
    /// Réimpression d'une facture déjà payée (`Factures payées`) : affiche
    /// un filigrane diagonal "FACTURE COPIE" pour la distinguer de
    /// l'original imprimé au moment de la vente.
    bool isCopie = false,
    /// Ticket d'un échange : filigrane incliné "Échange" (bas-gauche vers
    /// haut-droite) en premier plan transparent.
    bool isEchange = false,
    /// Devis non fiscal : filigrane "PROFORMA" à la place d'"Échange" (ou
    /// seul, pour une vente) — même document, juste le filigrane qui change.
    bool isProforma = false,
    /// Échange uniquement : l'article REPRIS au client (retourné en stock),
    /// affiché à part en bas de page — la ligne principale du tableau
    /// (`lines`) montre l'article remis au client (sortie du stock), pas
    /// celui-ci.
    ReceiptLine? articleRetourne,
    /// Bouton "Réserver" : filigrane "Reçue" à la place du filigrane normal,
    /// et le pied de page (garantie/exclusions/signature) est entièrement
    /// remplacé par le récapitulatif du paiement (total, acompte par type de
    /// paiement, reste à payer) suivi des conditions de réservation — design
    /// de reçu, pas de facture. En-tête et tableau des articles inchangés.
    bool isReservation = false,
    /// Acomptes versés pour cette réservation, ventilés par type de paiement
    /// — affichés dans le pied de page (voir isReservation ci-dessus).
    List<PaymentSplit>? paiements,
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

    final dateStr = _formatDateDMY(dateFacture);

    // Police Unicode complète (Noto Sans) plutôt que la Helvetica intégrée
    // du PDF, qui ne couvre que le Latin-1 : sur iOS, la saisie transforme
    // souvent les apostrophes/tirets en "smart punctuation" (’ – …) absente
    // de Helvetica, d'où un nom/prénom qui disparaissait silencieusement.
    // Téléchargée puis mise en cache par le paquet `printing` ; repli sur la
    // police par défaut si indisponible (hors ligne au 1er lancement).
    pw.ThemeData? theme;
    try {
      theme = pw.ThemeData.withFont(
        base: await PdfGoogleFonts.notoSansRegular(),
        bold: await PdfGoogleFonts.notoSansBold(),
        italic: await PdfGoogleFonts.notoSansItalic(),
      );
    } catch (_) {
      theme = null;
    }

    // pw.MultiPage (et non pw.Page) : une facture avec beaucoup d'articles
    // (tableau détaillé modèle/série/capacité/couleur/IMEI par ligne) peut
    // dépasser la hauteur d'une page A4 — avec pw.Page (page fixe unique),
    // tout ce qui dépasse est silencieusement coupé (le pied de page avec
    // garantie/signatures disparaissait). pw.MultiPage fait automatiquement
    // déborder le contenu (y compris le tableau lui-même) sur une page
    // suivante plutôt que de le tronquer.
    doc.addPage(
      pw.MultiPage(
        pageTheme: pw.PageTheme(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(26),
          theme: theme,
          buildForeground: (isCopie || isEchange || isProforma || isReservation)
              ? (context) => pw.Stack(
                    children: [
                      if (isProforma)
                        pw.Positioned.fill(child: _proformaWatermark())
                      else if (isReservation)
                        pw.Positioned.fill(child: _reservationWatermark())
                      else if (isEchange)
                        pw.Positioned.fill(child: _echangeWatermark()),
                      if (isCopie) pw.Positioned.fill(child: _copieWatermark()),
                    ],
                  )
              : null,
        ),
        build: (context) => [
          _header(
            shopName: shopName,
            shopAddress: shopAddress,
            shopLieu: shopLieu,
            shopNif: shopNif,
            shopStat: shopStat,
            shopPhone: shopPhone,
            shopPhone2: shopPhone2,
            shopPhoneMobile: shopPhoneMobile,
            shopEmail: shopEmail,
            shopFacebook: shopFacebook,
            shopInstagram: shopInstagram,
            logo: logo,
            dateStr: dateStr,
            numeroFacture: numeroFacture,
            clientNom: clientNom,
            clientPrenom: clientPrenom,
            clientTelephone: clientTelephone,
            clientCin: clientCin,
          ),
          pw.SizedBox(height: 10),
          _articlesTable(lines: lines, total: total),
          if (articleRetourne != null) ...[
            pw.SizedBox(height: 10),
            _articleRetourneSection(articleRetourne),
          ],
          pw.SizedBox(height: 10),
          isReservation ? _reservationFooter(total: total, paiements: paiements) : _garantieEtSignature(),
        ],
      ),
    );

    return doc;
  }

  /// Filigrane diagonal gris "FACTURE COPIE" — affiché en surimpression
  /// discrète (faible opacité) sur toute la page, pour une réimpression
  /// depuis "Factures payées".
  static pw.Widget _copieWatermark() {
    return pw.Center(
      child: pw.Transform.rotate(
        angle: -0.6,
        child: pw.Opacity(
          opacity: 0.16,
          child: pw.Text(
            'FACTURE COPIE',
            style: pw.TextStyle(fontSize: 62, fontWeight: pw.FontWeight.bold, color: PdfColors.grey700, letterSpacing: 4),
          ),
        ),
      ),
    );
  }

  /// Filigrane incliné "Échange" — de bas-gauche vers haut-droite (pente
  /// positive), premier plan transparent, pour tout ticket d'échange.
  static pw.Widget _echangeWatermark() {
    return pw.Center(
      child: pw.Transform.rotate(
        angle: 0.6,
        child: pw.Opacity(
          opacity: 0.18,
          child: pw.Text(
            'Échange',
            style: pw.TextStyle(fontSize: 90, fontWeight: pw.FontWeight.bold, color: PdfColors.blueGrey600, letterSpacing: 6),
          ),
        ),
      ),
    );
  }

  /// Filigrane incliné "PROFORMA" — même orientation qu'"Échange", pour un
  /// devis non fiscal (vente ou échange), à la place du filigrane normal.
  static pw.Widget _proformaWatermark() {
    return pw.Center(
      child: pw.Transform.rotate(
        angle: 0.6,
        child: pw.Opacity(
          opacity: 0.18,
          child: pw.Text(
            'PROFORMA',
            style: pw.TextStyle(fontSize: 80, fontWeight: pw.FontWeight.bold, color: PdfColors.blueGrey600, letterSpacing: 6),
          ),
        ),
      ),
    );
  }

  /// Filigrane incliné "Reçue" — de bas-gauche vers haut-droite, même
  /// orientation qu'"Échange"/"PROFORMA", pour le reçu de réservation
  /// (bouton "Réserver").
  static pw.Widget _reservationWatermark() {
    return pw.Center(
      child: pw.Transform.rotate(
        angle: 0.6,
        child: pw.Opacity(
          opacity: 0.18,
          child: pw.Text(
            'Reçue',
            style: pw.TextStyle(fontSize: 90, fontWeight: pw.FontWeight.bold, color: PdfColor.fromInt(0xFF7C3AED), letterSpacing: 6),
          ),
        ),
      ),
    );
  }

  /// Encadré "Article retourné" (échange uniquement) — affiche l'article
  /// repris au client (retourné en stock) séparément de la ligne principale
  /// du tableau, qui montre l'article remis (sortie du stock).
  static pw.Widget _articleRetourneSection(ReceiptLine article) {
    final details = <String>[];
    if ((article.numSerie ?? '').trim().isNotEmpty) details.add('N° série: ${article.numSerie}');
    if ((article.imei1 ?? '').trim().isNotEmpty) details.add('IMEI1: ${article.imei1}');
    if ((article.imei2 ?? '').trim().isNotEmpty) details.add('IMEI2: ${article.imei2}');
    if ((article.nomModel ?? '').trim().isNotEmpty) details.add('Modèle: ${article.nomModel}');
    if ((article.nomMarque ?? '').trim().isNotEmpty) details.add('Capacité: ${article.nomMarque}');

    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.6, color: PdfColors.grey600), borderRadius: pw.BorderRadius.circular(3)),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('Article retourné :', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9.5)),
          pw.SizedBox(height: 3),
          pw.Text(article.designation, style: const pw.TextStyle(fontSize: 9)),
          if (details.isNotEmpty) ...[
            pw.SizedBox(height: 2),
            pw.Text(details.join(' · '), style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
          ],
        ],
      ),
    );
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

  // Couleurs de marque approximatives (WhatsApp / Facebook), utilisées pour
  // les badges d'icône ci-dessous.
  static final _whatsappGreen = PdfColor.fromInt(0xFF25D366);
  static final _facebookBlue = PdfColor.fromInt(0xFF1877F2);
  static final _instagramPink = PdfColor.fromInt(0xFFC13584);
  static final _phoneBlueGrey = PdfColor.fromInt(0xFF546E7A);

  /// Petit badge rond coloré avec un glyphe blanc (lettre ASCII sûre, un
  /// caractère d'icône dédiée n'étant pas fiable à générer en PDF sans
  /// embarquer une police d'icônes complète) — sert de "vraie icône" pour
  /// WhatsApp/Email/Facebook.
  static pw.Widget _iconBadge({required PdfColor color, required String glyph, double size = 11}) {
    return pw.Container(
      width: size,
      height: size,
      alignment: pw.Alignment.center,
      decoration: pw.BoxDecoration(color: color, shape: pw.BoxShape.circle),
      child: pw.Text(
        glyph,
        style: pw.TextStyle(fontSize: size * 0.55, color: PdfColors.white, fontWeight: pw.FontWeight.bold),
      ),
    );
  }

  /// Badge Instagram (petit "appareil photo" stylisé : carré arrondi rose +
  /// cercle blanc central), entièrement composé de formes vectorielles — pas
  /// de glyphe de police nécessaire.
  static pw.Widget _instagramBadge({double size = 11}) {
    return pw.Container(
      width: size,
      height: size,
      decoration: pw.BoxDecoration(color: _instagramPink, borderRadius: pw.BorderRadius.circular(size * 0.28)),
      child: pw.Center(
        child: pw.Container(
          width: size * 0.5,
          height: size * 0.5,
          decoration: pw.BoxDecoration(shape: pw.BoxShape.circle, border: pw.Border.all(color: PdfColors.white, width: 0.7)),
        ),
      ),
    );
  }

  /// Ligne "icône + valeur" compacte pour les colonnes 1/2 de l'en-tête
  /// (contact boutique) — ex: badge WhatsApp vert + numéro.
  static pw.Widget _iconLine(pw.Widget icon, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 2.5),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          icon,
          pw.SizedBox(width: 4),
          pw.Expanded(child: pw.Text(value, style: const pw.TextStyle(fontSize: 8.5))),
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
    String? shopPhone2,
    String? shopPhoneMobile,
    String? shopEmail,
    String? shopFacebook,
    String? shopInstagram,
    pw.ImageProvider? logo,
    required String dateStr,
    String? numeroFacture,
    String? clientNom,
    String? clientPrenom,
    String? clientTelephone,
    String? clientCin,
  }) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        // Colonne 1 : logo, numéros WhatsApp/mobile, identifiants légaux.
        pw.Expanded(
          flex: 2,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              if (logo != null)
                pw.Container(width: 72, height: 72, child: pw.Image(logo, fit: pw.BoxFit.contain))
              else
                pw.Text(shopName, style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 6),
              if (shopPhone != null && shopPhone.trim().isNotEmpty)
                _iconLine(_iconBadge(color: _whatsappGreen, glyph: 'W'), shopPhone),
              if (shopPhone2 != null && shopPhone2.trim().isNotEmpty)
                _iconLine(_iconBadge(color: _whatsappGreen, glyph: 'W'), shopPhone2),
              if (shopPhoneMobile != null && shopPhoneMobile.trim().isNotEmpty)
                _iconLine(_iconBadge(color: _phoneBlueGrey, glyph: 'T'), shopPhoneMobile),
              pw.SizedBox(height: 4),
              if (shopNif != null && shopNif.trim().isNotEmpty)
                pw.Text('NIF: $shopNif', style: const pw.TextStyle(fontSize: 8.5)),
              if (shopStat != null && shopStat.trim().isNotEmpty)
                pw.Text('STAT: $shopStat', style: const pw.TextStyle(fontSize: 8.5)),
            ],
          ),
        ),
        pw.SizedBox(width: 10),
        // Colonne 2 : centre commercial / adresse / email / réseaux sociaux.
        pw.Expanded(
          flex: 2,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(shopName, style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 2),
              if (shopAddress != null && shopAddress.trim().isNotEmpty)
                pw.Text('Centre commercial : $shopAddress', style: const pw.TextStyle(fontSize: 8.5)),
              if (shopLieu != null && shopLieu.trim().isNotEmpty)
                pw.Text(shopLieu, style: const pw.TextStyle(fontSize: 8.5)),
              pw.SizedBox(height: 4),
              if (shopEmail != null && shopEmail.trim().isNotEmpty)
                _iconLine(_iconBadge(color: PdfColors.grey700, glyph: '@'), shopEmail),
              if (shopFacebook != null && shopFacebook.trim().isNotEmpty)
                _iconLine(_iconBadge(color: _facebookBlue, glyph: 'f'), shopFacebook),
              if (shopInstagram != null && shopInstagram.trim().isNotEmpty)
                _iconLine(_instagramBadge(), shopInstagram),
            ],
          ),
        ),
        pw.SizedBox(width: 10),
        // Colonne 3 : facture/client (inchangée).
        pw.Expanded(
          flex: 3,
          child: pw.Container(
            padding: const pw.EdgeInsets.all(8),
            decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.6)),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                _labelRow('Date', dateStr),
                _labelRow('N° Facture', numeroFacture),
                _labelRow('Nom', clientNom),
                _labelRow('Prénom', clientPrenom),
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
          padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 3),
          child: pw.Text(text, style: pw.TextStyle(fontSize: 9, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal), textAlign: align),
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
      // Seules les valeurs réellement renseignées sont affichées — une
      // ligne "N° de SERIE :" vide sur chaque article gaspillait du papier.
      // Regroupées deux par deux (côte à côte) plutôt qu'une par ligne, pour
      // ne pas occuper trop de hauteur dans la colonne description.
      const champStyle = pw.TextStyle(fontSize: 8);
      final paires = <List<String>>[
        ['N° du modèle', line.nomModel ?? ''],
        ['N° de série', line.numSerie ?? ''],
        ['Capacité', line.nomMarque ?? ''],
        ['Couleur', line.nomTypePiece ?? ''],
        ['IMEI 1', line.imei1 ?? ''],
        ['IMEI 2', line.imei2 ?? ''],
      ].where((p) => p[1].trim().isNotEmpty).toList();

      final descLines = <pw.Widget>[
        pw.Text(line.designation, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
      ];
      for (var i = 0; i < paires.length; i += 2) {
        final rowChildren = <pw.Widget>[
          pw.Expanded(child: pw.Text('${paires[i][0]} : ${paires[i][1]}', style: champStyle)),
        ];
        if (i + 1 < paires.length) {
          rowChildren.add(pw.SizedBox(width: 8));
          rowChildren.add(pw.Expanded(child: pw.Text('${paires[i + 1][0]} : ${paires[i + 1][1]}', style: champStyle)));
        }
        descLines.add(pw.Padding(
          padding: const pw.EdgeInsets.only(top: 1.5),
          child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: rowChildren),
        ));
      }

      rows.add(pw.TableRow(
        children: [
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 3),
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: descLines),
          ),
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
            0: pw.FlexColumnWidth(6.5),
            1: pw.FlexColumnWidth(0.8),
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

  /// Pied de page du reçu de réservation (bouton "Réserver") : récapitulatif
  /// du paiement (total, acompte par type de paiement, reste à payer) puis
  /// les conditions de réservation — remplace entièrement la garantie/les
  /// exclusions/la signature d'une facture normale. En-tête et tableau des
  /// articles restent ceux d'une facture classique (voir buildSaleReceiptA4).
  static pw.Widget _reservationFooter({required double total, List<PaymentSplit>? paiements}) {
    const small = pw.TextStyle(fontSize: 8);
    const smallBold = pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold);
    final splits = paiements ?? const <PaymentSplit>[];
    final acompte = splits.fold(0.0, (sum, p) => sum + p.montant);
    final reste = total - acompte;

    pw.Widget row(String label, String value, {bool bold = false, PdfColor? color}) => pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 2),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(label, style: pw.TextStyle(fontSize: 9.5, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal, color: color)),
              pw.Text(value, style: pw.TextStyle(fontSize: 9.5, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal, color: color)),
            ],
          ),
        );

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.all(10),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(width: 0.6, color: PdfColor.fromInt(0xFF7C3AED)),
            borderRadius: pw.BorderRadius.circular(4),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('RÉCAPITULATIF DU PAIEMENT', style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold, color: PdfColor.fromInt(0xFF7C3AED))),
              pw.SizedBox(height: 6),
              // Paiement total, sans reste : comme un encaissement normal, on
              // n'affiche que le montant total (pas d'acomptes ni de reste à
              // zéro qui n'apportent plus d'information utile).
              if (reste <= 0)
                row('Total', _money(total), bold: true)
              else ...[
                row('Total', _money(total)),
                if (splits.isEmpty)
                  row('Acompte versé', _money(acompte))
                else
                  for (final p in splits) row('Acompte (${p.typeLabel})', _money(p.montant)),
                pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 3), child: pw.Divider(height: 1, thickness: 0.5)),
                row('Reste à payer', _money(reste), bold: true, color: PdfColors.red),
              ],
            ],
          ),
        ),
        pw.SizedBox(height: 12),
        pw.Text('CONDITIONS DE RÉSERVATION', style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold, decoration: pw.TextDecoration.underline)),
        pw.SizedBox(height: 6),
        pw.Text('1. Réservation avec délai de 7 jours', style: smallBold),
        pw.SizedBox(height: 2),
        pw.Text(
          "La réservation est valable pour une durée maximale de 7 jours à compter de la date du versement de l'acompte. "
          "En cas d'annulation par le client avant l'expiration des 7 jours, une retenue de 10 % de la valeur totale du téléphone sera appliquée. "
          "Le solde éventuel de l'acompte pourra être remboursé. "
          "Au-delà du délai de 7 jours, la réservation sera automatiquement annulée et la totalité de l'acompte versé sera non remboursable.",
          style: small,
        ),
        pw.SizedBox(height: 8),
        pw.Text('2. Réservation sans limite de date', style: smallBold),
        pw.SizedBox(height: 2),
        pw.Text(
          "Pour une réservation sans limite de date, le client devra choisir un téléphone disponible dont la valeur correspond au montant total de l'acompte versé. "
          "L'acompte versé est non remboursable en aucun cas. Il pourra uniquement être utilisé pour l'acquisition d'un téléphone disponible correspondant au montant versé.",
          style: small,
        ),
      ],
    );
  }

  static pw.Widget _garantieEtSignature() {
    const small = pw.TextStyle(fontSize: 8);
    const smallBold = pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold);
    // Point dessiné en vectoriel (petit disque) plutôt que le caractère "•" :
    // ce glyphe n'est pas garanti par la police PDF par défaut et s'affichait
    // comme un carré barré d'une croix (glyphe manquant) sur certains
    // lecteurs/imprimantes.
    pw.Widget puce(String text, {pw.TextStyle style = small}) => pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 2),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Padding(
                padding: const pw.EdgeInsets.only(top: 3.2, right: 5),
                child: pw.Container(width: 2.6, height: 2.6, decoration: const pw.BoxDecoration(shape: pw.BoxShape.circle, color: PdfColors.black)),
              ),
              pw.Expanded(child: pw.Text(text, style: style)),
            ],
          ),
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
        puce("Pourcentage de la batterie ( capacité Maximum )"),
        puce("Les accessoires fournis (chargeur, câble, écouteurs, coque, etc.)"),
        pw.SizedBox(height: 6),
        pw.Text('nb : Veuillez tester et vérifier votre produit avant de partir', style: smallBold),
        pw.Text(
          "La garantie s'applique à la date d'achat, sous réserve que la panne soit couverte par la garantie. "
          "Tout retour de matériel sera diagnostiqué par notre technicien pour déterminer la cause ou la nature de la panne et réparer si possible.",
          style: small,
        ),
        pw.SizedBox(height: 8),
        pw.Text('ÉTAT DE LA BATTERIE (CAPACITÉ MAXIMUM, EXCLUSION DE GARANTIE) :', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.red, decoration: pw.TextDecoration.underline)),
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
