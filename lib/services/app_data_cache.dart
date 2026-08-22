import 'package:flutter/foundation.dart';

import '../models/facture_model.dart';
import '../models/produit_model.dart';
import 'credit_service.dart';
import 'facture_service.dart';
import 'produit_service.dart';

/// Domaine de données mis en cache — un `invalidate(domain)` cible
/// précisément ce qui a changé, plutôt que de tout vider à chaque action.
enum CacheDomain { produits, creditClients, facturesPayees, facturesAnnulees }

/// Cache mémoire des pages principales, préchargées au démarrage (voir
/// `splash_screen.dart::_scheduleNavigation()`) pour qu'ouvrir une page ne
/// déclenche plus systématiquement un appel réseau — seulement si le cache
/// est vide (premier lancement, cache invalidé) ou explicitement invalidé
/// après une action qui change les données (vente, modification d'article,
/// paiement de crédit...). Même principe que `CartService` (singleton
/// `ChangeNotifier`) : les écrans peuvent soit lire directement les
/// getters, soit s'abonner via `addListener` pour se redessiner
/// automatiquement quand le cache change en arrière-plan.
class AppDataCache extends ChangeNotifier {
  AppDataCache._();
  static final AppDataCache instance = AppDataCache._();

  List<ProduitModel>? _produits;
  List<CreditClient>? _creditClients;
  List<FactureListItem>? _facturesPayees;
  List<FactureListItem>? _facturesAnnulees;

  bool _preloading = false;

  List<ProduitModel>? get produits => _produits;
  List<CreditClient>? get creditClients => _creditClients;
  List<FactureListItem>? get facturesPayees => _facturesPayees;
  List<FactureListItem>? get facturesAnnulees => _facturesAnnulees;

  /// Précharge les 4 domaines en parallèle — appelé une fois au démarrage,
  /// pendant l'animation du splash screen (voir _scheduleNavigation()).
  /// Volontairement tolérant aux erreurs individuelles (pas de connexion au
  /// moment du démarrage, etc.) : un domaine qui échoue reste simplement
  /// vide, les écrans concernés retomberont sur leur chargement réseau
  /// habituel plutôt que d'afficher une erreur qui bloquerait tout.
  Future<void> preloadAll() async {
    if (_preloading) return;
    _preloading = true;
    try {
      await Future.wait([
        _safe(() => ProduitService.instance.loadArticles(), (v) => _produits = v),
        _safe(() => CreditService.instance.loadClients(), (v) => _creditClients = v),
        _safe(() => FactureService.instance.loadPayees(), (v) => _facturesPayees = v),
        _safe(() => FactureService.instance.loadAnnulees(), (v) => _facturesAnnulees = v),
      ]);
      notifyListeners();
    } finally {
      _preloading = false;
    }
  }

  Future<void> _safe<T>(Future<T> Function() fetch, void Function(T) assign) async {
    try {
      assign(await fetch());
    } catch (_) {
      // Domaine indisponible au démarrage (pas de réseau, serveur pas encore
      // joignable...) — reste vide, chaque écran refait sa propre tentative
      // réseau normalement si son cache est vide au moment de l'ouverture.
    }
  }

  /// Remplace le contenu d'un domaine par un résultat fraîchement chargé
  /// (ex: une recherche "sans filtre" sur l'écran Factures) — pour que la
  /// prochaine ouverture de l'écran réutilise ce résultat au lieu de
  /// retourner sur le réseau, sans attendre un nouveau `preloadAll()`.
  void setProduits(List<ProduitModel> v) {
    _produits = v;
    notifyListeners();
  }

  void setCreditClients(List<CreditClient> v) {
    _creditClients = v;
    notifyListeners();
  }

  void setFacturesPayees(List<FactureListItem> v) {
    _facturesPayees = v;
    notifyListeners();
  }

  void setFacturesAnnulees(List<FactureListItem> v) {
    _facturesAnnulees = v;
    notifyListeners();
  }

  /// À appeler juste après le succès d'une action qui change ce domaine
  /// (vente encaissée/mise en attente -> produits+facturesPayees ; article
  /// créé/modifié/validé -> produits ; crédit payé -> creditClients+
  /// facturesPayees). Le prochain écran concerné refera un vrai chargement
  /// réseau au lieu de réutiliser une donnée périmée.
  void invalidate(CacheDomain domain) {
    switch (domain) {
      case CacheDomain.produits:
        _produits = null;
      case CacheDomain.creditClients:
        _creditClients = null;
      case CacheDomain.facturesPayees:
        _facturesPayees = null;
      case CacheDomain.facturesAnnulees:
        _facturesAnnulees = null;
    }
    notifyListeners();
  }
}
