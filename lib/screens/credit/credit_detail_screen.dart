import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme.dart';
import '../../models/facture_model.dart';
import '../../models/lookup_model.dart';
import '../../models/payment_split.dart';
import '../../models/receipt_line.dart';
import '../../models/user_model.dart';
import '../../services/app_data_cache.dart';
import '../../services/credit_service.dart';
import '../../services/facture_service.dart';
import '../../services/receipt_print_service.dart';
import '../../services/vente_service.dart';
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

/// Détail des factures à crédit d'un client + paiement — miroir mobile de
/// `Clients/liste_Factures_credits` + `Clients/layout_payementcredit`
/// (`ClientManage::payedClientCredit()`, réutilisée telle quelle côté
/// serveur : le paiement saisi règle les factures impayées de ce client
/// dans l'ordre le plus ancien d'abord, jusqu'à épuisement de la somme).
class CreditDetailScreen extends StatefulWidget {
  const CreditDetailScreen({super.key, required this.client, required this.user, this.isReservation = false});
  final CreditClient client;
  final UserModel user;
  final bool isReservation;

  @override
  State<CreditDetailScreen> createState() => _CreditDetailScreenState();
}

class _CreditDetailScreenState extends State<CreditDetailScreen> {
  bool _loading = true;
  CreditFacturesDetail? _detail;

  List<LookupItem> _typesPaiement = [];
  String? _selectedTypePaiementId;
  final _sommeCtrl = TextEditingController();

  bool _submitting = false;
  String? _printingFactureId;
  String? _error;
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _load();
    VenteService.instance.loadTypesPaiement().then((types) {
      if (!mounted) return;
      setState(() {
        _typesPaiement = types;
        if (types.isNotEmpty) _selectedTypePaiementId = types.first.id;
      });
    });
  }

  @override
  void dispose() {
    _sommeCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final detail = await CreditService.instance.loadFactures(widget.client.idPersonnes);
    if (!mounted) return;
    setState(() {
      _detail = detail;
      _loading = false;
      _sommeCtrl.text = detail.restant > 0 ? detail.restant.toStringAsFixed(0) : '';
    });
  }

  Future<void> _confirmAndPayer() async {
    final somme = double.tryParse(_sommeCtrl.text.replaceAll(' ', ''));
    if (somme == null || somme <= 0) {
      setState(() => _error = 'Entrez une somme donnée valide.');
      return;
    }
    if (_selectedTypePaiementId == null) {
      setState(() => _error = 'Choisissez un mode de paiement.');
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.bgCard,
        title: const Text('Confirmer le paiement ?', style: TextStyle(color: AppColors.textPrimary)),
        content: Text(
          '${widget.client.nomComplet}\nSomme donnée : ${_fmt(somme)}',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Annuler')),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Encaisser', style: TextStyle(color: AppColors.green))),
        ],
      ),
    );
    if (ok != true) return;

    setState(() {
      _submitting = true;
      _error = null;
    });
    final result = await CreditService.instance.payer(
      idPersonnes: widget.client.idPersonnes,
      idTypePaiement: _selectedTypePaiementId!,
      sommeDonnee: somme,
      user: widget.user,
    );
    if (!mounted) return;
    if (result.success) {
      _changed = true;
      if (!widget.isReservation) AppDataCache.instance.invalidate(CacheDomain.creditClients);
      AppDataCache.instance.invalidate(CacheDomain.facturesPayees);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result.message ?? 'Paiement enregistré avec succès.')));
      await _load();
      if (mounted) setState(() => _submitting = false);
    } else {
      setState(() {
        _submitting = false;
        _error = result.message;
      });
    }
  }

  /// Réservations uniquement : imprime/partage le reçu (ticket ou A4) de
  /// CETTE facture précisément — comme un encaissement normal si elle est
  /// entièrement soldée (total seul), ou avec les acomptes déjà versés (par
  /// type, propres à cette facture) et le reste à payer sinon (voir
  /// ReceiptPrintService/PdfTicketBuilder). Utilisé pour le bouton "Imprimer
  /// reçu" et automatiquement après un paiement réussi.
  Future<void> _printReservationFacture(CreditFacture facture) async {
    if (_printingFactureId != null) return;
    setState(() => _printingFactureId = facture.idClient);
    final factureDetail = await FactureService.instance.loadDetail(facture.idClient);
    if (!mounted) return;
    final lines = [...factureDetail.actifs, ...factureDetail.offerts].map(ReceiptLine.fromFactureArticle).toList();
    if (lines.isEmpty) {
      setState(() => _printingFactureId = null);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Aucun article trouvé pour cette réservation.')));
      return;
    }
    final paiements = facture.paiements
        .map((p) => PaymentSplit(idTypePaiement: p.nomTypePaiement, typeLabel: p.nomTypePaiement, montant: p.donnee))
        .toList();
    final message = await ReceiptPrintService.instance.offerPrint(
      context,
      lines: lines,
      total: facture.montant,
      cashierName: widget.user.nomComplet,
      clientName: widget.client.nomComplet,
      clientPrenom: widget.client.prenom,
      clientTelephone: widget.client.telephone,
      clientCin: widget.client.cin,
      paiements: paiements,
      numeroFacture: facture.numeroFacture,
      isReservation: true,
    );
    if (!mounted) return;
    setState(() => _printingFactureId = null);
    if (message.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  /// Paiement d'UNE facture de réservation précise (voir _ReservationFactureCard
  /// ci-dessous) — jamais mélangé avec une autre facture de la même personne.
  /// Recharge la liste puis propose immédiatement l'impression du reçu, comme
  /// après un encaissement normal. Retourne un message d'erreur (affiché
  /// dans la carte) ou null si tout s'est bien passé.
  Future<String?> _payerFacture(CreditFacture facture, String idTypePaiement, double somme) async {
    final result = await CreditService.instance.payerFacture(
      idClient: facture.idClient,
      idTypePaiement: idTypePaiement,
      sommeDonnee: somme,
      user: widget.user,
    );
    if (!mounted) return result.message;
    if (!result.success) return result.message ?? 'Le paiement a échoué.';

    _changed = true;
    AppDataCache.instance.invalidate(CacheDomain.facturesPayees);
    await _load();
    if (!mounted) return null;

    final updated = _detail?.list.where((f) => f.idClient == facture.idClient);
    final factureAImprimer = (updated != null && updated.isNotEmpty) ? updated.first : facture;
    await _printReservationFacture(factureAImprimer);
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final detail = _detail;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) Navigator.of(context).pop(_changed);
      },
      child: Scaffold(
        backgroundColor: AppColors.bgDeep,
        appBar: AppBar(
          backgroundColor: AppColors.bgCard,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () => Navigator.of(context).pop(_changed),
          ),
          title: Text(widget.client.nomComplet, style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 17, color: AppColors.textPrimary)),
        ),
        body: SafeArea(
          child: _loading
              ? const Center(child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accentLight))
              : SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _clientCard(),
                      const SizedBox(height: 20),
                      Text(
                        widget.isReservation ? 'Réservations' : 'Factures impayées',
                        style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: 8),
                      if (detail == null || detail.list.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          child: Center(
                            child: Text(
                              widget.isReservation ? 'Aucune réservation' : 'Aucune facture impayée',
                              style: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 13),
                            ),
                          ),
                        )
                      else if (widget.isReservation)
                        // Chaque réservation est une facture indépendante : son propre
                        // récapitulatif de paiements, son propre formulaire de paiement et
                        // son propre bouton d'impression — jamais mélangée avec une autre
                        // facture du même client ("le paiement est par facture, pas mélangé").
                        ...detail.list.map((f) => _ReservationFactureCard(
                              key: ValueKey(f.idClient),
                              facture: f,
                              typesPaiement: _typesPaiement,
                              printing: _printingFactureId == f.idClient,
                              onPrint: () => _printReservationFacture(f),
                              onPayer: (idTypePaiement, somme) => _payerFacture(f, idTypePaiement, somme),
                            ))
                      else
                        ...detail.list.map(_factureTile),
                      if (!widget.isReservation && detail != null && detail.restant > 0) ...[
                        const SizedBox(height: 22),
                        _paiementSection(detail),
                      ],
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  Widget _clientCard() {
    final c = widget.client;
    final detail = _detail;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.bgCard, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (c.telephone != null) _infoRow(Icons.phone_rounded, c.telephone!),
          if (c.adresse != null) _infoRow(Icons.location_on_rounded, c.adresse!),
          if (c.email != null) _infoRow(Icons.email_rounded, c.email!),
          const Divider(color: AppColors.border, height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Reste à payer', style: GoogleFonts.inter(fontSize: 13, color: AppColors.textSecondary)),
              Text(_fmt(detail?.restant ?? c.restant), style: GoogleFonts.inter(fontSize: 19, fontWeight: FontWeight.w800, color: AppColors.orange)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(icon, size: 15, color: AppColors.textMuted),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: GoogleFonts.inter(fontSize: 12.5, color: AppColors.textSecondary))),
        ],
      ),
    );
  }

  Widget _factureTile(CreditFacture f) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _showFactureDetail(f),
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(color: AppColors.bgCard, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(f.numeroFacture ?? 'Facture', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                    if (f.dateVentes != null)
                      Text(f.dateVentes!, style: GoogleFonts.inter(fontSize: 11, color: AppColors.textMuted)),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('${f.montant.toStringAsFixed(0)} Ar', style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondary)),
                  Text('Reste ${_fmt(f.restant)}', style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w800, color: AppColors.orange)),
                ],
              ),
              const SizedBox(width: 6),
              const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted, size: 18),
            ],
          ),
        ),
      ),
    );
  }

  /// Détail des articles de la facture avant paiement — le web n'affiche
  /// que des totaux ici (`layout_payementcredit_tab.php`), on va plus loin
  /// côté mobile en réutilisant `Mob/facture_detail` (même endpoint que
  /// l'écran "Factures payées").
  void _showFactureDetail(CreditFacture f) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.bgCard,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => FutureBuilder<FactureDetail>(
          future: FactureService.instance.loadDetail(f.idClient),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accentLight));
            }
            final detail = snapshot.data!;
            final articles = [...detail.actifs, ...detail.offerts];
            return ListView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              children: [
                Center(
                  child: Container(width: 36, height: 4, decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2))),
                ),
                const SizedBox(height: 16),
                Text(f.numeroFacture ?? 'Facture', style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                const SizedBox(height: 4),
                Text('Total ${_fmt(detail.totalWithRemise)} · Reste ${_fmt(f.restant)}',
                    style: GoogleFonts.inter(fontSize: 12, color: AppColors.textMuted)),
                const SizedBox(height: 16),
                if (articles.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Center(child: Text('Aucun article', style: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 13))),
                  )
                else
                  ...articles.map((a) => Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(color: AppColors.bgElevated, borderRadius: BorderRadius.circular(12)),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(a.designation, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                                  if (a.numSerie != null)
                                    Text('N° série: ${a.numSerie}', style: GoogleFonts.inter(fontSize: 11, color: AppColors.textMuted)),
                                ],
                              ),
                            ),
                            Text('x${a.qte.toStringAsFixed(a.qte == a.qte.roundToDouble() ? 0 : 2)}',
                                style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondary)),
                            const SizedBox(width: 10),
                            Text(_fmt(a.montant ?? 0), style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.green)),
                          ],
                        ),
                      )),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _paiementSection(CreditFacturesDetail detail) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Paiement', style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
        const SizedBox(height: 8),
        if (_typesPaiement.isNotEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _typesPaiement.map((t) {
              final selected = t.id == _selectedTypePaiementId;
              return ChoiceChip(
                label: Text(t.label, style: TextStyle(fontSize: 12, color: selected ? Colors.white : AppColors.textSecondary)),
                selected: selected,
                selectedColor: AppColors.accent,
                backgroundColor: AppColors.bgElevated,
                onSelected: (_) => setState(() => _selectedTypePaiementId = t.id),
              );
            }).toList(),
          ),
        const SizedBox(height: 12),
        InlineField(
          label: 'Somme donnée (Ar)',
          controller: _sommeCtrl,
          prefixIcon: Icons.payments_rounded,
          keyboardType: TextInputType.number,
          onChanged: (_) => setState(() {}),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: const TextStyle(color: AppColors.red, fontSize: 12.5)),
        ],
        const SizedBox(height: 20),
        GradientButton(label: 'Encaisser', icon: Icons.check_circle_rounded, loading: _submitting, onPressed: _confirmAndPayer),
      ],
    );
  }
}

/// Carte d'une facture de réservation, autonome : ses propres acomptes déjà
/// versés (par type), son propre formulaire de paiement (si non soldée) et
/// son propre bouton d'impression — jamais de champ ou de paiement partagé
/// avec une autre facture du même client.
class _ReservationFactureCard extends StatefulWidget {
  const _ReservationFactureCard({
    super.key,
    required this.facture,
    required this.typesPaiement,
    required this.printing,
    required this.onPrint,
    required this.onPayer,
  });

  final CreditFacture facture;
  final List<LookupItem> typesPaiement;
  final bool printing;
  final VoidCallback onPrint;
  final Future<String?> Function(String idTypePaiement, double somme) onPayer;

  @override
  State<_ReservationFactureCard> createState() => _ReservationFactureCardState();
}

class _ReservationFactureCardState extends State<_ReservationFactureCard> {
  String? _selectedTypePaiementId;
  final _sommeCtrl = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.typesPaiement.isNotEmpty) _selectedTypePaiementId = widget.typesPaiement.first.id;
    if (widget.facture.restant > 0) _sommeCtrl.text = widget.facture.restant.toStringAsFixed(0);
  }

  @override
  void dispose() {
    _sommeCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final somme = double.tryParse(_sommeCtrl.text.replaceAll(' ', ''));
    if (somme == null || somme <= 0) {
      setState(() => _error = 'Entrez une somme donnée valide.');
      return;
    }
    if (_selectedTypePaiementId == null) {
      setState(() => _error = 'Choisissez un mode de paiement.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    final err = await widget.onPayer(_selectedTypePaiementId!, somme);
    if (!mounted) return;
    setState(() {
      _submitting = false;
      _error = err;
    });
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.facture;
    final soldee = f.restant <= 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.bgCard, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(f.numeroFacture ?? 'Facture', style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                    if (f.dateVentes != null)
                      Text(f.dateVentes!, style: GoogleFonts.inter(fontSize: 11, color: AppColors.textMuted)),
                  ],
                ),
              ),
              IconButton(
                onPressed: widget.printing ? null : widget.onPrint,
                tooltip: 'Imprimer reçu',
                icon: widget.printing
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFA78BFA)))
                    : const Icon(Icons.print_rounded, color: Color(0xFFA78BFA)),
              ),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Montant', style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondary)),
              Text(_fmt(f.montant), style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            ],
          ),
          if (f.paiements.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: f.paiements
                  .map((p) => Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(color: AppColors.bgElevated, borderRadius: BorderRadius.circular(8)),
                        child: Text('${p.nomTypePaiement}: ${_fmt(p.donnee)}', style: GoogleFonts.inter(fontSize: 11, color: AppColors.textSecondary)),
                      ))
                  .toList(),
            ),
          ],
          const SizedBox(height: 10),
          if (soldee)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(color: AppColors.green.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.check_circle_rounded, size: 15, color: AppColors.green),
                  const SizedBox(width: 6),
                  Text('Soldée', style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.green)),
                ],
              ),
            )
          else ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Reste à payer', style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondary)),
                Text(_fmt(f.restant), style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.orange)),
              ],
            ),
            const SizedBox(height: 10),
            if (widget.typesPaiement.isNotEmpty)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: widget.typesPaiement.map((t) {
                  final selected = t.id == _selectedTypePaiementId;
                  return ChoiceChip(
                    label: Text(t.label, style: TextStyle(fontSize: 11.5, color: selected ? Colors.white : AppColors.textSecondary)),
                    selected: selected,
                    selectedColor: AppColors.accent,
                    backgroundColor: AppColors.bgElevated,
                    onSelected: (_) => setState(() => _selectedTypePaiementId = t.id),
                  );
                }).toList(),
              ),
            const SizedBox(height: 10),
            InlineField(
              label: 'Somme donnée (Ar)',
              controller: _sommeCtrl,
              prefixIcon: Icons.payments_rounded,
              keyboardType: TextInputType.number,
              onChanged: (_) => setState(() {}),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(color: AppColors.red, fontSize: 12)),
            ],
            const SizedBox(height: 12),
            GradientButton(label: 'Payer', icon: Icons.check_circle_rounded, loading: _submitting, onPressed: _submit),
          ],
        ],
      ),
    );
  }
}
