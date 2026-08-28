/// Client (table `personnes`), utilisé pour rattacher une vente à un client
/// (`Mob/allpersonnes`, `Mob/addpersonnes`).
class PersonneModel {
  PersonneModel({required this.id, required this.nomComplet, required this.telephone, this.cin, this.prenom});

  final String id;
  final String nomComplet;
  final String? telephone;
  final String? cin;
  final String? prenom;

  static String? _s(dynamic v) {
    final t = v?.toString().trim();
    return (t == null || t.isEmpty) ? null : t;
  }

  factory PersonneModel.fromJson(Map<String, dynamic> json) {
    return PersonneModel(
      id: '${json['id_personnes'] ?? ''}',
      nomComplet: '${json['nom_complet'] ?? '(sans nom)'}',
      telephone: _s(json['telephone']),
      cin: _s(json['cin_personnes']),
      prenom: _s(json['prenom_personnes']),
    );
  }
}
