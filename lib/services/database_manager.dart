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
          iD TEXT,
          title TEXT,
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
          iD TEXT,
          title TEXT,
          plugin TEXT,
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
  for (var historyItem in results) {
    resultsList.add(UniversalSearchRequest(
      searchString: historyItem["searchString"] as String,
      sortingType: historyItem["sortingType"] as String,
      dateRange: historyItem["dateRange"] as String,
      minQuality: historyItem["minQuality"] as int,
      maxQuality: historyItem["maxQuality"] as int,
      minDuration: historyItem["minDuration"] as int,
      maxDuration: historyItem["maxDuration"] as int,
      minFramesPerSecond: historyItem["minFramesPerSecond"] as int,
      maxFramesPerSecond: historyItem["maxFramesPerSecond"] as int,
      virtualReality: historyItem["virtualReality"] as int == 1,
      categoriesInclude: List<String>.from(
          jsonDecode(historyItem["categoriesInclude"] as String)),
      categoriesExclude: List<String>.from(
          jsonDecode(historyItem["categoriesExclude"] as String)),
      keywordsInclude: List<String>.from(
          jsonDecode(historyItem["keywordsInclude"] as String)),
      keywordsExclude: List<String>.from(
          jsonDecode(historyItem["keywordsExclude"] as String)),
      historySearch: true,
    ));
  }

  return resultsList.reversed.toList();
}

Future<List<UniversalVideoPreview>> getWatchHistory() async {
  List<Map<String, Object?>> results = await _database.query("watch_history");
  List<UniversalVideoPreview> resultsList = [];

  for (var historyItem in results) {
    resultsList.add(UniversalVideoPreview(
        iD: historyItem["iD"] == null
            ? "iD database error"
            : historyItem["iD"] as String,
        title: historyItem["title"] == null
            ? "title database error"
            : historyItem["title"] as String,
        plugin: PluginManager.getPluginByName(historyItem["plugin"] == null
            ? "null"
            : historyItem["plugin"] as String),
        thumbnailBinary: historyItem["thumbnailBinary"] == null
            ? Uint8List(0)
            : historyItem["thumbnailBinary"] as Uint8List,
        // previewVideos are not stored due to size
        duration: historyItem["durationInSeconds"] as int == -1
            ? null
            : Duration(seconds: historyItem["durationInSeconds"] as int),
        // viewsTotal and ratingsPositivePercent are not stored to prevent outdated data
        maxQuality: historyItem["maxQuality"] as int == -1
            ? null
            : historyItem["maxQuality"] as int,
        virtualReality: historyItem["virtualReality"] as int == 1,
        authorName: historyItem["authorName"] == null
            ? null
            : historyItem["authorName"] as String,
        authorID: historyItem["authorID"] == null
            ? null
            : historyItem["authorID"] as String,
        verifiedAuthor: historyItem["verifiedAuthor"] as int == 1,
        // convert string back to bool
        lastWatched: DateTime.tryParse(historyItem["lastWatched"] == null
            ? ""
            : historyItem["lastWatched"] as String),
        addedOn: DateTime.tryParse(historyItem["addedOn"] == null
            ? ""
            : historyItem["addedOn"] as String)
        // No need to store the scrapeFailMessage
        ));
  }
  return resultsList.reversed.toList();
}

Future<List<UniversalVideoPreview>> getFavorites() async {
  List<Map<String, Object?>> results = await _database.query("favorites");
  List<UniversalVideoPreview> resultsList = [];

  for (var favorite in results) {
    resultsList.add(UniversalVideoPreview(
        iD: favorite["iD"] == null
            ? "iD database error"
            : favorite["iD"] as String,
        title: favorite["title"] == null
            ? "title database error"
            : favorite["title"] as String,
        plugin: PluginManager.getPluginByName(
            favorite["plugin"] == null ? "null" : favorite["plugin"] as String),
        thumbnailBinary: favorite["thumbnailBinary"] == null
            ? Uint8List(0)
            : favorite["thumbnailBinary"] as Uint8List,
        // previewVideos are not stored due to size
        duration: favorite["durationInSeconds"] as int == -1
            ? null
            : Duration(seconds: favorite["durationInSeconds"] as int),
        // viewsTotal and ratingsPositivePercent are not stored to prevent outdated data
        maxQuality: favorite["maxQuality"] as int == -1
            ? null
            : favorite["maxQuality"] as int,
        virtualReality: favorite["virtualReality"] == "1",
        authorName: favorite["authorName"] == null
            ? null
            : favorite["authorName"] as String,
        authorID: favorite["authorID"] == null
            ? null
            : favorite["authorID"] as String,
        verifiedAuthor: favorite["verifiedAuthor"] as int == 1,
        addedOn: DateTime.tryParse(
            favorite["addedOn"] == null ? "" : favorite["addedOn"] as String)
        // No need to store the scrapeFailMessage
        ));
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

  logger.d("Adding to search history:\n${request.toMap()}");

  // Delete old entry
  List<Map<String, Object?>> oldEntry = await _database.query("search_history",
      where: "searchString = ?", whereArgs: [request.searchString]);
  if (oldEntry.isNotEmpty) {
    logger.i("Found old entry, deleting");
    await _database.delete("search_history",
        where: "searchString = ?", whereArgs: [request.searchString]);
  }
  logger.i("Adding new entry");
  await _database.insert("search_history", {
    "searchString": request.searchString,
    "sortingType": request.sortingType,
    "dateRange": request.dateRange,
    "minQuality": request.minQuality,
    "maxQuality": request.maxQuality,
    "minDuration": request.minDuration,
    "maxDuration": request.maxDuration,
    "minFramesPerSecond": request.minFramesPerSecond,
    "maxFramesPerSecond": request.maxFramesPerSecond,
    "virtualReality": request.virtualReality ? 1 : 0,
    "categoriesInclude": jsonEncode(request.categoriesInclude),
    "categoriesExclude": jsonEncode(request.categoriesExclude),
    "keywordsInclude": jsonEncode(request.keywordsInclude),
    "keywordsExclude": jsonEncode(request.keywordsExclude)
  });
}

Future<void> addToWatchHistory(UniversalVideoPreview result) async {
  if (!(await sharedStorage.getBool("history_watch"))!) {
    logger.i("Watch history disabled, not adding");
    return;
  }
  logger.d("Adding to watch history:\n${result.toMap()}");

  // If entry already exists, fetch its addedOn value
  List<Map<String, Object?>> oldEntry = await _database.query("watch_history",
      columns: ["addedOn"], where: "iD = ?", whereArgs: [result.iD]);
  Map<String, Object?> newEntryData = {
    "iD": result.iD,
    "title": result.title,
    "plugin": result.plugin?.codeName ?? "null",
    "thumbnailBinary": await result.plugin
            ?.downloadThumbnail(Uri.parse(result.thumbnail ?? "")) ??
        Uint8List(0),
    "durationInSeconds": result.duration?.inSeconds ?? -1,
    "maxQuality": result.maxQuality ?? -1,
    "virtualReality": result.virtualReality ? 1 : 0,
    "authorName": result.authorName ?? "null",
    "authorID": result.authorID ?? "null",
    "verifiedAuthor": result.verifiedAuthor ? 1 : 0,
    "lastWatched": DateTime.now().toUtc().toString(),
    "addedOn": DateTime.now().toUtc().toString()
  };
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
  logger.d("Adding to favorites:\n${result.toMap()}");
  await _database.insert("favorites", <String, Object?>{
    "iD": result.iD,
    "title": result.title,
    "plugin": result.plugin?.codeName ?? "null",
    "thumbnailBinary": await result.plugin
            ?.downloadThumbnail(Uri.parse(result.thumbnail ?? "")) ??
        Uint8List(0),
    "durationInSeconds": result.duration?.inSeconds ?? -1,
    "maxQuality": result.maxQuality ?? -1,
    "virtualReality": result.virtualReality ? 1 : 0,
    "authorName": result.authorName ?? "null",
    "authorID": result.authorID ?? "null",
    "verifiedAuthor": result.verifiedAuthor ? 1 : 0,
    "addedOn": DateTime.now().toUtc().toString(),
  });
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
