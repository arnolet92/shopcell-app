import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme.dart';
import '../../models/produit_activite.dart';
import '../../models/produit_model.dart';
import '../../services/vente_service.dart';
import '../../widgets/produit_image.dart';

String _fmtDate(DateTime? d) {
  if (d == null) return 'Date inconnue';
  return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} à '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

String _fmtMoney(double v) {
  final s = v.round().toString();
  final buf = StringBuffer();
  for (int i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(' ');
    buf.write(s[i]);
  }
  return '${buf.toString()} Ar';
}

/// Historique d'un article : création, modifications (désignation/prix) et
/// ventes (avec lien vers la facture), ouvert depuis un tap sur un article
/// dans la recherche intelligente.
class ProduitActivitesScreen extends StatefulWidget {
  const ProduitActivitesScreen({super.key, required this.produit, required this.imageUrl, required this.baseUrl});

  final ProduitModel produit;
  final String? imageUrl;
  final String? baseUrl;

  @override
  State<ProduitActivitesScreen> createState() => _ProduitActivitesScreenState();
}

class _ProduitActivitesScreenState extends State<ProduitActivitesScreen> {
  bool _loading = true;
  String? _error;
  ProduitActivites _activites = ProduitActivites.empty();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await VenteService.instance.loadProduitActivites(widget.produit.idProduits);
      if (!mounted) return;
      setState(() {
        _activites = data;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = "Impossible de charger l'historique.";
      });
    }
  }

  Future<void> _openFacture(String idClient) async {
    if (widget.baseUrl == null) return;
    final url = Uri.parse('${widget.baseUrl}/index.php/Print_fact/print_fact_payed_client?id=$idClient');
    final ok = await launchUrl(url, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Impossible d'ouvrir la facture.")));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDeep,
      appBar: AppBar(
        backgroundColor: AppColors.bgCard,
        elevation: 0,
        title: Text('Historique de l\'article', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 15.5, color: AppColors.textPrimary)),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: AppColors.accentLight))
            : _error != null
                ? Center(child: Text(_error!, style: const TextStyle(color: AppColors.red)))
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                    children: [
                      _Header(produit: widget.produit, imageUrl: widget.imageUrl),
                      const SizedBox(height: 22),
                      _SectionTitle(icon: Icons.add_circle_outline_rounded, label: 'Création', color: AppColors.green),
                      const SizedBox(height: 10),
                      if (_activites.creations.isEmpty)
                        _EmptyNote(text: 'Aucune information de création trouvée.')
                      else
                        ..._activites.creations.map((g) => _CreationCard(activite: g)),
                      const SizedBox(height: 22),
                      _SectionTitle(icon: Icons.edit_note_rounded, label: 'Modifications', color: AppColors.blue),
                      const SizedBox(height: 10),
                      if (_activites.modifications.isEmpty)
                        _EmptyNote(text: 'Aucune modification enregistrée.')
                      else
                        ..._activites.modifications.map((g) => _ModificationCard(activite: g)),
                      const SizedBox(height: 22),
                      _SectionTitle(icon: Icons.point_of_sale_rounded, label: 'Ventes', color: AppColors.accentLight),
                      const SizedBox(height: 10),
                      if (_activites.ventes.isEmpty)
                        _EmptyNote(text: 'Cet article n\'a jamais été vendu.')
                      else
                        ..._activites.ventes.map((v) => _VenteCard(activite: v, onOpenFacture: v.idClient != null ? () => _openFacture(v.idClient!) : null)),
                    ],
                  ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.produit, required this.imageUrl});
  final ProduitModel produit;
  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        ProduitImage(url: imageUrl, size: 62, radius: 16),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(produit.designation, style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
              if (produit.numSerie != null || produit.codeProduits != null) ...[
                const SizedBox(height: 3),
                Text(
                  [if (produit.codeProduits != null) 'Code: ${produit.codeProduits}', if (produit.numSerie != null) 'S/N: ${produit.numSerie}'].join('  ·  '),
                  style: GoogleFonts.inter(fontSize: 11.5, color: AppColors.textMuted),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.icon, required this.label, required this.color});
  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 17, color: color),
        const SizedBox(width: 8),
        Text(label, style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
      ],
    );
  }
}

class _EmptyNote extends StatelessWidget {
  const _EmptyNote({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 25),
      child: Text(text, style: GoogleFonts.inter(fontSize: 12.5, color: AppColors.textMuted)),
    );
  }
}

class _TimelineCard extends StatelessWidget {
  const _TimelineCard({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8, left: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: child,
    );
  }
}

class _CreationCard extends StatelessWidget {
  const _CreationCard({required this.activite});
  final GestionActivite activite;

  @override
  Widget build(BuildContext context) {
    return _TimelineCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_fmtDate(activite.date), style: GoogleFonts.inter(fontSize: 11.5, color: AppColors.textMuted)),
          const SizedBox(height: 4),
          Text(
            '${activite.designationNew ?? 'Article'} — ${_fmtMoney(activite.prixNew)}',
            style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
          ),
        ],
      ),
    );
  }
}

class _ModificationCard extends StatelessWidget {
  const _ModificationCard({required this.activite});
  final GestionActivite activite;

  @override
  Widget build(BuildContext context) {
    final designationChanged = activite.designationOld != null &&
        activite.designationNew != null &&
        activite.designationOld != activite.designationNew;
    final prixChanged = activite.prixOld != activite.prixNew;

    return _TimelineCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_fmtDate(activite.date), style: GoogleFonts.inter(fontSize: 11.5, color: AppColors.textMuted)),
          const SizedBox(height: 4),
          if (designationChanged)
            Text(
              '"${activite.designationOld}" → "${activite.designationNew}"',
              style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
            ),
          if (prixChanged) ...[
            if (designationChanged) const SizedBox(height: 4),
            Text(
              '${_fmtMoney(activite.prixOld)} → ${_fmtMoney(activite.prixNew)}',
              style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.blue),
            ),
          ],
          if (!designationChanged && !prixChanged)
            Text('Mise à jour de l\'article', style: GoogleFonts.inter(fontSize: 13, color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}

class _VenteCard extends StatelessWidget {
  const _VenteCard({required this.activite, this.onOpenFacture});
  final VenteActivite activite;
  final VoidCallback? onOpenFacture;

  @override
  Widget build(BuildContext context) {
    return _TimelineCard(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  activite.numeroFacture != null ? '${_fmtDate(activite.date)}  ·  Facture ${activite.numeroFacture}' : _fmtDate(activite.date),
                  style: GoogleFonts.inter(fontSize: 11.5, color: AppColors.textMuted),
                ),
                const SizedBox(height: 4),
                Text(
                  '${activite.qte.toStringAsFixed(0)} x ${_fmtMoney(activite.prixVentes)}',
                  style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.green),
                ),
              ],
            ),
          ),
          if (onOpenFacture != null)
            TextButton.icon(
              onPressed: onOpenFacture,
              icon: const Icon(Icons.receipt_long_rounded, size: 16, color: AppColors.accentLight),
              label: const Text('Facture', style: TextStyle(color: AppColors.accentLight, fontSize: 12.5)),
            ),
        ],
      ),
    );
  }
}
