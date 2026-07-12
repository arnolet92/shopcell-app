import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'local_db.dart';

class ApiException implements Exception {
  ApiException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Client HTTP générique vers le back-office CodeIgniter ShopCell.
///
/// Le lien de base est celui découvert via le scan du QR code
/// (`QR/index` côté web -> encode `<lien>/Mob/checkQR`) et persisté dans
/// [LocalDb]. Toutes les routes mobiles vivent sous le module `Mob`
/// (`application/modules/Mob`), qui est whitelisté dans
/// `config['acces_home']` côté serveur : aucune session/cookie n'est donc
/// nécessaire, chaque appel est indépendant.
class ApiClient {
  ApiClient._();
  static final ApiClient instance = ApiClient._();

  String? _baseUrl;

  Future<String?> get baseUrl async {
    _baseUrl ??= await LocalDb.instance.getConfig(LocalDb.keyServerUrl);
    return _baseUrl;
  }

  Future<void> setBaseUrl(String url) async {
    final cleaned = url.trim().replaceAll(RegExp(r'/+$'), '');
    _baseUrl = cleaned;
    await LocalDb.instance.setConfig(LocalDb.keyServerUrl, cleaned);
  }

  Future<void> forgetBaseUrl() async {
    _baseUrl = null;
    await LocalDb.instance.clearConfig(LocalDb.keyServerUrl);
  }

  Uri _uri(String base, String path) => Uri.parse('$base/index.php/$path');

  /// POST vers `<base>/index.php/Mob/<path>`, encodage x-www-form-urlencoded
  /// (identique à ce qu'attend `$this->input->post()` côté CodeIgniter).
  Future<dynamic> post(
    String path, {
    Map<String, String>? fields,
    String? overrideBaseUrl,
    Duration timeout = const Duration(seconds: 12),
  }) async {
    final base = overrideBaseUrl ?? await baseUrl;
    if (base == null) {
      throw ApiException('Aucun serveur configuré. Veuillez scanner le QR code.');
    }
    final uri = _uri(base, 'Mob/$path');
    try {
      final response = await http.post(uri, body: fields ?? const {}).timeout(timeout);
      return _decode(response);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException(_describeNetworkError(e, uri));
    }
  }

  /// POST multipart/form-data, pour l'envoi d'une photo avec `save_produit`
  /// (équivalent de `$_FILES['photo']` côté PHP / `Media::upload_photo()`).
  Future<dynamic> postMultipart(
    String path, {
    Map<String, String>? fields,
    String? photoFieldName,
    String? photoPath,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final base = await baseUrl;
    if (base == null) {
      throw ApiException('Aucun serveur configuré. Veuillez scanner le QR code.');
    }
    final uri = _uri(base, 'Mob/$path');
    try {
      final request = http.MultipartRequest('POST', uri);
      request.fields.addAll(fields ?? const {});
      if (photoPath != null && photoFieldName != null) {
        request.files.add(await http.MultipartFile.fromPath(photoFieldName, photoPath));
      }
      final streamed = await request.send().timeout(timeout);
      final response = await http.Response.fromStream(streamed);
      return _decode(response);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException(_describeNetworkError(e, uri));
    }
  }

  Future<dynamic> get(
    String path, {
    Map<String, String>? query,
    String? overrideBaseUrl,
    Duration timeout = const Duration(seconds: 12),
  }) async {
    final base = overrideBaseUrl ?? await baseUrl;
    if (base == null) {
      throw ApiException('Aucun serveur configuré. Veuillez scanner le QR code.');
    }
    final uri = _uri(base, 'Mob/$path').replace(queryParameters: query);
    try {
      final response = await http.get(uri).timeout(timeout);
      return _decode(response);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException(_describeNetworkError(e, uri));
    }
  }

  /// Traduit l'exception réseau brute en message précis et actionnable,
  /// avec l'URL réellement tentée (utile pour diagnostiquer un problème de
  /// réseau/pare-feu plutôt qu'un bug de l'application).
  String _describeNetworkError(Object e, Uri uri) {
    if (e is TimeoutException) {
      return "Aucune réponse de $uri (délai dépassé).\nVérifiez que le téléphone est sur le même réseau que le serveur et que le pare-feu Windows autorise Apache.";
    }
    if (e is SocketException) {
      return "Connexion impossible à $uri (${e.osError?.message ?? e.message}).\nVérifiez l'adresse et que le serveur est démarré.";
    }
    if (e is HandshakeException) {
      return "Échec de connexion sécurisée à $uri.";
    }
    return "Erreur réseau vers $uri : $e";
  }

  dynamic _decode(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException('Le serveur a répondu une erreur (${response.statusCode}).');
    }
    final body = response.body.trim();
    if (body.isEmpty) return null;
    try {
      return jsonDecode(body);
    } catch (_) {
      throw ApiException('Réponse du serveur invalide.');
    }
  }
}
