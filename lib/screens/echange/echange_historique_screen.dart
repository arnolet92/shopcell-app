import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme.dart';
import '../../models/user_model.dart';
import '../../services/echange_service.dart';
import '../../services/echange_print.dart';
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

String _iso(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Historique des échanges archivés (`Mob/echange_historique`) — permet de
/// ré-imprimer le ticket/A4 d'un échange à tout moment. Miroir de la section
/// "Historique des échanges" de `Echange/index` (web).
class EchangeHistoriqueScreen extends StatefulWidget {
  const EchangeHistoriqueScreen({super.key, required this.user});
  final UserModel user;

  @override
  State<EchangeHistoriqueScreen> createState() => _EchangeHistoriqueScreenState();
}

class _EchangeHistoriqueScreenState extends State<EchangeHistoriqueScreen> {
  final _searchCtrl = TextEditingController();
  Timer? _debounce;
  DateTime _date1 = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _date2 = DateTime.now();

  List<EchangeHistoItem> _list = [];
  bool _loading = true;
  String? _printingId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final list = await EchangeService.instance.historique(
      arg: _searchCtrl.text,
      date1: _iso(_date1),
      date2: _iso(_date2),
    );
    if (!mounted) return;
    setState(() {
      _list = list;
      _loading = false;
    });
  }

  void _onSearch(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _load);
  }

  Future<void> _pickDate({required bool debut}) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: debut ? _date1 : _date2,
      firstDate: DateTime(now.year - 4),
      lastDate: now,
    );
    if (picked == null) return;
    setState(() {
      if (debut) {
        _date1 = picked;
      } else {
        _date2 = picked;
      }
    });
    _load();
  }

  Future<void> _reprint(EchangeHistoItem item) async {
    if (_printingId != null) return;
    setState(() => _printingId = item.idEchange);
    // Même document que celui imprimé depuis la liste des factures payées
    // (voir echange_print.dart) : article REMIS en ligne principale,
    // article RETOURNÉ en bas.
    final message = await printEchangeFromJson(
      context,
      item.raw,
      user: widget.user,
      numeroFacture: item.numeroFacture,
    );
    if (!mounted) return;
    setState(() => _printingId = null);
    if (message.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDeep,
      appBar: AppBar(
        backgroundColor: AppColors.bgCard,
        elevation: 0,
        title: Text('Historique des échanges', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 16, color: AppColors.textPrimary)),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
              child: Column(
                children: [
                  InlineField(
                    label: 'Rechercher (désignation, N° série, IMEI, modèle...)',
                    controller: _searchCtrl,
                    prefixIcon: Icons.search_rounded,
                    onChanged: _onSearch,
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(child: _DateButton(label: 'Du', date: _date1, onTap: () => _pickDate(debut: true))),
                      const SizedBox(width: 10),
                      Expanded(child: _DateButton(label: 'Au', date: _date2, onTap: () => _pickDate(debut: false))),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accentLight))
                  : _list.isEmpty
                      ? Center(child: Text('Aucun échange sur cette période', style: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 13)))
                      : RefreshIndicator(
                          onRefresh: _load,
                          color: AppColors.accentLight,
                          backgroundColor: AppColors.bgCard,
                          child: ListView.separated(
                            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                            itemCount: _list.length,
                            separatorBuilder: (_, index) => const SizedBox(height: 10),
                            itemBuilder: (context, i) => _EchangeCard(
                              item: _list[i],
                              printing: _printingId == _list[i].idEchange,
                              onReprint: () => _reprint(_list[i]),
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

class _DateButton extends StatelessWidget {
  const _DateButton({required this.label, required this.date, required this.onTap});
  final String label;
  final DateTime date;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.bgCard,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.border)),
          child: Row(
            children: [
              const Icon(Icons.calendar_today_rounded, size: 14, color: AppColors.textMuted),
              const SizedBox(width: 8),
              Text('$label ${_iso(date)}', style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondary)),
            ],
          ),
        ),
      ),
    );
  }
}

class _EchangeCard extends StatelessWidget {
  const _EchangeCard({required this.item, required this.printing, required this.onReprint});
  final EchangeHistoItem item;
  final bool printing;
  final VoidCallback onReprint;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: item.isAnnule ? AppColors.red.withValues(alpha: .35) : AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Facture ${item.numeroFacture}', style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
              ),
              if (item.isAnnule)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: AppColors.red.withValues(alpha: .12), borderRadius: BorderRadius.circular(20)),
                  child: Text('Annulé', style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w700, color: AppColors.red)),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(item.dateGest, style: GoogleFonts.inter(fontSize: 11, color: AppColors.textMuted)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: Text(item.oldDesignation, style: GoogleFonts.inter(fontSize: 12.5, color: AppColors.textSecondary), overflow: TextOverflow.ellipsis)),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 6),
                child: Icon(Icons.arrow_forward_rounded, size: 14, color: AppColors.accentLight),
              ),
              Expanded(child: Text(item.newDesignation, style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.textPrimary), overflow: TextOverflow.ellipsis)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Supplément : ${_fmt(item.prixAjoute)}', style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.green)),
              TextButton.icon(
                onPressed: printing ? null : onReprint,
                icon: printing
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accentLight))
                    : const Icon(Icons.print_rounded, size: 16, color: AppColors.accentLight),
                label: Text(printing ? '...' : 'Imprimer', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.accentLight)),
                style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
