import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/theme.dart';
import '../../models/lookup_model.dart';
import '../../models/produit_model.dart';
import '../../services/app_data_cache.dart';
import '../../services/produit_service.dart';
import '../../widgets/autocomplete_lookup_field.dart';
import '../../widgets/gradient_button.dart';
import '../../widgets/inline_field.dart';
import '../../widgets/produit_image.dart';

/// Création ou modification d'un article — équivalent mobile de
/// `Produit/addprod` (création) et `Produit/modif_lst` (modification), avec
/// le même principe "trouver ou créer" pour marque/couleur/batterie/carton/
/// défaut/fournisseur/modèle/système/famille que le formulaire web.
class ProduitFormScreen extends StatefulWidget {
  const ProduitFormScreen({
    super.key,
    required this.filters,
    this.existing,
    this.existingImageUrl,
  });

  final ProduitFilters filters;
  final ProduitModel? existing;
  final String? existingImageUrl;

  @override
  State<ProduitFormScreen> createState() => _ProduitFormScreenState();
}

class _ProduitFormScreenState extends State<ProduitFormScreen> {
  late final TextEditingController _designation;
  late final TextEditingController _code;
  late final TextEditingController _codeBar;
  late final TextEditingController _numSerie;
  late final TextEditingController _imei1;
  late final TextEditingController _imei2;
  late final TextEditingController _qte;
  late final TextEditingController _prixAchats;
  late final TextEditingController _prixRevient;
  late final TextEditingController _prixUnitaire;
  late final TextEditingController _description;

  late final TextEditingController _famille;
  late final TextEditingController _modele;
  late final TextEditingController _marque;
  late final TextEditingController _couleur;
  late final TextEditingController _batterie;
  late final TextEditingController _carton;
  late final TextEditingController _defaut;
  late final TextEditingController _fournisseur;
  late final TextEditingController _systeme;

  String? _lieuId;
  String? _lieuLabel;
  DateTime? _datePeremption;
  bool _enAttente = false;
  String? _photoPath;
  bool _submitting = false;
  String? _error;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final p = widget.existing;
    _designation = TextEditingController(text: p?.designation ?? '');
    _code = TextEditingController(text: p?.codeProduits ?? '');
    _codeBar = TextEditingController(text: p?.codeBarProduits ?? '');
    _numSerie = TextEditingController(text: p?.numSerie ?? '');
    _imei1 = TextEditingController(text: p?.imei1 ?? '');
    _imei2 = TextEditingController(text: p?.imei2 ?? '');
    _qte = TextEditingController(text: p != null ? p.qteProduits.toStringAsFixed(0) : '1');
    _prixAchats = TextEditingController(text: p != null ? p.prixAchats.toStringAsFixed(0) : '0');
    _prixRevient = TextEditingController(text: p != null ? p.prixRevient.toStringAsFixed(0) : '0');
    _prixUnitaire = TextEditingController(text: p != null ? p.prixUnitaire.toStringAsFixed(0) : '0');
    _description = TextEditingController(text: p?.description ?? '');
    _famille = TextEditingController(text: p?.nomSousType ?? '');
    _modele = TextEditingController(text: p?.nomModel ?? '');
    _marque = TextEditingController(text: p?.nomMarque ?? '');
    _couleur = TextEditingController(text: p?.nomTypePiece ?? '');
    _batterie = TextEditingController(text: p?.nomSousCategoriePiece ?? '');
    _carton = TextEditingController(text: p?.nomCarton ?? '');
    _defaut = TextEditingController(text: p?.nomDefaut ?? '');
    _fournisseur = TextEditingController(text: p?.nomFrns ?? '');
    _systeme = TextEditingController(text: p?.nomSysteme ?? '');
    if (p?.nomLieu != null) {
      _lieuLabel = p!.nomLieu;
      final match = widget.filters.lieux.where((l) => l.label == p.nomLieu);
      if (match.isNotEmpty) _lieuId = match.first.id;
    }
  }

  @override
  void dispose() {
    for (final c in [
      _designation, _code, _codeBar, _numSerie, _imei1, _imei2, _qte, _prixAchats, _prixRevient, _prixUnitaire,
      _description, _famille, _modele, _marque, _couleur, _batterie, _carton, _defaut, _fournisseur, _systeme,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final picker = ImagePicker();
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: AppColors.bgCard,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_rounded, color: AppColors.accentLight),
              title: const Text('Prendre une photo', style: TextStyle(color: AppColors.textPrimary)),
              onTap: () => Navigator.of(context).pop(ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded, color: AppColors.accentLight),
              title: const Text('Choisir dans la galerie', style: TextStyle(color: AppColors.textPrimary)),
              onTap: () => Navigator.of(context).pop(ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;
    final file = await picker.pickImage(source: source, maxWidth: 1280, imageQuality: 85);
    if (file != null) setState(() => _photoPath = file.path);
  }

  Future<void> _pickLieu() async {
    final result = await showModalBottomSheet<LookupItem?>(
      context: context,
      backgroundColor: AppColors.bgCard,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Text('Lieu de stockage', style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            const SizedBox(height: 8),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  ListTile(
                    title: const Text('Aucun', style: TextStyle(color: AppColors.textSecondary)),
                    onTap: () => Navigator.of(context).pop(),
                  ),
                  for (final l in widget.filters.lieux)
                    ListTile(
                      title: Text(l.label, style: const TextStyle(color: AppColors.textPrimary)),
                      onTap: () => Navigator.of(context).pop(l),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    setState(() {
      _lieuId = result?.id;
      _lieuLabel = result?.label;
    });
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _datePeremption ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 15),
    );
    if (picked != null) setState(() => _datePeremption = picked);
  }

  double _parse(TextEditingController c) => double.tryParse(c.text.replaceAll(' ', '').replaceAll(',', '.')) ?? 0;

  Future<void> _submit() async {
    if (_designation.text.trim().isEmpty) {
      setState(() => _error = "La désignation est obligatoire.");
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });

    final result = await ProduitService.instance.saveProduit(
      idProduits: widget.existing?.idProduits,
      designation: _designation.text.trim(),
      codeProduits: _code.text.trim().isEmpty ? null : _code.text.trim(),
      codeBar: _codeBar.text.trim().isEmpty ? null : _codeBar.text.trim(),
      numSerie: _numSerie.text.trim().isEmpty ? null : _numSerie.text.trim(),
      imei1: _imei1.text.trim().isEmpty ? null : _imei1.text.trim(),
      imei2: _imei2.text.trim().isEmpty ? null : _imei2.text.trim(),
      qteProduits: _parse(_qte),
      prixAchats: _parse(_prixAchats),
      prixRevient: _parse(_prixRevient),
      prixUnitaire: _parse(_prixUnitaire),
      description: _description.text.trim().isEmpty ? null : _description.text.trim(),
      enAttente: _enAttente,
      datePeremption: _datePeremption != null
          ? '${_datePeremption!.year.toString().padLeft(4, '0')}-${_datePeremption!.month.toString().padLeft(2, '0')}-${_datePeremption!.day.toString().padLeft(2, '0')}'
          : null,
      famille: _famille.text.trim().isEmpty ? null : _famille.text.trim(),
      modele: _modele.text.trim().isEmpty ? null : _modele.text.trim(),
      marque: _marque.text.trim().isEmpty ? null : _marque.text.trim(),
      couleur: _couleur.text.trim().isEmpty ? null : _couleur.text.trim(),
      batterie: _batterie.text.trim().isEmpty ? null : _batterie.text.trim(),
      carton: _carton.text.trim().isEmpty ? null : _carton.text.trim(),
      defaut: _defaut.text.trim().isEmpty ? null : _defaut.text.trim(),
      fournisseur: _fournisseur.text.trim().isEmpty ? null : _fournisseur.text.trim(),
      systeme: _systeme.text.trim().isEmpty ? null : _systeme.text.trim(),
      idLieu: _lieuId,
      photoPath: _photoPath,
    );

    if (!mounted) return;
    if (result.success) {
      AppDataCache.instance.invalidate(CacheDomain.produits);
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.message ?? (_isEdit ? 'Article modifié.' : 'Article créé.'))),
      );
    } else {
      setState(() {
        _submitting = false;
        _error = result.message ?? 'Une erreur est survenue.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDeep,
      appBar: AppBar(
        backgroundColor: AppColors.bgCard,
        elevation: 0,
        title: Text(
          _isEdit ? "Modifier l'article" : 'Créer un article',
          style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 16, color: AppColors.textPrimary),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          children: [
            Center(
              child: GestureDetector(
                onTap: _pickPhoto,
                child: Stack(
                  children: [
                    _photoPath != null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(20),
                            child: Image.file(File(_photoPath!), width: 96, height: 96, fit: BoxFit.cover),
                          )
                        : ProduitImage(url: widget.existingImageUrl, size: 96, radius: 20),
                    Positioned(
                      right: -2,
                      bottom: -2,
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: const BoxDecoration(color: AppColors.accent, shape: BoxShape.circle),
                        child: const Icon(Icons.camera_alt_rounded, size: 14, color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 26),
            _SectionTitle('Identification'),
            InlineField(label: 'Désignation *', controller: _designation, prefixIcon: Icons.smartphone_rounded),
            const SizedBox(height: 20),
            AutocompleteLookupField(
              label: 'Famille',
              controller: _famille,
              suggestions: widget.filters.familles.map((e) => e.label).toList(),
              prefixIcon: Icons.layers_rounded,
            ),
            const SizedBox(height: 20),
            InlineField(label: 'Code produit', controller: _code, prefixIcon: Icons.qr_code_rounded),
            const SizedBox(height: 20),
            InlineField(label: 'Code barre', controller: _codeBar, prefixIcon: Icons.barcode_reader),
            const SizedBox(height: 20),
            InlineField(label: 'Numéro de série', controller: _numSerie, prefixIcon: Icons.fingerprint_rounded),
            const SizedBox(height: 20),
            InlineField(label: 'IMEI 1', controller: _imei1, keyboardType: TextInputType.number),
            const SizedBox(height: 20),
            InlineField(label: 'IMEI 2', controller: _imei2, keyboardType: TextInputType.number),

            const SizedBox(height: 28),
            _SectionTitle('Caractéristiques'),
            AutocompleteLookupField(
              label: 'Modèle',
              controller: _modele,
              suggestions: widget.filters.modeles.map((e) => e.label).toList(),
              prefixIcon: Icons.phone_android_rounded,
            ),
            const SizedBox(height: 20),
            AutocompleteLookupField(
              label: 'Capacité',
              controller: _marque,
              suggestions: widget.filters.marques.map((e) => e.label).toList(),
              prefixIcon: Icons.memory_rounded,
            ),
            const SizedBox(height: 20),
            AutocompleteLookupField(
              label: 'Couleur',
              controller: _couleur,
              suggestions: widget.filters.couleurs.map((e) => e.label).toList(),
              prefixIcon: Icons.palette_rounded,
            ),
            const SizedBox(height: 20),
            AutocompleteLookupField(
              label: 'Batterie',
              controller: _batterie,
              suggestions: widget.filters.batteries.map((e) => e.label).toList(),
              prefixIcon: Icons.battery_full_rounded,
            ),
            const SizedBox(height: 20),
            AutocompleteLookupField(
              label: 'Carton',
              controller: _carton,
              suggestions: widget.filters.cartons.map((e) => e.label).toList(),
              prefixIcon: Icons.inventory_rounded,
            ),
            const SizedBox(height: 20),
            AutocompleteLookupField(
              label: 'Défaut',
              controller: _defaut,
              suggestions: widget.filters.defauts.map((e) => e.label).toList(),
              prefixIcon: Icons.report_gmailerrorred_rounded,
            ),
            const SizedBox(height: 20),
            AutocompleteLookupField(
              label: 'Système',
              controller: _systeme,
              suggestions: widget.filters.systemes.map((e) => e.label).toList(),
              prefixIcon: Icons.settings_suggest_rounded,
            ),
            const SizedBox(height: 20),
            AutocompleteLookupField(
              label: 'Fournisseur',
              controller: _fournisseur,
              suggestions: widget.filters.fournisseurs.map((e) => e.label).toList(),
              prefixIcon: Icons.local_shipping_rounded,
            ),
            const SizedBox(height: 20),
            InkWell(
              onTap: _pickLieu,
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Lieu de stockage',
                  prefixIcon: Icon(Icons.place_rounded, size: 19, color: AppColors.textMuted),
                ),
                child: Text(_lieuLabel ?? 'Aucun', style: const TextStyle(color: AppColors.textPrimary, fontSize: 15.5)),
              ),
            ),

            const SizedBox(height: 28),
            _SectionTitle('Stock & prix'),
            InlineField(label: 'Quantité', controller: _qte, keyboardType: TextInputType.number, prefixIcon: Icons.inventory_2_rounded),
            const SizedBox(height: 20),
            InlineField(label: "Prix d'achat (Ar)", controller: _prixAchats, keyboardType: TextInputType.number, prefixIcon: Icons.shopping_bag_rounded),
            const SizedBox(height: 20),
            InlineField(label: 'Prix de revient (Ar)', controller: _prixRevient, keyboardType: TextInputType.number, prefixIcon: Icons.calculate_rounded),
            const SizedBox(height: 20),
            InlineField(label: 'Prix de vente (Ar)', controller: _prixUnitaire, keyboardType: TextInputType.number, prefixIcon: Icons.sell_rounded),
            const SizedBox(height: 20),
            InkWell(
              onTap: _pickDate,
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Date de péremption',
                  prefixIcon: Icon(Icons.event_rounded, size: 19, color: AppColors.textMuted),
                ),
                child: Text(
                  _datePeremption != null
                      ? '${_datePeremption!.day.toString().padLeft(2, '0')}/${_datePeremption!.month.toString().padLeft(2, '0')}/${_datePeremption!.year}'
                      : 'Aucune',
                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 15.5),
                ),
              ),
            ),

            const SizedBox(height: 28),
            _SectionTitle('Autres'),
            InlineField(label: 'Description', controller: _description, prefixIcon: Icons.notes_rounded),
            const SizedBox(height: 12),
            SwitchListTile(
              value: _enAttente,
              onChanged: (v) => setState(() => _enAttente = v),
              activeThumbColor: AppColors.accent,
              contentPadding: EdgeInsets.zero,
              title: const Text('Mettre en attente de validation', style: TextStyle(color: AppColors.textPrimary, fontSize: 13.5)),
            ),

            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: AppColors.red, fontSize: 13)),
            ],

            const SizedBox(height: 26),
            GradientButton(
              label: _isEdit ? 'Enregistrer les modifications' : "Créer l'article",
              icon: Icons.check_rounded,
              loading: _submitting,
              onPressed: _submit,
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Text(
        title,
        style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.accentLight, letterSpacing: 0.3),
      ),
    );
  }
}
