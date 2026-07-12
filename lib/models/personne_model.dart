/// Client (table `personnes`), utilisé pour rattacher une vente à un client
/// (`Mob/allpersonnes`, `Mob/addpersonnes`).
class PersonneModel {
  PersonneModel({required this.id, required this.nomComplet, required this.telephone});

  final String id;
  final String nomComplet;
  final String? telephone;

  factory PersonneModel.fromJson(Map<String, dynamic> json) {
    return PersonneModel(
      id: '${json['id_personnes'] ?? ''}',
      nomComplet: '${json['nom_complet'] ?? '(sans nom)'}',
      telephone: (json['telephone'] as String?)?.trim().isEmpty ?? true ? null : json['telephone'] as String?,
    );
  }
}
