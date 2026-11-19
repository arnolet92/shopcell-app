import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Illustration animée de l'accueil : un iPhone, un Samsung et un Redmi qui
/// flottent doucement et pivotent à tour de rôle pour montrer leur dos
/// (bloc photo propre à chaque marque). Même mise en scène que la page de
/// connexion web (Templates/accueil_shopcell.php).
class PhonesShowcase extends StatefulWidget {
  const PhonesShowcase({super.key, this.height = 250});
  final double height;

  @override
  State<PhonesShowcase> createState() => _PhonesShowcaseState();
}

class _PhonesShowcaseState extends State<PhonesShowcase> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 15))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  /// Angle de rotation (radians) sur un cycle : face avant la plupart du
  /// temps, puis un tour complet qui laisse voir le dos.
  static double _flip(double u) {
    double ease(double t) => t < .5 ? 4 * t * t * t : 1 - math.pow(-2 * t + 2, 3) / 2;
    if (u < .58) return 0;
    if (u < .66) return math.pi * ease((u - .58) / .08);
    if (u < .80) return math.pi;
    if (u < .88) return math.pi + math.pi * ease((u - .80) / .08);
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.height / 250; // echelle globale
    return SizedBox(
      height: widget.height,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final t = _c.value;
          final now = DateTime.now();
          Widget phone(_Brand b, {required double dx, required double scale, required double tilt, required double phase}) {
            final u = (t + phase) % 1.0;
            final angle = _flip(u);
            final floatY = math.sin((t * 2 + phase) * 2 * math.pi) * 6 * s;
            final showBack = math.cos(angle) < 0;
            final w = 112 * s * scale, h = 232 * s * scale;
            return Transform.translate(
              offset: Offset(dx * s, floatY),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.identity()
                      ..setEntry(3, 2, 0.0013)
                      ..rotateY(tilt + angle),
                    child: showBack
                        ? Transform(
                            alignment: Alignment.center,
                            transform: Matrix4.rotationY(math.pi),
                            child: _Back(brand: b, w: w, h: h),
                          )
                        : _Front(brand: b, w: w, h: h, now: now),
                  ),
                  SizedBox(height: 8 * s),
                  Container(
                    width: w * .75,
                    height: 10 * s,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(40),
                      gradient: RadialGradient(colors: [Colors.black.withValues(alpha: .55), Colors.transparent]),
                    ),
                  ),
                ],
              ),
            );
          }

          return Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              // halo + orbites
              Container(
                width: 240 * s,
                height: 240 * s,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      const Color(0xFF3DDC84).withValues(alpha: .20 + .06 * math.sin(t * 4 * math.pi)),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
              Transform.rotate(
                angle: t * 2 * math.pi,
                child: Container(
                  width: 230 * s,
                  height: 230 * s,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0x243DDC84)),
                  ),
                  alignment: Alignment.topCenter,
                  child: Transform.translate(
                    offset: Offset(0, -3 * s),
                    child: Container(
                      width: 6 * s,
                      height: 6 * s,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0xFF3DDC84),
                        boxShadow: [BoxShadow(color: Color(0xFF3DDC84), blurRadius: 10)],
                      ),
                    ),
                  ),
                ),
              ),
              phone(_Brand.samsung, dx: -86, scale: .84, tilt: .38, phase: 0),
              phone(_Brand.redmi, dx: 86, scale: .84, tilt: -.38, phase: 2 / 3),
              phone(_Brand.iphone, dx: 0, scale: 1, tilt: 0, phase: 1 / 3),
            ],
          );
        },
      ),
    );
  }
}

enum _Brand { iphone, samsung, redmi }

class _Spec {
  const _Spec(this.frame, this.body, this.wall, this.glow, this.label);
  final List<Color> frame, body, wall;
  final Color glow;
  final String label;
}

const _specs = {
  _Brand.iphone: _Spec(
    [Color(0xFFD9D6CF), Color(0xFF8E8A82)],
    [Color(0xFFE8E3DA), Color(0xFFB9B2A6)],
    [Color(0xFF1E1B4B), Color(0xFF4C1D95), Color(0xFF0F172A)],
    Color(0xFFA78BFA),
    '',
  ),
  _Brand.samsung: _Spec(
    [Color(0xFF3F3A55), Color(0xFF1C1A26)],
    [Color(0xFFC4B5FD), Color(0xFF7C6BB8)],
    [Color(0xFF0C1445), Color(0xFF1D4ED8), Color(0xFF0B1023)],
    Color(0xFF60A5FA),
    'SAMSUNG',
  ),
  _Brand.redmi: _Spec(
    [Color(0xFF2B3A3A), Color(0xFF101818)],
    [Color(0xFF5EEAD4), Color(0xFF0F766E)],
    [Color(0xFF042F2E), Color(0xFF0D9488), Color(0xFF022C22)],
    Color(0xFF6EE7B7),
    'REDMI',
  ),
};

const _appColors = [
  [Color(0xFF34D399), Color(0xFF059669)],
  [Color(0xFF60A5FA), Color(0xFF2563EB)],
  [Color(0xFFFBBF24), Color(0xFFD97706)],
  [Color(0xFFF472B6), Color(0xFFDB2777)],
  [Color(0xFFA78BFA), Color(0xFF7C3AED)],
  [Color(0xFFF87171), Color(0xFFDC2626)],
  [Color(0xFF2DD4BF), Color(0xFF0D9488)],
  [Color(0xFFE5E7EB), Color(0xFF9CA3AF)],
];

class _Front extends StatelessWidget {
  const _Front({required this.brand, required this.w, required this.h, required this.now});
  final _Brand brand;
  final double w, h;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final sp = _specs[brand]!;
    final k = w / 112;
    final r = 22 * k;
    final hm = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    return Container(
      width: w,
      height: h,
      padding: EdgeInsets.all(4.5 * k),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(r),
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: sp.frame),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .6), blurRadius: 24, offset: const Offset(0, 14))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(r - 4.5 * k),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: sp.wall),
          ),
          child: Stack(
            children: [
              Positioned(
                top: h * .12,
                right: -w * .2,
                child: Container(
                  width: w * .9,
                  height: w * .9,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(colors: [sp.glow.withValues(alpha: .55), Colors.transparent]),
                  ),
                ),
              ),
              // encoche : ilot (iPhone) ou poinçon (Android)
              Align(
                alignment: Alignment.topCenter,
                child: Container(
                  margin: EdgeInsets.only(top: 6 * k),
                  width: brand == _Brand.iphone ? 32 * k : 7 * k,
                  height: brand == _Brand.iphone ? 9 * k : 7 * k,
                  decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(8 * k)),
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(8 * k, 22 * k, 8 * k, 8 * k),
                child: Column(
                  children: [
                    Text(
                      hm,
                      style: GoogleFonts.outfit(fontSize: 30 * k, fontWeight: FontWeight.w300, color: Colors.white, height: 1),
                    ),
                    SizedBox(height: 3 * k),
                    Text(
                      'ShopCell',
                      style: GoogleFonts.inter(fontSize: 6.5 * k, fontWeight: FontWeight.w700, color: Colors.white70),
                    ),
                    const Spacer(),
                    GridView.count(
                      crossAxisCount: 4,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      padding: EdgeInsets.zero,
                      mainAxisSpacing: 6 * k,
                      crossAxisSpacing: 6 * k,
                      children: [for (final c in _appColors) _App(colors: c, k: k)],
                    ),
                    SizedBox(height: 8 * k),
                    Container(
                      padding: EdgeInsets.all(4 * k),
                      decoration: BoxDecoration(color: Colors.white.withValues(alpha: .18), borderRadius: BorderRadius.circular(10 * k)),
                      child: Row(
                        children: [
                          for (final c in _appColors.take(4))
                            Expanded(
                              child: Padding(
                                padding: EdgeInsets.all(2 * k),
                                child: AspectRatio(
                                  aspectRatio: 1,
                                  child: _App(colors: c, k: k),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    SizedBox(height: 6 * k),
                    Container(
                      width: 30 * k,
                      height: 2.5 * k,
                      decoration: BoxDecoration(color: Colors.white70, borderRadius: BorderRadius.circular(4)),
                    ),
                  ],
                ),
              ),
              // reflet
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.center,
                      colors: [Colors.white.withValues(alpha: .14), Colors.transparent],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _App extends StatelessWidget {
  const _App({required this.colors, required this.k});
  final List<Color> colors;
  final double k;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6 * k),
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: colors),
      ),
    );
  }
}

class _Back extends StatelessWidget {
  const _Back({required this.brand, required this.w, required this.h});
  final _Brand brand;
  final double w, h;

  @override
  Widget build(BuildContext context) {
    final sp = _specs[brand]!;
    final k = w / 112;
    Widget lens(double x, double y, double d) => Positioned(
      left: x * k,
      top: y * k,
      child: Container(
        width: d * k,
        height: d * k,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const RadialGradient(center: Alignment(-.3, -.3), colors: [Color(0xFF3B4A6B), Color(0xFF0B0F18), Colors.black], stops: [0, .45, .75]),
          border: Border.all(color: const Color(0xFF15171D), width: 2 * k),
          boxShadow: [
            BoxShadow(color: Colors.white.withValues(alpha: .18), spreadRadius: 1),
            BoxShadow(color: Colors.black.withValues(alpha: .5), blurRadius: 6),
          ],
        ),
      ),
    );
    Widget flash(double x, double y) => Positioned(
      left: x * k,
      top: y * k,
      child: Container(
        width: 6 * k,
        height: 6 * k,
        decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFFF3E3A8)),
      ),
    );
    Widget bump(double x, double y, double bw, double bh, double r) => Positioned(
      left: x * k,
      top: y * k,
      child: Container(
        width: bw * k,
        height: bh * k,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(r * k),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Colors.white.withValues(alpha: .25), Colors.black.withValues(alpha: .15)],
          ),
          border: Border.all(color: Colors.white.withValues(alpha: .22)),
        ),
      ),
    );
    final parts = switch (brand) {
      _Brand.iphone => [bump(9, 9, 50, 50, 14), lens(13, 13, 19), lens(13, 35, 19), lens(35, 24, 19), flash(42, 14)],
      _Brand.samsung => [lens(12, 12, 20), lens(12, 37, 20), lens(12, 62, 20), flash(38, 18)],
      _Brand.redmi => [bump(9, 9, 44, 76, 12), lens(14, 14, 24), lens(14, 42, 24), lens(16, 69, 9), flash(31, 70)],
    };
    return Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22 * k),
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: sp.body),
        border: Border.all(color: Colors.white.withValues(alpha: .16), width: 1.2),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .6), blurRadius: 24, offset: const Offset(0, 14))],
      ),
      child: Stack(
        children: [
          ...parts,
          if (sp.label.isNotEmpty)
            Positioned(
              left: 0,
              right: 0,
              bottom: 30 * k,
              child: Text(
                sp.label,
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(fontSize: 7.5 * k, fontWeight: FontWeight.w600, letterSpacing: 2.4 * k, color: Colors.white.withValues(alpha: .6)),
              ),
            ),
        ],
      ),
    );
  }
}

/// Pastilles "iPhone · Samsung · Redmi" sous l'illustration.
class BrandChips extends StatelessWidget {
  const BrandChips({super.key});

  @override
  Widget build(BuildContext context) {
    Widget chip(String label, Color c) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .04),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: Colors.white.withValues(alpha: .08)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: c,
              boxShadow: [BoxShadow(color: c, blurRadius: 8)],
            ),
          ),
          const SizedBox(width: 7),
          Text(
            label,
            style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w700, color: const Color(0xFFB7C1C8)),
          ),
        ],
      ),
    );
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 8,
      runSpacing: 6,
      children: [chip('iPhone', const Color(0xFFE5E1D8)), chip('Samsung', const Color(0xFFA78BFA)), chip('Redmi', const Color(0xFF2DD4BF))],
    );
  }
}
