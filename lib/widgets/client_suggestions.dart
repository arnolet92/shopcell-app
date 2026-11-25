import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/theme.dart';
import '../models/personne_model.dart';
import '../services/vente_service.dart';

/// Liste des clients (`Mob/allpersonnes`) gardée en mémoire pour les
/// suggestions : rechargée après création d'un client, ou si elle date de
/// plus de 2 minutes (clients créés par un échange ou depuis le web).
class ClientDirectory {
  ClientDirectory._();
  static final ClientDirectory instance = ClientDirectory._();

  List<PersonneModel>? _clients;
  DateTime? _chargeLe;
  Future<List<PersonneModel>>? _loading;

  Future<List<PersonneModel>> get({bool refresh = false}) {
    final frais = _chargeLe != null && DateTime.now().difference(_chargeLe!) < const Duration(minutes: 2);
    if (!refresh && _clients != null && frais) return Future.value(_clients!);
    if (!refresh && _loading != null) return _loading!;
    _loading = VenteService.instance.loadClients().then((list) {
      _clients = list;
      _chargeLe = DateTime.now();
      _loading = null;
      return list;
    }).catchError((_) {
      _loading = null;
      return _clients ?? <PersonneModel>[];
    });
    return _loading!;
  }

  void invalidate() => _clients = null;

  /// Clients dont le nom, le prénom, le téléphone ou le CIN contient chacun
  /// des mots tapés ("jean de" trouve "Jean Denis").
  static List<PersonneModel> filtrer(List<PersonneModel> clients, String saisie, {int max = 6}) {
    final mots = saisie.trim().toLowerCase().split(RegExp(r'\s+')).where((m) => m.isNotEmpty).toList();
    if (mots.isEmpty || saisie.trim().length < 2) return const [];
    return clients.where((c) {
      final texte = '${c.nomComplet} ${c.prenom ?? ''} ${c.telephone ?? ''} ${c.cin ?? ''}'.toLowerCase();
      return mots.every(texte.contains);
    }).take(max).toList();
  }
}

/// Suggestions de clients existants sous un champ "Nom" : apparaît dès 2
/// caractères tapés, un tap choisit le client ([onSelect]). Masquée une fois
/// un client choisi, jusqu'à la prochaine modification du champ.
class ClientSuggestions extends StatefulWidget {
  const ClientSuggestions({super.key, required this.controller, required this.onSelect});
  final TextEditingController controller;
  final ValueChanged<PersonneModel> onSelect;

  @override
  State<ClientSuggestions> createState() => _ClientSuggestionsState();
}

class _ClientSuggestionsState extends State<ClientSuggestions> {
  List<PersonneModel> _clients = const [];
  String? _texteChoisi;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChange);
    ClientDirectory.instance.get().then((c) {
      if (mounted) setState(() => _clients = c);
    });
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final saisie = widget.controller.text;
    if (_texteChoisi != null && saisie == _texteChoisi) return const SizedBox.shrink();
    final list = ClientDirectory.filtrer(_clients, saisie);
    if (list.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(top: 6),
      decoration: BoxDecoration(
        color: AppColors.bgElevated,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 2),
            child: Text('Clients existants', style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w700, color: AppColors.textMuted)),
          ),
          for (final c in list)
            ListTile(
              dense: true,
              visualDensity: VisualDensity.compact,
              leading: const Icon(Icons.account_circle_rounded, color: AppColors.accentLight),
              title: Text('${c.nomComplet} ${c.prenom ?? ''}'.trim(), style: const TextStyle(color: AppColors.textPrimary, fontSize: 13)),
              subtitle: Text(
                [c.telephone, if ((c.cin ?? '').isNotEmpty) 'CIN ${c.cin}'].whereType<String>().join(' · '),
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
              ),
              onTap: () {
                widget.onSelect(c);
                setState(() => _texteChoisi = widget.controller.text);
                FocusScope.of(context).unfocus();
              },
            ),
        ],
      ),
    );
  }
}
