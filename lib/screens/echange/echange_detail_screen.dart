import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme.dart';
import '../../models/lookup_model.dart';
import '../../models/payment_split.dart';
import '../../models/produit_model.dart';
import '../../models/receipt_line.dart';
import '../../models/user_model.dart';
import '../../services/app_data_cache.dart';
import '../../services/echange_service.dart';
import '../../services/receipt_print_service.dart';
import '../../services/vente_service.dart';
import '../../widgets/client_info_dialog.dart';
import '../../widgets/gradient_button.dart';
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

/// Détail de la facture porteuse de l'article vendu + panneau d'échange
/// complet : choix du nouvel article, prix ajouté, récapitulatif dynamique
/// (autoritaire côté serveur à chaque frappe), switch "avec défaut", et
/// paiement du reste avant validation. Miroir mobile de
/// `Echange/_facture_detail` (web), sans la mécanique de session PHP : les
/// paiements sont accumulés localement puis envoyés en un seul appel à
/// "Valider".
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

  final _produitSearchCtrl = TextEditingController();
  final _prixVenteCtrl = TextEditingController();
  final _motifCtrl = TextEditingController();
  final _batterieCtrl = TextEditingController();
  Timer? _debounceProduit;
  Timer? _debouncePrix;
  List<ProduitModel> _produitResults = [];
  ProduitModel? _selectedProduit;

  bool _isDefaut = false;
  bool _nonUpgrade = false;
  EchangeRecap? _recap;
  bool _recapLoading = false;

  List<LookupItem> _typesPaiement = [];
  String? _selectedTypePaiementId;
  final _montantCtrl = TextEditingController();
  final List<PaymentSplit> _splits = [];

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
        _typesPaiement = types;
        if (types.isNotEmpty) _selectedTypePaiementId = types.first.id;
      });
    });
  }

  @override
  void dispose() {
    _produitSearchCtrl.dispose();
    _prixVenteCtrl.dispose();
    _motifCtrl.dispose();
    _batterieCtrl.dispose();
    _montantCtrl.dispose();
    _debounceProduit?.cancel();
    _debouncePrix?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final facture = await EchangeService.instance.factureDetail(widget.idVentes);
    if (!mounted) return;
    setState(() {
      _facture = facture;
      _loading = false;
    });
    // Pré-remplit avec la batterie actuelle de l'article retourné (modifiable
    // ensuite) — n'apparaît que si "avec défaut" est activé.
    final lignes = (facture?['lignes'] as List?) ?? [];
    final ligne = lignes.cast<Map<String, dynamic>?>().firstWhere(
          (l) => '${l?['id_ventes']}' == widget.idVentes,
          orElse: () => null,
        );
    final batterieActuelle = ligne?['nom_sous_categorie_piece']?.toString().trim();
    if (batterieActuelle != null && batterieActuelle.isNotEmpty) {
      _batterieCtrl.text = batterieActuelle;
    }
  }

  Map<String, dynamic>? get _entete => _facture?['entete'] as Map<String, dynamic>?;

  /// La ligne vendue reprise (l'article "échangé", qui retourne en stock) —
  /// c'est SON détail qui doit apparaître sur le ticket/A4 imprimé après
  /// validation, pas celui du nouvel article remis au client.
  Map<String, dynamic>? get _ligneRepris {
    final lignes = (_facture?['lignes'] as List?) ?? [];
    final match = lignes.cast<Map<String, dynamic>?>().firstWhere(
          (l) => '${l?['id_ventes']}' == widget.idVentes,
          orElse: () => null,
        );
    return match;
  }

  void _onProduitSearchChanged(String v) {
    _debounceProduit?.cancel();
    _debounceProduit = Timer(const Duration(milliseconds: 400), () async {
      final results = await EchangeService.instance.searchNewProduit(v);
      if (!mounted) return;
      setState(() => _produitResults = results);
    });
  }

  Future<void> _selectProduit(ProduitModel p) async {
    setState(() {
      _selectedProduit = p;
      _produitResults = [];
      _produitSearchCtrl.clear();
      // "Prix de vente" est automatique (prix catalogue de l'article choisi)
      // mais modifiable ensuite.
      _prixVenteCtrl.text = p.prixUnitaire.toStringAsFixed(0);
    });
    await _refreshRecap();
  }

  /// Appelé à chaque frappe dans le champ "Prix de vente" : on ne relance le
  /// calcul serveur qu'après une courte pause (sinon un appel réseau par
  /// caractère, réponses dans le désordre, et le champ qui "saute"). On ne
  /// réécrit jamais la valeur saisie dans le contrôleur (ça déplaçait le
  /// curseur / empêchait de corriger le montant).
  void _onPrixChanged(String _) {
    _debouncePrix?.cancel();
    _debouncePrix = Timer(const Duration(milliseconds: 500), _refreshRecap);
  }

  Future<void> _refreshRecap() async {
    final produit = _selectedProduit;
    if (produit == null) return;
    setState(() => _recapLoading = true);
    final prixVente = double.tryParse(_prixVenteCtrl.text.replaceAll(' ', ''));
    final rec = await EchangeService.instance.recap(idVentes: widget.idVentes, newProduitsId: produit.idProduits, prixVente: prixVente, nonUpgrade: _nonUpgrade);
    if (!mounted) return;
    setState(() {
      _recap = rec;
      _recapLoading = false;
      final remaining = rec.error ? 0.0 : (rec.reste - _splitsSum);
      _montantCtrl.text = remaining > 0 ? remaining.toStringAsFixed(0) : '0';
    });
  }

  double get _splitsSum => _splits.fold(0.0, (sum, s) => sum + s.montant);

  List<PaymentSplit> get _effectiveSplits {
    if (_splits.isNotEmpty) return _splits;
    final montant = double.tryParse(_montantCtrl.text.replaceAll(' ', '')) ?? 0;
    if (montant <= 0 || _selectedTypePaiementId == null) return [];
    final type = _typesPaiement.firstWhere((t) => t.id == _selectedTypePaiementId);
    return [PaymentSplit(idTypePaiement: type.id, typeLabel: type.label, montant: montant)];
  }

  void _addSplit() {
    final montant = double.tryParse(_montantCtrl.text.replaceAll(' ', ''));
    if (montant == null || montant <= 0 || _selectedTypePaiementId == null) return;
    final type = _typesPaiement.firstWhere((t) => t.id == _selectedTypePaiementId);
    setState(() {
      _splits.add(PaymentSplit(idTypePaiement: type.id, typeLabel: type.label, montant: montant));
      final reste = _recap?.reste ?? 0;
      final remaining = reste - _splitsSum;
      _montantCtrl.text = remaining > 0 ? remaining.toStringAsFixed(0) : '0';
    });
  }

  void _removeSplit(int index) {
    setState(() {
      _splits.removeAt(index);
      final reste = _recap?.reste ?? 0;
      final remaining = reste - _splitsSum;
      _montantCtrl.text = remaining > 0 ? remaining.toStringAsFixed(0) : reste.toStringAsFixed(0);
    });
  }

  Future<void> _confirmAndValider() async {
    final produit = _selectedProduit;
    final rec = _recap;
    if (produit == null || rec == null || rec.error) {
      setState(() => _error = 'Choisissez un article de remplacement.');
      return;
    }
    if (_isDefaut && _motifCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Le motif de réparation est obligatoire.');
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.bgCard,
        title: const Text("Confirmer l'échange ?", style: TextStyle(color: AppColors.textPrimary)),
        content: Text(
          '${rec.oldDesignation} → ${rec.newDesignation}\nMontant final : ${_fmt(rec.montantFinal)}\nReste à payer : ${_fmt(rec.reste)}',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Annuler')),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Valider', style: TextStyle(color: AppColors.green))),
        ],
      ),
    );
    if (ok != true) return;

    setState(() {
      _submitting = true;
      _error = null;
    });
    final prixVente = double.tryParse(_prixVenteCtrl.text.replaceAll(' ', '')) ?? rec.newPrixUnitaire;
    final result = await EchangeService.instance.valider(
      idVentes: widget.idVentes,
      newProduitsId: produit.idProduits,
      prixVente: prixVente,
      isDefaut: _isDefaut,
      motifReparation: _isDefaut ? _motifCtrl.text : null,
      batterie: _isDefaut ? _batterieCtrl.text : null,
      user: widget.user,
      paiements: _effectiveSplits,
      nonUpgrade: _nonUpgrade,
    );
    if (!mounted) return;
    if (result.success) {
      // L'échange mouvemente le stock des deux articles (ancien restocké,
      // nouveau décrémenté) et modifie la facture existante.
      AppDataCache.instance.invalidate(CacheDomain.produits);
      AppDataCache.instance.invalidate(CacheDomain.facturesPayees);

      // La description imprimée montre l'article REMIS au client (sortie du
      // stock) — l'article REPRIS (retourné en stock) est affiché à part,
      // sous "Article retourné", via `articleRetourne`. P.U = prix ajouté,
      // sauf si prix ajouté = 0 ("Non upgrade" ou repris à sa pleine valeur) :
      // dans ce cas P.U = prix de vente (le prix de l'article remis).
      final entete = _entete;
      final ligneRepris = _ligneRepris;
      String? s(dynamic v) {
        final t = v?.toString().trim();
        return (t == null || t.isEmpty) ? null : t;
      }

      final prixUnitaireTicket = rec.prixAjoute != 0 ? rec.prixAjoute : rec.newPrixUnitaire;
      final lines = [
        ReceiptLine(
          designation: produit.designation,
          qte: 1,
          prixUnitaire: prixUnitaireTicket,
          total: prixUnitaireTicket,
          numSerie: produit.numSerie,
          imei1: produit.imei1,
          imei2: produit.imei2,
          nomModel: produit.nomModel,
          nomMarque: produit.nomMarque,
        ),
      ];
      final articleRetourne = ReceiptLine(
        designation: s(ligneRepris?['designation_produits']) ?? rec.oldDesignation ?? 'Article',
        qte: 1,
        prixUnitaire: 0,
        total: 0,
        numSerie: s(ligneRepris?['num_serie']),
        imei1: s(ligneRepris?['imei1']),
        imei2: s(ligneRepris?['imei2']),
        nomModel: s(ligneRepris?['nom_model']),
        nomMarque: s(ligneRepris?['nom_marque']),
      );

      // Avant l'impression A4, on propose de saisir/corriger les
      // coordonnées client à afficher — facultatif, pré-rempli avec ce
      // qu'on connaît déjà de la facture d'origine.
      final clientInfo = await showClientInfoDialog(
        context,
        initialNom: entete?['nom_complet']?.toString(),
        initialPrenom: entete?['prenom_personnes']?.toString(),
        initialTelephone: entete?['telephone']?.toString(),
        initialCin: entete?['cin_personnes']?.toString(),
      );
      if (!mounted) return;

      final printMessage = await ReceiptPrintService.instance.offerPrint(
        context,
        lines: lines,
        total: prixUnitaireTicket,
        cashierName: widget.user.nomComplet,
        clientName: clientInfo?.nom,
        clientPrenom: clientInfo?.prenom,
        clientTelephone: clientInfo?.telephone,
        clientCin: clientInfo?.cin,
        numeroFacture: entete?['numero_facture']?.toString(),
        isEchange: true,
        articleRetourne: articleRetourne,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${result.message ?? 'Échange validé avec succès.'} $printMessage')),
      );
    } else {
      setState(() {
        _submitting = false;
        _error = result.message;
      });
    }
  }

  /// Devis non fiscal : imprime/partage le même contenu que le ticket
  /// d'échange, filigrane "PROFORMA" à la place — sans valider l'échange (le
  /// stock n'est pas mouvementé, rien n'est enregistré côté serveur).
  Future<void> _imprimerProforma() async {
    final produit = _selectedProduit;
    final rec = _recap;
    if (produit == null || rec == null || rec.error) {
      setState(() => _error = 'Choisissez un article de remplacement.');
      return;
    }
    setState(() => _proformaSubmitting = true);

    final entete = _entete;
    final ligneRepris = _ligneRepris;
    String? s(dynamic v) {
      final t = v?.toString().trim();
      return (t == null || t.isEmpty) ? null : t;
    }

    final prixUnitaireTicket = rec.prixAjoute != 0 ? rec.prixAjoute : rec.newPrixUnitaire;
    final lines = [
      ReceiptLine(
        designation: produit.designation,
        qte: 1,
        prixUnitaire: prixUnitaireTicket,
        total: prixUnitaireTicket,
        numSerie: produit.numSerie,
        imei1: produit.imei1,
        imei2: produit.imei2,
        nomModel: produit.nomModel,
        nomMarque: produit.nomMarque,
      ),
    ];
    final articleRetourne = ReceiptLine(
      designation: s(ligneRepris?['designation_produits']) ?? rec.oldDesignation ?? 'Article',
      qte: 1,
      prixUnitaire: 0,
      total: 0,
      numSerie: s(ligneRepris?['num_serie']),
      imei1: s(ligneRepris?['imei1']),
      imei2: s(ligneRepris?['imei2']),
      nomModel: s(ligneRepris?['nom_model']),
      nomMarque: s(ligneRepris?['nom_marque']),
    );

    final clientInfo = await showClientInfoDialog(
      context,
      initialNom: entete?['nom_complet']?.toString(),
      initialPrenom: entete?['prenom_personnes']?.toString(),
      initialTelephone: entete?['telephone']?.toString(),
      initialCin: entete?['cin_personnes']?.toString(),
    );
    if (!mounted) return;

    final printMessage = await ReceiptPrintService.instance.offerPrint(
      context,
      lines: lines,
      total: prixUnitaireTicket,
      cashierName: widget.user.nomComplet,
      clientName: clientInfo?.nom,
      clientPrenom: clientInfo?.prenom,
      clientTelephone: clientInfo?.telephone,
      clientCin: clientInfo?.cin,
      numeroFacture: entete?['numero_facture']?.toString(),
      isEchange: true,
      isProforma: true,
      articleRetourne: articleRetourne,
    );
    if (!mounted) return;
    setState(() => _proformaSubmitting = false);
    if (printMessage.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(printMessage)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDeep,
      appBar: AppBar(
        backgroundColor: AppColors.bgCard,
        elevation: 0,
        title: Text("Détail de l'échange", style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 17, color: AppColors.textPrimary)),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accentLight))
            : _facture == null
                ? Center(child: Text('Facture introuvable', style: GoogleFonts.inter(color: AppColors.textMuted)))
                : SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _factureCard(),
                        const SizedBox(height: 18),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(color: AppColors.bgElevated, borderRadius: BorderRadius.circular(14)),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Non upgrade', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                                    Text('Aucun supplément, prix ajouté = 0', style: GoogleFonts.inter(fontSize: 11, color: AppColors.textMuted)),
                                  ],
                                ),
                              ),
                              Switch(
                                value: _nonUpgrade,
                                activeThumbColor: AppColors.accentLight,
                                onChanged: (v) {
                                  setState(() => _nonUpgrade = v);
                                  _refreshRecap();
                                },
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 18),
                        Text('Article de remplacement', style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
                        const SizedBox(height: 8),
                        if (_selectedProduit != null) _selectedProduitCard() else _produitSearch(),
                        if (_selectedProduit != null) ...[
                          const SizedBox(height: 18),
                          _prixAjouteEtDefautSection(),
                          const SizedBox(height: 18),
                          // On garde le récapitulatif affiché pendant le
                          // recalcul (petit spinner) plutôt que de le
                          // remplacer par un gros indicateur — évite le
                          // clignotement à chaque frappe dans "Prix de vente".
                          if (_recap != null && !_recap!.error)
                            Opacity(opacity: _recapLoading ? 0.5 : 1, child: _recapCard(_recap!))
                          else if (_recapLoading)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 12),
                              child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accentLight)),
                            ),
                          if (_recap != null && !_recap!.error && _recap!.reste > 0) ...[
                            const SizedBox(height: 18),
                            _paiementSection(),
                          ],
                          if (_error != null) ...[
                            const SizedBox(height: 14),
                            Text(_error!, style: const TextStyle(color: AppColors.red, fontSize: 12.5)),
                          ],
                          const SizedBox(height: 18),
                          OutlinedButton.icon(
                            onPressed: (_recap != null && !_recap!.error && !_proformaSubmitting) ? _imprimerProforma : null,
                            icon: _proformaSubmitting
                                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.textSecondary))
                                : const Icon(Icons.description_outlined, size: 17),
                            label: const Text('Proforma'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.textPrimary,
                              side: const BorderSide(color: AppColors.border),
                              padding: const EdgeInsets.symmetric(vertical: 13),
                              minimumSize: const Size(double.infinity, 0),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                            ),
                          ),
                          const SizedBox(height: 10),
                          GradientButton(
                            label: "Valider l'échange",
                            icon: Icons.swap_horizontal_circle_rounded,
                            loading: _submitting,
                            onPressed: (_recap != null && !_recap!.error) ? _confirmAndValider : null,
                          ),
                        ],
                      ],
                    ),
                  ),
      ),
    );
  }

  Widget _factureCard() {
    final entete = _entete;
    final lignes = (_facture?['lignes'] as List?) ?? [];
    final ligne = lignes.cast<Map<String, dynamic>?>().firstWhere(
          (l) => '${l?['id_ventes']}' == widget.idVentes,
          orElse: () => lignes.isNotEmpty ? lignes.first as Map<String, dynamic> : null,
        );
    final totalAvant = (_facture?['total_avant_remise'] as num?)?.toDouble() ?? 0;
    final dejaPaye = (_facture?['deja_paye'] as num?)?.toDouble() ?? 0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.bgCard, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.receipt_long_rounded, size: 17, color: AppColors.accentLight),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Facture ${entete?['numero_facture'] ?? '-'}',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 14.5, color: AppColors.textPrimary),
                ),
              ),
            ],
          ),
          if (entete?['nom_complet'] != null) ...[
            const SizedBox(height: 4),
            Text('Client : ${entete!['nom_complet']}', style: GoogleFonts.inter(fontSize: 12.5, color: AppColors.textSecondary)),
          ],
          const Divider(color: AppColors.border, height: 20),
          Text('Article vendu', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textMuted, letterSpacing: .04)),
          const SizedBox(height: 4),
          Text(
            '${ligne?['designation_produits'] ?? '-'}',
            style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _miniStat('Total facture', _fmt(totalAvant)),
              _miniStat('Déjà payé', _fmt(dejaPaye)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _miniStat(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: GoogleFonts.inter(fontSize: 10.5, color: AppColors.textMuted, fontWeight: FontWeight.w600)),
        const SizedBox(height: 2),
        Text(value, style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
      ],
    );
  }

  Widget _produitSearch() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InlineField(
          label: 'Rechercher un article en stock',
          controller: _produitSearchCtrl,
          prefixIcon: Icons.inventory_2_rounded,
          onChanged: _onProduitSearchChanged,
        ),
        if (_produitResults.isNotEmpty) ...[
          const SizedBox(height: 10),
          ..._produitResults.take(8).map((p) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => _selectProduit(p),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(color: AppColors.bgElevated, borderRadius: BorderRadius.circular(12)),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(p.designation, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                                if (p.numSerie != null)
                                  Text('S/N: ${p.numSerie}', style: GoogleFonts.inter(fontSize: 11, color: AppColors.textMuted)),
                              ],
                            ),
                          ),
                          Text('${p.prixUnitaire.toStringAsFixed(0)} Ar', style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.green)),
                        ],
                      ),
                    ),
                  ),
                ),
              )),
        ],
      ],
    );
  }

  Widget _selectedProduitCard() {
    final p = _selectedProduit!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(color: AppColors.accentGlow, borderRadius: BorderRadius.circular(14)),
      child: Row(
        children: [
          const Icon(Icons.check_circle_rounded, size: 18, color: AppColors.accentLight),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p.designation, style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                Text('${p.prixUnitaire.toStringAsFixed(0)} Ar', style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondary)),
              ],
            ),
          ),
          GestureDetector(
            onTap: () => setState(() {
              _selectedProduit = null;
              _recap = null;
              _splits.clear();
            }),
            child: const Icon(Icons.close_rounded, size: 18, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }

  Widget _prixAjouteEtDefautSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InlineField(
          label: 'Prix actuel (prix vente article retourné) (Ar)',
          controller: _prixVenteCtrl,
          prefixIcon: Icons.sell_rounded,
          keyboardType: TextInputType.number,
          onChanged: _onPrixChanged,
        ),
        const SizedBox(height: 14),
        // "Prix ajouté" n'est plus saisi : recalculé automatiquement côté
        // serveur (prix de vente - 80% du prix de vente d'origine de
        // l'article retourné, arrondi au multiple de 50 000 supérieur).
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(color: AppColors.bgElevated, borderRadius: BorderRadius.circular(14)),
          child: Row(
            children: [
              Text('Prix ajouté', style: GoogleFonts.inter(fontSize: 12.5, color: AppColors.textMuted)),
              const Spacer(),
              Text(
                _fmt(_recap?.prixAjoute ?? 0),
                style: GoogleFonts.inter(fontSize: 14.5, fontWeight: FontWeight.w800, color: AppColors.accentLight),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(color: AppColors.bgElevated, borderRadius: BorderRadius.circular(14)),
          child: Row(
            children: [
              Expanded(
                child: Text('Article retourné avec défaut', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
              ),
              Switch(
                value: _isDefaut,
                activeThumbColor: AppColors.orange,
                onChanged: (v) => setState(() => _isDefaut = v),
              ),
            ],
          ),
        ),
        if (_isDefaut) ...[
          const SizedBox(height: 12),
          InlineField(label: 'Motif de la réparation', controller: _motifCtrl, prefixIcon: Icons.build_rounded),
          const SizedBox(height: 12),
          InlineField(label: "Batterie de l'article retourné", controller: _batterieCtrl, prefixIcon: Icons.battery_full_rounded),
        ],
      ],
    );
  }

  Widget _recapCard(EchangeRecap rec) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.bgElevated, borderRadius: BorderRadius.circular(14)),
      child: Column(
        children: [
          _recapRow('Montant final', _fmt(rec.montantFinal)),
          const SizedBox(height: 6),
          _recapRow('Total après échange', _fmt(rec.totalApres)),
          const SizedBox(height: 6),
          _recapRow('Déjà payé', _fmt(rec.dejaPaye)),
          const Divider(color: AppColors.border, height: 18),
          _recapRow(
            rec.reste > 0 ? 'Reste à payer' : 'Monnaie à rendre',
            _fmt(rec.reste > 0 ? rec.reste : rec.rendu),
            color: rec.reste > 0 ? AppColors.orange : AppColors.green,
          ),
        ],
      ),
    );
  }

  Widget _recapRow(String label, String value, {Color? color}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: GoogleFonts.inter(fontSize: 12.5, color: AppColors.textSecondary)),
        Text(value, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w800, color: color ?? AppColors.textPrimary)),
      ],
    );
  }

  Widget _paiementSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Paiement du reste', style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
        const SizedBox(height: 8),
        if (_typesPaiement.isNotEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _typesPaiement.map((t) {
              final selected = t.id == _selectedTypePaiementId;
              return ChoiceChip(
                label: Text(t.label, style: TextStyle(fontSize: 12, color: selected ? Colors.white : AppColors.textSecondary)),
                selected: selected,
                selectedColor: AppColors.accent,
                backgroundColor: AppColors.bgElevated,
                onSelected: (_) => setState(() => _selectedTypePaiementId = t.id),
              );
            }).toList(),
          ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: InlineField(
                label: 'Montant (Ar)',
                controller: _montantCtrl,
                prefixIcon: Icons.payments_rounded,
                keyboardType: TextInputType.number,
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: IconButton.filled(
                onPressed: _addSplit,
                icon: const Icon(Icons.add_rounded),
                tooltip: 'Ajouter un autre paiement',
                style: IconButton.styleFrom(backgroundColor: AppColors.bgElevated, foregroundColor: AppColors.accentLight),
              ),
            ),
          ],
        ),
        if (_splits.isNotEmpty) ...[
          const SizedBox(height: 10),
          ..._splits.asMap().entries.map((entry) {
            final i = entry.key;
            final s = entry.value;
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                decoration: BoxDecoration(color: AppColors.bgElevated, borderRadius: BorderRadius.circular(10)),
                child: Row(
                  children: [
                    Expanded(child: Text('${s.typeLabel} — ${_fmt(s.montant)}', style: const TextStyle(color: AppColors.textPrimary, fontSize: 13))),
                    GestureDetector(onTap: () => _removeSplit(i), child: const Icon(Icons.close_rounded, size: 16, color: AppColors.red)),
                  ],
                ),
              ),
            );
          }),
        ],
      ],
    );
  }
}
