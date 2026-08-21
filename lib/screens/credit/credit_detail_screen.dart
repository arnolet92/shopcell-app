import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme.dart';
import '../../models/lookup_model.dart';
import '../../models/user_model.dart';
import '../../services/credit_service.dart';
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
  const CreditDetailScreen({super.key, required this.client, required this.user});
  final CreditClient client;
  final UserModel user;

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
                      Text('Factures impayées', style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
                      const SizedBox(height: 8),
                      if (detail == null || detail.list.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          child: Center(child: Text('Aucune facture impayée', style: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 13))),
                        )
                      else
                        ...detail.list.map(_factureTile),
                      if (detail != null && detail.restant > 0) ...[
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
    return Container(
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
        ],
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
