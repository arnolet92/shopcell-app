// Génère le logo ShopCell (badge dégradé + glyphe téléphone) en PNG,
// en pur Dart via package:image — même design que ShopCellMark
// (lib/widgets/shopcell_logo.dart), pour l'icône de l'app.
import 'dart:io';
import 'package:image/image.dart' as img;

bool insideRoundedRect(double x, double y, double cx, double cy, double hw, double hh, double r) {
  final dx = (x - cx).abs() - (hw - r);
  final dy = (y - cy).abs() - (hh - r);
  final ddx = dx < 0 ? 0 : dx;
  final ddy = dy < 0 ? 0 : dy;
  return (ddx * ddx + ddy * ddy) <= r * r;
}

void main() {
  const size = 1024;
  final full = img.Image(width: size, height: size, numChannels: 4);

  const cx = size / 2;
  const cy = size / 2;
  const hw = size / 2 * 0.94;
  const hh = size / 2 * 0.94;
  const corner = size * 0.24;

  // Couleurs : AppColors.accent (#12B76A) -> plus sombre (#0C8F52), diagonal.
  const c1 = [0x12, 0xB7, 0x6A];
  const c2 = [0x0C, 0x8F, 0x52];

  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      if (insideRoundedRect(x.toDouble(), y.toDouble(), cx, cy, hw, hh, corner)) {
        final t = ((x + y) / (size * 2)).clamp(0.0, 1.0);
        final r = (c1[0] + (c2[0] - c1[0]) * t).round();
        final g = (c1[1] + (c2[1] - c1[1]) * t).round();
        final b = (c1[2] + (c2[2] - c1[2]) * t).round();
        full.setPixelRgba(x, y, r, g, b, 255);
      } else {
        full.setPixelRgba(x, y, 0, 0, 0, 0);
      }
    }
  }

  // Glyphe "téléphone" blanc centré (corps arrondi + écran + bouton).
  void drawPhoneGlyph(img.Image target, double scale) {
    final pcx = size / 2.0;
    final pcy = size / 2.0;
    final phw = size / 2 * 0.19 * scale;
    final phh = size / 2 * 0.34 * scale;
    final pcorner = phw * 0.55;

    final shw = phw * 0.78;
    final shh = phh * 0.72;
    final scorner = shw * 0.3;
    final screenCy = pcy - phh * 0.12;

    final buttonCx = pcx;
    final buttonCy = pcy + phh * 0.76;
    final buttonR = phw * 0.16;

    for (var y = (pcy - phh - 4).floor(); y <= (pcy + phh + 4).ceil(); y++) {
      for (var x = (pcx - phw - 4).floor(); x <= (pcx + phw + 4).ceil(); x++) {
        if (x < 0 || y < 0 || x >= size || y >= size) continue;
        final isBody = insideRoundedRect(x.toDouble(), y.toDouble(), pcx, pcy, phw, phh, pcorner);
        if (!isBody) continue;
        final isScreen = insideRoundedRect(x.toDouble(), y.toDouble(), pcx, screenCy, shw, shh, scorner);
        final dxb = x - buttonCx;
        final dyb = y - buttonCy;
        final isButton = (dxb * dxb + dyb * dyb) <= buttonR * buttonR;
        if (isScreen || isButton) continue; // laisse transparaître le fond (découpe l'écran/bouton)
        target.setPixelRgba(x, y, 255, 255, 255, 255);
      }
    }
  }

  drawPhoneGlyph(full, 1.0);
  Directory('assets_out').createSync(recursive: true);
  File('assets_out/app_icon.png').writeAsBytesSync(img.encodePng(full));

  // Version "foreground" adaptative : glyphe seul sur fond transparent,
  // avec la marge de sécurité Android (~66% de la zone visible).
  final fg = img.Image(width: size, height: size, numChannels: 4);
  drawPhoneGlyph(fg, 0.62);
  File('assets_out/app_icon_fg.png').writeAsBytesSync(img.encodePng(fg));

  print('OK: assets_out/app_icon.png + app_icon_fg.png');
}
