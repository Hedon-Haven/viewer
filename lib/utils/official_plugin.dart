import 'dart:async';
import 'dart:isolate';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_hls_parser/flutter_hls_parser.dart';
import 'package:html/dom.dart';

import '/utils/global_vars.dart';

/// This class contains internal functions / pre-implemented functions for official plugins
abstract class OfficialPlugin {
  Isolate? getProgressThumbnailsIsolate;

  // This Map must be overriden in plugins that extend this class
  // It is only accessible if the plugin is initialized as an OfficialPlugin
  // or from the plugin itself
  // The ignoreScrapedErrors vars are used in the plugin code and in tests
  // The rest are only used by CI-tests
  late Map<String, dynamic> testingMap = {
    "ignoreScrapedErrors": {
      "homepage": [],
      "searchResults": [],
      "videoMetadata": [],
      "videoSuggestions": [],
      "authorVideos": [],
      "comments": [],
      "authorPage": [],
    },
    "testingVideos": [
      {"videoID": "", "progressThumbnailsAmount": 0},
      {"videoID": "", "progressThumbnailsAmount": 0}
    ],
    "testingAuthorPageIds": ["", "", ""]
  };

  // No need for actual dispose in OfficialPlugins
  void dispose() {}

  /// Parse a master m3u8 into media m3u8s
  Future<Map<int, Uri>> parseM3U8(Uri playListUri) async {
    Map<int, Uri> playListMap = {};
    // download and convert the m3u8 into a string
    var response = await client.get(playListUri);
    if (response.statusCode == 200) {
      String contentString = response.body;
      HlsMasterPlaylist? playList = (await HlsPlaylistParser.create()
          .parseString(playListUri, contentString)) as HlsMasterPlaylist?;

      // verify the playList is not empty
      if (playList != null) {
        for (var variant in playList.variants) {
          if (variant.format.height != null) {
            playListMap[variant.format.height!] = variant.url;
          } else {
            logger.e("Error parsing m3u8: $playListUri");
          }
        }
      } else {
        logger.e("M3U8 is empty: $playListUri");
      }
    } else {
      logger.e(
          "Error downloading m3u8 master file: ${response.statusCode} - ${response.reasonPhrase}");
    }
    return playListMap;
  }

  /// The pluginInterface runs all functions as isolates due to the nature of how third-party plugins are implemented
  /// However, most functions are not that performance heavy and can be run in the main isolate, except for getProgressThumbnails
  /// This function is called by the main isolate and overrides the pluginInterface one in official plugins
  @nonVirtual
  Future<List<Uint8List>?> getProgressThumbnails(
      String videoID, Document rawHtml) async {
    // spawn the isolate
    final receivePort = ReceivePort();
    final rootToken = RootIsolateToken.instance!;
    getProgressThumbnailsIsolate =
        await Isolate.spawn(isolateGetProgressThumbnails, receivePort.sendPort);
    final isolateSendPort = await receivePort.first as SendPort;

    final resultsPort = ReceivePort();
    final logsPort = ReceivePort();
    final fetchPort = ReceivePort();

    // Passing the custom client to the isolate is not allowed by dart
    // -> Allow the isolate to call the client from the main isolate
    fetchPort.listen((message) async {
      final url = message[0] as Uri;
      final responseSendPort = message[1] as SendPort;

      try {
        final response = await client.get(url);
        responseSendPort.send(response.bodyBytes);
      } catch (e) {
        // Don't actually handle any errors, just make the isolate fail
        responseSendPort.send(null);
      }
    });

    logger.d("Sending arguments to isolate process");
    isolateSendPort.send([
      rootToken,
      resultsPort.sendPort,
      logsPort.sendPort,
      fetchPort.sendPort,
      videoID,
      rawHtml
    ]);

    // Print incoming logs
    logsPort.listen((value) {
      List<String> log = value as List<String>;
      switch (log[0]) {
        case "trace":
          logger.t(log[1]);
          break;
        case "debug":
          logger.d(log[1]);
          break;
        case "info":
          logger.i(log[1]);
          break;
        case "warning":
          logger.w(log[1]);
          break;
        case "error":
          logger.e(log[1]);
          break;
        case "fatal":
          logger.f(log[1]);
          break;
      }
    });

    // Wait for the results
    final List<Uint8List>? thumbnails =
        await resultsPort.first as List<Uint8List>?;
    logger.d("Received ${thumbnails?.length} thumbnails from isolate process");
    // Cleanup
    receivePort.close();
    getProgressThumbnailsIsolate!.kill(priority: Isolate.immediate);
    return thumbnails;
  }

  /// This is the actual function for getting thumbnails that is specific to each official plugin
  Future<void> isolateGetProgressThumbnails(SendPort sendPort);

  Future<Uint8List> downloadThumbnail(Uri uri) async {
    try {
      var response = await client.get(uri);
      if (response.statusCode == 200) {
        return response.bodyBytes;
      } else {
        logger.e(
            "Error downloading preview: ${response.statusCode} - ${response.reasonPhrase}");
        return Uint8List(0);
      }
    } catch (e, stacktrace) {
      logger.e("Error downloading preview: $e\n$stacktrace");
      return Uint8List(0);
    }
  }

  @nonVirtual
  void cancelGetProgressThumbnails() {
    if (getProgressThumbnailsIsolate != null) {
      getProgressThumbnailsIsolate!.kill(priority: Isolate.immediate);
    }
  }
}
