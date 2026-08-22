import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme.dart';
import '../../models/user_model.dart';
import '../../services/app_data_cache.dart';
import '../../services/credit_service.dart';
import '../../widgets/inline_field.dart';
import 'credit_detail_screen.dart';

String _fmt(double v) {
  final s = v.round().toString();
  final buf = StringBuffer();
  for (int i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(' ');
    buf.write(s[i]);
  }
  return '${buf.toString()} Ar';
}

/// Liste des clients ayant un solde impayé — miroir mobile de
/// `Clients/liste_client_credit`.
class CreditClientsScreen extends StatefulWidget {
  const CreditClientsScreen({super.key, required this.user});
  final UserModel user;

  @override
  State<CreditClientsScreen> createState() => _CreditClientsScreenState();
}

class _CreditClientsScreenState extends State<CreditClientsScreen> {
  final _searchCtrl = TextEditingController();
  List<CreditClient> _clients = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  /// Réutilise le cache préchargé au démarrage (voir AppDataCache) tant
  /// qu'aucun rechargement explicite n'est demandé — mêmes principes que
  /// VenteHomeScreen._load().
  Future<void> _load({bool forceNetwork = false}) async {
    if (!forceNetwork) {
      final cached = AppDataCache.instance.creditClients;
      if (cached != null) {
        setState(() {
          _clients = cached;
          _loading = false;
        });
        return;
      }
    }
    setState(() => _loading = true);
    final clients = await CreditService.instance.loadClients();
    if (!mounted) return;
    AppDataCache.instance.setCreditClients(clients);
    setState(() {
      _clients = clients;
      _loading = false;
    });
  }

  List<CreditClient> get _filtered {
    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isEmpty) return _clients;
    return _clients.where((c) => c.nomComplet.toLowerCase().contains(q) || (c.telephone ?? '').contains(q)).toList();
  }

  Future<void> _openDetail(CreditClient client) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => CreditDetailScreen(client: client, user: widget.user)),
    );
    if (changed == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final list = _filtered;
    final totalRestant = _clients.fold(0.0, (sum, c) => sum + c.restant);

    return Scaffold(
      backgroundColor: AppColors.bgDeep,
      appBar: AppBar(
        backgroundColor: AppColors.bgCard,
        elevation: 0,
        title: Text('Les crédits', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 17, color: AppColors.textPrimary)),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => _load(forceNetwork: true),
          color: AppColors.accentLight,
          backgroundColor: AppColors.bgCard,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!_loading && _clients.isNotEmpty)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [AppColors.accentGlow, Colors.transparent]),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.borderAccent),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.account_balance_wallet_rounded, color: AppColors.orange, size: 22),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Total dû (${_clients.length} client${_clients.length > 1 ? 's' : ''})',
                                  style: GoogleFonts.inter(fontSize: 11.5, color: AppColors.textMuted, fontWeight: FontWeight.w600)),
                              Text(_fmt(totalRestant), style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.orange)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                InlineField(label: 'Rechercher un client', controller: _searchCtrl, prefixIcon: Icons.search_rounded, onChanged: (_) => setState(() {})),
                const SizedBox(height: 14),
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accentLight))
                      : list.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.check_circle_outline_rounded, size: 42, color: AppColors.green),
                                  const SizedBox(height: 10),
                                  Text('Aucun crédit en attente', style: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 13)),
                                ],
                              ),
                            )
                          : ListView.separated(
                              itemCount: list.length,
                              separatorBuilder: (_, index) => const SizedBox(height: 10),
                              itemBuilder: (context, i) => _CreditClientCard(client: list[i], onTap: () => _openDetail(list[i])),
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

class _CreditClientCard extends StatelessWidget {
  const _CreditClientCard({required this.client, required this.onTap});
  final CreditClient client;
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
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(color: AppColors.accentGlow, borderRadius: BorderRadius.circular(21)),
                child: const Icon(Icons.person_rounded, color: AppColors.accentLight, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(client.nomComplet, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                    if (client.telephone != null) ...[
                      const SizedBox(height: 3),
                      Text(client.telephone!, style: GoogleFonts.inter(fontSize: 12, color: AppColors.textMuted)),
                    ],
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(_fmt(client.restant), style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w800, color: AppColors.orange)),
                  const SizedBox(height: 4),
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
