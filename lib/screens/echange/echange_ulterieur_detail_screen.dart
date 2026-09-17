import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme.dart';
import '../../models/produit_model.dart';
import '../../models/receipt_line.dart';
import '../../models/user_model.dart';
import '../../services/app_data_cache.dart';
import '../../services/echange_service.dart';
import '../../services/receipt_print_service.dart';
import '../../widgets/client_info_dialog.dart';
import '../../widgets/gradient_button.dart';
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

/// "Article vendu ultérieurement" : l'article repris par le client n'a
/// jamais été vendu via ce logiciel (pas de ligne `ventes`, pas de facture,
/// pas de client à retrouver). On saisit juste sa valeur de reprise ("prix
/// actuel de l'article repris") puis on enchaîne sur la même procédure
/// "Article en échange" que l'échange normal. Miroir mobile de
/// `Echange/_ulterieur_detail` (web).
class EchangeUlterieurDetailScreen extends StatefulWidget {
  const EchangeUlterieurDetailScreen({super.key, required this.designation, required this.user});
  final String designation;
  final UserModel user;

  @override
  State<EchangeUlterieurDetailScreen> createState() => _EchangeUlterieurDetailScreenState();
}

class _EchangeUlterieurDetailScreenState extends State<EchangeUlterieurDetailScreen> {
  final _prixActuelReprisCtrl = TextEditingController(text: '0');
  final _produitSearchCtrl = TextEditingController();
  final _prixVenteCtrl = TextEditingController();
  final _motifCtrl = TextEditingController();
  final _batterieCtrl = TextEditingController();
  Timer? _debounceProduit;
  Timer? _debouncePrix;
  List<ProduitModel> _produitResults = [];
  ProduitModel? _selectedProduit;

  bool _isDefaut = false;
  bool _nonUpgrade = false;
  EchangeRecap? _recap;
  bool _recapLoading = false;

  bool _submitting = false;
  bool _proformaSubmitting = false;
  String? _error;

  @override
  void dispose() {
    _prixActuelReprisCtrl.dispose();
    _produitSearchCtrl.dispose();
    _prixVenteCtrl.dispose();
    _motifCtrl.dispose();
    _batterieCtrl.dispose();
    _debounceProduit?.cancel();
    _debouncePrix?.cancel();
    super.dispose();
  }

  void _onProduitSearchChanged(String v) {
    _debounceProduit?.cancel();
    _debounceProduit = Timer(const Duration(milliseconds: 400), () async {
      final results = await EchangeService.instance.searchNewProduit(v);
      if (!mounted) return;
      setState(() => _produitResults = results);
    });
  }

  Future<void> _selectProduit(ProduitModel p) async {
    setState(() {
      _selectedProduit = p;
      _produitResults = [];
      _produitSearchCtrl.clear();
      _prixVenteCtrl.text = p.prixUnitaire.toStringAsFixed(0);
    });
    await _refreshRecap();
  }

  void _onFieldChanged(String _) {
    _debouncePrix?.cancel();
    _debouncePrix = Timer(const Duration(milliseconds: 500), _refreshRecap);
  }

  Future<void> _refreshRecap() async {
    final produit = _selectedProduit;
    if (produit == null) return;
    setState(() => _recapLoading = true);
    final prixActuelRepris = double.tryParse(_prixActuelReprisCtrl.text.replaceAll(' ', '')) ?? 0;
    final prixVente = double.tryParse(_prixVenteCtrl.text.replaceAll(' ', ''));
    final rec = await EchangeService.instance.recapUlterieur(
      designation: widget.designation,
      prixActuelRepris: prixActuelRepris,
      newProduitsId: produit.idProduits,
      prixVente: prixVente,
      nonUpgrade: _nonUpgrade,
    );
    if (!mounted) return;
    setState(() {
      _recap = rec;
      _recapLoading = false;
    });
  }

  Future<void> _confirmAndValider() async {
    final produit = _selectedProduit;
    final rec = _recap;
    if (produit == null || rec == null || rec.error) {
      setState(() => _error = 'Choisissez un article de remplacement.');
      return;
    }
    if (_isDefaut && _motifCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Le motif de réparation est obligatoire.');
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.bgCard,
        title: const Text("Confirmer l'échange ?", style: TextStyle(color: AppColors.textPrimary)),
        content: Text(
          '${widget.designation} → ${rec.newDesignation}\nMontant final : ${_fmt(rec.montantFinal)}',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Annuler')),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Valider', style: TextStyle(color: AppColors.green))),
        ],
      ),
    );
    if (ok != true) return;

    setState(() {
      _submitting = true;
      _error = null;
    });
    final prixActuelRepris = double.tryParse(_prixActuelReprisCtrl.text.replaceAll(' ', '')) ?? 0;
    final prixVente = double.tryParse(_prixVenteCtrl.text.replaceAll(' ', '')) ?? rec.newPrixUnitaire;
    final result = await EchangeService.instance.validerUlterieur(
      designation: widget.designation,
      prixActuelRepris: prixActuelRepris,
      newProduitsId: produit.idProduits,
      prixVente: prixVente,
      isDefaut: _isDefaut,
      motifReparation: _isDefaut ? _motifCtrl.text : null,
      batterie: _isDefaut ? _batterieCtrl.text : null,
      user: widget.user,
      nonUpgrade: _nonUpgrade,
    );
    if (!mounted) return;
    if (result.success) {
      AppDataCache.instance.invalidate(CacheDomain.produits);

      // La description montre l'article REMIS au client (sortie du stock).
      // L'article REPRIS (retourné) est affiché à part sous "Article
      // retourné" — ici juste sa désignation saisie, il n'a pas d'autre
      // détail (N° série, IMEI...) puisqu'il n'existait pas encore dans le
      // logiciel.
      final prixUnitaireTicket = rec.prixAjoute != 0 ? rec.prixAjoute : rec.newPrixUnitaire;
      final lines = [
        ReceiptLine(
          designation: produit.designation,
          qte: 1,
          prixUnitaire: prixUnitaireTicket,
          total: prixUnitaireTicket,
          numSerie: produit.numSerie,
          imei1: produit.imei1,
          imei2: produit.imei2,
          nomModel: produit.nomModel,
          nomMarque: produit.nomMarque,
        ),
      ];
      final articleRetourne = ReceiptLine(
        designation: widget.designation,
        qte: 1,
        prixUnitaire: 0,
        total: 0,
      );

      final clientInfo = await showClientInfoDialog(context);
      if (!mounted) return;

      final printMessage = await ReceiptPrintService.instance.offerPrint(
        context,
        lines: lines,
        total: prixUnitaireTicket,
        cashierName: widget.user.nomComplet,
        clientName: clientInfo?.nom,
        clientPrenom: clientInfo?.prenom,
        clientTelephone: clientInfo?.telephone,
        clientCin: clientInfo?.cin,
        isEchange: true,
        articleRetourne: articleRetourne,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${result.message ?? 'Échange validé avec succès.'} $printMessage')),
      );
    } else {
      setState(() {
        _submitting = false;
        _error = result.message;
      });
    }
  }

  /// Devis non fiscal : imprime/partage le même contenu que le ticket
  /// d'échange, filigrane "PROFORMA" à la place — sans valider l'échange
  /// (rien n'est enregistré côté serveur, `validerUlterieur` n'est pas
  /// appelé).
  Future<void> _imprimerProforma() async {
    final produit = _selectedProduit;
    final rec = _recap;
    if (produit == null || rec == null || rec.error) {
      setState(() => _error = 'Choisissez un article de remplacement.');
      return;
    }
    setState(() => _proformaSubmitting = true);

    final prixUnitaireTicket = rec.prixAjoute != 0 ? rec.prixAjoute : rec.newPrixUnitaire;
    final lines = [
      ReceiptLine(
        designation: produit.designation,
        qte: 1,
        prixUnitaire: prixUnitaireTicket,
        total: prixUnitaireTicket,
        numSerie: produit.numSerie,
        imei1: produit.imei1,
        imei2: produit.imei2,
        nomModel: produit.nomModel,
        nomMarque: produit.nomMarque,
      ),
    ];
    final articleRetourne = ReceiptLine(
      designation: widget.designation,
      qte: 1,
      prixUnitaire: 0,
      total: 0,
    );

    final clientInfo = await showClientInfoDialog(context);
    if (!mounted) return;

    final printMessage = await ReceiptPrintService.instance.offerPrint(
      context,
      lines: lines,
      total: prixUnitaireTicket,
      cashierName: widget.user.nomComplet,
      clientName: clientInfo?.nom,
      clientPrenom: clientInfo?.prenom,
      clientTelephone: clientInfo?.telephone,
      clientCin: clientInfo?.cin,
      isEchange: true,
      isProforma: true,
      articleRetourne: articleRetourne,
    );
    if (!mounted) return;
    setState(() => _proformaSubmitting = false);
    if (printMessage.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(printMessage)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDeep,
      appBar: AppBar(
        backgroundColor: AppColors.bgCard,
        elevation: 0,
        title: Text("Article vendu ultérieurement", style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 16, color: AppColors.textPrimary)),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: AppColors.bgCard, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),
                child: Row(
                  children: [
                    const Icon(Icons.inventory_2_rounded, size: 17, color: AppColors.accentLight),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('Article repris : ${widget.designation}', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 13.5, color: AppColors.textPrimary)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              InlineField(
                label: 'Prix actuel (valeur de reprise, article retourné en stock) (Ar)',
                controller: _prixActuelReprisCtrl,
                prefixIcon: Icons.price_change_rounded,
                keyboardType: TextInputType.number,
                onChanged: _onFieldChanged,
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(color: AppColors.bgElevated, borderRadius: BorderRadius.circular(14)),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Non upgrade', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                          Text('Aucun supplément, prix ajouté = 0', style: GoogleFonts.inter(fontSize: 11, color: AppColors.textMuted)),
                        ],
                      ),
                    ),
                    Switch(
                      value: _nonUpgrade,
                      activeThumbColor: AppColors.accentLight,
                      onChanged: (v) {
                        setState(() => _nonUpgrade = v);
                        _refreshRecap();
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Text('Article en échange', style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
              const SizedBox(height: 8),
              if (_selectedProduit != null) _selectedProduitCard() else _produitSearch(),
              if (_selectedProduit != null) ...[
                const SizedBox(height: 18),
                _prixEtDefautSection(),
                const SizedBox(height: 18),
                if (_recap != null && !_recap!.error)
                  Opacity(opacity: _recapLoading ? 0.5 : 1, child: _recapCard(_recap!))
                else if (_recapLoading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accentLight)),
                  ),
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  Text(_error!, style: const TextStyle(color: AppColors.red, fontSize: 12.5)),
                ],
                const SizedBox(height: 22),
                OutlinedButton.icon(
                  onPressed: (_recap != null && !_recap!.error && !_proformaSubmitting) ? _imprimerProforma : null,
                  icon: _proformaSubmitting
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.textSecondary))
                      : const Icon(Icons.description_outlined, size: 17),
                  label: const Text('Proforma'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textPrimary,
                    side: const BorderSide(color: AppColors.border),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    minimumSize: const Size(double.infinity, 0),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                  ),
                ),
                const SizedBox(height: 10),
                GradientButton(
                  label: "Valider l'échange",
                  icon: Icons.swap_horizontal_circle_rounded,
                  loading: _submitting,
                  onPressed: (_recap != null && !_recap!.error) ? _confirmAndValider : null,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _produitSearch() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InlineField(
          label: 'Rechercher un article en stock',
          controller: _produitSearchCtrl,
          prefixIcon: Icons.inventory_2_rounded,
          onChanged: _onProduitSearchChanged,
        ),
        if (_produitResults.isNotEmpty) ...[
          const SizedBox(height: 10),
          ..._produitResults.take(8).map((p) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => _selectProduit(p),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(color: AppColors.bgElevated, borderRadius: BorderRadius.circular(12)),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(p.designation, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                                if (p.numSerie != null)
                                  Text('S/N: ${p.numSerie}', style: GoogleFonts.inter(fontSize: 11, color: AppColors.textMuted)),
                              ],
                            ),
                          ),
                          Text('${p.prixUnitaire.toStringAsFixed(0)} Ar', style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.green)),
                        ],
                      ),
                    ),
                  ),
                ),
              )),
        ],
      ],
    );
  }

  Widget _selectedProduitCard() {
    final p = _selectedProduit!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(color: AppColors.accentGlow, borderRadius: BorderRadius.circular(14)),
      child: Row(
        children: [
          const Icon(Icons.check_circle_rounded, size: 18, color: AppColors.accentLight),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p.designation, style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                Text('${p.prixUnitaire.toStringAsFixed(0)} Ar', style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondary)),
              ],
            ),
          ),
          GestureDetector(
            onTap: () => setState(() {
              _selectedProduit = null;
              _recap = null;
            }),
            child: const Icon(Icons.close_rounded, size: 18, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }

  Widget _prixEtDefautSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InlineField(
          label: 'Prix de vente (article en échange) (Ar)',
          controller: _prixVenteCtrl,
          prefixIcon: Icons.sell_rounded,
          keyboardType: TextInputType.number,
          onChanged: _onFieldChanged,
        ),
        const SizedBox(height: 14),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(color: AppColors.bgElevated, borderRadius: BorderRadius.circular(14)),
          child: Row(
            children: [
              Text('Prix ajouté', style: GoogleFonts.inter(fontSize: 12.5, color: AppColors.textMuted)),
              const Spacer(),
              Text(
                _fmt(_recap?.prixAjoute ?? 0),
                style: GoogleFonts.inter(fontSize: 14.5, fontWeight: FontWeight.w800, color: AppColors.accentLight),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(color: AppColors.bgElevated, borderRadius: BorderRadius.circular(14)),
          child: Row(
            children: [
              Expanded(
                child: Text('Article retourné avec défaut', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
              ),
              Switch(
                value: _isDefaut,
                activeThumbColor: AppColors.orange,
                onChanged: (v) => setState(() => _isDefaut = v),
              ),
            ],
          ),
        ),
        if (_isDefaut) ...[
          const SizedBox(height: 12),
          InlineField(label: 'Motif de la réparation', controller: _motifCtrl, prefixIcon: Icons.build_rounded),
          const SizedBox(height: 12),
          InlineField(label: "Batterie de l'article retourné", controller: _batterieCtrl, prefixIcon: Icons.battery_full_rounded),
        ],
      ],
    );
  }

  Widget _recapCard(EchangeRecap rec) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.bgElevated, borderRadius: BorderRadius.circular(14)),
      child: Column(
        children: [
          _recapRow('Montant final', _fmt(rec.montantFinal)),
        ],
      ),
    );
  }

  Widget _recapRow(String label, String value, {Color? color}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: GoogleFonts.inter(fontSize: 12.5, color: AppColors.textSecondary)),
        Text(value, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w800, color: color ?? AppColors.textPrimary)),
      ],
    );
  }
}
