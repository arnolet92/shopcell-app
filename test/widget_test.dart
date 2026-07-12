import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shopcell/widgets/shopcell_logo.dart';

// Note : un test qui monte ShopCellApp/SplashScreen directement toucherait
// sqflite (base locale) dès initState, ce qui nécessite un
// sqflite_common_ffi configuré pour l'environnement de test. On vérifie ici
// le rendu de la marque ShopCell, qui ne dépend d'aucune plateforme.
void main() {
  testWidgets('ShopCellMark and wordmark render without error', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [ShopCellMark(size: 64), ShopCellWordmark()],
            ),
          ),
        ),
      ),
    );

    expect(find.byType(ShopCellMark), findsOneWidget);
    expect(find.byType(ShopCellWordmark), findsOneWidget);
  });
}
