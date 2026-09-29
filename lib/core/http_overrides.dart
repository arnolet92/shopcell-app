import 'dart:io';

import 'api_client.dart';

/// Autorise la connexion HTTPS à un serveur ShopCell même quand son
/// certificat ne correspond pas à l'hôte demandé — cas typique d'un accès
/// par IP brute (ex: `https://91.234.194.155/shopcell`) à un serveur dont le
/// certificat est délivré pour un nom de domaine (ex: grosprix.creitic.online).
///
/// Restreint au(x) seul(s) hôte(s) que l'utilisateur a explicitement
/// configuré(s) (scan QR / saisie manuelle du lien serveur, voir
/// `ServerService`/`ApiClient.isTrustedHost`) : jamais à un hôte arbitraire,
/// puisque `ApiClient` est le seul client HTTP de l'application et ne parle
/// qu'au serveur ShopCell choisi par l'utilisateur.
class ShopCellHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.badCertificateCallback = (cert, host, port) => ApiClient.instance.isTrustedHost(host);
    return client;
  }
}
