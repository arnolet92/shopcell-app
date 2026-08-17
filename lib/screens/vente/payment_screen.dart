import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme.dart';
import '../../models/lookup_model.dart';
import '../../models/payment_split.dart';
import '../../models/personne_model.dart';
import '../../models/user_model.dart';
import '../../services/cart_service.dart';
import '../../services/printer_service.dart';
import '../../services/ticket_builder.dart';
import '../../services/vente_service.dart';
import '../../widgets/gradient_button.dart';
import '../../widgets/inline_field.dart';

String _fmtMoney(double v) {
  final s = v.round().toString();
  final buf = StringBuffer();
  for (int i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(' ');
    buf.write(s[i]);
  }
  return '${buf.toString()} Ar';
}

/// Écran de paiement, ouvert depuis "Encaisser" (Panier) : recherche client,
/// choix du type de paiement (espèces -> somme donnée + rendue automatique),
/// possibilité de scinder en plusieurs paiements, puis "Valider" avec
/// confirmation et impression du ticket.
class PaymentScreen extends StatefulWidget {
  const PaymentScreen({super.key, required this.user});
  final UserModel user;

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  final _clientSearchCtrl = TextEditingController();
  final _montantCtrl = TextEditingController();

  List<PersonneModel> _clients = [];
  PersonneModel? _selectedClient;
  List<LookupItem> _typesPaiement = [];
  String? _selectedTypePaiementId;

  final List<PaymentSplit> _splits = [];

  bool _loadingRefs = true;
  bool _submitting = false;
  String? _error;

  double get _total => CartService.instance.total;
  bool get _isEspeces {
    if (_selectedTypePaiementId == null) return false;
    final match = _typesPaiement.where((t) => t.id == _selectedTypePaiementId);
    if (match.isEmpty) return false;
    return match.first.label.toLowerCase().contains('esp');
  }

  double get _splitsSum => _splits.fold(0.0, (sum, s) => sum + s.montant);

  @override
  void initState() {
    super.initState();
    _montantCtrl.text = _total.toStringAsFixed(0);
    _loadRefs();
  }

  @override
  void dispose() {
    _clientSearchCtrl.dispose();
    _montantCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadRefs() async {
    try {
      final results = await Future.wait([
        VenteService.instance.loadClients(),
        VenteService.instance.loadTypesPaiement(),
      ]);
      if (!mounted) return;
      setState(() {
        _clients = results[0] as List<PersonneModel>;
        _typesPaiement = results[1] as List<LookupItem>;
        if (_typesPaiement.isNotEmpty) _selectedTypePaiementId = _typesPaiement.first.id;
        _loadingRefs = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingRefs = false);
    }
  }

  List<PersonneModel> get _filteredClients {
    final q = _clientSearchCtrl.text.trim().toLowerCase();
    if (q.isEmpty) return _clients.take(6).toList();
    return _clients.where((c) => c.nomComplet.toLowerCase().contains(q)).take(10).toList();
  }

  Future<void> _quickAddClient() async {
    final nom = _clientSearchCtrl.text.trim();
    if (nom.isEmpty) return;
    setState(() => _submitting = true);
    final result = await VenteService.instance.addClient(nom);
    if (!mounted) return;
    if (result.success) {
      final refreshed = await VenteService.instance.loadClients();
      final created = refreshed.where((c) => c.nomComplet.toLowerCase() == nom.toLowerCase()).toList();
      setState(() {
        _clients = refreshed;
        _selectedClient = created.isNotEmpty ? created.last : null;
        _submitting = false;
      });
    } else {
      setState(() {
        _submitting = false;
        _error = result.message ?? "Impossible d'ajouter ce client.";
      });
    }
  }

  void _addSplit() {
    final montant = double.tryParse(_montantCtrl.text.replaceAll(' ', ''));
    if (montant == null || montant <= 0 || _selectedTypePaiementId == null) return;
    final type = _typesPaiement.firstWhere((t) => t.id == _selectedTypePaiementId);
    setState(() {
      _splits.add(PaymentSplit(idTypePaiement: type.id, typeLabel: type.label, montant: montant));
      final remaining = _total - _splitsSum;
      _montantCtrl.text = remaining > 0 ? remaining.toStringAsFixed(0) : '0';
    });
  }

  void _removeSplit(int index) {
    setState(() {
      _splits.removeAt(index);
      final remaining = _total - _splitsSum;
      _montantCtrl.text = remaining > 0 ? remaining.toStringAsFixed(0) : _total.toStringAsFixed(0);
    });
  }

  /// Si l'utilisateur n'a ajouté aucun paiement explicite via "+", on
  /// considère que le champ courant représente le paiement unique (cas le
  /// plus fréquent : un seul mode de paiement pour toute la vente).
  List<PaymentSplit> get _effectiveSplits {
    if (_splits.isNotEmpty) return _splits;
    final montant = double.tryParse(_montantCtrl.text.replaceAll(' ', '')) ?? _total;
    if (_selectedTypePaiementId == null) return [];
    final type = _typesPaiement.firstWhere((t) => t.id == _selectedTypePaiementId);
    return [PaymentSplit(idTypePaiement: type.id, typeLabel: type.label, montant: montant)];
  }

  double get _effectiveSum => _effectiveSplits.fold(0.0, (sum, s) => sum + s.montant);

  Future<void> _confirmAndValidate() async {
    final splits = _effectiveSplits;
    if (splits.isEmpty) {
      setState(() => _error = 'Choisissez un mode de paiement.');
      return;
    }
    final sum = _effectiveSum;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.bgCard,
        title: const Text('Confirmer la vente ?', style: TextStyle(color: AppColors.textPrimary)),
        content: Text(
          'Total : ${_fmtMoney(_total)}\nReçu : ${_fmtMoney(sum)}${sum > _total ? '\nMonnaie à rendre : ${_fmtMoney(sum - _total)}' : ''}',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Annuler')),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Valider', style: TextStyle(color: AppColors.green))),
        ],
      ),
    );
    if (ok != true) return;
    await _validate(splits);
  }

  Future<void> _validate(List<PaymentSplit> splits) async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    final result = await VenteService.instance.encaisser(
      lines: CartService.instance.lines,
      user: widget.user,
      paiements: splits,
      client: _selectedClient,
    );
    if (!mounted) return;
    if (result.success) {
      final lines = List<CartLine>.from(CartService.instance.lines);
      final printMessage = await _printReceipt(lines: lines, splits: splits);
      if (!mounted) return;
      CartService.instance.clear();
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${result.message ?? 'Vente encaissée avec succès.'} $printMessage')),
      );
    } else {
      setState(() {
        _submitting = false;
        _error = result.message;
      });
    }
  }

  Future<String> _printReceipt({required List<CartLine> lines, required List<PaymentSplit> splits}) async {
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
        cashierName: widget.user.nomComplet,
        lines: lines,
        total: _total,
        paiements: splits,
        clientName: _selectedClient?.nomComplet,
      );
      final result = await PrinterService.instance.printBytes(bytes);
      return result.success ? '(Ticket imprimé.)' : '(Impression échouée : ${result.message ?? 'imprimante non configurée'})';
    } catch (_) {
      return '(Impression du ticket impossible.)';
    }
  }

  @override
  Widget build(BuildContext context) {
    final sum = _splits.isNotEmpty ? _splitsSum : (double.tryParse(_montantCtrl.text.replaceAll(' ', '')) ?? 0);
    final rendue = sum - _total;

    return Scaffold(
      backgroundColor: AppColors.bgDeep,
      appBar: AppBar(
        backgroundColor: AppColors.bgCard,
        elevation: 0,
        title: Text('Paiement', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 17, color: AppColors.textPrimary)),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: AppColors.bgCard, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Total à payer', style: GoogleFonts.inter(fontSize: 13.5, color: AppColors.textSecondary)),
                    Text(_fmtMoney(_total), style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.green)),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              Text('Client (optionnel)', style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
              const SizedBox(height: 8),
              if (_selectedClient != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(color: AppColors.accentGlow, borderRadius: BorderRadius.circular(12)),
                  child: Row(
                    children: [
                      const Icon(Icons.person_rounded, size: 17, color: AppColors.accentLight),
                      const SizedBox(width: 8),
                      Expanded(child: Text(_selectedClient!.nomComplet, style: const TextStyle(color: AppColors.textPrimary, fontSize: 13.5))),
                      GestureDetector(onTap: () => setState(() => _selectedClient = null), child: const Icon(Icons.close_rounded, size: 17, color: AppColors.textMuted)),
                    ],
                  ),
                )
              else ...[
                InlineField(
                  label: 'Rechercher ou créer un client',
                  controller: _clientSearchCtrl,
                  prefixIcon: Icons.person_search_rounded,
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 8),
                if (_loadingRefs)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accentLight)),
                  )
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ..._filteredClients.map(
                        (c) => ActionChip(
                          avatar: const Icon(Icons.person_outline_rounded, size: 15, color: AppColors.textSecondary),
                          label: Text(c.nomComplet, style: const TextStyle(fontSize: 12)),
                          backgroundColor: AppColors.bgElevated,
                          onPressed: () => setState(() => _selectedClient = c),
                        ),
                      ),
                      if (_clientSearchCtrl.text.trim().isNotEmpty)
                        ActionChip(
                          avatar: const Icon(Icons.add_rounded, size: 15, color: AppColors.accentLight),
                          label: Text('Créer "${_clientSearchCtrl.text.trim()}"', style: const TextStyle(fontSize: 12)),
                          backgroundColor: AppColors.accentGlow,
                          onPressed: _submitting ? null : _quickAddClient,
                        ),
                    ],
                  ),
              ],

              const SizedBox(height: 22),
              Text('Type de paiement', style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
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
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: InlineField(
                      label: _isEspeces ? 'Somme donnée (Ar)' : 'Montant (Ar)',
                      controller: _montantCtrl,
                      prefixIcon: Icons.payments_rounded,
                      keyboardType: TextInputType.number,
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: IconButton.filled(
                      onPressed: _addSplit,
                      icon: const Icon(Icons.add_rounded),
                      tooltip: 'Ajouter un autre paiement (multi-paiement)',
                      style: IconButton.styleFrom(backgroundColor: AppColors.bgElevated, foregroundColor: AppColors.accentLight),
                    ),
                  ),
                ],
              ),

              if (_splits.isNotEmpty) ...[
                const SizedBox(height: 10),
                ..._splits.asMap().entries.map((entry) {
                  final i = entry.key;
                  final s = entry.value;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                      decoration: BoxDecoration(color: AppColors.bgElevated, borderRadius: BorderRadius.circular(10)),
                      child: Row(
                        children: [
                          Expanded(child: Text('${s.typeLabel} — ${_fmtMoney(s.montant)}', style: const TextStyle(color: AppColors.textPrimary, fontSize: 13))),
                          GestureDetector(onTap: () => _removeSplit(i), child: const Icon(Icons.close_rounded, size: 16, color: AppColors.red)),
                        ],
                      ),
                    ),
                  );
                }),
              ],

              const SizedBox(height: 18),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: AppColors.bgElevated, borderRadius: BorderRadius.circular(14)),
                child: Column(
                  children: [
                    _SummaryRow(label: 'Total donné', value: _fmtMoney(sum)),
                    const SizedBox(height: 6),
                    _SummaryRow(
                      label: rendue >= 0 ? 'Monnaie à rendre' : 'Reste à payer',
                      value: _fmtMoney(rendue.abs()),
                      valueColor: rendue >= 0 ? AppColors.green : AppColors.orange,
                    ),
                  ],
                ),
              ),

              if (_error != null) ...[
                const SizedBox(height: 14),
                Text(_error!, style: const TextStyle(color: AppColors.red, fontSize: 12.5)),
              ],

              const SizedBox(height: 24),
              GradientButton(
                label: 'Valider',
                icon: Icons.check_circle_rounded,
                loading: _submitting,
                onPressed: _confirmAndValidate,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.label, required this.value, this.valueColor});
  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: GoogleFonts.inter(fontSize: 13, color: AppColors.textSecondary)),
        Text(value, style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w800, color: valueColor ?? AppColors.textPrimary)),
      ],
    );
  }
}
