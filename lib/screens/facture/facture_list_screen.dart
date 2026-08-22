import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme.dart';
import '../../models/facture_model.dart';
import '../../models/user_model.dart';
import '../../services/app_data_cache.dart';
import '../../services/facture_service.dart';
import '../../widgets/inline_field.dart';
import 'facture_detail_screen.dart';

String _fmt(double v) {
  final s = v.round().toString();
  final buf = StringBuffer();
  for (int i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(' ');
    buf.write(s[i]);
  }
  return '${buf.toString()} Ar';
}

String _fmtDate(String? iso) {
  if (iso == null) return '-';
  final dt = DateTime.tryParse(iso);
  if (dt == null) return iso;
  String p2(int n) => n.toString().padLeft(2, '0');
  return '${p2(dt.day)}/${p2(dt.month)}/${dt.year} ${p2(dt.hour)}:${p2(dt.minute)}';
}

/// Liste des factures payées OU annulées — un seul écran paramétré par
/// [mode] plutôt que deux écrans quasi identiques : même mise en page en
/// cartes, même recherche/filtre par date que côté web
/// (`liste_Facture_payer.php`/`liste_Facture_cancel.php`), la seule
/// vraie différence entre les deux étant l'endpoint appelé et le libellé
/// de la colonne date (paiement vs annulation) — le mobile n'a de toute
/// façon pas de bouton "Annuler" à masquer, contrairement à la version web.
class FactureListScreen extends StatefulWidget {
  const FactureListScreen({super.key, required this.mode, required this.user});
  final FactureListMode mode;
  final UserModel user;

  @override
  State<FactureListScreen> createState() => _FactureListScreenState();
}

class _FactureListScreenState extends State<FactureListScreen> {
  final _searchCtrl = TextEditingController();
  DateTime? _date1;
  DateTime? _date2;
  List<FactureListItem> _list = [];
  bool _loading = true;
  String? _error;

  bool get _isPayee => widget.mode == FactureListMode.payee;
  String get _titre => _isPayee ? 'Factures payées' : 'Factures annulées';
  String get _labelDate => _isPayee ? 'Date de paiement' : "Date d'annulation";

  @override
  void initState() {
    super.initState();
    _loadFromCacheOrNetwork();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  /// Au premier affichage : réutilise le cache préchargé au démarrage
  /// (voir AppDataCache/splash_screen.dart) s'il est déjà rempli, sinon
  /// fait un vrai appel réseau — jamais d'attente inutile si les données
  /// sont déjà là.
  Future<void> _loadFromCacheOrNetwork() async {
    final cached = _isPayee ? AppDataCache.instance.facturesPayees : AppDataCache.instance.facturesAnnulees;
    if (cached != null) {
      setState(() {
        _list = cached;
        _loading = false;
      });
      return;
    }
    await _search();
  }

  /// Recherche/filtre : appelle toujours le réseau (une recherche doit
  /// refléter l'état actuel des données, jamais servie depuis un vieux
  /// cache) — mais met aussi à jour le cache si la recherche est "vide"
  /// (aucun filtre actif), pour que la prochaine ouverture de l'écran
  /// réutilise ce résultat frais sans nouvel appel.
  Future<void> _search() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final arg = _searchCtrl.text.trim();
    final d1 = _date1 == null ? null : _isoDate(_date1!);
    final d2 = _date2 == null ? null : _isoDate(_date2!);
    try {
      final list = _isPayee
          ? await FactureService.instance.loadPayees(arg: arg, date1: d1, date2: d2)
          : await FactureService.instance.loadAnnulees(arg: arg, date1: d1, date2: d2);
      if (!mounted) return;
      setState(() {
        _list = list;
        _loading = false;
      });
      // Résultat "sans filtre" : rafraîchit aussi le cache, pour que la
      // prochaine ouverture de cet écran réutilise ce résultat frais au
      // lieu de repartir sur le réseau.
      if (arg.isEmpty && d1 == null && d2 == null) {
        if (_isPayee) {
          AppDataCache.instance.setFacturesPayees(list);
        } else {
          AppDataCache.instance.setFacturesAnnulees(list);
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  String _isoDate(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _pickDate({required bool isDebut}) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: (isDebut ? _date1 : _date2) ?? now,
      firstDate: DateTime(now.year - 3),
      lastDate: now,
    );
    if (picked == null) return;
    setState(() {
      if (isDebut) {
        _date1 = picked;
      } else {
        _date2 = picked;
      }
    });
    _search();
  }

  Future<void> _openDetail(FactureListItem item) async {
    final changed = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => FactureDetailScreen(idClient: item.idClient, numeroFacture: item.numeroFacture, mode: widget.mode, user: widget.user),
    ));
    if (changed == true) _search();
  }

  @override
  Widget build(BuildContext context) {
    final totalMontant = _list.fold(0.0, (sum, f) => sum + f.montant);

    return Scaffold(
      backgroundColor: AppColors.bgDeep,
      appBar: AppBar(
        backgroundColor: AppColors.bgCard,
        elevation: 0,
        title: Text(_titre, style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 17, color: AppColors.textPrimary)),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _search,
          color: AppColors.accentLight,
          backgroundColor: AppColors.bgCard,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!_loading && _list.isNotEmpty)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 14),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [(_isPayee ? AppColors.accentGlow : AppColors.red.withValues(alpha: .16)), Colors.transparent]),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: _isPayee ? AppColors.borderAccent : AppColors.red.withValues(alpha: .3)),
                    ),
                    child: Row(children: [
                      Icon(_isPayee ? Icons.receipt_long_rounded : Icons.block_rounded, color: _isPayee ? AppColors.accentLight : AppColors.red, size: 22),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('${_list.length} facture${_list.length > 1 ? 's' : ''}',
                              style: GoogleFonts.inter(fontSize: 11.5, color: AppColors.textMuted, fontWeight: FontWeight.w600)),
                          Text(_fmt(totalMontant), style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w800, color: _isPayee ? AppColors.accentLight : AppColors.red)),
                        ]),
                      ),
                    ]),
                  ),
                InlineField(
                  label: 'N° facture, désignation, N° série, IMEI...',
                  controller: _searchCtrl,
                  prefixIcon: Icons.search_rounded,
                  onSubmitted: (_) => _search(),
                ),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(child: _DateChip(label: 'Du', value: _date1, onTap: () => _pickDate(isDebut: true))),
                  const SizedBox(width: 8),
                  Expanded(child: _DateChip(label: 'Au', value: _date2, onTap: () => _pickDate(isDebut: false))),
                  if (_date1 != null || _date2 != null)
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 18, color: AppColors.textMuted),
                      onPressed: () {
                        setState(() {
                          _date1 = null;
                          _date2 = null;
                        });
                        _search();
                      },
                    ),
                ]),
                const SizedBox(height: 12),
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accentLight))
                      : _error != null
                          ? Center(child: Text(_error!, style: GoogleFonts.inter(color: AppColors.red, fontSize: 13)))
                          : _list.isEmpty
                              ? Center(
                                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                                    Icon(Icons.inbox_rounded, size: 42, color: AppColors.textMuted),
                                    const SizedBox(height: 10),
                                    Text('Aucune facture trouvée', style: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 13)),
                                  ]),
                                )
                              : ListView.separated(
                                  itemCount: _list.length,
                                  separatorBuilder: (_, index) => const SizedBox(height: 10),
                                  itemBuilder: (context, i) => _FactureCard(
                                    item: _list[i],
                                    labelDate: _labelDate,
                                    accent: _isPayee ? AppColors.accentLight : AppColors.red,
                                    onTap: () => _openDetail(_list[i]),
                                  ),
                                ),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DateChip extends StatelessWidget {
  const _DateChip({required this.label, required this.value, required this.onTap});
  final String label;
  final DateTime? value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    String txt = label;
    if (value != null) {
      String p2(int n) => n.toString().padLeft(2, '0');
      txt = '${p2(value!.day)}/${p2(value!.month)}/${value!.year}';
    }
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.border)),
          child: Row(children: [
            const Icon(Icons.calendar_today_rounded, size: 14, color: AppColors.textMuted),
            const SizedBox(width: 8),
            Text(txt, style: GoogleFonts.inter(fontSize: 12.5, color: value != null ? AppColors.textPrimary : AppColors.textMuted)),
          ]),
        ),
      ),
    );
  }
}

class _FactureCard extends StatelessWidget {
  const _FactureCard({required this.item, required this.labelDate, required this.accent, required this.onTap});
  final FactureListItem item;
  final String labelDate;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: AppColors.bgCard, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(Icons.receipt_rounded, size: 16, color: accent),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(item.numeroFacture, style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w800, color: AppColors.textPrimary), overflow: TextOverflow.ellipsis),
                ),
                Text(_fmt(item.montant), style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w800, color: accent)),
              ]),
              if (item.articlesApercu != null) ...[
                const SizedBox(height: 4),
                Text(item.articlesApercu!, style: GoogleFonts.inter(fontSize: 11.5, color: AppColors.textMuted), maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(item.nomAffiche, style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.textSecondary), overflow: TextOverflow.ellipsis),
                    Text(item.contactAffiche, style: GoogleFonts.inter(fontSize: 11, color: AppColors.textMuted)),
                  ]),
                ),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text(labelDate, style: GoogleFonts.inter(fontSize: 9.5, color: AppColors.textMuted, letterSpacing: .03)),
                  Text(_fmtDate(item.dateReference), style: GoogleFonts.inter(fontSize: 11.5, color: AppColors.textSecondary)),
                ]),
                const SizedBox(width: 8),
                const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted, size: 20),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}
