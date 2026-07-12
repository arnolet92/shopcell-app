import 'package:flutter/foundation.dart';

import '../models/produit_model.dart';

class CartLine {
  CartLine({required this.produit, required this.qte});
  final ProduitModel produit;
  int qte;

  double get total => qte * produit.prixUnitaire;
}

/// Panier de vente partagé entre l'écran Vente et l'écran "vente par scan
/// QR" (le scan doit pouvoir ajouter un article au panier puis renvoyer
/// directement vers l'écran Vente, donc l'état doit vivre au-dessus des deux
/// écrans plutôt que dans le seul State de VenteHomeScreen).
class CartService extends ChangeNotifier {
  CartService._();
  static final CartService instance = CartService._();

  final Map<String, CartLine> _lines = {};

  List<CartLine> get lines => _lines.values.toList(growable: false);

  int get count => _lines.values.fold(0, (sum, l) => sum + l.qte);

  double get total => _lines.values.fold(0.0, (sum, l) => sum + l.total);

  bool get isEmpty => _lines.isEmpty;

  int qteOf(String idProduits) => _lines[idProduits]?.qte ?? 0;

  void add(ProduitModel produit, {int qte = 1}) {
    final existing = _lines[produit.idProduits];
    if (existing != null) {
      existing.qte += qte;
    } else {
      _lines[produit.idProduits] = CartLine(produit: produit, qte: qte);
    }
    notifyListeners();
  }

  void setQte(String idProduits, int qte) {
    if (qte <= 0) {
      _lines.remove(idProduits);
    } else if (_lines.containsKey(idProduits)) {
      _lines[idProduits]!.qte = qte;
    }
    notifyListeners();
  }

  void remove(String idProduits) {
    _lines.remove(idProduits);
    notifyListeners();
  }

  void clear() {
    _lines.clear();
    notifyListeners();
  }
}
