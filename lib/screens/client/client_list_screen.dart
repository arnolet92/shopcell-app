import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme.dart';
import '../../models/user_model.dart';
import '../../services/client_service.dart';

/// Menu "Clients" : liste des clients, informations visibles directement.
/// Seuls patron et magasinier peuvent modifier un client.
class ClientListScreen extends StatefulWidget {
  const ClientListScreen({super.key, required this.user});
  final UserModel user;

  @override
  State<ClientListScreen> createState() => _ClientListScreenState();
}

class _ClientListScreenState extends State<ClientListScreen> {
  final _search = TextEditingController();
  Timer? _debounce;
  List<ClientModel> _clients = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final list = await ClientService.instance.liste(arg: _search.text);
    if (!mounted) return;
    setState(() {
      _clients = list;
      _loading = false;
    });
  }

  void _onSearch(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _load);
  }

  Future<void> _edit(ClientModel c) async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.bgCard,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (_) => _ClientEditSheet(client: c, user: widget.user),
    );
    if (ok == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final canEdit = widget.user.canEditClient;
    return Scaffold(
      appBar: AppBar(title: Text('Clients', style: GoogleFonts.inter(fontWeight: FontWeight.w800))),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _search,
              onChanged: _onSearch,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search_rounded),
                hintText: 'Nom, prénom, téléphone, CIN…',
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _load,
                    child: _clients.isEmpty
                        ? ListView(children: [
                            const SizedBox(height: 80),
                            Center(child: Text('Aucun client', style: GoogleFonts.inter(color: AppColors.textMuted))),
                          ])
                        : ListView.builder(
                            padding: const EdgeInsets.only(bottom: 24),
                            itemCount: _clients.length,
                            itemBuilder: (_, i) => _ClientCard(client: _clients[i], onEdit: canEdit ? () => _edit(_clients[i]) : null),
                          ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _ClientCard extends StatelessWidget {
  const _ClientCard({required this.client, this.onEdit});
  final ClientModel client;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final c = client;
    final infos = <(IconData, String)>[
      if (c.telephone != null) (Icons.phone_rounded, c.telephone!),
      if (c.email != null) (Icons.mail_outline_rounded, c.email!),
      if (c.adresse != null) (Icons.place_outlined, c.adresse!),
      if (c.cin != null) (Icons.badge_outlined, 'CIN : ${c.cin}'),
      if (c.nif != null) (Icons.receipt_outlined, 'NIF : ${c.nif}'),
      if (c.stat != null) (Icons.receipt_outlined, 'STAT : ${c.stat}'),
    ];
    final nomComplet = [c.nom, if (c.prenom != null) c.prenom!].join(' ');
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: BoxDecoration(
        color: AppColors.bgElevated,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderAccent),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: AppColors.accentGlow,
            child: Text(
              nomComplet.isEmpty ? '?' : nomComplet.characters.first.toUpperCase(),
              style: GoogleFonts.inter(fontWeight: FontWeight.w800, color: AppColors.accentLight),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(nomComplet, style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                if (infos.isNotEmpty) const SizedBox(height: 6),
                Wrap(
                  spacing: 10,
                  runSpacing: 5,
                  children: [
                    for (final (icon, label) in infos)
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(icon, size: 13, color: AppColors.accentLight),
                        const SizedBox(width: 4),
                        Text(label, style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondary)),
                      ]),
                  ],
                ),
              ],
            ),
          ),
          if (onEdit != null)
            IconButton(icon: const Icon(Icons.edit_rounded, size: 18, color: AppColors.textMuted), tooltip: 'Modifier', onPressed: onEdit),
        ],
      ),
    );
  }
}

class _ClientEditSheet extends StatefulWidget {
  const _ClientEditSheet({required this.client, required this.user});
  final ClientModel client;
  final UserModel user;

  @override
  State<_ClientEditSheet> createState() => _ClientEditSheetState();
}

class _ClientEditSheetState extends State<_ClientEditSheet> {
  static const _champs = [
    ('nom_complet', 'Nom'),
    ('prenom_personnes', 'Prénom'),
    ('telephone', 'Téléphone'),
    ('email', 'Email'),
    ('adresse', 'Adresse'),
    ('cin_personnes', 'CIN'),
    ('nif_personnes', 'NIF'),
    ('stat_personnes', 'STAT'),
  ];
  late final Map<String, TextEditingController> _ctrl = {
    for (final (k, _) in _champs) k: TextEditingController(text: widget.client.field(k) ?? ''),
  };
  bool _saving = false;

  @override
  void dispose() {
    for (final c in _ctrl.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_ctrl['nom_complet']!.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Le nom est obligatoire.')));
      return;
    }
    setState(() => _saving = true);
    final (ok, msg) = await ClientService.instance.modifier(
      user: widget.user,
      idPersonnes: widget.client.id,
      champs: {for (final e in _ctrl.entries) e.key: e.value.text.trim()},
    );
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg.isNotEmpty ? msg : (ok ? 'Client modifié.' : 'Échec.'))));
    if (ok) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
          children: [
            Text('Modifier le client', style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
            const SizedBox(height: 14),
            for (final (k, label) in _champs) ...[
              TextField(controller: _ctrl[k], decoration: InputDecoration(labelText: label)),
              const SizedBox(height: 10),
            ],
            const SizedBox(height: 6),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.save_rounded),
              label: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
  }
}
