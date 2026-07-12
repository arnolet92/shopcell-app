import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme.dart';
import '../../../models/lookup_model.dart';
import '../../../models/personne_model.dart';
import '../../../models/user_model.dart';
import '../../../services/cart_service.dart';
import '../../../services/printer_service.dart';
import '../../../services/ticket_builder.dart';
import '../../../services/vente_service.dart';
import '../../../widgets/gradient_button.dart';
import '../../../widgets/inline_field.dart';

/// Feuille de finalisation de vente : client optionnel, puis "Encaisser"
/// (paiement complet immédiat, `Mob/all_payed`) ou "Mettre en attente"
/// (`Mob/all_data`) — même principe que les boutons "Encaisser" / "En
/// attente" de l'écran web `Vente/commande_direct`.
Future<bool?> showCheckoutSheet(BuildContext context, {required UserModel user}) {
  return showModalBottomSheet<bool>(
    context: context,
    backgroundColor: AppColors.bgCard,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    builder: (context) => _CheckoutContent(user: user),
  );
}

String _fmtMoney(double v) {
  final s = v.round().toString();
  final buf = StringBuffer();
  for (int i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(' ');
    buf.write(s[i]);
  }
  return '${buf.toString()} Ar';
}

class _CheckoutContent extends StatefulWidget {
  const _CheckoutContent({required this.user});
  final UserModel user;

  @override
  State<_CheckoutContent> createState() => _CheckoutContentState();
}

class _CheckoutContentState extends State<_CheckoutContent> {
  final _clientSearchCtrl = TextEditingController();
  final _montantCtrl = TextEditingController();
  final _referenceCtrl = TextEditingController();

  List<PersonneModel> _clients = [];
  PersonneModel? _selectedClient;
  List<LookupItem> _typesPaiement = [];
  String? _selectedTypePaiementId;

  bool _loadingRefs = true;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _montantCtrl.text = CartService.instance.total.toStringAsFixed(0);
    _loadRefs();
  }

  @override
  void dispose() {
    _clientSearchCtrl.dispose();
    _montantCtrl.dispose();
    _referenceCtrl.dispose();
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

  Future<void> _encaisser() async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    final montant = double.tryParse(_montantCtrl.text.replaceAll(' ', '')) ?? CartService.instance.total;
    final result = await VenteService.instance.encaisser(
      lines: CartService.instance.lines,
      user: widget.user,
      client: _selectedClient,
      idTypePaiement: _selectedTypePaiementId,
      sommeDonnee: montant,
    );
    if (!mounted) return;
    if (result.success) {
      final lines = List<CartLine>.from(CartService.instance.lines);
      final printMessage = await _printReceipt(lines: lines, montant: montant);
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

  /// Imprime le ticket sur l'imprimante configurée (`PrinterSettingsScreen`).
  /// Retourne un court message de statut à concaténer à la confirmation de
  /// vente, sans jamais bloquer/faire échouer la vente elle-même si
  /// l'imprimante est absente ou injoignable.
  Future<String> _printReceipt({required List<CartLine> lines, required double montant}) async {
    try {
      final shopInfo = await VenteService.instance.loadShopInfo();
      final matchingTypes = _typesPaiement.where((t) => t.id == _selectedTypePaiementId);
      final typeLabel = matchingTypes.isEmpty ? null : matchingTypes.first.label;
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
        total: CartService.instance.total,
        montantDonne: montant,
        typePaiementLabel: typeLabel,
        clientName: _selectedClient?.nomComplet,
      );
      final result = await PrinterService.instance.printBytes(bytes);
      return result.success ? '(Ticket imprimé.)' : '(Impression échouée : ${result.message ?? 'imprimante non configurée'})';
    } catch (_) {
      return '(Impression du ticket impossible.)';
    }
  }

  Future<void> _enAttente() async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    final result = await VenteService.instance.mettreEnAttente(
      lines: CartService.instance.lines,
      user: widget.user,
      client: _selectedClient,
      reference: _referenceCtrl.text,
    );
    if (!mounted) return;
    if (result.success) {
      CartService.instance.clear();
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.message ?? 'Commande mise en attente.')),
      );
    } else {
      setState(() {
        _submitting = false;
        _error = result.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = CartService.instance.total;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(4)),
                ),
              ),
              const SizedBox(height: 18),
              Text('Finaliser la vente', style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
              const SizedBox(height: 4),
              Text('Total du panier : ${_fmtMoney(total)}', style: GoogleFonts.inter(fontSize: 13.5, color: AppColors.accentLight, fontWeight: FontWeight.w700)),
              const SizedBox(height: 20),

              Text('Client (optionnel)', style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
              const SizedBox(height: 8),
              if (_selectedClient != null)
                _SelectedClientChip(client: _selectedClient!, onClear: () => setState(() => _selectedClient = null))
              else ...[
                InlineField(
                  label: 'Rechercher ou créer un client',
                  controller: _clientSearchCtrl,
                  prefixIcon: Icons.person_search_rounded,
                  textInputAction: TextInputAction.done,
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
                        (c) => _ClientOption(client: c, onTap: () => setState(() => _selectedClient = c)),
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
              const SizedBox(height: 14),
              InlineField(
                label: 'Montant donné (Ar)',
                controller: _montantCtrl,
                prefixIcon: Icons.payments_rounded,
                keyboardType: TextInputType.number,
              ),

              const SizedBox(height: 18),
              Text('Référence (si pas de client, pour mettre en attente)', style: GoogleFonts.inter(fontSize: 11.5, color: AppColors.textMuted)),
              const SizedBox(height: 6),
              InlineField(
                label: 'Ex: nom du client, table...',
                controller: _referenceCtrl,
                prefixIcon: Icons.tag_rounded,
              ),

              if (_error != null) ...[
                const SizedBox(height: 14),
                Text(_error!, style: const TextStyle(color: AppColors.red, fontSize: 12.5)),
              ],

              const SizedBox(height: 24),
              GradientButton(
                label: 'Encaisser',
                icon: Icons.check_circle_rounded,
                loading: _submitting,
                onPressed: _encaisser,
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _submitting ? null : _enAttente,
                  icon: const Icon(Icons.schedule_send_rounded, size: 18, color: AppColors.blue),
                  label: const Text('Mettre en attente', style: TextStyle(color: AppColors.blue)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.blue),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SelectedClientChip extends StatelessWidget {
  const _SelectedClientChip({required this.client, required this.onClear});
  final PersonneModel client;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: AppColors.accentGlow, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          const Icon(Icons.person_rounded, size: 17, color: AppColors.accentLight),
          const SizedBox(width: 8),
          Expanded(child: Text(client.nomComplet, style: const TextStyle(color: AppColors.textPrimary, fontSize: 13.5))),
          GestureDetector(
            onTap: onClear,
            child: const Icon(Icons.close_rounded, size: 17, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}

class _ClientOption extends StatelessWidget {
  const _ClientOption({required this.client, required this.onTap});
  final PersonneModel client;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      avatar: const Icon(Icons.person_outline_rounded, size: 15, color: AppColors.textSecondary),
      label: Text(client.nomComplet, style: const TextStyle(fontSize: 12)),
      backgroundColor: AppColors.bgElevated,
      onPressed: onTap,
    );
  }
}
