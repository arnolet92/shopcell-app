import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme.dart';
import '../../models/lookup_model.dart';
import '../../models/payment_split.dart';
import '../../models/receipt_line.dart';
import '../../models/user_model.dart';
import '../../services/app_data_cache.dart';
import '../../services/echange_service.dart';
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

/// Échanges "en réservation" (bouton "Réservez l'échange") : le supplément
/// n'est payé que partiellement, aucun mouvement de stock n'a encore eu
/// lieu — miroir mobile de l'onglet web "Échanges en réservation"
/// (`Echange::reservation_pending()`).
class EchangeReservationListScreen extends StatefulWidget {
  const EchangeReservationListScreen({super.key, required this.user});
  final UserModel user;

  @override
  State<EchangeReservationListScreen> createState() => _EchangeReservationListScreenState();
}

class _EchangeReservationListScreenState extends State<EchangeReservationListScreen> {
  final _searchCtrl = TextEditingController();
  List<EchangeReservationItem> _list = [];
  List<LookupItem> _typesPaiement = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
    VenteService.instance.loadTypesPaiement().then((types) {
      if (!mounted) return;
      setState(() => _typesPaiement = types);
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final list = await EchangeService.instance.loadPendingReservations(arg: _searchCtrl.text);
    if (!mounted) return;
    setState(() {
      _list = list;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDeep,
      appBar: AppBar(
        backgroundColor: AppColors.bgCard,
        elevation: 0,
        title: Text('Échanges en réservation', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 17, color: AppColors.textPrimary)),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: InlineField(
                label: 'Rechercher (client, article, facture)',
                controller: _searchCtrl,
                prefixIcon: Icons.search_rounded,
                onChanged: (_) => _load(),
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accentLight))
                  : _list.isEmpty
                      ? Center(child: Text('Aucun échange en réservation', style: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 13)))
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: ListView.builder(
                            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                            itemCount: _list.length,
                            itemBuilder: (context, i) => _ReservationCard(
                              item: _list[i],
                              user: widget.user,
                              typesPaiement: _typesPaiement,
                              onChanged: _load,
                            ),
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReservationCard extends StatefulWidget {
  const _ReservationCard({required this.item, required this.user, required this.typesPaiement, required this.onChanged});
  final EchangeReservationItem item;
  final UserModel user;
  final List<LookupItem> typesPaiement;
  final VoidCallback onChanged;

  @override
  State<_ReservationCard> createState() => _ReservationCardState();
}

class _ReservationCardState extends State<_ReservationCard> {
  final _sommeCtrl = TextEditingController();
  String? _selectedTypePaiementId;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.typesPaiement.isNotEmpty) _selectedTypePaiementId = widget.typesPaiement.first.id;
  }

  @override
  void dispose() {
    _sommeCtrl.dispose();
    super.dispose();
  }

  Future<void> _payer() async {
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
    final result = await EchangeService.instance.payerReservation(
      idEchangeReservation: widget.item.idEchangeReservation,
      somme: somme,
      idTypePaiement: _selectedTypePaiementId!,
      user: widget.user,
    );
    if (!mounted) return;
    if (result.success) {
      widget.onChanged();
    } else {
      setState(() {
        _submitting = false;
        _error = result.message;
      });
    }
  }

  Future<void> _valider() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.bgCard,
        title: const Text("Valider cet échange ?", style: TextStyle(color: AppColors.textPrimary)),
        content: const Text(
          "Cette action est définitive : l'article repris entrera en stock et le nouvel article en sortira.",
          style: TextStyle(color: AppColors.textSecondary),
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
    final result = await EchangeService.instance.validerReservation(
      idEchangeReservation: widget.item.idEchangeReservation,
      user: widget.user,
    );
    if (!mounted) return;
    if (!result.success) {
      setState(() {
        _submitting = false;
        _error = result.message;
      });
      return;
    }

    AppDataCache.instance.invalidate(CacheDomain.produits);
    AppDataCache.instance.invalidate(CacheDomain.facturesPayees);

    final printMessage = await _imprimerA4(silent: true);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${result.message ?? 'Échange validé avec succès.'} $printMessage')),
    );
    widget.onChanged();
  }

  /// Imprime/partage le reçu A4 de cette réservation, à tout moment (pas
  /// seulement après validation) — filigrane "Échange en réservation",
  /// acompte déjà versé et reste à payer. [silent] : n'affiche pas son
  /// propre snackbar (utilisé quand l'appelant affiche déjà son propre
  /// message, voir _valider()).
  Future<String> _imprimerA4({bool silent = false}) async {
    final item = widget.item;
    // Un appareil par ligne (réservation de plusieurs appareils) ; chaque
    // ligne vaut son supplément, le total = supplément dû.
    final lignes = item.lignes;
    final lines = lignes.isNotEmpty
        ? lignes
            .map((l) => ReceiptLine(
                  designation: l.newDesignation,
                  qte: l.qte,
                  prixUnitaire: l.prixAjoute,
                  total: l.prixAjoute * l.qte,
                  numSerie: l.newNumSerie,
                  imei1: l.newImei1,
                  imei2: l.newImei2,
                  nomModel: l.newNomModel,
                  nomMarque: l.newNomMarque,
                ))
            .toList()
        : [
            ReceiptLine(
              designation: item.newDesignation,
              qte: 1,
              prixUnitaire: item.prixAjoute,
              total: item.prixAjoute,
              numSerie: item.newNumSerie,
              imei1: item.newImei1,
              imei2: item.newImei2,
            ),
          ];
    final retournes = lignes.isNotEmpty
        ? lignes.map((l) => ReceiptLine(designation: l.oldDesignation, qte: l.qte, prixUnitaire: 0, total: 0, nomMarque: l.oldNomMarque)).toList()
        : [ReceiptLine(designation: item.oldDesignation, qte: 1, prixUnitaire: 0, total: 0)];
    // Acomptes ventilés par type de paiement (repli : un total "Acompte").
    final paiements = item.paiementsParType.isNotEmpty
        ? item.paiementsParType.map((e) => PaymentSplit(idTypePaiement: e.key, typeLabel: e.key, montant: e.value)).toList()
        : (item.paye > 0 ? [PaymentSplit(idTypePaiement: '0', typeLabel: 'Acompte', montant: item.paye)] : <PaymentSplit>[]);

    final printMessage = await ReceiptPrintService.instance.offerPrint(
      context,
      lines: lines,
      total: item.prixAjoute,
      cashierName: widget.user.nomComplet,
      clientName: item.clientNomComplet,
      clientPrenom: item.clientPrenom,
      clientTelephone: item.clientTelephone,
      clientCin: item.clientCin,
      numeroFacture: item.numeroFacture,
      isEchange: true,
      isEchangeReservation: true,
      articlesRetournes: retournes,
      paiements: paiements,
    );
    if (!silent && mounted && printMessage.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(printMessage)));
    }
    return printMessage;
  }

  Future<void> _annuler() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.bgCard,
        title: const Text('Annuler cette réservation ?', style: TextStyle(color: AppColors.textPrimary)),
        content: const Text(
          'Les deux articles seront de nouveau disponibles à la vente. Les paiements déjà perçus ne sont pas remboursés automatiquement.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Retour')),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Annuler la réservation', style: TextStyle(color: AppColors.red))),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _submitting = true);
    final result = await EchangeService.instance.annulerReservation(
      idEchangeReservation: widget.item.idEchangeReservation,
      user: widget.user,
    );
    if (!mounted) return;
    if (result.success) {
      widget.onChanged();
    } else {
      setState(() {
        _submitting = false;
        _error = result.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final soldee = item.reste <= 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFA78BFA).withValues(alpha: .35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.clientNomComplet ?? 'Client', style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                    if (item.clientTelephone != null)
                      Text(item.clientTelephone!, style: GoogleFonts.inter(fontSize: 11.5, color: AppColors.textMuted)),
                  ],
                ),
              ),
              IconButton(
                onPressed: _submitting ? null : _imprimerA4,
                icon: const Icon(Icons.print_rounded, color: Color(0xFFA78BFA)),
                tooltip: 'Imprimer reçu A4',
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (item.lignes.isEmpty)
            Text('${item.oldDesignation} → ${item.newDesignation}', style: GoogleFonts.inter(fontSize: 12.5, color: AppColors.textSecondary))
          else
            ...item.lignes.map((l) => Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Row(
                    children: [
                      const Icon(Icons.smartphone_rounded, size: 13, color: AppColors.textSecondary),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text('${l.oldDesignation} → ${l.newDesignation}',
                            style: GoogleFonts.inter(fontSize: 12.5, color: AppColors.textSecondary)),
                      ),
                      Text('+ ${_fmt(l.prixAjoute * l.qte)}', style: GoogleFonts.inter(fontSize: 11.5, color: const Color(0xFFA78BFA))),
                    ],
                  ),
                )),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Supplément dû', style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondary)),
              Text(_fmt(item.prixAjoute), style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Payé', style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondary)),
              Text(_fmt(item.paye), style: GoogleFonts.inter(fontSize: 13, color: AppColors.textPrimary)),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Reste à payer', style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondary)),
              Text(_fmt(item.reste), style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w800, color: soldee ? AppColors.green : AppColors.orange)),
            ],
          ),
          const SizedBox(height: 10),
          if (!soldee) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: InlineField(
                    label: 'Somme donnée (Ar)',
                    controller: _sommeCtrl,
                    prefixIcon: Icons.payments_rounded,
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 8),
                if (widget.typesPaiement.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: DropdownButton<String>(
                      value: _selectedTypePaiementId,
                      dropdownColor: AppColors.bgElevated,
                      items: widget.typesPaiement
                          .map((t) => DropdownMenuItem(value: t.id, child: Text(t.label, style: const TextStyle(color: AppColors.textPrimary, fontSize: 12.5))))
                          .toList(),
                      onChanged: (v) => setState(() => _selectedTypePaiementId = v),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
          ],
          if (_error != null) ...[
            Text(_error!, style: const TextStyle(color: AppColors.red, fontSize: 12)),
            const SizedBox(height: 8),
          ],
          if (soldee)
            GradientButton(
              label: "Valider l'échange",
              icon: Icons.check_circle_rounded,
              loading: _submitting,
              onPressed: _valider,
            )
          else
            GradientButton(
              label: 'Ajouter le paiement',
              icon: Icons.add_circle_rounded,
              loading: _submitting,
              onPressed: _payer,
            ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _submitting ? null : _annuler,
            icon: const Icon(Icons.close_rounded, size: 16, color: AppColors.red),
            label: const Text('Annuler la réservation', style: TextStyle(color: AppColors.red, fontSize: 12.5)),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: AppColors.red),
              padding: const EdgeInsets.symmetric(vertical: 10),
              minimumSize: const Size(double.infinity, 0),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ],
      ),
    );
  }
}
