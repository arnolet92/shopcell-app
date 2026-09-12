import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme.dart';
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

/// Simple calculateur de prix, sans article ni enregistrement : juste les 3
/// champs "prix actuel" / "prix de l'article en échange" / "prix ajouté"
/// (même formule que l'échange réel), miroir de l'onglet "Simulation
/// d'échange" côté web (`Echange/index`).
class EchangeSimulationScreen extends StatefulWidget {
  const EchangeSimulationScreen({super.key});

  @override
  State<EchangeSimulationScreen> createState() => _EchangeSimulationScreenState();
}

class _EchangeSimulationScreenState extends State<EchangeSimulationScreen> {
  final _prixActuelCtrl = TextEditingController();
  final _prixArticleEchangeCtrl = TextEditingController();
  double _prixAjoute = 0;

  @override
  void dispose() {
    _prixActuelCtrl.dispose();
    _prixArticleEchangeCtrl.dispose();
    super.dispose();
  }

  void _calc() {
    final prixActuel = double.tryParse(_prixActuelCtrl.text.replaceAll(' ', '')) ?? 0;
    final prixArticleEchange = double.tryParse(_prixArticleEchangeCtrl.text.replaceAll(' ', '')) ?? 0;
    final valeurReprise = prixActuel * 0.8;
    final brut = (prixArticleEchange - valeurReprise) > 0 ? (prixArticleEchange - valeurReprise) : 0.0;
    setState(() {
      _prixAjoute = brut > 0 ? (brut / 50000).ceil() * 50000 : 0.0;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDeep,
      appBar: AppBar(
        backgroundColor: AppColors.bgCard,
        elevation: 0,
        title: Text("Simulation d'échange", style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 16, color: AppColors.textPrimary)),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Simple calcul de prix : aucun article n'est sélectionné, rien n'est enregistré.",
                style: GoogleFonts.inter(fontSize: 12.5, color: AppColors.textMuted),
              ),
              const SizedBox(height: 18),
              InlineField(
                label: 'Prix actuel',
                controller: _prixActuelCtrl,
                prefixIcon: Icons.sell_rounded,
                keyboardType: TextInputType.number,
                onChanged: (_) => _calc(),
              ),
              const SizedBox(height: 14),
              InlineField(
                label: "Prix de l'article en échange (sortie du stock)",
                controller: _prixArticleEchangeCtrl,
                prefixIcon: Icons.inventory_2_rounded,
                keyboardType: TextInputType.number,
                onChanged: (_) => _calc(),
              ),
              const SizedBox(height: 18),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                decoration: BoxDecoration(color: AppColors.bgElevated, borderRadius: BorderRadius.circular(16)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Prix ajouté (automatique)', style: GoogleFonts.inter(fontSize: 12, color: AppColors.textMuted)),
                    const SizedBox(height: 6),
                    Text(_fmt(_prixAjoute), style: GoogleFonts.inter(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.accentLight)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
