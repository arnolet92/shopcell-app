import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme.dart';
import '../../models/facture_model.dart';
import '../../models/user_model.dart';
import '../../services/echange_print.dart';

const Color _echangeColor = Color(0xFFA78BFA);
const Color _echangeExtColor = Color(0xFF38BDF8);
const Color _reprisColor = Color(0xFFF59E0B);

String _fmt(double v) {
  final s = v.round().toString();
  final buf = StringBuffer();
  for (int i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(' ');
    buf.write(s[i]);
  }
  return '${buf.toString()} Ar';
}

double _d(dynamic v) => v == null ? 0 : (v is num ? v.toDouble() : double.tryParse('$v') ?? 0);

String? _s(dynamic v) {
  final t = v?.toString().trim();
  return (t == null || t.isEmpty) ? null : t;
}

String _fmtDate(String? iso) {
  if (iso == null) return '-';
  final dt = DateTime.tryParse(iso);
  if (dt == null) return iso;
  String p2(int n) => n.toString().padLeft(2, '0');
  return '${p2(dt.day)}/${p2(dt.month)}/${dt.year} ${p2(dt.hour)}:${p2(dt.minute)}';
}

/// Détail d'un ÉCHANGE affiché dans "Factures payées" — miroir mobile de
/// `_echange_detail_row.php` (web) : type d'échange (normal / extérieur),
/// article REPRIS (entré en stock) et article REMIS (sorti du stock) avec
/// leurs caractéristiques, et volontairement AUCUNE option d'annulation
/// (l'annulation d'un échange se fait depuis l'historique d'échange). Le
/// bouton "Imprimer" imprime le ticket/A4 d'ÉCHANGE, pas une facture.
class FactureEchangeDetailScreen extends StatefulWidget {
  const FactureEchangeDetailScreen({super.key, required this.item, required this.user});
  final FactureListItem item;
  final UserModel user;

  @override
  State<FactureEchangeDetailScreen> createState() => _FactureEchangeDetailScreenState();
}

class _FactureEchangeDetailScreenState extends State<FactureEchangeDetailScreen> {
  bool _printing = false;

  Map<String, dynamic> get _j => widget.item.echangeRaw ?? const {};

  Future<void> _print() async {
    if (_printing || widget.item.echangeRaw == null) return;
    setState(() => _printing = true);
    final message = await printEchangeFromJson(
      context,
      _j,
      user: widget.user,
      numeroFacture: widget.item.numeroFacture,
    );
    if (!mounted) return;
    setState(() => _printing = false);
    if (message.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  List<MapEntry<String, String>> _champs(String p, {bool lieu = false}) {
    final j = _j;
    final m = <String, String>{
      '${p}num_serie': 'N° série',
      '${p}nom_model': 'Modèle',
      '${p}nom_marque': 'Capacité',
      '${p}nom_type_piece': 'Couleur',
      '${p}nom_batterie': 'Batterie',
      if (lieu) '${p}nom_lieu': 'Lieu',
      '${p}imei1': 'IMEI 1',
      '${p}imei2': 'IMEI 2',
    };
    return [
      for (final e in m.entries)
        if (_s(j[e.key]) != null) MapEntry(e.value, _s(j[e.key])!),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final j = _j;
    final ext = widget.item.isEchangeExterieur;
    final typeColor = ext ? _echangeExtColor : _echangeColor;
    final qte = _d(j['qte']) == 0 ? 1.0 : _d(j['qte']);
    final repris = _champs('old_');
    final defaut = _s(j['old_motif_reparation']);
    if (defaut != null) repris.add(MapEntry('Défaut constaté', defaut));
    final factureOrigine = _s(j['numero_factures_client']);
    final numero = widget.item.idEchange ?? '';

    return Scaffold(
      backgroundColor: AppColors.bgDeep,
      appBar: AppBar(
        backgroundColor: AppColors.bgCard,
        elevation: 0,
        title: Text(widget.item.numeroFacture, style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 16, color: AppColors.textPrimary)),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 14),
            child: _PrintPill(loading: _printing, onTap: _print),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: typeColor.withValues(alpha: .1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: typeColor.withValues(alpha: .4)),
              ),
              child: Row(children: [
                Icon(ext ? Icons.login_rounded : Icons.swap_horiz_rounded, size: 20, color: typeColor),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(widget.item.typeEchangeLabel, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w800, color: typeColor)),
                    const SizedBox(height: 2),
                    Text(
                      ext
                          ? "Article repris venant de l'extérieur (non vendu par la boutique) · N°$numero"
                          : "Article repris vendu par la boutique${factureOrigine != null ? ' (facture $factureOrigine)' : ''} · N°$numero",
                      style: GoogleFonts.inter(fontSize: 11, color: AppColors.textMuted),
                    ),
                  ]),
                ),
              ]),
            ),
            const SizedBox(height: 14),
            _ArticleCard(
              titre: 'ARTICLE REPRIS (ENTRÉ EN STOCK)',
              icon: Icons.south_rounded,
              color: _reprisColor,
              designation: _s(j['old_designation']) ?? '-',
              qte: qte,
              champs: repris,
              pied: [MapEntry('Valeur de reprise', _fmt(_d(j['old_prix_ventes'])))],
            ),
            const SizedBox(height: 12),
            _ArticleCard(
              titre: 'ARTICLE REMIS (SORTI DU STOCK)',
              icon: Icons.north_rounded,
              color: AppColors.green,
              designation: _s(j['new_designation']) ?? '-',
              qte: qte,
              champs: _champs('new_', lieu: true),
              pied: [
                MapEntry("Prix de l'article", _fmt(_d(j['new_prix_unitaire']))),
                MapEntry('Supplément', _fmt(_d(j['prix_ajoute']))),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: AppColors.bgCard, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),
              child: Column(children: [
                _row("Montant de l'échange", _fmt(widget.item.montant), AppColors.textPrimary, bold: true),
                _row('Date', _fmtDate(widget.item.dateReference), AppColors.textSecondary),
                if (widget.item.caissierPseudo != null) _row('Caissier', widget.item.caissierPseudo!, AppColors.textSecondary),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value, Color color, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label, style: GoogleFonts.inter(fontSize: 12.5, color: AppColors.textSecondary)),
        Text(value, style: GoogleFonts.inter(fontSize: 13.5, fontWeight: bold ? FontWeight.w800 : FontWeight.w600, color: color)),
      ]),
    );
  }
}

/// Carte "Article repris" / "Article remis" du détail d'échange.
class _ArticleCard extends StatelessWidget {
  const _ArticleCard({
    required this.titre,
    required this.icon,
    required this.color,
    required this.designation,
    required this.qte,
    required this.champs,
    required this.pied,
  });
  final String titre;
  final IconData icon;
  final Color color;
  final String designation;
  final double qte;
  final List<MapEntry<String, String>> champs;
  final List<MapEntry<String, String>> pied;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: .4)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Text(titre, style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w800, color: color, letterSpacing: .04)),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: Text(designation, style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          ),
          Text('x${qte.toStringAsFixed(qte == qte.roundToDouble() ? 0 : 2)}',
              style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.accentLight)),
        ]),
        if (champs.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 14,
            runSpacing: 4,
            children: champs
                .map((c) => RichText(
                      text: TextSpan(
                        style: GoogleFonts.inter(fontSize: 11.5),
                        children: [
                          TextSpan(text: '${c.key}: ', style: const TextStyle(color: AppColors.textMuted)),
                          TextSpan(text: c.value, style: const TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ))
                .toList(),
          ),
        ],
        const SizedBox(height: 8),
        Wrap(spacing: 16, runSpacing: 4, children: [
          for (final p in pied) Text('${p.key} : ${p.value}', style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w600, color: color)),
        ]),
      ]),
    );
  }
}

class _PrintPill extends StatelessWidget {
  const _PrintPill({required this.loading, required this.onTap});
  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: loading ? null : onTap,
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            gradient: AppColors.accentGradient,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [BoxShadow(color: AppColors.accent.withValues(alpha: 0.35), blurRadius: 12, offset: const Offset(0, 4))],
          ),
          child: loading
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.print_rounded, size: 16, color: Colors.white),
                  const SizedBox(width: 6),
                  Text('Imprimer', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
                ]),
        ),
      ),
    );
  }
}
