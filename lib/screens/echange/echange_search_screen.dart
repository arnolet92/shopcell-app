import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme.dart';
import '../../models/user_model.dart';
import '../../services/echange_service.dart';
import '../../widgets/inline_field.dart';
import 'echange_detail_screen.dart';

/// Point d'entrée du système d'échange côté mobile : recherche d'un article
/// déjà vendu (désignation, N° série, IMEI, modèle, capacité) — miroir de
/// `Echange/index` (web), version premium épurée pour mobile.
class EchangeSearchScreen extends StatefulWidget {
  const EchangeSearchScreen({super.key, required this.user});
  final UserModel user;

  @override
  State<EchangeSearchScreen> createState() => _EchangeSearchScreenState();
}

class _EchangeSearchScreenState extends State<EchangeSearchScreen> {
  final _searchCtrl = TextEditingController();
  List<VenteLigne> _results = [];
  bool _loading = false;
  bool _searched = false;
  Timer? _debounce;

  @override
  void dispose() {
    _searchCtrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () => _search(v));
  }

  Future<void> _search(String arg) async {
    if (arg.trim().isEmpty) {
      setState(() {
        _results = [];
        _searched = false;
      });
      return;
    }
    setState(() => _loading = true);
    final results = await EchangeService.instance.searchVentes(arg);
    if (!mounted) return;
    setState(() {
      _results = results;
      _loading = false;
      _searched = true;
    });
  }

  Future<void> _openDetail(VenteLigne ligne) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => EchangeDetailScreen(idVentes: ligne.idVentes, user: widget.user)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDeep,
      appBar: AppBar(
        backgroundColor: AppColors.bgCard,
        elevation: 0,
        title: Text('Faire un échange', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 17, color: AppColors.textPrimary)),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Recherchez l\'article déjà vendu à échanger',
                style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 10),
              InlineField(
                label: 'Désignation, N° série, IMEI, modèle...',
                controller: _searchCtrl,
                prefixIcon: Icons.search_rounded,
                autofocus: true,
                onChanged: _onChanged,
              ),
              const SizedBox(height: 18),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accentLight)),
                )
              else if (!_searched)
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.swap_horizontal_circle_rounded, size: 44, color: AppColors.textMuted),
                        const SizedBox(height: 10),
                        Text('Tapez pour rechercher un article vendu', style: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 13)),
                      ],
                    ),
                  ),
                )
              else if (_results.isEmpty)
                Expanded(
                  child: Center(
                    child: Text('Aucun article vendu trouvé', style: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 13)),
                  ),
                )
              else
                Expanded(
                  child: ListView.separated(
                    itemCount: _results.length,
                    separatorBuilder: (_, index) => const SizedBox(height: 10),
                    itemBuilder: (context, i) => _VenteLigneCard(ligne: _results[i], onTap: () => _openDetail(_results[i])),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VenteLigneCard extends StatelessWidget {
  const _VenteLigneCard({required this.ligne, required this.onTap});
  final VenteLigne ligne;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final attrs = <String>[
      if (ligne.nomModel != null) 'Modèle: ${ligne.nomModel}',
      if (ligne.nomMarque != null) 'Capacité: ${ligne.nomMarque}',
      if (ligne.numSerie != null) 'S/N: ${ligne.numSerie}',
      if (ligne.imei1 != null) 'IMEI1: ${ligne.imei1}',
    ];
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.bgCard,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(color: AppColors.accentGlow, borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.receipt_long_rounded, color: AppColors.accentLight, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(ligne.designation, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                    if (ligne.numeroFacture != null) ...[
                      const SizedBox(height: 3),
                      Text('Facture ${ligne.numeroFacture}', style: GoogleFonts.inter(fontSize: 11.5, color: AppColors.textMuted)),
                    ],
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
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('${ligne.prixVentes.toStringAsFixed(0)} Ar', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.green)),
                  const SizedBox(height: 6),
                  const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted, size: 20),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
