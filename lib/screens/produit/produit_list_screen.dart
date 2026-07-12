import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../models/lookup_model.dart';
import '../../models/produit_model.dart';
import '../../services/produit_service.dart';
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
  Map<String, String> _imagesParDesignation = {};

  @override
  void initState() {
    super.initState();
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
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
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
    setState(() => _vue = vue);
    _reload();
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
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => ProduitFormScreen(filters: _filters)),
    );
    if (saved == true) _reload();
  }

  Future<void> _openEdit(ProduitModel p, String? imageUrl) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => ProduitFormScreen(filters: _filters, existing: p, existingImageUrl: imageUrl)),
    );
    if (saved == true) _reload();
  }

  Future<void> _valider(ProduitModel p, bool valider) async {
    final result = await ProduitService.instance.validerAttente(idProduits: p.idProduits, valider: valider);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(result.message ?? (result.success ? 'Opération effectuée.' : 'Échec.'))),
    );
    if (result.success) _reload();
  }

  @override
  Widget build(BuildContext context) {
    final groups = ProduitGroup.groupBy(_produits);
    final valeurVente = _produits.fold(0.0, (sum, p) => sum + (p.totalStock * p.prixUnitaire));
    final valeurAchat = _produits.fold(0.0, (sum, p) => sum + (p.totalStock * p.prixAchats));

    return Scaffold(
      backgroundColor: AppColors.bgDeep,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openCreate,
        backgroundColor: AppColors.accent,
        icon: const Icon(Icons.add_rounded, color: Colors.white),
        label: const Text('Créer un article', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
      ),
      body: SafeArea(
        child: RefreshIndicator(
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
                  child: StatBar(nbArticles: _produits.length, valeurStock: valeurVente, valeurAchat: valeurAchat),
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
              const SliverToBoxAdapter(child: SizedBox(height: 14)),
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
                    onEdit: (p, imageUrl) => _openEdit(p, imageUrl),
                    onValider: (p) => _valider(p, true),
                  ),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 90)),
            ],
          ),
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
          chip(ProduitVue.vente, 'Articles vendus', Icons.shopping_cart_rounded),
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
