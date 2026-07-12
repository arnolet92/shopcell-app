import 'dart:convert';

import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

/// Base de données locale SQLite de l'application.
///
/// Deux tables :
/// - `app_config` : paire clé/valeur (notamment le lien du serveur découvert
///   via le scan du QR code sur l'écran d'accueil web `QR/index`).
/// - `session` : l'utilisateur actuellement connecté (réponse brute de
///   `Mob/login`), pour rester connecté entre deux ouvertures de l'appli.
class LocalDb {
  LocalDb._();
  static final LocalDb instance = LocalDb._();

  static const _dbName = 'shopcell.db';
  static const _dbVersion = 1;

  static const keyServerUrl = 'server_url';
  static const keyPrinterConfig = 'printer_config';

  Database? _db;

  Future<Database> get _database async {
    if (_db != null) return _db!;
    _db = await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, _dbName);
    return openDatabase(
      path,
      version: _dbVersion,
      onCreate: (db, version) async {
        await db.execute(
          'CREATE TABLE app_config (key TEXT PRIMARY KEY, value TEXT)',
        );
        await db.execute(
          'CREATE TABLE session (id INTEGER PRIMARY KEY CHECK (id = 1), user_json TEXT, saved_at TEXT)',
        );
      },
    );
  }

  // ---- Config clé/valeur (lien serveur) ----

  Future<void> setConfig(String key, String value) async {
    final db = await _database;
    await db.insert(
      'app_config',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<String?> getConfig(String key) async {
    final db = await _database;
    final rows = await db.query('app_config', where: 'key = ?', whereArgs: [key]);
    if (rows.isEmpty) return null;
    return rows.first['value'] as String?;
  }

  Future<void> clearConfig(String key) async {
    final db = await _database;
    await db.delete('app_config', where: 'key = ?', whereArgs: [key]);
  }

  // ---- Session utilisateur ----

  Future<void> saveSession(Map<String, dynamic> user) async {
    final db = await _database;
    await db.insert(
      'session',
      {
        'id': 1,
        'user_json': jsonEncode(user),
        'saved_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Map<String, dynamic>?> loadSession() async {
    final db = await _database;
    final rows = await db.query('session', where: 'id = 1');
    if (rows.isEmpty) return null;
    final raw = rows.first['user_json'] as String?;
    if (raw == null) return null;
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  Future<void> clearSession() async {
    final db = await _database;
    await db.delete('session', where: 'id = 1');
  }
}
