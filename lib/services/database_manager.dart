import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '/services/plugin_manager.dart';
import '/utils/global_vars.dart';
import '/utils/plugin_interface.dart';
import '/utils/universal_formats.dart';

late Database _database;

bool _factoryInitialized = false;

Future<void> initDb() async {
  if (!_factoryInitialized) {
    logger.i("Initializing database backend");
    if (Platform.isLinux) {
      logger.i("Linux detected, initializing sqflite_ffi");
      sqfliteFfiInit();
    }
    databaseFactory = databaseFactoryFfi;
    _factoryInitialized = true;
  } else {
    logger.i("Database backend already initialized. Skipping...");
  }

  Directory appSupportDir = await getApplicationSupportDirectory();
  String dbPath = "${appSupportDir.path}/hedon_haven.db";

  logger.i("Opening database at $dbPath");
  await openDatabase(dbPath, version: 1,
      onCreate: (Database db, int version) async {
    _database = db;
    logger.i("No database detected, creating new");
    createDefaultTables();
  }, onUpgrade: (Database db, int oldVersion, int newVersion) async {
    _database = db;
    logger.i("Database upgrade from $oldVersion to $newVersion");
    // TODO: Implement database upgrades if needed
  }, onDowngrade: (Database db, int oldVersion, int newVersion) async {
    _database = db;
    logger.w("UNEXPECTED DATABASE DOWNGRADE! Backing up to hedon_haven.db_old");
    // copy database to old database
    await File(dbPath).copy("${dbPath}_old");
    logger.w("DROPPING ALL TABLES TO PREVENT ERRORS!!!");
    await db.execute("DROP TABLE watch_history");
    await db.execute("DROP TABLE search_history");
    await db.execute("DROP TABLE favorites");
    createDefaultTables();
  }, onOpen: (Database db) async {
    _database = db;
    logger.i("Database opened successfully");
  });
}

Future<void> closeDb() async {
  try {
    // Ensure any transaction is committed
    await _database
        .execute('COMMIT;')
        .onError((_, __) => logger.d("Nothing to commit before closing db"));
    // Ensure all data is flushed to disk
    await _database
        .execute('PRAGMA synchronous = FULL;')
        .onError((_, __) => logger.d("Nothing to sync before closing db"));
    await _database.close();
  } catch (e, stacktrace) {
    logger.w("Error closing database (Continuing anyways): $e\n$stacktrace");
  }
}

/// Delete all rows from a table
/// Possible tableNames: watch_history, search_history, favorites
Future<void> deleteAllFrom(String tableName) async {
  logger.w("Deleting all rows from $tableName");
  await _database.execute("DELETE FROM $tableName");
}

/// Unlike deleteAllFrom, this deletes the database file itself
Future<void> purgeDatabase() async {
  logger.w("Purging database");
  logger.i("Closing old db");
  await closeDb();
  Directory appSupportDir = await getApplicationSupportDirectory();
  File databaseFile = File("${appSupportDir.path}/hedon_haven.db");
  if (await databaseFile.exists()) {
    await databaseFile.delete();
    logger.i("Database deleted successfully");
  } else {
    logger.w("Database not found, nothing was deleted");
  }
}

Future<void> createDefaultTables() async {
  logger.i("Creating default tables in database");
  // Reimplementation of some parts of UniversalSearchResult
  // This is only used to show a preview in the history screen
  // If the user decides to replay a video from history, the corresponding
  // plugin will be called upon to fetch fresh video metadata
  // Storing videoPreview would take up a lot of storage
  // "db_id" is an internal database id
  // "iD" is the provider-specific id used in the app itself
  await _database.execute('''
        CREATE TABLE watch_history (
          db_id INTEGER PRIMARY KEY,
          iD TEXT NOT NULL,
          title TEXT NOT NULL,
          plugin TEXT,
          thumbnailBinary BLOB,
          duration INTEGER,
          maxQuality INTEGER,
          virtualReality INTEGER,
          authorName TEXT,
          authorID TEXT,
          verifiedAuthor INTEGER,
          lastWatched TEXT,
          addedOn Text
        )
        ''');
  // Reimplementation of UniversalSearchRequest
  // Plugins is a list of plugins the search was attempted on
  // virtualReality is actually a boolean
  // categories and keywords are actually lists of strings
  // "db_id" is an internal database id
  await _database.execute('''
        CREATE TABLE search_history (
          db_id INTEGER PRIMARY KEY,
          searchString TEXT,
          sortingType TEXT,
          dateRange TEXT,
          minQuality INTEGER,
          maxQuality INTEGER,
          minDuration INTEGER,
          maxDuration INTEGER,
          minFramesPerSecond INTEGER,
          maxFramesPerSecond INTEGER,
          virtualReality INTEGER,
          categoriesInclude TEXT,
          categoriesExclude TEXT,
          keywordsInclude TEXT,
          keywordsExclude TEXT
        )
      ''');
  // Reimplementation of some parts of UniversalSearchResult
  // This is only used to show a preview in the history screen
  // If the user decides to replay a video from history, the corresponding
  // plugin will be called upon to fetch fresh video metadata
  // Storing videoPreview would take up a lot of storage
  // "db_id" is an internal database id
  // "iD" is the provider-specific id used in the app itself
  await _database.execute('''
        CREATE TABLE favorites (
          db_id INTEGER PRIMARY KEY,
          iD TEXT NOT NULL,
          title TEXT NOT NULL,
          plugin TEXT NOT NULL,
          thumbnailBinary BLOB,
          duration INTEGER,
          maxQuality INTEGER,
          virtualReality INTEGER,
          authorName TEXT,
          authorID TEXT,
          verifiedAuthor INTEGER,
          addedOn Text
        )
        ''');
}

Future<List<Map<String, Object?>>> getAllFrom(
    String dbName, String tableName) async {
  logger.i("Getting all rows from $tableName");
  return await _database.query(tableName);
}

Future<bool> isInFavorites(String iD) async {
  //logger.i("Checking if $iD is in favorites");
  List<Map<String, Object?>> results = await _database.query("favorites",
      columns: ["iD"], where: "iD = ?", whereArgs: [iD]);
  return results.isNotEmpty;
}

Future<List<UniversalSearchRequest>> getSearchHistory() async {
  logger.i("Getting search history");
  List<Map<String, Object?>> results = await _database.query("search_history");
  List<UniversalSearchRequest> resultsList = [];

  logger.i("Converting search history");
  for (var raw in results) {
    try {
      // mutable copy
      final historyItem = Map<String, Object?>.from(raw);
      // Convert int back into bool
      historyItem["virtualReality"] = historyItem["virtualReality"] as int == 1;

      // Convert String to List
      historyItem["categoriesInclude"] = List<String>.from(
          jsonDecode(historyItem["categoriesInclude"] as String));
      historyItem["categoriesExclude"] = List<String>.from(
          jsonDecode(historyItem["categoriesExclude"] as String));
      historyItem["keywordsInclude"] = List<String>.from(
          jsonDecode(historyItem["keywordsInclude"] as String));
      historyItem["keywordsExclude"] = List<String>.from(
          jsonDecode(historyItem["keywordsExclude"] as String));

      // mark as history search
      historyItem["historySearch"] = true;

      resultsList.add(UniversalSearchRequest.fromMap(historyItem));
    } catch (e, st) {
      logger.e("Error converting search history entry from database: $e\n$st");
    }
  }

  return resultsList.reversed.toList();
}

Future<List<UniversalVideoPreview>> getWatchHistory() async {
  List<Map<String, Object?>> results = await _database.query("watch_history");
  List<UniversalVideoPreview> resultsList = [];

  for (var raw in results) {
    try {
      // mutable copy
      final historyItem = Map<String, Object?>.from(raw);
      // Convert int back into bool
      historyItem["virtualReality"] = historyItem["virtualReality"] as int == 1;
      historyItem["verifiedAuthor"] = historyItem["verifiedAuthor"] as int == 1;
      resultsList.add(UniversalVideoPreview.fromMap(historyItem,
          PluginManager.getPluginByName(historyItem["plugin"] as String?)));
    } catch (e, st) {
      logger.e("Error converting watch history entry from database: $e\n$st");
    }
  }
  return resultsList.reversed.toList();
}

Future<List<UniversalVideoPreview>> getFavorites() async {
  List<Map<String, Object?>> results = await _database.query("favorites");
  List<UniversalVideoPreview> resultsList = [];

  for (var raw in results) {
    try {
      // mutable copy
      final favorite = Map<String, Object?>.from(raw);
      // Convert int back into bool
      favorite["virtualReality"] = favorite["virtualReality"] as int == 1;
      favorite["verifiedAuthor"] = favorite["verifiedAuthor"] as int == 1;
      resultsList.add(UniversalVideoPreview.fromMap(favorite,
          PluginManager.getPluginByName(favorite["plugin"] as String?)));
    } catch (e, st) {
      logger.e("Error converting favorites entry from database: $e\n$st");
    }
  }
  return resultsList.toList();
}

Future<void> addToSearchHistory(
    UniversalSearchRequest request, List<PluginInterface> plugins) async {
  if (!(await sharedStorage.getBool("history_search"))!) {
    logger.i("Search history disabled, not adding");
    return;
  }
  if (request.searchString.isEmpty) {
    logger.w("Search string is empty, not adding to search history");
    return;
  }

  Map<String, Object?> newEntryData = request.toMap();
  logger.d("Adding to search history:\n$newEntryData");

  // remove unnecessary fields
  newEntryData.remove("historySearch");

  // convert bool to int
  newEntryData["virtualReality"] =
      newEntryData["virtualReality"] == true ? 1 : 0;

  // Convert List to String
  newEntryData["categoriesInclude"] =
      jsonEncode(newEntryData["categoriesInclude"]);
  newEntryData["categoriesExclude"] =
      jsonEncode(newEntryData["categoriesExclude"]);
  newEntryData["keywordsInclude"] = jsonEncode(newEntryData["keywordsInclude"]);
  newEntryData["keywordsExclude"] = jsonEncode(newEntryData["keywordsExclude"]);

  // Delete old entry
  List<Map<String, Object?>> oldEntry = await _database.query("search_history",
      where: "searchString = ?", whereArgs: [request.searchString]);
  if (oldEntry.isNotEmpty) {
    logger.i("Found old entry, deleting");
    await _database.delete("search_history",
        where: "searchString = ?", whereArgs: [request.searchString]);
  }

  await _database.insert("search_history", newEntryData);
}

Future<void> addToWatchHistory(UniversalVideoPreview result) async {
  if (!(await sharedStorage.getBool("history_watch"))!) {
    logger.i("Watch history disabled, not adding");
    return;
  }
  Map<String, Object?> newEntryData = result.toMap();
  logger.d("Adding to watch history:\n$newEntryData");

  // remove unnecessary values
  newEntryData.remove("thumbnail");
  newEntryData.remove("thumbnailHttpHeaders");
  newEntryData.remove("previewVideo");
  newEntryData.remove("viewsTotal");
  newEntryData.remove("ratingsPositivePercent");
  newEntryData.remove("scrapeFailMessage");

  // update values
  newEntryData["thumbnailBinary"] = await result.plugin
          ?.downloadThumbnail(Uri.parse(result.thumbnail ?? "")) ??
      Uint8List(0);
  newEntryData["lastWatched"] = DateTime.now().toUtc().toString();
  newEntryData["addedOn"] = DateTime.now().toUtc().toString();

  // convert bool to int
  newEntryData["virtualReality"] = result.virtualReality == true ? 1 : 0;
  newEntryData["verifiedAuthor"] = result.verifiedAuthor == true ? 1 : 0;

  // If entry already exists, fetch its addedOn value
  List<Map<String, Object?>> oldEntry = await _database.query("watch_history",
      columns: ["addedOn"], where: "iD = ?", whereArgs: [result.iD]);
  if (oldEntry.isNotEmpty) {
    logger.i("Found old entry, updating everything except addedOn");
    newEntryData["addedOn"] = oldEntry.first["addedOn"];
    await _database.update(
      "watch_history",
      newEntryData,
      where: "iD = ?",
      whereArgs: [result.iD],
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  } else {
    logger.i("No old entry found, creating new entry");
    await _database.insert("watch_history", newEntryData);
  }
}

Future<void> addToFavorites(UniversalVideoPreview result) async {
  Map<String, Object?> newEntryData = result.toMap();
  logger.d("Adding to favorites:\n$newEntryData");

  // remove unnecessary values
  newEntryData.remove("thumbnail");
  newEntryData.remove("thumbnailHttpHeaders");
  newEntryData.remove("previewVideo");
  newEntryData.remove("viewsTotal");
  newEntryData.remove("ratingsPositivePercent");
  newEntryData.remove("scrapeFailMessage");
  newEntryData.remove("lastWatched");

  // update values
  newEntryData["thumbnailBinary"] = await result.plugin
          ?.downloadThumbnail(Uri.parse(result.thumbnail ?? "")) ??
      Uint8List(0);
  newEntryData["addedOn"] = DateTime.now().toUtc().toString();

  // convert bool to int
  newEntryData["virtualReality"] = result.virtualReality == true ? 1 : 0;
  newEntryData["verifiedAuthor"] = result.verifiedAuthor == true ? 1 : 0;

  await _database.insert("favorites", newEntryData);
}

Future<void> removeFromSearchHistory(UniversalSearchRequest request) async {
  logger.d("Removing from search history:\n${request.toMap()}");
  await _database.delete("search_history",
      where: "searchString = ?", whereArgs: [request.searchString]);
}

Future<void> removeFromWatchHistory(UniversalVideoPreview result) async {
  logger.d("Removing from watch history:\n${result.toMap()}");
  await _database
      .delete("watch_history", where: "iD = ?", whereArgs: [result.iD]);
}

Future<void> removeFromFavorites(UniversalVideoPreview result) async {
  logger.d("Removing from favorites:\n${result.toMap()}");
  await _database.delete("favorites", where: "iD = ?", whereArgs: [result.iD]);
}
