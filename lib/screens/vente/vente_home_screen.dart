import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../models/produit_model.dart';
import '../../models/user_model.dart';
import '../../services/app_data_cache.dart';
import '../../services/auth_service.dart';
import '../../services/cart_service.dart';
import '../../services/produit_service.dart';
import '../../widgets/inline_field.dart';
import '../../widgets/produit_image.dart';
import '../produit/widgets/produit_detail_sheet.dart';
import 'cart_screen.dart';
import 'qr_sell_scan_screen.dart';
import 'widgets/quantity_modal.dart';

/// Page par défaut après connexion : écran de vente.
/// Reprend l'organisation de `Vente/commande_direct` côté web
/// (`allproduct.php`) : une carte détaillée par unité (photo, modèle,
/// système, IMEI, série, couleur, capacité, batterie, carton, défaut, lieu),
/// dont un tap ajoute directement au panier — puis "Encaisser"/"En attente"
/// via `Mob/all_payed` / `Mob/all_data`.
class VenteHomeScreen extends StatefulWidget {
  const VenteHomeScreen({super.key});

  @override
  State<VenteHomeScreen> createState() => _VenteHomeScreenState();
}

class _VenteHomeScreenState extends State<VenteHomeScreen> {
  final _searchController = TextEditingController();

  List<ProduitModel> _produits = [];
  bool _loading = true;
  String? _error;
  String? _baseUrl;
  UserModel? _user;
  Map<String, String> _imagesParDesignation = {};

  @override
  void initState() {
    super.initState();
    CartService.instance.addListener(_onCartChanged);
    _load();
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
    _searchController.dispose();
    super.dispose();
  }

  void _onCartChanged() {
    if (mounted) setState(() {});
  }

  /// Réutilise le cache préchargé au démarrage (voir AppDataCache /
  /// splash_screen.dart) s'il est disponible et qu'aucun rechargement
  /// explicite n'est demandé (pull-to-refresh, retour après une vente qui a
  /// invalidé le cache) — évite de refaire l'appel réseau à chaque fois que
  /// cet écran (page par défaut de l'app) est affiché.
  Future<void> _load({bool forceNetwork = false}) async {
    if (!forceNetwork) {
      final cached = AppDataCache.instance.produits;
      if (cached != null) {
        setState(() {
          _produits = cached;
          _loading = false;
        });
        return;
      }
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await ProduitService.instance.loadArticles();
      if (!mounted) return;
      AppDataCache.instance.setProduits(list);
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

  /// Même principe que la recherche intelligente (désignation, code, IMEI 1
  /// et 2, numéro de série, capacité) — voir `Produits::search_prod()`.
  List<ProduitModel> get _filtered {
    final q = _searchController.text.trim().toLowerCase();
    if (q.isEmpty) return _produits;
    bool matches(String? field) => field != null && field.toLowerCase().contains(q);
    return _produits
        .where((p) =>
            matches(p.designation) ||
            matches(p.codeProduits) ||
            matches(p.numSerie) ||
            matches(p.imei1) ||
            matches(p.imei2) ||
            matches(p.nomMarque))
        .toList();
  }

  Future<void> _openQrSell() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const QrSellScanScreen()));
  }

  Future<void> _openCart() async {
    if (_user == null) return;
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => CartScreen(user: _user!, baseUrl: _baseUrl)));
  }

  void _openDetail(ProduitModel p, String? imageUrl) {
    showProduitDetailSheet(
      context,
      produit: p,
      baseUrl: _baseUrl,
      imageUrlOverride: imageUrl,
      onAddToCart: () => _pickQuantityAndAdd(p, imageUrl),
    );
  }

  Future<void> _pickQuantityAndAdd(ProduitModel p, String? imageUrl) async {
    final qte = await showQuantityModal(context, produit: p, imageUrl: imageUrl);
    if (qte == null || !mounted) return;
    CartService.instance.add(p, qte: qte);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(milliseconds: 900),
        content: Text('${p.designation} ajouté au panier'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cart = CartService.instance;

    return Scaffold(
      backgroundColor: AppColors.bgDeep,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(color: AppColors.accentGlow, borderRadius: BorderRadius.circular(9)),
                    child: const Icon(Icons.point_of_sale_rounded, size: 17, color: AppColors.accentLight),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text('Vente', style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                  ),
                  IconButton(
                    onPressed: _openQrSell,
                    icon: const Icon(Icons.qr_code_scanner_rounded, color: AppColors.accentLight),
                    tooltip: 'Vendre par scan QR',
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: InlineSearchField(
                controller: _searchController,
                hint: 'Rechercher un article à vendre...',
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(height: 10),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
      floatingActionButton: cart.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: _openCart,
              backgroundColor: AppColors.accent,
              icon: const Icon(Icons.shopping_cart_rounded, color: Colors.white),
              label: Text('${cart.count} · ${cart.total.toStringAsFixed(0)} Ar', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
            ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.accentLight));
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off_rounded, size: 34, color: AppColors.red),
            const SizedBox(height: 10),
            Text(_error!, style: GoogleFonts.inter(color: AppColors.textSecondary, fontSize: 13)),
            const SizedBox(height: 12),
            TextButton(onPressed: _load, child: const Text('Réessayer', style: TextStyle(color: AppColors.accentLight))),
          ],
        ),
      );
    }
    final list = _filtered;
    if (list.isEmpty) {
      return Center(child: Text('Aucun article', style: GoogleFonts.inter(color: AppColors.textMuted)));
    }
    // Une photo par désignation partagée entre toutes ses unités, comme
    // `$images_par_designation` dans allproduct.php.
    final imageResolver = ProduitImageResolver(_produits, _baseUrl)..seedGlobalMap(_imagesParDesignation);

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
      itemCount: list.length,
      separatorBuilder: (_, index) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final p = list[i];
        final imageUrl = imageResolver.resolve(p, _baseUrl);
        return _ProductCard(
          produit: p,
          imageUrl: imageUrl,
          qty: CartService.instance.qteOf(p.idProduits),
          onAdd: () => _pickQuantityAndAdd(p, imageUrl),
          onDetail: () => _openDetail(p, imageUrl),
        );
      },
    );
  }
}

/// Carte article dense, sur le même principe que `.card-produit` dans
/// allproduct.php : photo + désignation + attributs (modèle, système,
/// code, série, IMEI, couleur, capacité, batterie, carton, défaut, lieu).
/// Un tap ajoute directement au panier (comme le `onclick` du web).
class _ProductCard extends StatelessWidget {
  const _ProductCard({
    required this.produit,
    required this.imageUrl,
    required this.qty,
    required this.onAdd,
    required this.onDetail,
  });

  final ProduitModel produit;
  final String? imageUrl;
  final int qty;
  final VoidCallback onAdd;
  final VoidCallback onDetail;

  @override
  Widget build(BuildContext context) {
    final attrs = <String>[
      if (produit.nomModel != null) produit.nomModel!,
      if (produit.nomSysteme != null) produit.nomSysteme!,
      if (produit.nomTypePiece != null) produit.nomTypePiece!,
      if (produit.nomMarque != null) produit.nomMarque!,
      if (produit.nomSousCategoriePiece != null) produit.nomSousCategoriePiece!,
      if (produit.nomCarton != null) produit.nomCarton!,
      if (produit.nomDefaut != null) produit.nomDefaut!,
      if (produit.nomLieu != null) produit.nomLieu!,
    ];

    return Material(
      color: AppColors.bgCard,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onAdd,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: qty > 0 ? AppColors.borderAccent : AppColors.border),
          ),
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ProduitImage(url: imageUrl, size: 68, radius: 14),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            produit.nomSousType != null ? '${produit.nomSousType} ${produit.designation}' : produit.designation,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
                          ),
                        ),
                        InkWell(
                          onTap: onDetail,
                          borderRadius: BorderRadius.circular(20),
                          child: const Padding(
                            padding: EdgeInsets.all(2),
                            child: Icon(Icons.info_outline_rounded, size: 17, color: AppColors.textMuted),
                          ),
                        ),
                      ],
                    ),
                    if (produit.codeProduits != null || produit.numSerie != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        [if (produit.codeProduits != null) produit.codeProduits!, if (produit.numSerie != null) 'S/N ${produit.numSerie}'].join('  ·  '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(fontSize: 10.5, color: AppColors.textMuted),
                      ),
                    ],
                    if (attrs.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 5,
                        runSpacing: 5,
                        children: attrs.take(4).map((a) => _MiniTag(label: a)).toList(),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '${produit.prixUnitaire.toStringAsFixed(0)} Ar',
                          style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w800, color: AppColors.green),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (qty > 0)
                              Container(
                                margin: const EdgeInsets.only(right: 6),
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(20)),
                                child: Text('$qty', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                              ),
                            const Icon(Icons.add_circle_rounded, size: 20, color: AppColors.accentLight),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniTag extends StatelessWidget {
  const _MiniTag({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(color: AppColors.bgElevated, borderRadius: BorderRadius.circular(20)),
      child: Text(label, style: GoogleFonts.inter(fontSize: 10, color: AppColors.textSecondary)),
    );
  }
}
