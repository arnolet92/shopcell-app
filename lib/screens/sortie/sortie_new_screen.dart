import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme.dart';
import '../../models/produit_model.dart';
import '../../models/user_model.dart';
import '../../services/sortie_service.dart';
import '../../widgets/gradient_button.dart';
import '../../widgets/inline_field.dart';

class _Ligne {
  _Ligne(this.produit);
  final ProduitModel produit;
  int qte = 1;
}

/// Nouvelle sortie : plusieurs articles, note obligatoire, aucune facture.
class SortieNewScreen extends StatefulWidget {
  const SortieNewScreen({super.key, required this.user});
  final UserModel user;

  @override
  State<SortieNewScreen> createState() => _SortieNewScreenState();
}

class _SortieNewScreenState extends State<SortieNewScreen> {
  final _searchCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  final Map<String, _Ligne> _lignes = {};
  List<ProduitModel> _resultats = [];
  Timer? _debounce;
  bool _saving = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  void _rechercher(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      final res = await SortieService.instance.rechercher(v);
      if (!mounted || v != _searchCtrl.text) return;
      setState(() => _resultats = res);
    });
  }

  void _ajouter(ProduitModel p) {
    setState(() {
      _lignes.putIfAbsent(p.idProduits, () => _Ligne(p));
      _resultats = [];
      _searchCtrl.clear();
    });
  }

  void _setQte(_Ligne l, int qte) {
    if (qte < 1 || qte > l.produit.qteProduits) return;
    setState(() => l.qte = qte);
  }

  void _message(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _valider() async {
    if (_lignes.isEmpty) return _message('Ajoutez au moins un article.');
    final note = _noteCtrl.text.trim();
    if (note.isEmpty) return _message('La note est obligatoire.');
    setState(() => _saving = true);
    final res = await SortieService.instance.valider(
      quantites: {for (final l in _lignes.values) l.produit.idProduits: l.qte},
      note: note,
      user: widget.user,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (res.success) {
      _message('Sortie enregistrée.');
      Navigator.of(context).pop(true);
    } else {
      _message(res.message ?? 'La sortie a échoué.');
    }
  }

  String _infos(ProduitModel p) {
    return [
      if ((p.numSerie ?? '').trim().isNotEmpty) 'N° série : ${p.numSerie}',
      if ((p.imei1 ?? '').trim().isNotEmpty) 'IMEI : ${p.imei1}',
      'Stock : ${p.qteProduits.toStringAsFixed(0)}',
    ].join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDeep,
      appBar: AppBar(
        backgroundColor: AppColors.bgCard,
        elevation: 0,
        title: Text('Nouvelle sortie', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 17, color: AppColors.textPrimary)),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            InlineField(label: 'Rechercher un article', controller: _searchCtrl, prefixIcon: Icons.search_rounded, onChanged: _rechercher),
            for (final p in _resultats)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(p.designation, style: GoogleFonts.inter(fontSize: 13.5, color: AppColors.textPrimary)),
                subtitle: Text(_infos(p), style: GoogleFonts.inter(fontSize: 11.5, color: AppColors.textSecondary)),
                onTap: () => _ajouter(p),
              ),
            const SizedBox(height: 16),
            Text('Articles à sortir', style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
            const SizedBox(height: 8),
            if (_lignes.isEmpty) Text('Aucun article ajouté', style: GoogleFonts.inter(fontSize: 12.5, color: AppColors.textMuted)),
            for (final l in _lignes.values)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(color: AppColors.bgCard, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(l.produit.designation, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                      Text(_infos(l.produit), style: GoogleFonts.inter(fontSize: 11, color: AppColors.textSecondary)),
                    ]),
                  ),
                  IconButton(icon: const Icon(Icons.remove_circle_outline, color: AppColors.textSecondary, size: 20), onPressed: () => _setQte(l, l.qte - 1)),
                  Text('${l.qte}', style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                  IconButton(icon: const Icon(Icons.add_circle_outline, color: AppColors.textSecondary, size: 20), onPressed: () => _setQte(l, l.qte + 1)),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: AppColors.red, size: 20),
                    onPressed: () => setState(() => _lignes.remove(l.produit.idProduits)),
                  ),
                ]),
              ),
            const SizedBox(height: 12),
            InlineField(label: 'Note (obligatoire)', controller: _noteCtrl, prefixIcon: Icons.notes_rounded),
            const SizedBox(height: 22),
            GradientButton(label: 'Valider la sortie', icon: Icons.check_rounded, loading: _saving, onPressed: _valider),
          ],
        ),
      ),
    );
  }
}
