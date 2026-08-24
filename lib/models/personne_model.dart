/// Client (table `personnes`), utilisé pour rattacher une vente à un client
/// (`Mob/allpersonnes`, `Mob/addpersonnes`).
class PersonneModel {
  PersonneModel({required this.id, required this.nomComplet, required this.telephone, this.cin});

  final String id;
  final String nomComplet;
  final String? telephone;
  final String? cin;

  factory PersonneModel.fromJson(Map<String, dynamic> json) {
    return PersonneModel(
      id: '${json['id_personnes'] ?? ''}',
      nomComplet: '${json['nom_complet'] ?? '(sans nom)'}',
      telephone: (json['telephone'] as String?)?.trim().isEmpty ?? true ? null : json['telephone'] as String?,
      cin: (json['cin_personnes'] as String?)?.trim().isEmpty ?? true ? null : json['cin_personnes'] as String?,
    );
  }
}
