import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme.dart';
import '../../models/user_model.dart';
import '../../services/sortie_service.dart';
import 'sortie_list_screen.dart';

/// Détail d'une sortie archivée : annulation complète ou article par article.
class SortieDetailScreen extends StatefulWidget {
  const SortieDetailScreen({super.key, required this.user, required this.idSortie});
  final UserModel user;
  final String idSortie;

  @override
  State<SortieDetailScreen> createState() => _SortieDetailScreenState();
}

class _SortieDetailScreenState extends State<SortieDetailScreen> {
  SortieDetail? _detail;
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final d = await SortieService.instance.detail(widget.idSortie);
    if (!mounted) return;
    setState(() {
      _detail = d;
      _loading = false;
    });
  }

  Future<void> _annuler({String? idLigne}) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgCard,
        title: Text(idLigne == null ? 'Annuler toute la sortie ?' : 'Annuler cet article ?', style: GoogleFonts.inter(fontSize: 16, color: AppColors.textPrimary)),
        content: const Text('Le stock sera rétabli.', style: TextStyle(color: AppColors.textSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Non')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Oui, annuler', style: TextStyle(color: AppColors.red))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    final res = await SortieService.instance.annuler(idSortie: widget.idSortie, idLigne: idLigne, user: widget.user);
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res.message ?? (res.success ? 'Annulation effectuée.' : "L'annulation a échoué."))));
    if (res.success) _load();
  }

  @override
  Widget build(BuildContext context) {
    final d = _detail;
    return Scaffold(
      backgroundColor: AppColors.bgDeep,
      appBar: AppBar(
        backgroundColor: AppColors.bgCard,
        elevation: 0,
        title: Text(d?.resume.numero ?? 'Sortie', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 17, color: AppColors.textPrimary)),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: AppColors.accentLight))
            : d == null
                ? const Center(child: Text('Sortie introuvable', style: TextStyle(color: AppColors.textSecondary)))
                : _contenu(d),
      ),
    );
  }

  Widget _contenu(SortieDetail d) {
    final actives = d.lignes.where((l) => !l.annule).length;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(d.resume.statut, style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 14, color: sortieStatutColor(d.resume.statut))),
        const SizedBox(height: 6),
        Text('${d.resume.date} · ${d.resume.nomUser}', style: GoogleFonts.inter(fontSize: 12, color: AppColors.textMuted)),
        const SizedBox(height: 10),
        Text('Note : ${d.resume.note}', style: GoogleFonts.inter(fontSize: 13.5, color: AppColors.textPrimary)),
        const SizedBox(height: 16),
        for (final l in d.lignes)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
            decoration: BoxDecoration(color: AppColors.bgCard, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(l.designation,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: l.annule ? AppColors.textMuted : AppColors.textPrimary,
                        decoration: l.annule ? TextDecoration.lineThrough : null,
                      )),
                  Text(
                    [
                      'Qté : ${l.qte.toStringAsFixed(0)}',
                      if ((l.numSerie ?? '').trim().isNotEmpty) 'N° série : ${l.numSerie}',
                      if ((l.imei1 ?? '').trim().isNotEmpty) 'IMEI : ${l.imei1}',
                      if (l.annule) 'Annulé',
                    ].join(' · '),
                    style: GoogleFonts.inter(fontSize: 11, color: AppColors.textSecondary),
                  ),
                ]),
              ),
              if (!l.annule)
                TextButton(onPressed: _busy ? null : () => _annuler(idLigne: l.id), child: const Text('Annuler', style: TextStyle(color: AppColors.red))),
            ]),
          ),
        if (actives > 0) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _busy ? null : () => _annuler(),
            style: OutlinedButton.styleFrom(foregroundColor: AppColors.red, side: const BorderSide(color: AppColors.red), minimumSize: const Size.fromHeight(48)),
            icon: const Icon(Icons.block_rounded),
            label: const Text('Annuler toute la sortie'),
          ),
        ],
      ],
    );
  }
}
