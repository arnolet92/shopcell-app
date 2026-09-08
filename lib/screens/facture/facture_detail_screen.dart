import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme.dart';
import '../../models/facture_model.dart';
import '../../models/receipt_line.dart';
import '../../models/user_model.dart';
import '../../services/app_data_cache.dart';
import '../../services/facture_service.dart';
import '../../services/receipt_print_service.dart';
import '../../widgets/inline_field.dart';

String _fmt(double v) {
  final s = v.round().toString();
  final buf = StringBuffer();
  for (int i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(' ');
    buf.write(s[i]);
  }
  return '${buf.toString()} Ar';
}

/// Détail d'une facture (payée ou annulée) : articles actifs/offerts/
/// annulés + paiements + totaux — miroir mobile de `_facture_detail_row.php`
/// / `_facture_detail_row_cancel.php` côté web (le panneau "Plus
/// d'information"). En mode payée, patron/gerant peuvent annuler une ligne
/// active/offerte (bouton "Annuler" de `_facture_detail_row.php`) ; le mode
/// annulée reste en lecture seule, comme côté web.
class FactureDetailScreen extends StatefulWidget {
  const FactureDetailScreen({
    super.key,
    required this.idClient,
    required this.numeroFacture,
    required this.mode,
    required this.user,
    this.personnesId,
    this.clientNom,
    this.clientPrenom,
    this.clientTelephone,
    this.clientCin,
    this.dateFacture,
    this.caissierPseudo,
  });
  final String idClient;
  final String numeroFacture;
  final FactureListMode mode;
  final UserModel user;
  /// Renseignés depuis `FactureListItem` (voir `FactureListScreen`), pour
  /// l'en-tête du reçu imprimé — pas de round-trip serveur supplémentaire.
  final String? personnesId;
  final String? clientNom;
  final String? clientPrenom;
  final String? clientTelephone;
  final String? clientCin;
  final String? dateFacture;
  final String? caissierPseudo;

  @override
  State<FactureDetailScreen> createState() => _FactureDetailScreenState();
}

class _FactureDetailScreenState extends State<FactureDetailScreen> {
  FactureDetail? _detail;
  bool _loading = true;
  String? _error;
  bool _changed = false;

  // Infos client modifiables depuis le sheet affiché avant impression
  // (voir _editClientAndPrint) — initialisées depuis ce que la liste a
  // transmis, mises à jour localement après un enregistrement réussi.
  late String? _personnesId = widget.personnesId;
  late String? _clientNom = widget.clientNom;
  late String? _clientPrenom = widget.clientPrenom;
  late String? _clientTelephone = widget.clientTelephone;
  late String? _clientCin = widget.clientCin;

  bool get _peutAnnuler =>
      widget.mode == FactureListMode.payee && (widget.user.role == 'patron' || widget.user.role == 'gerant');

  String? _cancellingIdVentes;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final detail = await FactureService.instance.loadDetail(widget.idClient);
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _confirmCancel(FactureDetailArticle article) async {
    final idVentes = article.idVentes;
    if (idVentes == null) return;
    final result0 = await showModalBottomSheet<_CancelArticleResult>(
      context: context,
      backgroundColor: AppColors.bgCard,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (context) => _CancelArticleSheet(designation: article.designation),
    );
    if (result0 == null) return;

    setState(() => _cancellingIdVentes = idVentes);
    final result = await FactureService.instance.cancelArticle(
      idVentes: idVentes,
      role: widget.user.role,
      motif: result0.motif,
      mettreEnReparation: result0.mettreEnReparation,
    );
    if (!mounted) return;
    setState(() => _cancellingIdVentes = null);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(result.message ?? (result.success ? 'Article annulé.' : 'Échec de l\'annulation.'))),
    );
    if (result.success) {
      _changed = true;
      // L'annulation restocke l'article (et éventuellement le met en
      // réparation) : le cache "Gestion d'article"/Vente doit lui aussi être
      // rafraîchi, pas seulement les factures payées.
      AppDataCache.instance.invalidate(CacheDomain.facturesPayees);
      AppDataCache.instance.invalidate(CacheDomain.produits);
      _load();
    }
  }

  bool _printing = false;

  /// Étape obligatoire avant impression : affiche les infos du client
  /// (nom/prénom/téléphone/CIN) — modifiables, ou remplaçables par un
  /// nouveau client — puis enregistre et lance l'impression.
  Future<void> _editClientAndPrint() async {
    if (_detail == null || _printing) return;
    final saisie = await showModalBottomSheet<_ClientInfoResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.bgCard,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (_) => _ClientInfoSheet(
        nomInitial: _clientNom,
        prenomInitial: _clientPrenom,
        telephoneInitial: _clientTelephone,
        cinInitial: _clientCin,
        aDejaUnClient: _personnesId != null,
      ),
    );
    if (saisie == null || !mounted) return;

    setState(() => _printing = true);
    final result = await FactureService.instance.updateClientFacture(
      idClient: widget.idClient,
      nom: saisie.nom,
      prenom: saisie.prenom,
      telephone: saisie.telephone,
      cin: saisie.cin,
      nouveau: saisie.nouveau || _personnesId == null,
    );
    if (!mounted) return;
    if (!result.success) {
      setState(() => _printing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.message ?? "Impossible d'enregistrer les infos du client.")),
      );
      return;
    }
    setState(() {
      _clientNom = saisie.nom;
      _clientPrenom = saisie.prenom;
      _clientTelephone = saisie.telephone;
      _clientCin = saisie.cin;
      _personnesId ??= 'rattaché'; // un client existe désormais pour cette facture
      _changed = true;
    });
    await _print();
  }

  /// Réimpression d'une facture déjà payée — même système que l'écran
  /// d'encaissement (`PaymentScreen`/`ReceiptPrintService`) : ticket
  /// thermique, PDF A4, ou partage du PDF.
  Future<void> _print() async {
    final lines = [..._detail!.actifs, ..._detail!.offerts].map(ReceiptLine.fromFactureArticle).toList();
    if (lines.isEmpty) {
      setState(() => _printing = false);
      return;
    }
    final message = await ReceiptPrintService.instance.offerPrint(
      context,
      lines: lines,
      total: _detail!.totalWithRemise,
      cashierName: widget.caissierPseudo,
      clientName: _clientNom,
      clientPrenom: _clientPrenom,
      clientTelephone: _clientTelephone,
      clientCin: _clientCin,
      numeroFacture: widget.numeroFacture,
      dateFacture: widget.dateFacture,
      isCopie: true,
    );
    if (!mounted) return;
    setState(() => _printing = false);
    if (message.isEmpty) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        Navigator.of(context).pop(_changed);
      },
      child: Scaffold(
        backgroundColor: AppColors.bgDeep,
        appBar: AppBar(
          backgroundColor: AppColors.bgCard,
          elevation: 0,
          title: Text(widget.numeroFacture, style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 16, color: AppColors.textPrimary)),
          actions: [
            if (_detail != null && (_detail!.actifs.isNotEmpty || _detail!.offerts.isNotEmpty))
              Padding(
                padding: const EdgeInsets.only(right: 14),
                child: _PrintPillButton(loading: _printing, onTap: _editClientAndPrint),
              ),
          ],
        ),
        body: SafeArea(
          child: _loading
              ? const Center(child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accentLight))
              : _error != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(_error!, textAlign: TextAlign.center, style: GoogleFonts.inter(color: AppColors.red, fontSize: 13)),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      color: AppColors.accentLight,
                      backgroundColor: AppColors.bgCard,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                        children: [
                          if (_detail!.actifs.isNotEmpty) ..._section('Articles', Icons.inventory_2_rounded, AppColors.accentLight, _detail!.actifs),
                          if (_detail!.offerts.isNotEmpty) ..._section('Articles offerts', Icons.card_giftcard_rounded, AppColors.green, _detail!.offerts),
                          if (_detail!.annules.isNotEmpty) ..._section('Articles annulés', Icons.block_rounded, AppColors.red, _detail!.annules),
                          if (_detail!.actifs.isEmpty && _detail!.offerts.isEmpty && _detail!.annules.isEmpty)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 24),
                              child: Center(child: Text('Aucun article', style: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 13))),
                            ),
                          const SizedBox(height: 8),
                          _paiementsSection(),
                          const SizedBox(height: 16),
                          _totauxCard(),
                        ],
                      ),
                    ),
        ),
      ),
    );
  }

  List<Widget> _section(String title, IconData icon, Color color, List<FactureDetailArticle> list) {
    return [
      Row(children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(width: 6),
        Text(title.toUpperCase(), style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w800, color: color, letterSpacing: .04)),
      ]),
      const SizedBox(height: 10),
      ...list.map((a) => _ArticleCard(
            article: a,
            onCancel: _peutAnnuler && a.idVentes != null ? () => _confirmCancel(a) : null,
            cancelling: _cancellingIdVentes != null && _cancellingIdVentes == a.idVentes,
          )),
      const SizedBox(height: 16),
    ];
  }

  Widget _paiementsSection() {
    final paiements = _detail!.paiements;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          const Icon(Icons.account_balance_wallet_rounded, size: 15, color: AppColors.blue),
          const SizedBox(width: 6),
          Text('PAIEMENTS', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.blue, letterSpacing: .04)),
        ]),
        const SizedBox(height: 10),
        if (paiements.isEmpty)
          Text('Aucun paiement enregistré', style: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 12.5))
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: paiements
                .map((p) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(color: AppColors.bgCard, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.border)),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(p.nomTypePaiement, style: GoogleFonts.inter(fontSize: 10.5, color: AppColors.textMuted)),
                        Text(_fmt(p.montant), style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                      ]),
                    ))
                .toList(),
          ),
      ],
    );
  }

  Widget _totauxCard() {
    final d = _detail!;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.bgCard, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),
      child: Column(children: [
        _totalRow('Total facture', d.totalWithRemise, AppColors.textPrimary),
        _totalRow('Déjà payé', d.donnee, AppColors.green),
        if (d.restant > 0) _totalRow('Reste à payer', d.restant, AppColors.red),
        if (d.rendu > 0) _totalRow('Rendu', d.rendu, AppColors.orange),
      ]),
    );
  }

  Widget _totalRow(String label, double value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label, style: GoogleFonts.inter(fontSize: 12.5, color: AppColors.textSecondary)),
        Text(_fmt(value), style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w800, color: color)),
      ]),
    );
  }
}

class _ArticleCard extends StatelessWidget {
  const _ArticleCard({required this.article, this.onCancel, this.cancelling = false});
  final FactureDetailArticle article;
  final VoidCallback? onCancel;
  final bool cancelling;

  @override
  Widget build(BuildContext context) {
    final champs = <MapEntry<String, String>>[
      if (article.numSerie != null) MapEntry('N° série', article.numSerie!),
      if (article.nomModel != null) MapEntry('Modèle', article.nomModel!),
      if (article.nomLieu != null) MapEntry('Lieu', article.nomLieu!),
      if (article.imei1 != null) MapEntry('IMEI 1', article.imei1!),
      if (article.imei2 != null) MapEntry('IMEI 2', article.imei2!),
    ];
    final estAnnule = article.motif != null || article.dateAnnulation != null;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: estAnnule ? AppColors.red.withValues(alpha: .35) : AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(child: Text(article.designation, style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w700, color: AppColors.textPrimary))),
            Text('x${article.qte.toStringAsFixed(article.qte == article.qte.roundToDouble() ? 0 : 2)}',
                style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.accentLight)),
          ]),
          if (article.accompagnement != null) ...[
            const SizedBox(height: 4),
            Text(article.accompagnement!, style: GoogleFonts.inter(fontSize: 11.5, color: AppColors.textMuted)),
          ],
          if (champs.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 14,
              runSpacing: 4,
              children: champs
                  .map((c) => RichText(
                        text: TextSpan(
                          style: GoogleFonts.inter(fontSize: 11.5),
                          children: [
                            TextSpan(text: '${c.key}: ', style: const TextStyle(color: AppColors.textMuted)),
                            TextSpan(text: c.value, style: const TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ))
                  .toList(),
            ),
          ],
          const SizedBox(height: 8),
          if (estAnnule) ...[
            if (article.motif != null) Text('Défaut : ${article.motif}', style: GoogleFonts.inter(fontSize: 11.5, color: AppColors.red)),
            if (article.dateAnnulation != null) Text('Annulé le ${article.dateAnnulation}', style: GoogleFonts.inter(fontSize: 11, color: AppColors.textMuted)),
          ] else
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('PU : ${_fmt(article.prixUnitaire ?? 0)}', style: GoogleFonts.inter(fontSize: 11.5, color: AppColors.textMuted)),
              Text(_fmt(article.montant ?? 0), style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.green)),
            ]),
          if (onCancel != null) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: cancelling
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.red))
                  : TextButton.icon(
                      onPressed: onCancel,
                      icon: const Icon(Icons.block_rounded, size: 15, color: AppColors.red),
                      label: Text('Annuler', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.red)),
                      style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                    ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CancelArticleResult {
  _CancelArticleResult({required this.motif, required this.mettreEnReparation});
  final String motif;
  final bool mettreEnReparation;
}

/// Modal affiché avant l'annulation d'un article — miroir mobile de
/// `Vente/annuler_article_modal` côté web : champ Défaut + interrupteur
/// "Mettre en réparation" + bouton "Valider l'annulation".
class _CancelArticleSheet extends StatefulWidget {
  const _CancelArticleSheet({required this.designation});
  final String designation;

  @override
  State<_CancelArticleSheet> createState() => _CancelArticleSheetState();
}

class _CancelArticleSheetState extends State<_CancelArticleSheet> {
  final _motifController = TextEditingController();
  bool _mettreEnReparation = false;

  @override
  void dispose() {
    _motifController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 14, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(4)),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Annuler "${widget.designation}"',
            style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
          ),
          const SizedBox(height: 16),
          Text('Défaut', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
          const SizedBox(height: 6),
          TextField(
            controller: _motifController,
            autofocus: true,
            maxLines: 3,
            style: const TextStyle(color: AppColors.textPrimary),
            decoration: InputDecoration(
              hintText: "Décrire le défaut / la raison de l'annulation...",
              hintStyle: const TextStyle(color: AppColors.textMuted),
              enabledBorder: OutlineInputBorder(borderSide: const BorderSide(color: AppColors.border), borderRadius: BorderRadius.circular(10)),
              focusedBorder: OutlineInputBorder(borderSide: const BorderSide(color: AppColors.borderAccent), borderRadius: BorderRadius.circular(10)),
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(color: AppColors.bgElevated, borderRadius: BorderRadius.circular(10)),
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text("Mettre l'article en réparation", style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
              value: _mettreEnReparation,
              activeThumbColor: AppColors.orange,
              onChanged: (v) => setState(() => _mettreEnReparation = v),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).pop(
                _CancelArticleResult(motif: _motifController.text, mettreEnReparation: _mettreEnReparation),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.red,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text("Valider l'annulation", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Annuler', style: TextStyle(color: AppColors.textSecondary)),
            ),
          ),
        ],
      ),
    );
  }
}

/// Bouton "Imprimer" premium (pilule dégradée) pour l'AppBar du détail
/// facture — remplace l'icône plate par un accent visuel cohérent avec le
/// reste de l'app (`GradientButton`).
class _PrintPillButton extends StatelessWidget {
  const _PrintPillButton({required this.loading, required this.onTap});
  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: loading ? null : onTap,
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            gradient: AppColors.accentGradient,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(color: AppColors.accent.withValues(alpha: 0.35), blurRadius: 12, offset: const Offset(0, 4)),
            ],
          ),
          child: loading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.print_rounded, size: 16, color: Colors.white),
                    const SizedBox(width: 6),
                    Text(
                      'Imprimer',
                      style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _ClientInfoResult {
  _ClientInfoResult({required this.nom, this.prenom, this.telephone, this.cin, required this.nouveau});
  final String nom;
  final String? prenom;
  final String? telephone;
  final String? cin;
  final bool nouveau;
}

/// Affiché avant toute impression depuis "Factures payées" : infos du
/// client (nom/prénom/téléphone/CIN), pré-remplies, modifiables — ou
/// remplaçables par un nouveau client via l'interrupteur dédié.
class _ClientInfoSheet extends StatefulWidget {
  const _ClientInfoSheet({
    this.nomInitial,
    this.prenomInitial,
    this.telephoneInitial,
    this.cinInitial,
    required this.aDejaUnClient,
  });
  final String? nomInitial;
  final String? prenomInitial;
  final String? telephoneInitial;
  final String? cinInitial;
  final bool aDejaUnClient;

  @override
  State<_ClientInfoSheet> createState() => _ClientInfoSheetState();
}

class _ClientInfoSheetState extends State<_ClientInfoSheet> {
  late final _nomCtrl = TextEditingController(text: widget.nomInitial ?? '');
  late final _prenomCtrl = TextEditingController(text: widget.prenomInitial ?? '');
  late final _telephoneCtrl = TextEditingController(text: widget.telephoneInitial ?? '');
  late final _cinCtrl = TextEditingController(text: widget.cinInitial ?? '');
  bool _nouveau = false;

  @override
  void dispose() {
    _nomCtrl.dispose();
    _prenomCtrl.dispose();
    _telephoneCtrl.dispose();
    _cinCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final nom = _nomCtrl.text.trim();
    if (nom.isEmpty) return;
    Navigator.of(context).pop(_ClientInfoResult(
      nom: nom,
      prenom: _prenomCtrl.text.trim().isEmpty ? null : _prenomCtrl.text.trim(),
      telephone: _telephoneCtrl.text.trim().isEmpty ? null : _telephoneCtrl.text.trim(),
      cin: _cinCtrl.text.trim().isEmpty ? null : _cinCtrl.text.trim(),
      nouveau: _nouveau,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 14, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(4)),
              ),
            ),
            const SizedBox(height: 16),
            Text('Informations du client', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
            const SizedBox(height: 4),
            Text(
              'Vérifiez ou complétez avant impression.',
              style: GoogleFonts.inter(fontSize: 12, color: AppColors.textMuted),
            ),
            const SizedBox(height: 16),
            InlineField(label: 'Nom', controller: _nomCtrl, prefixIcon: Icons.badge_rounded),
            const SizedBox(height: 12),
            InlineField(label: 'Prénom', controller: _prenomCtrl, prefixIcon: Icons.person_rounded),
            const SizedBox(height: 12),
            InlineField(label: 'Téléphone', controller: _telephoneCtrl, prefixIcon: Icons.phone_rounded),
            const SizedBox(height: 12),
            InlineField(label: 'N°CIN', controller: _cinCtrl, prefixIcon: Icons.credit_card_rounded),
            if (widget.aDejaUnClient) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(color: AppColors.bgElevated, borderRadius: BorderRadius.circular(10)),
                child: SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('Remplacer par un nouveau client', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                  subtitle: Text(
                    _nouveau ? 'Un nouveau client sera créé et rattaché à cette facture.' : 'Ces informations mettront à jour le client déjà rattaché.',
                    style: GoogleFonts.inter(fontSize: 11, color: AppColors.textMuted),
                  ),
                  value: _nouveau,
                  activeThumbColor: AppColors.accentLight,
                  onChanged: (v) => setState(() => _nouveau = v),
                ),
              ),
            ],
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Enregistrer et imprimer', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Annuler', style: TextStyle(color: AppColors.textSecondary)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
