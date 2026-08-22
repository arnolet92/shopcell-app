import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme.dart';
import '../../models/facture_model.dart';
import '../../services/facture_service.dart';

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
/// d'information"). Aucune action d'annulation ici : le mobile n'a pas de
/// fonctionnalité d'annulation d'article, ce détail est en lecture seule
/// pour les deux modes (payée / annulée) — pas besoin de dupliquer l'écran.
class FactureDetailScreen extends StatefulWidget {
  const FactureDetailScreen({super.key, required this.idClient, required this.numeroFacture});
  final String idClient;
  final String numeroFacture;

  @override
  State<FactureDetailScreen> createState() => _FactureDetailScreenState();
}

class _FactureDetailScreenState extends State<FactureDetailScreen> {
  FactureDetail? _detail;
  bool _loading = true;
  String? _error;

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDeep,
      appBar: AppBar(
        backgroundColor: AppColors.bgCard,
        elevation: 0,
        title: Text(widget.numeroFacture, style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 16, color: AppColors.textPrimary)),
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
      ...list.map((a) => _ArticleCard(article: a)),
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
  const _ArticleCard({required this.article});
  final FactureDetailArticle article;

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
            if (article.motif != null) Text('Motif : ${article.motif}', style: GoogleFonts.inter(fontSize: 11.5, color: AppColors.red)),
            if (article.dateAnnulation != null) Text('Annulé le ${article.dateAnnulation}', style: GoogleFonts.inter(fontSize: 11, color: AppColors.textMuted)),
          ] else
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('PU : ${_fmt(article.prixUnitaire ?? 0)}', style: GoogleFonts.inter(fontSize: 11.5, color: AppColors.textMuted)),
              Text(_fmt(article.montant ?? 0), style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.green)),
            ]),
        ],
      ),
    );
  }
}
