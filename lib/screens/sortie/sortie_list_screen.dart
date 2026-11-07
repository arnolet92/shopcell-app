import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme.dart';
import '../../models/user_model.dart';
import '../../services/sortie_service.dart';
import '../../widgets/gradient_button.dart';
import '../../widgets/inline_field.dart';
import 'sortie_detail_screen.dart';
import 'sortie_new_screen.dart';

Color sortieStatutColor(String statut) {
  if (statut == 'Annulée') return AppColors.red;
  if (statut == 'Annulée en partie') return AppColors.orange;
  return AppColors.green;
}

/// "Les sorties" : archive des sorties de stock, avec "Nouvelle sortie" en haut.
class SortieListScreen extends StatefulWidget {
  const SortieListScreen({super.key, required this.user});
  final UserModel user;

  @override
  State<SortieListScreen> createState() => _SortieListScreenState();
}

class _SortieListScreenState extends State<SortieListScreen> {
  final _searchCtrl = TextEditingController();
  Timer? _debounce;
  List<SortieResume> _list = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final arg = _searchCtrl.text;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await SortieService.instance.liste(arg: arg);
      if (!mounted || arg != _searchCtrl.text) return;
      setState(() {
        _list = list;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Impossible de charger les sorties.';
        _loading = false;
      });
    }
  }

  void _onSearch(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _load);
  }

  Future<void> _nouvelle() async {
    final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => SortieNewScreen(user: widget.user)));
    if (saved == true) _load();
  }

  Future<void> _ouvrir(SortieResume s) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => SortieDetailScreen(user: widget.user, idSortie: s.id)));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDeep,
      appBar: AppBar(
        backgroundColor: AppColors.bgCard,
        elevation: 0,
        title: Text('Les sorties', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 17, color: AppColors.textPrimary)),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: Column(
            children: [
              GradientButton(label: 'Nouvelle sortie', icon: Icons.add_rounded, onPressed: _nouvelle),
              const SizedBox(height: 12),
              InlineField(label: 'N°, note, article, N° série, IMEI...', controller: _searchCtrl, prefixIcon: Icons.search_rounded, onChanged: _onSearch),
              const SizedBox(height: 12),
              Expanded(child: _contenu()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _contenu() {
    if (_loading) return const Center(child: CircularProgressIndicator(color: AppColors.accentLight));
    if (_error != null) return Center(child: Text(_error!, style: const TextStyle(color: AppColors.red)));
    if (_list.isEmpty) {
      return Center(child: Text('Aucune sortie', style: GoogleFonts.inter(color: AppColors.textSecondary, fontSize: 13.5)));
    }
    return RefreshIndicator(
      onRefresh: _load,
      color: AppColors.accentLight,
      backgroundColor: AppColors.bgCard,
      child: ListView.separated(
        itemCount: _list.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, i) {
          final s = _list[i];
          return InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => _ouvrir(s),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: AppColors.bgCard, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(child: Text(s.numero, style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 13.5, color: AppColors.textPrimary))),
                    Text(s.statut, style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 11.5, color: sortieStatutColor(s.statut))),
                  ]),
                  const SizedBox(height: 6),
                  Text(s.note, maxLines: 2, overflow: TextOverflow.ellipsis, style: GoogleFonts.inter(fontSize: 12.5, color: AppColors.textSecondary)),
                  const SizedBox(height: 6),
                  Text('${s.date} · ${s.nbLignes} article${s.nbLignes > 1 ? 's' : ''} · ${s.nomUser}',
                      style: GoogleFonts.inter(fontSize: 11, color: AppColors.textMuted)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
