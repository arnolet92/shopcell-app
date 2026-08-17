import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme.dart';
import '../../models/personne_model.dart';
import '../../models/user_model.dart';
import '../../services/cart_service.dart';
import '../../services/vente_service.dart';
import '../../widgets/gradient_button.dart';
import '../../widgets/inline_field.dart';
import '../../widgets/produit_image.dart';
import 'payment_screen.dart';

/// Panier : liste des articles choisis (avec IMEI/série/capacité/modèle),
/// possibilité de vider le panier ou d'annuler chaque ligne, puis
/// "Encaisser" (-> PaymentScreen) ou "Mettre en attente".
class CartScreen extends StatefulWidget {
  const CartScreen({super.key, required this.user, required this.baseUrl});

  final UserModel user;
  final String? baseUrl;

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  @override
  void initState() {
    super.initState();
    CartService.instance.addListener(_onCartChanged);
  }

  @override
  void dispose() {
    CartService.instance.removeListener(_onCartChanged);
    super.dispose();
  }

  void _onCartChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _confirmClear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.bgCard,
        title: const Text('Vider le panier ?', style: TextStyle(color: AppColors.textPrimary)),
        content: const Text('Tous les articles du panier seront retirés.', style: TextStyle(color: AppColors.textSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Annuler')),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Vider', style: TextStyle(color: AppColors.red))),
        ],
      ),
    );
    if (ok == true) CartService.instance.clear();
  }

  Future<void> _openPayment() async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => PaymentScreen(user: widget.user)),
    );
    if (result == true && mounted) Navigator.of(context).pop(true);
  }

  Future<void> _openEnAttente() async {
    final clients = await VenteService.instance.loadClients();
    if (!mounted) return;
    final result = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: AppColors.bgCard,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (context) => _EnAttenteSheet(user: widget.user, clients: clients),
    );
    if (result == true && mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final lines = CartService.instance.lines;

    return Scaffold(
      backgroundColor: AppColors.bgDeep,
      appBar: AppBar(
        backgroundColor: AppColors.bgCard,
        elevation: 0,
        title: Text('Panier', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 17, color: AppColors.textPrimary)),
        actions: [
          if (lines.isNotEmpty)
            IconButton(
              onPressed: _confirmClear,
              icon: const Icon(Icons.delete_sweep_rounded, color: AppColors.red),
              tooltip: 'Vider le panier',
            ),
        ],
      ),
      body: SafeArea(
        child: lines.isEmpty
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.shopping_cart_outlined, size: 40, color: AppColors.textMuted),
                    const SizedBox(height: 12),
                    Text('Panier vide', style: GoogleFonts.inter(color: AppColors.textMuted)),
                  ],
                ),
              )
            : Column(
                children: [
                  Expanded(
                    child: ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: lines.length,
                      separatorBuilder: (_, index) => const SizedBox(height: 10),
                      itemBuilder: (context, i) {
                        final line = lines[i];
                        final imageUrl = widget.baseUrl != null ? line.produit.imageUrl(widget.baseUrl!) : null;
                        return _CartLineTile(
                          line: line,
                          imageUrl: imageUrl,
                          onRemove: () => CartService.instance.remove(line.produit.idProduits),
                        );
                      },
                    ),
                  ),
                  _BottomBar(onEncaisser: _openPayment, onEnAttente: _openEnAttente),
                ],
              ),
      ),
    );
  }
}

class _CartLineTile extends StatelessWidget {
  const _CartLineTile({required this.line, required this.imageUrl, required this.onRemove});
  final CartLine line;
  final String? imageUrl;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final p = line.produit;
    final attrs = <String>[
      if (p.nomModel != null) 'Modèle: ${p.nomModel}',
      if (p.nomMarque != null) 'Capacité: ${p.nomMarque}',
      if (p.numSerie != null) 'S/N: ${p.numSerie}',
      if (p.imei1 != null) 'IMEI1: ${p.imei1}',
      if (p.imei2 != null) 'IMEI2: ${p.imei2}',
    ];

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ProduitImage(url: imageUrl, size: 60, radius: 14),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p.designation, style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                if (attrs.isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: attrs
                        .map((a) => Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(color: AppColors.bgElevated, borderRadius: BorderRadius.circular(20)),
                              child: Text(a, style: GoogleFonts.inter(fontSize: 10, color: AppColors.textSecondary)),
                            ))
                        .toList(),
                  ),
                ],
                const SizedBox(height: 8),
                Text(
                  '${line.qte} x ${p.prixUnitaire.toStringAsFixed(0)} Ar = ${line.total.toStringAsFixed(0)} Ar',
                  style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.green),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onRemove,
            icon: const Icon(Icons.close_rounded, size: 18, color: AppColors.red),
            tooltip: 'Annuler cette ligne',
          ),
        ],
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.onEncaisser, required this.onEnAttente});
  final VoidCallback onEncaisser;
  final VoidCallback onEnAttente;

  @override
  Widget build(BuildContext context) {
    final total = CartService.instance.total;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: const BoxDecoration(
        color: AppColors.bgCard,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Total', style: GoogleFonts.inter(fontSize: 14, color: AppColors.textSecondary)),
                Text('${total.toStringAsFixed(0)} Ar', style: GoogleFonts.inter(fontSize: 19, fontWeight: FontWeight.w800, color: AppColors.green)),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onEnAttente,
                    icon: const Icon(Icons.schedule_send_rounded, size: 18, color: AppColors.blue),
                    label: const Text('Mettre en attente', style: TextStyle(color: AppColors.blue)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppColors.blue),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: GradientButton(label: 'Encaisser', icon: Icons.check_circle_rounded, onPressed: onEncaisser),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EnAttenteSheet extends StatefulWidget {
  const _EnAttenteSheet({required this.user, required this.clients});
  final UserModel user;
  final List<PersonneModel> clients;

  @override
  State<_EnAttenteSheet> createState() => _EnAttenteSheetState();
}

class _EnAttenteSheetState extends State<_EnAttenteSheet> {
  final _clientSearchCtrl = TextEditingController();
  final _referenceCtrl = TextEditingController();
  PersonneModel? _selectedClient;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _clientSearchCtrl.dispose();
    _referenceCtrl.dispose();
    super.dispose();
  }

  List<PersonneModel> get _filteredClients {
    final q = _clientSearchCtrl.text.trim().toLowerCase();
    if (q.isEmpty) return widget.clients.take(6).toList();
    return widget.clients.where((c) => c.nomComplet.toLowerCase().contains(q)).take(10).toList();
  }

  Future<void> _submit() async {
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result.message ?? 'Commande mise en attente.')));
    } else {
      setState(() {
        _submitting = false;
        _error = result.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Mettre en attente', style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
              const SizedBox(height: 16),
              if (_selectedClient != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(color: AppColors.accentGlow, borderRadius: BorderRadius.circular(12)),
                  child: Row(
                    children: [
                      const Icon(Icons.person_rounded, size: 17, color: AppColors.accentLight),
                      const SizedBox(width: 8),
                      Expanded(child: Text(_selectedClient!.nomComplet, style: const TextStyle(color: AppColors.textPrimary))),
                      GestureDetector(onTap: () => setState(() => _selectedClient = null), child: const Icon(Icons.close_rounded, size: 17, color: AppColors.textMuted)),
                    ],
                  ),
                )
              else ...[
                InlineField(label: 'Rechercher un client (optionnel)', controller: _clientSearchCtrl, prefixIcon: Icons.person_search_rounded, onChanged: (_) => setState(() {})),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _filteredClients
                      .map((c) => ActionChip(
                            label: Text(c.nomComplet, style: const TextStyle(fontSize: 12)),
                            backgroundColor: AppColors.bgElevated,
                            onPressed: () => setState(() => _selectedClient = c),
                          ))
                      .toList(),
                ),
              ],
              const SizedBox(height: 16),
              InlineField(label: 'Référence (si pas de client)', controller: _referenceCtrl, prefixIcon: Icons.tag_rounded),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: AppColors.red, fontSize: 12.5)),
              ],
              const SizedBox(height: 22),
              GradientButton(label: 'Confirmer', icon: Icons.schedule_send_rounded, loading: _submitting, onPressed: _submit),
            ],
          ),
        ),
      ),
    );
  }
}
