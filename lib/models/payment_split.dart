/// Une ligne de paiement (type + montant). Le paiement d'une vente peut être
/// scindé en plusieurs lignes (ex: une partie en espèces, une partie en
/// mobile money) — voir `VenteMob::allpayed()` côté serveur, étendu pour
/// accepter un tableau de paiements plutôt qu'un seul.
class PaymentSplit {
  PaymentSplit({required this.idTypePaiement, required this.typeLabel, required this.montant});

  final String idTypePaiement;
  final String typeLabel;
  final double montant;

  Map<String, dynamic> toJson() => {'id_type_paiement': idTypePaiement, 'somme': montant};
}
