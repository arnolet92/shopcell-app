import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../models/lookup_model.dart';
import '../../models/produit_model.dart';
import '../../models/user_model.dart';
import '../../services/app_data_cache.dart';
import '../../services/auth_service.dart';
import '../../services/cart_service.dart';
import '../../services/produit_service.dart';
import '../vente/cart_screen.dart';
import 'produit_form_screen.dart';
import 'widgets/produit_filter_bar.dart';
import 'widgets/produit_group_card.dart';
import 'widgets/stat_bar.dart';

/// Écran "Gestion d'article" — reprend l'organisation d'affichage de
/// `http://.../Produit/lst` côté web : barre de recherche + filtres
/// (famille, capacité, couleur, batterie, carton, défaut), les 3 vues
/// (Tous / En attente / Vendus, comme `Produit::lst()`/`lst_attente()`/
/// `lst_vente()`), la création/modification d'article, et une liste
/// d'articles regroupés par désignation, chaque groupe ventilé par
/// capacité/lieu de stockage (même logique que tabproduit2.php).
class ProduitListScreen extends StatefulWidget {
  const ProduitListScreen({super.key});

  @override
  State<ProduitListScreen> createState() => _ProduitListScreenState();
}

class _ProduitListScreenState extends State<ProduitListScreen> {
  final _searchController = TextEditingController();
  Timer? _debounce;

  ProduitFilters _filters = ProduitFilters.empty();
  FilterSelection _selection = FilterSelection.empty;
  String _query = '';
  ProduitVue _vue = ProduitVue.tous;

  List<ProduitModel> _produits = [];
  bool _loading = true;
  String? _error;
  String? _baseUrl;
  UserModel? _user;
  Map<String, String> _imagesParDesignation = {};

  // Onglet "Achat confirmé" : panneau "classeurs" par bulk (voir
  // Produit/lst_achat_confirme côté web). '__tous__'/'__sans_bulk__' sont
  // des repères spéciaux, sinon un nom de bulk existant.
  String _bulkFiltreActif = '__sans_bulk__';
  final Set<String> _selectedBulkIds = {};
  bool get _canOrganizeBulk => _user?.role == 'patron' || _user?.role == 'gerant';

  @override
  void initState() {
    super.initState();
    CartService.instance.addListener(_onCartChanged);
    // Écran persistant (IndexedStack de HomeShell) : sans cet abonnement,
    // une vente/annulation/échange effectué depuis un autre écran (qui
    // invalide le cache produits) ne rafraîchit cette liste qu'au
    // redémarrage complet de l'app.
    AppDataCache.instance.addListener(_onProduitsCacheChanged);
    _bootstrap();
    ApiClient.instance.baseUrl.then((url) {
      if (!mounted) return;
      setState(() => _baseUrl = url);
      if (url != null) {
        ProduitService.instance.loadImagesParDesignation(url).then((map) {
          if (mounted) setState(() => _imagesParDesignation = map);
        });
      }
    });
    AuthService.instance.currentUser.then((user) {
      if (mounted) setState(() => _user = user);
    });
  }

  @override
  void dispose() {
    CartService.instance.removeListener(_onCartChanged);
    AppDataCache.instance.removeListener(_onProduitsCacheChanged);
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onCartChanged() {
    if (mounted) setState(() {});
  }

  void _onProduitsCacheChanged() {
    // Ne recharge que si le cache a bien été invalidé (pas à chaque
    // notification d'un autre domaine, ex: facturesPayees) — cet écran fait
    // toujours un vrai appel réseau (filtres actifs), pas la peine de le
    // déclencher pour rien.
    if (AppDataCache.instance.produits == null) _reload();
  }

  void _addToCart(ProduitModel p) {
    CartService.instance.add(p, qte: 1);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(duration: const Duration(milliseconds: 900), content: Text('${p.designation} ajouté au ticket')),
    );
  }

  Future<void> _openCart() async {
    if (_user == null) return;
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => CartScreen(user: _user!, baseUrl: _baseUrl)));
  }

  Future<void> _bootstrap() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        ProduitService.instance.loadFilters(),
        ProduitService.instance.loadArticles(vue: _vue),
      ]);
      if (!mounted) return;
      setState(() {
        _filters = results[0] as ProduitFilters;
        _produits = results[1] as List<ProduitModel>;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Impossible de charger les articles.';
      });
    }
  }

  void _onSearchChanged(String value) {
    setState(() => _query = value);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), _reload);
  }

  void _onSelectionChanged(FilterSelection selection) {
    setState(() => _selection = selection);
    _reload();
  }

  void _onVueChanged(ProduitVue vue) {
    setState(() {
      _vue = vue;
      _bulkFiltreActif = '__sans_bulk__';
      _selectedBulkIds.clear();
    });
    _reload();
  }

  void _onBulkFiltreChanged(String filtre) {
    setState(() {
      _bulkFiltreActif = filtre;
      _selectedBulkIds.clear();
    });
  }

  void _onBulkCheckChanged(String idProduits, bool checked) {
    setState(() {
      if (checked) {
        _selectedBulkIds.add(idProduits);
      } else {
        _selectedBulkIds.remove(idProduits);
      }
    });
  }

  Future<void> _entrerToutStock(String bulk) async {
    final ok = await _confirmDialog('Entrer tout ce lot en stock ?', 'Tous les articles du classeur "$bulk" deviendront vendables normalement.');
    if (!ok || !mounted) return;
    final result = await ProduitService.instance.entrerStockBulk(bulk: bulk);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(result.message ?? (result.success ? 'Opération effectuée.' : 'Échec.'))),
    );
    if (result.success) {
      AppDataCache.instance.invalidate(CacheDomain.produits);
      _reload();
    }
  }

  Future<void> _ouvrirModalDeplacer(List<String> bulkNames) async {
    if (_selectedBulkIds.isEmpty) return;
    final selectedProduits = _produits.where((p) => _selectedBulkIds.contains(p.idProduits)).toList();
    final bulk = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _DeplacerBulkSheet(bulkNames: bulkNames, selectedProduits: selectedProduits),
    );
    if (bulk == null || bulk.trim().isEmpty || !mounted) return;
    final result = await ProduitService.instance.assignerBulk(ids: _selectedBulkIds.toList(), bulk: bulk.trim());
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(result.message ?? (result.success ? 'Opération effectuée.' : 'Échec.'))),
    );
    if (result.success) {
      setState(() => _selectedBulkIds.clear());
      AppDataCache.instance.invalidate(CacheDomain.produits);
      _reload();
    }
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await ProduitService.instance.loadArticles(
        vue: _vue,
        recherche: _query,
        idFamille: _selection.familleId,
        idMarque: _selection.marqueId,
        idCouleur: _selection.couleurId,
        idBatterie: _selection.batterieId,
        idCarton: _selection.cartonId,
        idDefaut: _selection.defautId,
      );
      if (!mounted) return;
      setState(() {
        _produits = list;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Impossible de charger les articles.';
      });
    }
  }

  Future<void> _openCreate() async {
    if (_user == null) return;
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => ProduitFormScreen(filters: _filters, user: _user!)),
    );
    if (saved == true) _reload();
  }

  Future<void> _openEdit(ProduitModel p, String? imageUrl) async {
    if (_user == null) return;
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => ProduitFormScreen(filters: _filters, user: _user!, existing: p, existingImageUrl: imageUrl)),
    );
    if (saved == true) _reload();
  }

  Future<void> _valider(ProduitModel p, bool valider) async {
    final result = await ProduitService.instance.validerAttente(idProduits: p.idProduits, valider: valider);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(result.message ?? (result.success ? 'Opération effectuée.' : 'Échec.'))),
    );
    if (result.success) {
      AppDataCache.instance.invalidate(CacheDomain.produits);
      _reload();
    }
  }

  Future<void> _remettreEnStock(ProduitModel p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.bgCard,
        title: const Text('Remettre en stock ?', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
        content: const Text(
          'Cet article redeviendra visible et vendable normalement.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Annuler')),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Confirmer', style: TextStyle(color: AppColors.accentLight, fontWeight: FontWeight.w700))),
        ],
      ),
    );
    if (ok != true) return;
    final result = await ProduitService.instance.remettreEnStock(idProduits: p.idProduits);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(result.message ?? (result.success ? 'Article remis en stock.' : 'Échec.'))),
    );
    if (result.success) {
      AppDataCache.instance.invalidate(CacheDomain.produits);
      _reload();
    }
  }

  Future<String?> _promptMotif({required String title, required String confirmLabel, String? initial}) {
    final controller = TextEditingController(text: initial ?? '');
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.bgCard,
        title: Text(title, style: GoogleFonts.inter(color: AppColors.textPrimary, fontWeight: FontWeight.w700, fontSize: 16)),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 3,
          style: const TextStyle(color: AppColors.textPrimary),
          decoration: InputDecoration(
            hintText: 'Défaut / motif...',
            hintStyle: const TextStyle(color: AppColors.textMuted),
            enabledBorder: OutlineInputBorder(borderSide: const BorderSide(color: AppColors.border), borderRadius: BorderRadius.circular(10)),
            focusedBorder: OutlineInputBorder(borderSide: const BorderSide(color: AppColors.borderAccent), borderRadius: BorderRadius.circular(10)),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Annuler')),
          TextButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: Text(confirmLabel, style: const TextStyle(color: AppColors.accentLight, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Future<void> _miseEnReparation(ProduitModel p) async {
    final motif = await _promptMotif(title: 'Mise en réparation', confirmLabel: 'Mettre en réparation', initial: p.motifReparationProduits);
    if (motif == null || !mounted) return;
    final result = await ProduitService.instance.miseEnReparation(idProduits: p.idProduits, motif: motif);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(result.message ?? (result.success ? 'Opération effectuée.' : 'Échec.'))),
    );
    if (result.success) {
      AppDataCache.instance.invalidate(CacheDomain.produits);
      _reload();
    }
  }

  Future<void> _terminerReparation(ProduitModel p) async {
    final motif = await _promptMotif(title: 'Terminer la réparation', confirmLabel: 'Enregistrer', initial: p.motifReparationProduits);
    if (motif == null || !mounted) return;
    final result = await ProduitService.instance.terminerReparation(idProduits: p.idProduits, motif: motif);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(result.message ?? (result.success ? 'Opération effectuée.' : 'Échec.'))),
    );
    if (result.success) {
      AppDataCache.instance.invalidate(CacheDomain.produits);
      _reload();
    }
  }

  Future<bool> _confirmDialog(String title, String message) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.bgCard,
        title: Text(title, style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
        content: Text(message, style: const TextStyle(color: AppColors.textSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Annuler')),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Confirmer', style: TextStyle(color: AppColors.accentLight, fontWeight: FontWeight.w700))),
        ],
      ),
    );
    return ok == true;
  }

  // Onglet "Achat confirmé" — équivalent de Produit::entrer_en_stock_achat().
  Future<void> _entrerEnStockAchat(ProduitModel p) async {
    final ok = await _confirmDialog('Entrer en stock ?', 'Cet article deviendra vendable normalement.');
    if (!ok || !mounted) return;
    final result = await ProduitService.instance.entrerEnStockAchat(idProduits: p.idProduits);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(result.message ?? (result.success ? 'Article entré en stock.' : 'Échec.'))),
    );
    if (result.success) {
      AppDataCache.instance.invalidate(CacheDomain.produits);
      _reload();
    }
  }

  // Onglet "Achat en attente" (patron uniquement) — équivalent de
  // Produit::confirmer_achat().
  Future<void> _confirmerAchat(ProduitModel p) async {
    final ok = await _confirmDialog('Confirmer cet achat ?', '');
    if (!ok || !mounted) return;
    final result = await ProduitService.instance.confirmerAchat(idProduits: p.idProduits);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(result.message ?? (result.success ? 'Achat confirmé.' : 'Échec.'))),
    );
    if (result.success) {
      AppDataCache.instance.invalidate(CacheDomain.produits);
      _reload();
    }
  }

  // Bouton "Mettre en achat" de l'onglet "En attente" (patron uniquement) —
  // équivalent de Produit::mettre_en_achat_depuis_attente().
  Future<void> _mettreEnAchatDepuisAttente(ProduitModel p) async {
    final ok = await _confirmDialog('Mettre cet article en achat ?', '');
    if (!ok || !mounted) return;
    final result = await ProduitService.instance.mettreEnAchatDepuisAttente(idProduits: p.idProduits);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(result.message ?? (result.success ? 'Article mis en achat.' : 'Échec.'))),
    );
    if (result.success) {
      AppDataCache.instance.invalidate(CacheDomain.produits);
      _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAchatConfirmeVue = _vue == ProduitVue.achatConfirme;
    final groups = isAchatConfirmeVue ? const <ProduitGroup>[] : ProduitGroup.groupBy(_produits);
    final valeurVente = _produits.fold(0.0, (sum, p) => sum + (p.totalStock * p.prixUnitaire));
    final valeurAchat = _produits.fold(0.0, (sum, p) => sum + (p.totalStock * p.prixAchats));
    // Comptes hors patron/gérant/magasinier : n'affichent que prix de vente,
    // modèle, n° de série, IMEI et batterie sur les articles (le rôle n'est
    // pas encore chargé -> restriction par défaut, par sécurité).
    final restrictedInfo = !(_user?.hasFullArticleAccess ?? false);

    // Panneau "classeurs" (onglet "Achat confirmé") : comptage par bulk,
    // calculé côté client à partir de la liste déjà chargée (pas d'appel
    // réseau supplémentaire par filtre, voir Produit/lst_achat_confirme
    // côté web pour l'équivalent serveur).
    final bulkCounts = <String, int>{};
    var sansBulkCount = 0;
    if (isAchatConfirmeVue) {
      for (final p in _produits) {
        final b = (p.bulk ?? '').trim();
        if (b.isEmpty) {
          sansBulkCount++;
        } else {
          bulkCounts[b] = (bulkCounts[b] ?? 0) + 1;
        }
      }
    }
    final bulkNames = bulkCounts.keys.toList()..sort();
    List<ProduitModel> achatFiltres = const [];
    if (isAchatConfirmeVue) {
      if (_bulkFiltreActif == '__tous__') {
        achatFiltres = _produits;
      } else if (_bulkFiltreActif == '__sans_bulk__') {
        achatFiltres = _produits.where((p) => (p.bulk ?? '').trim().isEmpty).toList();
      } else {
        achatFiltres = _produits.where((p) => (p.bulk ?? '').trim() == _bulkFiltreActif).toList();
      }
    }

    final cart = CartService.instance;

    return Scaffold(
      backgroundColor: AppColors.bgDeep,
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!cart.isEmpty) ...[
            FloatingActionButton.extended(
              heroTag: 'produit-cart-fab',
              onPressed: _openCart,
              backgroundColor: AppColors.green,
              icon: const Icon(Icons.shopping_cart_rounded, color: Colors.black),
              label: Text(
                '${cart.count} · ${cart.total.toStringAsFixed(0)} Ar',
                style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(height: 12),
          ],
          FloatingActionButton.extended(
            heroTag: 'produit-create-fab',
            onPressed: _openCreate,
            backgroundColor: AppColors.accent,
            icon: const Icon(Icons.add_rounded, color: Colors.white),
            label: const Text('Créer un article', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
      body: SafeArea(
        child: Stack(
          children: [
          RefreshIndicator(
          color: AppColors.accentLight,
          backgroundColor: AppColors.bgCard,
          onRefresh: _bootstrap,
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 4),
                  child: Row(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: AppColors.accentGlow,
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: const Icon(Icons.inventory_2_rounded, size: 17, color: AppColors.accentLight),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        "Gestion d'article",
                        style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
                      ),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(child: _VueTabs(vue: _vue, onChanged: _onVueChanged)),
              const SliverToBoxAdapter(child: SizedBox(height: 10)),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: StatBar(
                    nbArticles: _produits.length,
                    valeurStock: valeurVente,
                    valeurAchat: valeurAchat,
                    restrictedInfo: restrictedInfo,
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: ProduitFilterBar(
                  searchController: _searchController,
                  onSearchChanged: _onSearchChanged,
                  filters: _filters,
                  selection: _selection,
                  onSelectionChanged: _onSelectionChanged,
                ),
              ),
              if (isAchatConfirmeVue) ...[
                SliverToBoxAdapter(
                  child: _BulkFiltreBar(
                    filtreActif: _bulkFiltreActif,
                    totalCount: _produits.length,
                    sansBulkCount: sansBulkCount,
                    bulkCounts: bulkCounts,
                    bulkNames: bulkNames,
                    canOrganize: _canOrganizeBulk,
                    onChanged: _onBulkFiltreChanged,
                    onEntrerToutStock: _entrerToutStock,
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 10)),
              ],
              const SliverToBoxAdapter(child: SizedBox(height: 4)),
              if (_loading)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: CircularProgressIndicator(color: AppColors.accentLight)),
                )
              else if (_error != null)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _ErrorState(message: _error!, onRetry: _reload),
                )
              else if (isAchatConfirmeVue)
                if (achatFiltres.isEmpty)
                  const SliverFillRemaining(hasScrollBody: false, child: _EmptyState())
                else
                  SliverList.builder(
                    itemCount: achatFiltres.length,
                    itemBuilder: (context, i) => _AchatArticleRow(
                      produit: achatFiltres[i],
                      showCheckbox: _bulkFiltreActif == '__sans_bulk__',
                      checked: _selectedBulkIds.contains(achatFiltres[i].idProduits),
                      onCheckChanged: (v) => _onBulkCheckChanged(achatFiltres[i].idProduits, v),
                      onEntrerEnStock: _entrerEnStockAchat,
                    ),
                  )
              else if (groups.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: _EmptyState(),
                )
              else
                SliverList.builder(
                  itemCount: groups.length,
                  itemBuilder: (context, i) => ProduitGroupCard(
                    group: groups[i],
                    baseUrl: _baseUrl,
                    imagesParDesignation: _imagesParDesignation,
                    showValiderAction: _vue == ProduitVue.attente,
                    restrictedInfo: restrictedInfo,
                    isAchatConfirmeVue: _vue == ProduitVue.achatConfirme,
                    isAchatAttenteVue: _vue == ProduitVue.achatAttente,
                    showMettreEnAchatAction: _vue == ProduitVue.attente && _user?.role == 'patron',
                    isPatron: _user?.role == 'patron',
                    onEdit: (p, imageUrl) => _openEdit(p, imageUrl),
                    onValider: (p) => _valider(p, true),
                    onMiseEnReparation: _miseEnReparation,
                    onTerminerReparation: _terminerReparation,
                    onAddToCart: _addToCart,
                    onRemettreEnStock: _remettreEnStock,
                    onEntrerEnStockAchat: _entrerEnStockAchat,
                    onConfirmerAchat: _confirmerAchat,
                    onMettreEnAchat: _mettreEnAchatDepuisAttente,
                  ),
                ),
              SliverToBoxAdapter(child: SizedBox(height: _selectedBulkIds.isNotEmpty ? 140 : 90)),
            ],
          ),
          ),
          _DeplacerFloatingBar(
            visible: _selectedBulkIds.isNotEmpty,
            count: _selectedBulkIds.length,
            onDeplacer: () => _ouvrirModalDeplacer(bulkNames),
          ),
          ],
        ),
      ),
    );
  }
}

class _VueTabs extends StatelessWidget {
  const _VueTabs({required this.vue, required this.onChanged});
  final ProduitVue vue;
  final ValueChanged<ProduitVue> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget chip(ProduitVue v, String label, IconData icon) {
      final selected = v == vue;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          label: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 13, color: selected ? Colors.white : AppColors.textSecondary),
              const SizedBox(width: 6),
              Text(label, style: TextStyle(fontSize: 12.5, color: selected ? Colors.white : AppColors.textSecondary)),
            ],
          ),
          selected: selected,
          selectedColor: AppColors.accent,
          backgroundColor: AppColors.bgElevated,
          onSelected: (_) => onChanged(v),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          chip(ProduitVue.tous, "Gestion d'article", Icons.list_rounded),
          chip(ProduitVue.attente, 'En attente', Icons.access_time_rounded),
          chip(ProduitVue.apresEchange, 'Après échange', Icons.undo_rounded),
          chip(ProduitVue.vente, 'Articles vendus', Icons.shopping_cart_rounded),
          chip(ProduitVue.reparation, 'Article en réparation', Icons.build_rounded),
          chip(ProduitVue.achatConfirme, 'Achat confirmé', Icons.check_circle_rounded),
          chip(ProduitVue.achatAttente, 'Achat en attente', Icons.hourglass_bottom_rounded),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.inbox_rounded, size: 40, color: AppColors.textMuted),
          const SizedBox(height: 12),
          Text('Aucun article trouvé', style: GoogleFonts.inter(color: AppColors.textSecondary, fontSize: 13.5)),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.wifi_off_rounded, size: 36, color: AppColors.red),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(message, textAlign: TextAlign.center, style: GoogleFonts.inter(color: AppColors.textSecondary, fontSize: 13)),
          ),
          const SizedBox(height: 14),
          TextButton(onPressed: onRetry, child: const Text('Réessayer', style: TextStyle(color: AppColors.accentLight))),
        ],
      ),
    );
  }
}

/// Panneau "classeurs" de l'onglet "Achat confirmé" — équivalent mobile du
/// panneau de gauche (1/4) de `Produit/lst_achat_confirme` côté web : une
/// barre horizontale de chips (au lieu d'une colonne, écran étroit oblige)
/// avec "Afficher tout", un chip par bulk (avec son compteur et, pour
/// patron/gérant, un bouton "Entrer tout dans stock"), puis "Sans bulk"
/// (sélectionné par défaut).
class _BulkFiltreBar extends StatelessWidget {
  const _BulkFiltreBar({
    required this.filtreActif,
    required this.totalCount,
    required this.sansBulkCount,
    required this.bulkCounts,
    required this.bulkNames,
    required this.canOrganize,
    required this.onChanged,
    required this.onEntrerToutStock,
  });

  final String filtreActif;
  final int totalCount;
  final int sansBulkCount;
  final Map<String, int> bulkCounts;
  final List<String> bulkNames;
  final bool canOrganize;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onEntrerToutStock;

  @override
  Widget build(BuildContext context) {
    Widget chip({
      required String key,
      required String label,
      required IconData icon,
      required int count,
      VoidCallback? onEntrerTout,
    }) {
      final selected = filtreActif == key;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => onChanged(key),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            constraints: const BoxConstraints(maxWidth: 220),
            decoration: BoxDecoration(
              gradient: selected
                  ? const LinearGradient(colors: [AppColors.accent, AppColors.green])
                  : null,
              color: selected ? null : AppColors.bgElevated,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: selected ? Colors.transparent : AppColors.border),
              boxShadow: selected ? [BoxShadow(color: AppColors.accent.withValues(alpha: 0.35), blurRadius: 12, offset: const Offset(0, 4))] : null,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 13, color: selected ? Colors.white : AppColors.textSecondary),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        label,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: selected ? Colors.white : AppColors.textPrimary),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: selected ? Colors.white.withValues(alpha: 0.25) : Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text('$count', style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w800, color: selected ? Colors.white : AppColors.textSecondary)),
                    ),
                  ],
                ),
                if (onEntrerTout != null) ...[
                  const SizedBox(height: 6),
                  InkWell(
                    onTap: onEntrerTout,
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: selected ? Colors.white.withValues(alpha: 0.2) : AppColors.green.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'Entrer tout dans stock',
                        style: GoogleFonts.inter(fontSize: 9.5, fontWeight: FontWeight.w700, color: selected ? Colors.white : AppColors.green),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          chip(key: '__tous__', label: 'Afficher tout', icon: Icons.layers_rounded, count: totalCount),
          for (final name in bulkNames)
            chip(
              key: name,
              label: name,
              icon: Icons.folder_rounded,
              count: bulkCounts[name] ?? 0,
              onEntrerTout: canOrganize ? () => onEntrerToutStock(name) : null,
            ),
          chip(key: '__sans_bulk__', label: 'Les articles sans bulk', icon: Icons.help_outline_rounded, count: sansBulkCount),
        ],
      ),
    );
  }
}

/// Ligne détaillée d'un article (onglet "Achat confirmé") — équivalent
/// mobile d'une `.aca-row` de `tabproduit_achat_confirme_articles.php` côté
/// web : case à cocher (vue "Sans bulk" uniquement), désignation, n° série,
/// badge bulk, prix, et bouton "Entrer en stock".
class _AchatArticleRow extends StatelessWidget {
  const _AchatArticleRow({
    required this.produit,
    required this.showCheckbox,
    required this.checked,
    required this.onCheckChanged,
    this.onEntrerEnStock,
  });

  final ProduitModel produit;
  final bool showCheckbox;
  final bool checked;
  final ValueChanged<bool> onCheckChanged;
  final void Function(ProduitModel produit)? onEntrerEnStock;

  String _fmt(double v) {
    final s = v.round().toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(' ');
      buf.write(s[i]);
    }
    return buf.toString();
  }

  @override
  Widget build(BuildContext context) {
    final bulk = (produit.bulk ?? '').trim();
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF10131C), AppColors.bgElevated],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          if (showCheckbox) ...[
            SizedBox(
              width: 22,
              height: 22,
              child: Checkbox(
                value: checked,
                activeColor: AppColors.green,
                onChanged: (v) => onCheckChanged(v ?? false),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  produit.designation,
                  style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      produit.numSerie ?? 'Réf. ${produit.idProduits}',
                      style: GoogleFonts.inter(fontSize: 10.5, color: AppColors.textMuted),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                      decoration: BoxDecoration(
                        color: (bulk.isEmpty ? AppColors.textMuted : AppColors.green).withValues(alpha: 0.12),
                        border: Border.all(color: (bulk.isEmpty ? AppColors.textMuted : AppColors.green).withValues(alpha: 0.3)),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Text(
                        bulk.isEmpty ? 'Sans bulk' : bulk,
                        style: GoogleFonts.inter(fontSize: 9.5, fontWeight: FontWeight.w700, color: bulk.isEmpty ? AppColors.textSecondary : AppColors.green),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${_fmt(produit.prixUnitaire)} Ar',
            style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w800, color: AppColors.green),
          ),
          if (onEntrerEnStock != null) ...[
            const SizedBox(width: 6),
            IconButton(
              icon: const Icon(Icons.move_to_inbox_rounded, size: 19, color: AppColors.green),
              tooltip: 'Entrer en stock',
              onPressed: () => onEntrerEnStock!(produit),
            ),
          ],
        ],
      ),
    );
  }
}

/// Barre flottante "Déplacer sur un bulk" (sélection active en vue "Sans
/// bulk") — équivalent mobile de la `.deplacer-bar` de
/// `lst_achat_confirme.php` côté web.
class _DeplacerFloatingBar extends StatelessWidget {
  const _DeplacerFloatingBar({required this.visible, required this.count, required this.onDeplacer});
  final bool visible;
  final int count;
  final VoidCallback onDeplacer;

  @override
  Widget build(BuildContext context) {
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      left: 16,
      right: 16,
      bottom: visible ? 16 : -120,
      child: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: BoxDecoration(
            gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF141826), Color(0xFF0D1018)]),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.borderAccent),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 24, offset: const Offset(0, 10))],
          ),
          child: Row(
            children: [
              Icon(Icons.check_circle_rounded, size: 16, color: AppColors.green),
              const SizedBox(width: 8),
              Expanded(
                child: Text('$count sélectionné(s)', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.green)),
              ),
              ElevatedButton.icon(
                onPressed: onDeplacer,
                icon: const Icon(Icons.folder_open_rounded, size: 16),
                label: const Text('Déplacer sur un bulk'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
                  textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bottom sheet "Déplacer sur un bulk" : liste des articles sélectionnés,
/// choix unique d'un bulk existant ou création d'un nouveau — équivalent
/// mobile du modal de `lst_achat_confirme.php` côté web.
class _DeplacerBulkSheet extends StatefulWidget {
  const _DeplacerBulkSheet({required this.bulkNames, required this.selectedProduits});
  final List<String> bulkNames;
  final List<ProduitModel> selectedProduits;

  @override
  State<_DeplacerBulkSheet> createState() => _DeplacerBulkSheetState();
}

class _DeplacerBulkSheetState extends State<_DeplacerBulkSheet> {
  late List<String> _choices;
  String? _selected;
  final _newBulkController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _choices = List.of(widget.bulkNames);
  }

  @override
  void dispose() {
    _newBulkController.dispose();
    super.dispose();
  }

  void _ajouterNouveau() {
    final nom = _newBulkController.text.trim();
    if (nom.isEmpty) return;
    setState(() {
      if (!_choices.contains(nom)) _choices.insert(0, nom);
      _selected = nom;
      _newBulkController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: AppColors.bgCard,
            borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2))),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.folder_open_rounded, size: 18, color: AppColors.accentLight),
                        const SizedBox(width: 8),
                        Text('Déplacer sur un bulk', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: AppColors.bgElevated, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.border)),
                      constraints: const BoxConstraints(maxHeight: 130),
                      child: ListView(
                        shrinkWrap: true,
                        children: widget.selectedProduits
                            .map((p) => Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 2),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(child: Text(p.designation, overflow: TextOverflow.ellipsis, style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondary))),
                                      Text(p.numSerie ?? '', style: GoogleFonts.inter(fontSize: 11, color: AppColors.textMuted)),
                                    ],
                                  ),
                                ))
                            .toList(),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _newBulkController,
                            style: const TextStyle(color: AppColors.textPrimary, fontSize: 13.5),
                            decoration: InputDecoration(
                              isDense: true,
                              hintText: 'Créer un nouveau bulk...',
                              hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 13),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(9), borderSide: const BorderSide(color: AppColors.border)),
                              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(9), borderSide: const BorderSide(color: AppColors.border)),
                              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(9), borderSide: const BorderSide(color: AppColors.borderAccent)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: _ajouterNouveau,
                          style: ElevatedButton.styleFrom(backgroundColor: AppColors.accent, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9))),
                          child: const Text('Ajouter'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    if (_choices.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text('Aucun bulk existant — créez-en un ci-dessus.', style: GoogleFonts.inter(fontSize: 12.5, color: AppColors.textMuted)),
                      )
                    else
                      ..._choices.map((b) => RadioListTile<String>(
                            value: b,
                            groupValue: _selected,
                            onChanged: (v) => setState(() => _selected = v),
                            activeColor: AppColors.green,
                            contentPadding: EdgeInsets.zero,
                            title: Text(b, style: const TextStyle(color: AppColors.textPrimary, fontSize: 13.5)),
                          )),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.of(context).pop(),
                            style: OutlinedButton.styleFrom(foregroundColor: AppColors.textSecondary, side: const BorderSide(color: AppColors.border), padding: const EdgeInsets.symmetric(vertical: 13)),
                            child: const Text('Annuler'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _selected == null ? null : () => Navigator.of(context).pop(_selected),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.green,
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(vertical: 13),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            child: const Text('Valider', style: TextStyle(fontWeight: FontWeight.w800)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
