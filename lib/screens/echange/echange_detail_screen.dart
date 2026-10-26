import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme.dart';
import '../../models/lookup_model.dart';
import '../../models/payment_split.dart';
import '../../models/personne_model.dart';
import '../../models/produit_model.dart';
import '../../models/receipt_line.dart';
import '../../models/user_model.dart';
import '../../services/app_data_cache.dart';
import '../../services/echange_service.dart';
import '../../services/receipt_print_service.dart';
import '../../services/vente_service.dart';
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

const _violet = Color(0xFF8B5CF6);
const _rouge = Color(0xFFEF4444);
const _carte = Color(0xFF0F172A);
const _carte2 = Color(0xFF111C33);
const _ligne = Color(0xFF1F2A44);

/// Un appareil de la facture sélectionné pour l'échange.
class _Item {
  _Item({required this.ligne})
      : prixActuelCtrl = TextEditingController(text: _num(ligne['prix_ventes']).toStringAsFixed(0)),
        batterieCtrl = TextEditingController(text: '${ligne['nom_sous_categorie_piece'] ?? ''}'.trim());

  final Map<String, dynamic> ligne;
  ProduitModel? nouveau;
  final TextEditingController prixActuelCtrl;
  final TextEditingController motifCtrl = TextEditingController();
  final TextEditingController batterieCtrl;
  final TextEditingController rechercheCtrl = TextEditingController();
  List<ProduitModel> resultats = [];
  Timer? timer;
  bool nonUpgrade = false;
  bool isDefaut = false;

  String get idVentes => '${ligne['id_ventes']}';
  String get designation => '${ligne['designation_produits'] ?? 'Article'}';

  void dispose() {
    prixActuelCtrl.dispose();
    motifCtrl.dispose();
    batterieCtrl.dispose();
    rechercheCtrl.dispose();
    timer?.cancel();
  }

  static double _num(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
}

class _Paiement {
  _Paiement(this.typeId) : ctrl = TextEditingController(text: '0');
  String? typeId;
  final TextEditingController ctrl;
  double get montant => double.tryParse(ctrl.text.replaceAll(' ', '')) ?? 0;
}

/// Échange d'un ou plusieurs appareils d'une même facture : chaque appareil
/// repris a son "Prix actuel" (modifiable) et son "Prix ajouté" (calculé),
/// le montant à payer porte sur le total. La somme donnée vaut 0 par
/// défaut : payée en totalité → "Valider l'échange" ; sinon → "Réserver
/// l'échange" (aucun mouvement de stock) ou "Valider en crédit" (échange
/// fait, reste en crédit) — le nom du client est alors obligatoire. Les
/// coordonnées saisies sont enregistrées (suggestions depuis les clients).
/// Miroir mobile de `Echange/index` (web).
class EchangeDetailScreen extends StatefulWidget {
  const EchangeDetailScreen({super.key, required this.idVentes, required this.user});
  final String idVentes;
  final UserModel user;

  @override
  State<EchangeDetailScreen> createState() => _EchangeDetailScreenState();
}

class _EchangeDetailScreenState extends State<EchangeDetailScreen> {
  bool _loading = true;
  Map<String, dynamic>? _facture;
  List<Map<String, dynamic>> _lignes = [];
  final Map<String, _Item> _items = {};

  EchangeRecapMulti? _recap;
  bool _recapLoading = false;
  int _recapSeq = 0;
  Timer? _recapTimer;

  List<LookupItem> _types = [];
  final List<_Paiement> _paiements = [];

  final _nomCtrl = TextEditingController();
  final _prenomCtrl = TextEditingController();
  final _telCtrl = TextEditingController();
  final _cinCtrl = TextEditingController();
  String? _idPersonnes;
  List<PersonneModel> _clients = [];
  List<PersonneModel> _suggestions = [];

  bool _submitting = false;
  bool _proformaSubmitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
    VenteService.instance.loadTypesPaiement().then((types) {
      if (!mounted) return;
      setState(() {
        _types = types;
        if (_paiements.isEmpty) _paiements.add(_Paiement(types.isNotEmpty ? types.first.id : null));
      });
    });
    VenteService.instance.loadClients().then((c) {
      if (mounted) _clients = c;
    });
  }

  @override
  void dispose() {
    for (final it in _items.values) {
      it.dispose();
    }
    for (final p in _paiements) {
      p.ctrl.dispose();
    }
    _nomCtrl.dispose();
    _prenomCtrl.dispose();
    _telCtrl.dispose();
    _cinCtrl.dispose();
    _recapTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final facture = await EchangeService.instance.factureDetail(widget.idVentes);
    if (!mounted) return;
    final lignes = ((facture?['lignes'] as List?) ?? []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    final entete = facture?['entete'] as Map?;
    setState(() {
      _facture = facture;
      _lignes = lignes;
      _loading = false;
      final init = lignes.where((l) => '${l['id_ventes']}' == widget.idVentes);
      if (init.isNotEmpty) _items[widget.idVentes] = _Item(ligne: init.first);
      _nomCtrl.text = '${entete?['nom_complet'] ?? ''}'.trim();
      _prenomCtrl.text = '${entete?['prenom_personnes'] ?? ''}'.trim();
      _telCtrl.text = '${entete?['telephone'] ?? ''}'.trim();
      _cinCtrl.text = '${entete?['cin_personnes'] ?? ''}'.trim();
      final pid = '${entete?['personnes_id'] ?? ''}'.trim();
      _idPersonnes = pid.isEmpty ? null : pid;
    });
  }

  Map<String, dynamic>? get _entete => _facture?['entete'] as Map<String, dynamic>?;

  List<_Item> get _selection => _lignes.map((l) => _items['${l['id_ventes']}']).whereType<_Item>().toList();
  bool get _complet => _selection.isNotEmpty && _selection.every((i) => i.nouveau != null);
  double get _somme => _paiements.fold(0.0, (s, p) => s + p.montant);
  double get _reste => _recap?.reste ?? 0;
  bool get _insuffisant => _recap != null && _somme < _reste;

  List<EchangeItem> _payload({bool complets = true}) => _selection
      .where((i) => !complets || i.nouveau != null)
      .map((i) => EchangeItem(
            idVentes: i.idVentes,
            newProduitsId: i.nouveau?.idProduits,
            prixActuelRepris: double.tryParse(i.prixActuelCtrl.text.replaceAll(' ', '')),
            nonUpgrade: i.nonUpgrade,
            isDefaut: i.isDefaut,
            motifReparation: i.motifCtrl.text,
            batterie: i.batterieCtrl.text,
          ))
      .toList();

  void _toggleLigne(Map<String, dynamic> l, bool on) {
    final id = '${l['id_ventes']}';
    setState(() {
      if (on) {
        _items.putIfAbsent(id, () => _Item(ligne: l));
      } else {
        _items.remove(id)?.dispose();
      }
    });
    _planifierRecap(immediat: true);
  }

  void _planifierRecap({bool immediat = false}) {
    _recapTimer?.cancel();
    _recapTimer = Timer(Duration(milliseconds: immediat ? 0 : 450), _refreshRecap);
  }

  Future<void> _refreshRecap() async {
    final items = _payload();
    if (items.isEmpty) {
      setState(() => _recap = null);
      return;
    }
    final seq = ++_recapSeq;
    setState(() => _recapLoading = true);
    final rec = await EchangeService.instance.recapMulti(items);
    if (!mounted || seq != _recapSeq) return;
    setState(() {
      _recapLoading = false;
      _recap = rec.error ? null : rec;
      _error = rec.error ? rec.message : null;
    });
  }

  void _rechercher(_Item it, String v) {
    it.timer?.cancel();
    it.timer = Timer(const Duration(milliseconds: 350), () async {
      final res = v.trim().isEmpty ? <ProduitModel>[] : await EchangeService.instance.searchNewProduit(v);
      if (!mounted) return;
      setState(() => it.resultats = res);
    });
  }

  void _choisir(_Item it, ProduitModel p) {
    setState(() {
      it.nouveau = p;
      it.resultats = [];
      it.rechercheCtrl.clear();
    });
    _planifierRecap(immediat: true);
  }

  void _onNom(String v) {
    final q = v.trim().toLowerCase();
    setState(() {
      if (q.isEmpty) _idPersonnes = null;
      _suggestions = q.length < 2
          ? []
          : _clients
              .where((c) =>
                  c.nomComplet.toLowerCase().contains(q) ||
                  (c.prenom ?? '').toLowerCase().contains(q) ||
                  (c.telephone ?? '').toLowerCase().contains(q) ||
                  (c.cin ?? '').toLowerCase().contains(q))
              .take(6)
              .toList();
    });
  }

  void _choisirClient(PersonneModel c) {
    setState(() {
      _idPersonnes = c.id;
      _nomCtrl.text = c.nomComplet;
      _prenomCtrl.text = c.prenom ?? '';
      _telCtrl.text = c.telephone ?? '';
      _cinCtrl.text = c.cin ?? '';
      _suggestions = [];
    });
    FocusScope.of(context).unfocus();
  }

  EchangeClientInfo get _client => EchangeClientInfo(
        idPersonnes: _idPersonnes,
        nom: _nomCtrl.text,
        prenom: _prenomCtrl.text,
        telephone: _telCtrl.text,
        cin: _cinCtrl.text,
      );

  List<PaymentSplit> get _splits => _paiements
      .where((p) => p.montant != 0 && p.typeId != null)
      .map((p) => PaymentSplit(
            idTypePaiement: p.typeId!,
            typeLabel: _types.firstWhere((t) => t.id == p.typeId, orElse: () => LookupItem(id: '', label: 'Paiement')).label,
            montant: p.montant,
          ))
      .toList();

  Future<void> _confirmer(String mode) async {
    final rec = _recap;
    if (rec == null || !_complet) {
      setState(() => _error = "Choisissez l'appareil remis pour chaque article.");
      return;
    }
    for (final it in _selection) {
      if (it.isDefaut && it.motifCtrl.text.trim().isEmpty) {
        setState(() => _error = 'Précisez le motif de réparation de : ${it.designation}');
        return;
      }
    }
    if (mode != 'normal' && _nomCtrl.text.trim().isEmpty) {
      setState(() => _error = mode == 'credit'
          ? 'Le nom du client est obligatoire pour un échange en crédit.'
          : 'Le nom du client est obligatoire pour une réservation.');
      return;
    }
    final titres = {'normal': "Valider l'échange ?", 'credit': "Valider en crédit ?", 'reservation': "Réserver l'échange ?"};
    final textes = {
      'normal': 'Les appareils repris reviennent en stock et les nouveaux en sortent.',
      'credit': "L'échange est fait maintenant ; le reste (${_fmt(_reste - _somme)}) devient un crédit du client.",
      'reservation': "Aucun appareil ne bouge en stock : ils sont verrouillés jusqu'au paiement complet (${_fmt(_reste - _somme)} restant).",
    };
    final couleurs = {'normal': AppColors.accent, 'credit': _rouge, 'reservation': _violet};
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _carte,
        title: Text(titres[mode]!, style: const TextStyle(color: AppColors.textPrimary)),
        content: Text(
          '${rec.items.length} appareil(s) · Montant à payer ${_fmt(_reste)}\n${textes[mode]}',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Retour')),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: Text('Confirmer', style: TextStyle(color: couleurs[mode]))),
        ],
      ),
    );
    if (ok != true) return;

    setState(() {
      _submitting = true;
      _error = null;
    });
    final splits = _splits;
    final res = mode == 'reservation'
        ? await EchangeService.instance.reserverMulti(items: _payload(), paiements: splits, client: _client, user: widget.user)
        : await EchangeService.instance.validerMulti(items: _payload(), paiements: splits, mode: mode, client: _client, user: widget.user);
    if (!mounted) return;
    if (!res.success) {
      setState(() {
        _submitting = false;
        _error = res.message;
      });
      return;
    }
    AppDataCache.instance.invalidate(CacheDomain.produits);
    AppDataCache.instance.invalidate(CacheDomain.facturesPayees);
    AppDataCache.instance.invalidate(CacheDomain.creditClients);

    final printMessage = await _imprimer(
      rec,
      reservation: mode == 'reservation',
      credit: mode == 'credit' && res.isCredit,
      paiements: splits,
    );
    if (!mounted) return;
    Navigator.of(context).pop(true);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${res.message ?? ''} $printMessage')));
  }

  /// Reçu A4 / ticket : appareils remis dans le tableau, appareils repris
  /// à part. Crédit et réservation : récapitulatif total / somme donnée
  /// par type / reste.
  Future<String> _imprimer(EchangeRecapMulti rec,
      {bool reservation = false, bool credit = false, bool proforma = false, List<PaymentSplit> paiements = const []}) {
    final parId = {for (final i in _selection) i.idVentes: i};
    final recap = reservation || credit;
    final lines = rec.items.map((l) {
      final p = parId[l.idVentes]?.nouveau;
      // Crédit / réservation : le supplément de chaque appareil (le total du
      // tableau = montant à payer). Sinon, règle habituelle : supplément, ou
      // prix de vente si aucun supplément.
      final pu = recap ? l.prixAjoute : (l.prixAjoute != 0 ? l.prixAjoute : l.newPrixUnitaire);
      return ReceiptLine(
        designation: l.newDesignation,
        qte: l.qte,
        prixUnitaire: pu,
        total: pu * l.qte,
        numSerie: p?.numSerie,
        imei1: p?.imei1,
        imei2: p?.imei2,
        nomModel: p?.nomModel,
        nomMarque: p?.nomMarque,
      );
    }).toList();
    final retournes = rec.items.map((l) {
      final ligne = parId[l.idVentes]?.ligne;
      return ReceiptLine(
        designation: l.oldDesignation,
        qte: l.qte,
        prixUnitaire: 0,
        total: 0,
        nomMarque: ligne == null ? null : '${ligne['nom_marque'] ?? ''}'.trim().isEmpty ? null : '${ligne['nom_marque']}',
      );
    }).toList();
    final totalTableau = lines.fold(0.0, (s, l) => s + l.total);
    return ReceiptPrintService.instance.offerPrint(
      context,
      lines: lines,
      total: recap ? rec.reste : totalTableau,
      cashierName: widget.user.nomComplet,
      clientName: _nomCtrl.text.trim().isEmpty ? null : _nomCtrl.text.trim(),
      clientPrenom: _prenomCtrl.text.trim().isEmpty ? null : _prenomCtrl.text.trim(),
      clientTelephone: _telCtrl.text.trim().isEmpty ? null : _telCtrl.text.trim(),
      clientCin: _cinCtrl.text.trim().isEmpty ? null : _cinCtrl.text.trim(),
      numeroFacture: _entete?['numero_facture']?.toString(),
      isEchange: true,
      isProforma: proforma,
      isEchangeReservation: reservation,
      isEchangeCredit: credit,
      articlesRetournes: retournes,
      paiements: recap ? paiements : null,
    );
  }

  Future<void> _proforma() async {
    final rec = _recap;
    if (rec == null) return;
    setState(() => _proformaSubmitting = true);
    final msg = await _imprimer(rec, proforma: true);
    if (!mounted) return;
    setState(() => _proformaSubmitting = false);
    if (msg.isNotEmpty) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // =====================================================================
  // Affichage
  // =====================================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDeep,
      appBar: AppBar(
        backgroundColor: AppColors.bgCard,
        elevation: 0,
        title: Text("Échange d'appareils", style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 17, color: AppColors.textPrimary)),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accentLight))
            : _facture == null
                ? Center(child: Text('Facture introuvable', style: GoogleFonts.inter(color: AppColors.textMuted)))
                : GestureDetector(
                    onTap: () => setState(() => _suggestions = []),
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
                      children: [
                        _enteteCard(),
                        const SizedBox(height: 16),
                        _titre(Icons.phone_iphone_rounded, 'Appareils de la facture', 'Activez ceux que le client rapporte'),
                        ..._lignes.map(_deviceTile),
                        const SizedBox(height: 10),
                        _titre(Icons.swap_horiz_rounded, 'Appareils échangés', null),
                        if (_selection.isEmpty)
                          _vide('Activez au moins un appareil de la facture.')
                        else
                          ..._selection.asMap().entries.map((e) => _itemCard(e.key + 1, e.value)),
                        const SizedBox(height: 6),
                        _resumeCard(),
                        const SizedBox(height: 14),
                        _paiementCard(),
                        const SizedBox(height: 14),
                        _clientCard(),
                        if (_error != null) ...[
                          const SizedBox(height: 12),
                          Text(_error!, style: const TextStyle(color: AppColors.red, fontSize: 12.5)),
                        ],
                        const SizedBox(height: 16),
                        ..._actions(),
                      ],
                    ),
                  ),
      ),
    );
  }

  Widget _titre(IconData icon, String titre, String? sous) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, top: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.accentLight),
          const SizedBox(width: 8),
          Text(titre, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
          if (sous != null) ...[
            const SizedBox(width: 8),
            Expanded(child: Text(sous, overflow: TextOverflow.ellipsis, style: GoogleFonts.inter(fontSize: 11, color: AppColors.textSecondary))),
          ],
        ],
      ),
    );
  }

  Widget _vide(String t) => Container(
        padding: const EdgeInsets.all(18),
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: _ligne)),
        child: Text(t, textAlign: TextAlign.center, style: GoogleFonts.inter(color: AppColors.textSecondary, fontSize: 12.5)),
      );

  Widget _enteteCard() {
    final e = _entete;
    final nom = '${e?['nom_complet'] ?? ''}'.trim();
    final total = (_facture?['total_avant_remise'] as num?)?.toDouble() ?? 0;
    final paye = (_facture?['deja_paye'] as num?)?.toDouble() ?? 0;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(colors: [Color(0xFF0B2A22), Color(0xFF0F172A)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        border: Border.all(color: AppColors.borderAccent),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), gradient: AppColors.accentGradient),
                child: const Icon(Icons.receipt_long_rounded, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Facture ${e?['numero_facture'] ?? '-'}', style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 15, color: AppColors.textPrimary)),
                    Text(nom.isEmpty ? 'Client passant' : nom, style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondary)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: _stat('Total facture', _fmt(total))),
              Expanded(child: _stat('Déjà payé', _fmt(paye))),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stat(String label, String value) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: GoogleFonts.inter(fontSize: 10.5, color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text(value, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
        ],
      );

  String _meta(Map<String, dynamic> l) {
    final m = <String>[];
    for (final k in ['num_serie', 'imei1', 'nom_model', 'nom_marque']) {
      final v = '${l[k] ?? ''}'.trim();
      if (v.isNotEmpty) m.add(v);
    }
    return m.join(' · ');
  }

  Widget _deviceTile(Map<String, dynamic> l) {
    final id = '${l['id_ventes']}';
    final on = _items.containsKey(id);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: on ? const Color(0xFF0D2620) : _carte,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: on ? AppColors.borderAccent : _ligne),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(color: _carte2, borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.smartphone_rounded, color: AppColors.blue, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${l['designation_produits'] ?? '-'}', maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                Text(_meta(l), maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.inter(fontSize: 10.5, color: AppColors.textSecondary)),
                Text(_fmt(_Item._num(l['prix_ventes'])), style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.accentLight)),
              ],
            ),
          ),
          Switch(value: on, activeThumbColor: AppColors.accentLight, onChanged: (v) => _toggleLigne(l, v)),
        ],
      ),
    );
  }

  Widget _itemCard(int n, _Item it) {
    final recapLigne = _recap?.items.where((l) => l.idVentes == it.idVentes);
    final pa = (recapLigne != null && recapLigne.isNotEmpty) ? recapLigne.first.prixAjoute * recapLigne.first.qte : null;
    final np = it.nouveau;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(colors: [_carte2, _carte], begin: Alignment.topCenter, end: Alignment.bottomCenter),
        border: Border.all(color: _ligne),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(radius: 12, backgroundColor: AppColors.accent, child: Text('$n', style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w800))),
              const SizedBox(width: 8),
              Expanded(child: Text(it.designation, style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w800, color: AppColors.textPrimary))),
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: () => _toggleLigne(it.ligne, false),
                icon: const Icon(Icons.close_rounded, size: 18, color: AppColors.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _boite(Icons.undo_rounded, 'Repris (retour stock)', it.designation, _meta(it.ligne), false),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 4),
            child: Center(child: Icon(Icons.arrow_downward_rounded, color: AppColors.accentLight, size: 18)),
          ),
          if (np != null)
            Stack(
              children: [
                _boite(Icons.inventory_2_rounded, 'Remis au client', np.designation, '${_fmt(np.prixUnitaire)}${np.numSerie != null ? ' · S/N ${np.numSerie}' : ''}', true),
                Positioned(
                  right: 4,
                  top: 4,
                  child: TextButton(onPressed: () => setState(() => it.nouveau = null), child: const Text('Changer', style: TextStyle(fontSize: 12))),
                ),
              ],
            )
          else ...[
            InlineField(
              label: "Rechercher l'appareil remis (en stock)",
              controller: it.rechercheCtrl,
              prefixIcon: Icons.search_rounded,
              onChanged: (v) => _rechercher(it, v),
            ),
            ...it.resultats.take(6).map((p) => InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => _choisir(it, p),
                  child: Container(
                    margin: const EdgeInsets.only(top: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                    decoration: BoxDecoration(color: AppColors.bgElevated, borderRadius: BorderRadius.circular(10)),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(p.designation, style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                              if (p.numSerie != null) Text('S/N ${p.numSerie}', style: GoogleFonts.inter(fontSize: 10.5, color: AppColors.textSecondary)),
                            ],
                          ),
                        ),
                        Text(_fmt(p.prixUnitaire), style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.green)),
                      ],
                    ),
                  ),
                )),
          ],
          const SizedBox(height: 12),
          InlineField(
            label: 'Prix actuel (prix vente article retourné) (Ar)',
            controller: it.prixActuelCtrl,
            prefixIcon: Icons.price_change_rounded,
            keyboardType: TextInputType.number,
            onChanged: (_) => _planifierRecap(),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: .1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.borderAccent),
            ),
            child: Row(
              children: [
                Text('Prix ajouté (automatique)', style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondary)),
                const Spacer(),
                Text(pa == null ? '—' : _fmt(pa), style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.accentLight)),
              ],
            ),
          ),
          const SizedBox(height: 6),
          _switch('Non upgrade (aucun supplément)', it.nonUpgrade, AppColors.accentLight, (v) {
            setState(() => it.nonUpgrade = v);
            _planifierRecap(immediat: true);
          }),
          _switch('Article retourné avec défaut', it.isDefaut, AppColors.orange, (v) => setState(() => it.isDefaut = v)),
          if (it.isDefaut) ...[
            InlineField(label: 'Motif de la réparation', controller: it.motifCtrl, prefixIcon: Icons.build_rounded),
            const SizedBox(height: 10),
            InlineField(label: "Batterie de l'article retourné", controller: it.batterieCtrl, prefixIcon: Icons.battery_full_rounded),
          ],
        ],
      ),
    );
  }

  Widget _boite(IconData icon, String titre, String nom, String meta, bool sortie) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF0B1426),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: sortie ? AppColors.borderAccent : _ligne),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icon, size: 13, color: AppColors.textSecondary),
              const SizedBox(width: 5),
              Text(titre.toUpperCase(), style: GoogleFonts.inter(fontSize: 9.5, letterSpacing: .6, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
            ]),
            const SizedBox(height: 4),
            Text(nom, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            if (meta.isNotEmpty) Text(meta, style: GoogleFonts.inter(fontSize: 10.5, color: AppColors.textSecondary)),
          ],
        ),
      );

  Widget _switch(String label, bool value, Color color, ValueChanged<bool> onChanged) => Row(
        children: [
          Expanded(child: Text(label, style: GoogleFonts.inter(fontSize: 12.5, color: AppColors.textPrimary))),
          Switch(value: value, activeThumbColor: color, onChanged: onChanged),
        ],
      );

  Widget _carteTitre(IconData icon, String titre, {Widget? trailing, required Widget child}) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: _carte, borderRadius: BorderRadius.circular(16), border: Border.all(color: _ligne)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icon, size: 17, color: AppColors.accentLight),
              const SizedBox(width: 8),
              Expanded(child: Text(titre, style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w800, color: AppColors.textPrimary))),
              ?trailing,
            ]),
            const SizedBox(height: 12),
            child,
          ],
        ),
      );

  Widget _ligneResume(String label, String value, {Color? color}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: GoogleFonts.inter(fontSize: 12.5, color: AppColors.textSecondary)),
            Text(value, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: color ?? AppColors.textPrimary)),
          ],
        ),
      );

  Widget _resumeCard() {
    final r = _recap;
    final manquants = _selection.where((i) => i.nouveau == null).length;
    return _carteTitre(
      Icons.receipt_rounded,
      'Montant à payer',
      trailing: _recapLoading ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accentLight)) : null,
      child: r == null
          ? Text(
              _selection.isEmpty ? 'Aucun appareil sélectionné.' : "Choisissez l'appareil remis pour chaque article ($manquants manquant${manquants > 1 ? 's' : ''}).",
              style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondary),
            )
          : Column(
              children: [
                _ligneResume('Appareils échangés', '${r.items.length}'),
                _ligneResume('Total supplément (prix ajouté)', _fmt(r.totalPrixAjoute)),
                _ligneResume('Déjà payé sur la facture', _fmt(r.dejaPaye)),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    gradient: const LinearGradient(colors: [Color(0xFF052E22), Color(0xFF064E3B)]),
                    border: Border.all(color: AppColors.borderAccent),
                  ),
                  child: Row(
                    children: [
                      Text('À payer', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.accentLight)),
                      const Spacer(),
                      Text(_fmt(r.reste), style: GoogleFonts.inter(fontSize: 21, fontWeight: FontWeight.w900, color: Colors.white)),
                    ],
                  ),
                ),
                if (manquants > 0) ...[
                  const SizedBox(height: 8),
                  Text('$manquants appareil(s) sans article de remplacement.', style: const TextStyle(color: AppColors.orange, fontSize: 11.5)),
                ],
              ],
            ),
    );
  }

  Widget _paiementCard() {
    final diff = _somme - _reste;
    return _carteTitre(
      Icons.payments_rounded,
      'Somme donnée',
      child: Column(
        children: [
          ..._paiements.asMap().entries.map((e) {
            final i = e.key;
            final p = e.value;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    flex: 5,
                    child: DropdownButtonFormField<String>(
                      initialValue: p.typeId,
                      dropdownColor: AppColors.bgElevated,
                      isExpanded: true,
                      decoration: InputDecoration(
                        isDense: true,
                        filled: true,
                        fillColor: const Color(0xFF0B1426),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _ligne)),
                      ),
                      style: const TextStyle(color: AppColors.textPrimary, fontSize: 12.5),
                      items: _types.map((t) => DropdownMenuItem(value: t.id, child: Text(t.label))).toList(),
                      onChanged: (v) => setState(() => p.typeId = v),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 4,
                    child: TextField(
                      controller: p.ctrl,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700),
                      decoration: InputDecoration(
                        isDense: true,
                        filled: true,
                        fillColor: const Color(0xFF0B1426),
                        suffixText: 'Ar',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _ligne)),
                      ),
                      onTap: () {
                        if (p.ctrl.text == '0') p.ctrl.clear();
                      },
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  if (_paiements.length > 1)
                    IconButton(
                      onPressed: () => setState(() => _paiements.removeAt(i).ctrl.dispose()),
                      icon: const Icon(Icons.close_rounded, size: 18, color: AppColors.red),
                    ),
                ],
              ),
            );
          }),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () {
                final pris = _paiements.map((p) => p.typeId).toSet();
                final libre = _types.where((t) => !pris.contains(t.id));
                setState(() => _paiements.add(_Paiement(libre.isNotEmpty ? libre.first.id : (_types.isNotEmpty ? _types.first.id : null))));
              },
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Ajouter un mode de paiement'),
            ),
          ),
          if (_recap != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: (diff >= 0 ? AppColors.accent : _rouge).withValues(alpha: .12),
                border: Border.all(color: (diff >= 0 ? AppColors.accent : _rouge).withValues(alpha: .4)),
              ),
              child: Row(
                children: [
                  Text(diff >= 0 ? (diff > 0 ? 'Monnaie à rendre' : 'Paiement complet') : 'Reste à payer',
                      style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 12.5, color: diff >= 0 ? AppColors.accentLight : const Color(0xFFFCA5A5))),
                  const Spacer(),
                  Text(_fmt(diff.abs()), style: GoogleFonts.inter(fontWeight: FontWeight.w800, color: diff >= 0 ? AppColors.accentLight : const Color(0xFFFCA5A5))),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _clientCard() {
    return _carteTitre(
      Icons.person_pin_rounded,
      'Client',
      trailing: Text(_insuffisant ? 'nom obligatoire' : 'facultatif',
          style: GoogleFonts.inter(fontSize: 11, color: _insuffisant ? const Color(0xFFFCA5A5) : AppColors.textSecondary)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InlineField(label: 'Nom complet (rechercher ou saisir)', controller: _nomCtrl, prefixIcon: Icons.person_search_rounded, onChanged: _onNom),
          if (_suggestions.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 6),
              decoration: BoxDecoration(color: AppColors.bgElevated, borderRadius: BorderRadius.circular(12), border: Border.all(color: _ligne)),
              child: Column(
                children: _suggestions
                    .map((c) => ListTile(
                          dense: true,
                          leading: const Icon(Icons.account_circle_rounded, color: AppColors.accentLight),
                          title: Text('${c.nomComplet} ${c.prenom ?? ''}'.trim(), style: const TextStyle(color: AppColors.textPrimary, fontSize: 13)),
                          subtitle: Text([c.telephone, if ((c.cin ?? '').isNotEmpty) 'CIN ${c.cin}'].whereType<String>().join(' · '),
                              style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                          onTap: () => _choisirClient(c),
                        ))
                    .toList(),
              ),
            ),
          const SizedBox(height: 10),
          InlineField(label: 'Prénom', controller: _prenomCtrl, prefixIcon: Icons.badge_outlined),
          const SizedBox(height: 10),
          InlineField(label: 'Téléphone', controller: _telCtrl, prefixIcon: Icons.phone_rounded, keyboardType: TextInputType.phone),
          const SizedBox(height: 10),
          InlineField(label: 'N° CIN', controller: _cinCtrl, prefixIcon: Icons.credit_card_rounded),
          const SizedBox(height: 8),
          Text(
            _idPersonnes != null
                ? 'Client enregistré — ses coordonnées seront mises à jour si vous les modifiez.'
                : 'Nouveau client : il sera enregistré avec ces coordonnées.',
            style: GoogleFonts.inter(fontSize: 10.5, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _bouton(String label, IconData icon, List<Color> couleurs, VoidCallback? onPressed) {
    final actif = onPressed != null && !_submitting;
    return Opacity(
      opacity: actif ? 1 : .5,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: LinearGradient(colors: couleurs),
          boxShadow: [BoxShadow(color: couleurs.last.withValues(alpha: .35), blurRadius: 14, offset: const Offset(0, 5))],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: actif ? onPressed : null,
            child: SizedBox(
              height: 52,
              child: Center(
                child: _submitting
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white))
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(icon, color: Colors.white, size: 19),
                          const SizedBox(width: 8),
                          Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _actions() {
    final pret = _complet && _recap != null;
    return [
      OutlinedButton.icon(
        onPressed: pret && !_proformaSubmitting ? _proforma : null,
        icon: _proformaSubmitting
            ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.textSecondary))
            : const Icon(Icons.description_outlined, size: 17),
        label: const Text('Proforma'),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          side: const BorderSide(color: _ligne),
          padding: const EdgeInsets.symmetric(vertical: 13),
          minimumSize: const Size(double.infinity, 0),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      const SizedBox(height: 12),
      if (!pret || !_insuffisant)
        _bouton("Valider l'échange", Icons.check_circle_rounded, const [Color(0xFF059669), Color(0xFF10B981)], pret ? () => _confirmer('normal') : null)
      else ...[
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(
            "La somme donnée est inférieure au montant à payer : réservez l'échange ou validez-le en crédit.",
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(fontSize: 11.5, color: const Color(0xFFFCA5A5)),
          ),
        ),
        _bouton("Réserver l'échange", Icons.event_available_rounded, const [Color(0xFF6D28D9), _violet], () => _confirmer('reservation')),
        _bouton('Valider en crédit', Icons.request_quote_rounded, const [Color(0xFFB91C1C), _rouge], () => _confirmer('credit')),
      ],
    ];
  }
}
