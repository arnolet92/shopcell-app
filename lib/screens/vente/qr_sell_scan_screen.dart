import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:qr_code_scanner_plus/qr_code_scanner_plus.dart';

import '../../core/theme.dart';
import '../../models/produit_model.dart';
import '../../services/cart_service.dart';
import '../../services/vente_service.dart';
import '../../widgets/camera_permission_gate.dart';

/// Vente par scan QR code : le QR encode directement l'id_produits de
/// l'article. Un scan valide ajoute l'article au panier et referme l'écran
/// (retour direct sur Vente) ; un id inconnu affiche une erreur animée sans
/// quitter le scanner, pour pouvoir réessayer tout de suite.
class QrSellScanScreen extends StatefulWidget {
  const QrSellScanScreen({super.key});

  @override
  State<QrSellScanScreen> createState() => _QrSellScanScreenState();
}

class _QrSellScanScreenState extends State<QrSellScanScreen> with SingleTickerProviderStateMixin {
  final _qrKey = GlobalKey(debugLabel: 'qr_sell');
  QRViewController? _qrController;
  bool _busy = false;
  ProduitModel? _found;
  String? _notFoundCode;

  late final AnimationController _feedbackAnim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );

  @override
  void dispose() {
    _feedbackAnim.dispose();
    super.dispose();
  }

  void _onQrViewCreated(QRViewController controller) {
    _qrController = controller;
    controller.scannedDataStream.listen((scanData) {
      final code = scanData.code;
      if (code != null) _handleScan(code);
    });
  }

  Future<void> _handleScan(String raw) async {
    if (_busy) return;
    final code = raw.trim();
    setState(() {
      _busy = true;
      _found = null;
      _notFoundCode = null;
    });

    final produit = await VenteService.instance.findProduitById(code);

    if (!mounted) return;

    if (produit != null) {
      CartService.instance.add(produit);
      setState(() => _found = produit);
      _feedbackAnim.forward(from: 0);
      await Future.delayed(const Duration(milliseconds: 850));
      if (mounted) Navigator.of(context).pop();
      return;
    }

    setState(() {
      _notFoundCode = code;
      _busy = false;
    });
    _feedbackAnim.forward(from: 0);
    await Future.delayed(const Duration(milliseconds: 1800));
    if (mounted) {
      setState(() {
        _notFoundCode = null;
      });
      await _qrController?.resumeCamera();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDeep,
      appBar: AppBar(
        backgroundColor: AppColors.bgCard,
        elevation: 0,
        title: Text('Vente par scan QR', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 16, color: AppColors.textPrimary)),
      ),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                "Scannez le QR code de l'article : il sera ajouté au panier automatiquement.",
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(fontSize: 13, color: AppColors.textSecondary),
              ),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 36),
                child: AspectRatio(
                  aspectRatio: 1,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(28),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        CameraPermissionGate(
                          builder: (_) => QRView(
                            key: _qrKey,
                            onQRViewCreated: _onQrViewCreated,
                            overlay: QrScannerOverlayShape(
                              borderColor: AppColors.accent,
                              borderRadius: 28,
                              borderLength: 30,
                              borderWidth: 8,
                              cutOutSize: 220,
                            ),
                            onPermissionSet: (controller, granted) {
                              if (!granted && mounted) {
                                setState(() => _notFoundCode = null);
                              }
                            },
                          ),
                        ),
                        if (_found != null) _SuccessOverlay(animation: _feedbackAnim, produit: _found!),
                        if (_notFoundCode != null) _ErrorOverlay(animation: _feedbackAnim, code: _notFoundCode!),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

class _SuccessOverlay extends StatelessWidget {
  const _SuccessOverlay({required this.animation, required this.produit});
  final Animation<double> animation;
  final ProduitModel produit;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final scale = Curves.elasticOut.transform(animation.value);
        return Container(
          color: Colors.black.withValues(alpha: 0.72),
          child: Center(
            child: Transform.scale(
              scale: scale,
              child: Opacity(
                opacity: animation.value.clamp(0.0, 1.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: AppColors.accentGlow,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.accentLight, width: 2),
                      ),
                      child: const Icon(Icons.check_rounded, color: AppColors.accentLight, size: 36),
                    ),
                    const SizedBox(height: 14),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Text(
                        produit.designation,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(fontSize: 14.5, fontWeight: FontWeight.w700, color: Colors.white),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text('Ajouté au panier', style: GoogleFonts.inter(fontSize: 12, color: AppColors.accentLight)),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ErrorOverlay extends StatelessWidget {
  const _ErrorOverlay({required this.animation, required this.code});
  final Animation<double> animation;
  final String code;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final shake = (1 - animation.value) * 6 * ((animation.value * 20).floor().isEven ? 1 : -1);
        return Container(
          color: Colors.black.withValues(alpha: 0.72),
          child: Center(
            child: Transform.translate(
              offset: Offset(shake, 0),
              child: Opacity(
                opacity: animation.value.clamp(0.0, 1.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: AppColors.red.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.red, width: 2),
                      ),
                      child: const Icon(Icons.close_rounded, color: AppColors.red, size: 36),
                    ),
                    const SizedBox(height: 14),
                    Text('Article introuvable', style: GoogleFonts.inter(fontSize: 14.5, fontWeight: FontWeight.w700, color: Colors.white)),
                    const SizedBox(height: 4),
                    Text('Code scanné : $code', style: GoogleFonts.inter(fontSize: 12, color: AppColors.red)),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
