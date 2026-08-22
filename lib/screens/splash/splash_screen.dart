import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme.dart';
import '../../services/app_data_cache.dart';
import '../../services/auth_service.dart';
import '../../services/server_service.dart';
import '../../widgets/shopcell_logo.dart';
import '../home/home_shell.dart';
import '../pairing/qr_scan_screen.dart';
import '../auth/login_screen.dart';

const _splashDuration = Duration(seconds: 7);

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: _splashDuration)
      ..forward();
    _scheduleNavigation();
  }

  Future<void> _scheduleNavigation() async {
    // Précharge les données pendant que l'animation joue, pour ne jamais
    // faire attendre l'utilisateur une fois les 7s écoulées.
    final serverUrl = await ServerService.instance.savedServerUrl;
    final user = await AuthService.instance.currentUser;

    // Précharge les pages principales (produits, crédits, factures) en
    // arrière-plan pendant l'animation, pour que naviguer dessus une fois
    // connecté ne déclenche plus de chargement réseau à chaque fois — voir
    // AppDataCache. Volontairement non "await" : ne doit jamais retarder la
    // navigation (l'écran de destination affiche son propre indicateur de
    // chargement si le préchargement n'est pas encore terminé).
    if (serverUrl != null && user != null) {
      unawaited(AppDataCache.instance.preloadAll());
    }

    await Future.delayed(_splashDuration);
    if (!mounted) return;

    Widget next;
    if (serverUrl == null) {
      next = const QrScanScreen();
    } else if (user == null) {
      next = const LoginScreen();
    } else {
      next = const HomeShell();
    }

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 650),
        pageBuilder: (_, anim, secondaryAnim) => FadeTransition(opacity: anim, child: next),
      ),
    );
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDeep,
      body: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final t = _c.value;

          // Fondu de sortie global tout à la fin.
          final exitOpacity = 1 - Interval(0.94, 1.0, curve: Curves.easeIn).transform(t);

          return Opacity(
            opacity: exitOpacity.clamp(0.0, 1.0),
            child: Stack(
              fit: StackFit.expand,
              children: [
                _Background(t: t),
                _BrandIntro(t: t),
                _LogoReveal(t: t),
                _LoadingBar(t: t),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Fond dégradé profond + halo lumineux qui pulse doucement.
class _Background extends StatelessWidget {
  const _Background({required this.t});
  final double t;

  @override
  Widget build(BuildContext context) {
    final fadeIn = Interval(0.0, 0.18, curve: Curves.easeOut).transform(t);
    final pulse = 0.5 + 0.5 * math.sin(t * math.pi * 2 * 1.4);

    return Opacity(
      opacity: fadeIn,
      child: Container(
        decoration: const BoxDecoration(gradient: AppColors.backgroundGradient),
        child: Align(
          alignment: const Alignment(0, -0.15),
          child: Container(
            width: 340,
            height: 340,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  AppColors.accent.withValues(alpha: 0.20 + 0.08 * pulse),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BrandSpec {
  const _BrandSpec(this.icon, this.label, this.begin, this.color);
  final IconData icon;
  final String label;
  final double begin; // début de l'apparition (fraction de la durée totale)
  final Color color;
}

const _brands = [
  _BrandSpec(Icons.apple_rounded, 'Apple', 0.06, Colors.white),
  _BrandSpec(Icons.phone_android_rounded, 'Samsung', 0.16, AppColors.blue),
  _BrandSpec(Icons.devices_other_rounded, 'Et plus encore', 0.26, AppColors.green),
];

/// Séquence d'intro : les badges des grandes marques de téléphones
/// apparaissent en cascade, restent un instant, puis convergent/s'effacent
/// pour laisser place au logo ShopCell.
class _BrandIntro extends StatelessWidget {
  const _BrandIntro({required this.t});
  final double t;

  @override
  Widget build(BuildContext context) {
    // Toute la séquence des marques vit entre 0% et 58% de la durée totale.
    final groupFade = 1 - Interval(0.50, 0.60, curve: Curves.easeIn).transform(t);
    if (t > 0.62) return const SizedBox.shrink();

    return Opacity(
      opacity: groupFade.clamp(0.0, 1.0),
      child: Center(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: _brands.map((b) => _BrandBadge(spec: b, t: t)).toList(),
        ),
      ),
    );
  }
}

class _BrandBadge extends StatelessWidget {
  const _BrandBadge({required this.spec, required this.t});
  final _BrandSpec spec;
  final double t;

  @override
  Widget build(BuildContext context) {
    final end = (spec.begin + 0.22).clamp(0.0, 1.0);
    final appear = Interval(spec.begin, end, curve: Curves.elasticOut).transform(t);
    final fadeIn = Interval(spec.begin, (spec.begin + 0.10).clamp(0.0, 1.0), curve: Curves.easeOut).transform(t);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Opacity(
        opacity: fadeIn.clamp(0.0, 1.0),
        child: Transform.scale(
          scale: appear.clamp(0.0, 1.4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: AppColors.bgCard,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppColors.border),
                  boxShadow: [
                    BoxShadow(color: spec.color.withValues(alpha: 0.25), blurRadius: 22),
                  ],
                ),
                child: Icon(spec.icon, color: spec.color, size: 30),
              ),
              const SizedBox(height: 10),
              Text(
                spec.label,
                style: GoogleFonts.inter(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Révélation du logo ShopCell (badge + wordmark + accroche), qui prend le
/// relais après la cascade des marques.
class _LogoReveal extends StatelessWidget {
  const _LogoReveal({required this.t});
  final double t;

  @override
  Widget build(BuildContext context) {
    final logoAppear = Interval(0.55, 0.78, curve: Curves.easeOutBack).transform(t);
    final textAppear = Interval(0.68, 0.86, curve: Curves.easeOut).transform(t);
    final taglineAppear = Interval(0.80, 0.94, curve: Curves.easeOut).transform(t);

    if (t < 0.52) return const SizedBox.shrink();

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Transform.scale(
            scale: logoAppear.clamp(0.0, 1.15),
            child: Opacity(
              opacity: logoAppear.clamp(0.0, 1.0),
              child: const ShopCellMark(size: 96),
            ),
          ),
          const SizedBox(height: 22),
          Opacity(
            opacity: textAppear.clamp(0.0, 1.0),
            child: Transform.translate(
              offset: Offset(0, 12 * (1 - textAppear.clamp(0.0, 1.0))),
              child: const ShopCellWordmark(fontSize: 34),
            ),
          ),
          const SizedBox(height: 10),
          Opacity(
            opacity: taglineAppear.clamp(0.0, 1.0),
            child: Text(
              'La gestion premium de votre boutique',
              style: GoogleFonts.inter(
                fontSize: 13,
                color: AppColors.textSecondary,
                letterSpacing: 0.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Fine barre de chargement en dégradé, avec effet de "shimmer" glissant.
class _LoadingBar extends StatelessWidget {
  const _LoadingBar({required this.t});
  final double t;

  @override
  Widget build(BuildContext context) {
    final appear = Interval(0.72, 0.86, curve: Curves.easeOut).transform(t);
    if (appear <= 0) return const SizedBox.shrink();

    final progress = Interval(0.72, 0.98, curve: Curves.easeInOut).transform(t);

    return Positioned(
      left: 48,
      right: 48,
      bottom: 64,
      child: Opacity(
        opacity: appear.clamp(0.0, 1.0),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Container(
            height: 4,
            color: AppColors.border,
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: progress.clamp(0.0, 1.0),
              child: Container(
                decoration: const BoxDecoration(gradient: AppColors.accentGradient),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
