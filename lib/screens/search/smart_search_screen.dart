import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../../models/produit_model.dart';
import '../../services/produit_service.dart';
import '../../widgets/inline_field.dart';
import '../produit/widgets/produit_group_card.dart';
import 'produit_activites_screen.dart';

/// Recherche intelligente d'articles par désignation, IMEI (1 et 2),
/// capacité ou numéro de série — s'appuie sur `Produits::search_prod()`
/// côté serveur (`Mob/produits_gestion` avec `arg`), qui couvre désormais
/// ces 5 champs (capacité ajoutée à la demande).
class SmartSearchScreen extends StatefulWidget {
  const SmartSearchScreen({super.key});

  @override
  State<SmartSearchScreen> createState() => _SmartSearchScreenState();
}

class _SmartSearchScreenState extends State<SmartSearchScreen> {
  final _searchController = TextEditingController();
  Timer? _debounce;

  List<ProduitModel> _results = [];
  bool _loading = false;
  bool _searched = false;
  String? _error;
  String? _baseUrl;
  Map<String, String> _imagesParDesignation = {};

  @override
  void initState() {
    super.initState();
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

  void _onChanged(String value) {
    _debounce?.cancel();
    if (value.trim().isEmpty) {
      setState(() {
        _results = [];
        _searched = false;
        _error = null;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () => _search(value.trim()));
  }

  Future<void> _search(String query) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await ProduitService.instance.loadArticles(recherche: query);
      if (!mounted) return;
      setState(() {
        _results = list;
        _loading = false;
        _searched = true;
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
        _error = 'Recherche impossible.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final groups = ProduitGroup.groupBy(_results);

    return Scaffold(
      backgroundColor: AppColors.bgDeep,
      appBar: AppBar(
        backgroundColor: AppColors.bgCard,
        elevation: 0,
        title: Text('Recherche intelligente', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 16, color: AppColors.textPrimary)),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: InlineField(
                label: 'Désignation, IMEI 1/2, capacité ou n° série',
                controller: _searchController,
                prefixIcon: Icons.travel_explore_rounded,
                autofocus: true,
                onChanged: _onChanged,
                onSubmitted: _search,
              ),
            ),
            Expanded(child: _buildBody(groups)),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(List<ProduitGroup> groups) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.accentLight));
    }
    if (_error != null) {
      return Center(
        child: Text(_error!, style: GoogleFonts.inter(color: AppColors.textSecondary, fontSize: 13), textAlign: TextAlign.center),
      );
    }
    if (!_searched) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.travel_explore_rounded, size: 40, color: AppColors.textMuted),
              const SizedBox(height: 12),
              Text(
                "Tapez au moins un critère : nom du modèle, IMEI, capacité (ex: 128 Go) ou numéro de série.",
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }
    if (groups.isEmpty) {
      return Center(
        child: Text('Aucun article trouvé', style: GoogleFonts.inter(color: AppColors.textSecondary, fontSize: 13.5)),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.only(top: 8, bottom: 24),
      itemCount: groups.length,
      itemBuilder: (context, i) => ProduitGroupCard(
        group: groups[i],
        baseUrl: _baseUrl,
        imagesParDesignation: _imagesParDesignation,
        onTapUnit: (produit, imageUrl) => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => ProduitActivitesScreen(produit: produit, imageUrl: imageUrl, baseUrl: _baseUrl)),
        ),
      ),
    );
  }
}
