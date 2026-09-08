import 'facture_model.dart';
import 'produit_model.dart';

/// Ligne d'article générique pour l'impression (ticket ESC/POS ou PDF A4),
/// indépendante de la source des données : panier en cours (`CartLine`,
/// écran Vente) ou facture déjà enregistrée (`FactureDetailArticle`, écran
/// Factures payées). Voir `TicketBuilder`/`PdfTicketBuilder`.
class ReceiptLine {
  ReceiptLine({
    required this.designation,
    required this.qte,
    required this.prixUnitaire,
    required this.total,
    this.numSerie,
    this.imei1,
    this.imei2,
    this.nomModel,
    this.nomMarque,
    this.nomTypePiece,
    this.nomSousCategoriePiece,
  });

  final String designation;
  final double qte;
  final double prixUnitaire;
  final double total;
  final String? numSerie;
  final String? imei1;
  final String? imei2;
  final String? nomModel;
  final String? nomMarque;
  final String? nomTypePiece;
  /// "Batterie".
  final String? nomSousCategoriePiece;

  factory ReceiptLine.fromProduit(ProduitModel produit, {required double qte}) => ReceiptLine(
        designation: produit.designation,
        qte: qte,
        prixUnitaire: produit.prixUnitaire,
        total: qte * produit.prixUnitaire,
        numSerie: produit.numSerie,
        imei1: produit.imei1,
        imei2: produit.imei2,
        nomModel: produit.nomModel,
        nomMarque: produit.nomMarque,
        nomTypePiece: produit.nomTypePiece,
        nomSousCategoriePiece: produit.nomSousCategoriePiece,
      );

  factory ReceiptLine.fromFactureArticle(FactureDetailArticle article) => ReceiptLine(
        designation: article.designation,
        qte: article.qte,
        prixUnitaire: article.prixUnitaire ?? 0,
        total: article.montant ?? 0,
        numSerie: article.numSerie,
        imei1: article.imei1,
        imei2: article.imei2,
        nomModel: article.nomModel,
        nomMarque: article.nomMarque,
        nomTypePiece: article.nomTypePiece,
        nomSousCategoriePiece: article.nomBatterie,
      );
}
