import 'dart:isolate';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:html/dom.dart';

import '/utils/global_vars.dart';
import '/utils/official_plugin.dart';
import '/utils/plugin_interface.dart';
import '/utils/universal_formats.dart';

/// This plugin is only used for testing and is hidden in the release version
class TesterPlugin extends OfficialPlugin implements PluginInterface {
  @override
  bool isOfficialPlugin = true;
  @override
  String codeName = "tester-official";
  @override
  String prettyName = "Tester plugin";
  @override
  Uri iconUrl = Uri.parse("https://placehold.co/favicon.ico");
  @override
  String providerUrl = "https://tester-plugin.com";
  @override
  int initialHomePage = 0;
  @override
  int initialSearchPage = 0;
  @override
  int initialCommentsPage = 0;
  @override
  int initialVideoSuggestionsPage = 0;
  @override
  int initialAuthorVideosPage = 0;
  @override
  bool providesDownloads = true;
  @override
  bool providesHomepage = true;
  @override
  bool providesResults = true;
  @override
  bool providesSearchSuggestions = true;
  @override
  bool providesVideo = true;

  // The following fields are inherited from PluginInterface, but not needed due to this class not actually being an interface
  @override
  Uri? updateUrl;
  @override
  double version = 0.1;

  // For development only: Set this setting to false to disable simulated delays
  final bool _simulateDelays = false;

  // There is no need to override the testingMap, as this tester plugin wont fail to scrape anything

  @override
  Future<List<UniversalVideoPreview>> getHomePage(int page,
      [void Function(String body)? debugCallback]) async {
    // Simulate a delay without blocking the entire app
    if (_simulateDelays) await Future.delayed(Duration(seconds: 2));
    return List.generate(
      50,
      (index) => UniversalVideoPreview(
        iD: "${(index * pi * 10000).toInt()}",
        title: "Test homepage video $index",
        plugin: this,
        thumbnail: "https://placehold.co/1280x720.png",
        previewVideo: Uri.parse(
            "https://docs.evostream.com/sample_content/assets/bunny.mp4"),
        duration: Duration(seconds: 120 + index * 10),
        viewsTotal: (index * pi * 1000000).toInt(),
        ratingsPositivePercent:
            int.tryParse((index * pi * 10000).toStringAsFixed(2)) ?? 50,
        maxQuality: 720,
        virtualReality: false,
        authorName: "Tester-author $index",
        authorID: "Tester-author $index",
        verifiedAuthor: index % 2 == 0,
        // Make every 4th video a fail
        scrapeFailMessage: index % 4 != 0 ? "Test fail scrape message" : null,
      ),
    );
  }

  @override
  Future<List<UniversalVideoPreview>> getSearchResults(
      UniversalSearchRequest request, int page,
      [void Function(String body)? debugCallback]) async {
    // Simulate a delay without blocking the entire app
    if (_simulateDelays) await Future.delayed(Duration(seconds: 2));
    return List.generate(
      50,
      (index) => UniversalVideoPreview(
        iD: "${(index * pi * 10000).toInt()}",
        title: "Test result video $index",
        plugin: this,
        thumbnail: "https://placehold.co/1280x720.png",
        previewVideo: Uri.parse(
            "https://docs.evostream.com/sample_content/assets/bunny.mp4"),
        duration: Duration(seconds: 120 + index * 10),
        viewsTotal: (index * pi * 1000000).toInt(),
        ratingsPositivePercent:
            int.tryParse((index * pi * 10000).toStringAsFixed(2)) ?? 50,
        maxQuality: 720,
        virtualReality: false,
        authorName: "Tester-author $index",
        authorID: "Tester-author $index",
        verifiedAuthor: index % 2 == 0,
        // Make every 4th video a fail
        scrapeFailMessage: index % 4 != 0 ? "Test fail scrape message" : null,
      ),
    );
  }

  @override
  Future<UniversalVideoMetadata> getVideoMetadata(
      String videoId, UniversalVideoPreview uvp,
      [void Function(String body)? debugCallback]) async {
    // Simulate a delay without blocking the entire app
    if (_simulateDelays) await Future.delayed(Duration(seconds: 2));
    return UniversalVideoMetadata(
      iD: videoId,
      m3u8Uris: {
        1080: Uri.parse(
            "https://docs.evostream.com/sample_content/assets/bunny.mp4"),
        720: Uri.parse(
            "https://docs.evostream.com/sample_content/assets/bunny.mp4"),
        480: Uri.parse(
            "https://docs.evostream.com/sample_content/assets/bunny.mp4"),
      },
      title: "Tester video metadata title",
      plugin: this,
      universalVideoPreview: uvp,
      // Change this to test partial metadata scrape fail
      //scrapeFailMessage: "Test fail scrape message",
      authorID: "tester-author-$videoId",
      authorName: "Tester-author",
      authorSubscriberCount: 335433,
      authorAvatar: "https://placehold.co/1280x720.png",
      actors: ["Tester-actor-1", "Tester-actor-2"],
      description: "Tester video description" * 10,
      viewsTotal: 2532823,
      tags: ["Tester-tag-1", "Tester-tag-2"],
      categories: ["Tester-category-1", "Tester-category-2"],
      uploadDate: DateTime.now(),
      ratingsPositiveTotal: 90,
      ratingsNegativeTotal: 10,
      ratingsTotal: 47384,
      virtualReality: false,
      chapters: {
        Duration(seconds: 0): "Chapter 1",
        Duration(seconds: 120): "Chapter 2",
        Duration(seconds: 240): "Chapter 3",
      },
      rawHtml: Document(),
    );
  }

  @override
  Future<void> isolateGetProgressThumbnails(SendPort sendPort) async {
    // Receive data from the main isolate
    final receivePort = ReceivePort();
    sendPort.send(receivePort.sendPort);
    final message = await receivePort.first as List;
    final rootToken = message[0] as RootIsolateToken;
    final resultsPort = message[1] as SendPort;
    // final logPort = message[2] as SendPort;
    // final fetchPort = message[3] as SendPort;
    //final videoID = message[4] as String;
    // final rawHtml = message[5] as Document;

    // Not quite sure what this is needed for, but fails otherwise
    BackgroundIsolateBinaryMessenger.ensureInitialized(rootToken);

    List<Uint8List> completedProcessedImages = [];

    // convert placeholder image to Uint8List
    final response =
        await client.get(Uri.parse("https://placehold.co/720x480.png"));
    if (response.statusCode == 200) {
      for (int i = 0; i < 10; i++) {
        completedProcessedImages.add(response.bodyBytes);
      }
    } else {
      throw Exception("Failed to download/convert placeholder image");
    }

    resultsPort.send(completedProcessedImages);
  }

  @override
  Future<List<String>> getSearchSuggestions(String searchString,
      [void Function(String body)? debugCallback]) async {
    // Simulate a delay without blocking the entire app
    if (_simulateDelays) await Future.delayed(Duration(milliseconds: 200));
    return List.generate(30, (index) => "$searchString-$index");
  }

  @override
  Future<bool> initPlugin([void Function(String body)? debugCallback]) {
    return Future.value(true);
  }

  @override
  bool runFunctionalityTest() {
    return true;
  }

  @override
  Future<Uri?> getCommentUriFromID(String commentID, String videoID) {
    return Future.value(Uri.parse("https://example.com/$videoID/$commentID"));
  }

  @override
  Future<List<UniversalComment>> getComments(
      String videoID, Document rawHtml, int page,
      [void Function(String body)? debugCallback]) async {
    if (page == 5) {
      return [];
    }
    // Simulate a delay without blocking the entire app
    if (_simulateDelays) await Future.delayed(Duration(seconds: 2));
    return List.generate(
      5,
      (index) => UniversalComment(
        iD: "comment-$index",
        videoID: videoID,
        author: "author-$index",
        commentBody: List<String>.filled(5, "test comment $index ").join(),
        hidden: index % 4 == 0,
        plugin: this,
        authorID: "author-$index",
        countryID: "US",
        orientation: null,
        profilePicture: "https://placehold.co/240x240.png",
        ratingsPositiveTotal: index % 4 == 0 ? 30 : null,
        ratingsNegativeTotal: index % 4 == 0 ? 2 : null,
        ratingsTotal: index % 4 == 0 ? 32 : 76,
        commentDate: DateTime.now().subtract(Duration(days: index)),
        replyComments: index % 2 == 0
            ? List.generate(
                3,
                (index) => UniversalComment(
                  iD: "comment-reply-$index",
                  videoID: videoID,
                  author: "author-reply-$index",
                  commentBody:
                      List<String>.filled(5, "test reply comment $index ")
                          .join(),
                  hidden: index % 4 == 0,
                  plugin: this,
                  authorID: "author-reply-$index",
                  countryID: "US",
                  orientation: null,
                  profilePicture: "https://placehold.co/240x240",
                  ratingsPositiveTotal: index % 2 == 0 ? 4 : null,
                  ratingsNegativeTotal: index % 2 == 0 ? 1 : null,
                  ratingsTotal: index % 2 == 0 ? 5 : 6,
                  commentDate: DateTime.now().subtract(Duration(days: index)),
                  replyComments: [],
                  // Make every 4th comment a fail
                  scrapeFailMessage:
                      index % 4 != 0 ? "Test fail scrape message" : null,
                ),
              )
            : [],
        // Make every 4th comment a fail
        scrapeFailMessage: index % 4 != 0 ? "Test fail scrape message" : null,
      ),
    );
  }

  @override
  Future<List<UniversalVideoPreview>> getVideoSuggestions(
      String videoID, Document rawHtml, int page,
      [void Function(String body)? debugCallback]) async {
    // Simulate a delay without blocking the entire app
    if (_simulateDelays) await Future.delayed(Duration(seconds: 2));
    return List.generate(
      50,
      (index) => UniversalVideoPreview(
        iD: "${(index * pi * 10000).toInt()}",
        title: "Test suggestion video $index",
        plugin: this,
        thumbnail: "https://placehold.co/1280x720.png",
        previewVideo: Uri.parse(
            "https://docs.evostream.com/sample_content/assets/bunny.mp4"),
        duration: Duration(seconds: 120 + index * 10),
        viewsTotal: (index * pi * 1000000).toInt(),
        ratingsPositivePercent:
            int.tryParse((index * pi * 10000).toStringAsFixed(2)) ?? 50,
        maxQuality: 720,
        virtualReality: false,
        authorName: "Tester-suggestion-author $index",
        authorID: "Tester-suggestion-author $index",
        verifiedAuthor: index % 2 == 0,
        // Make every 4th video a fail
        scrapeFailMessage: index % 4 != 0 ? "Test fail scrape message" : null,
      ),
    );
  }

  @override
  Uri? getVideoUriFromID(String videoID) {
    return Uri.parse("https://example.com/$videoID");
  }

  @override
  Future<UniversalAuthorPage> getAuthorPage(String authorID,
      [void Function(String body)? debugCallback]) {
    return Future.value(UniversalAuthorPage(
        iD: authorID,
        name: "Test author name",
        plugin: this,
        avatar: "https://placehold.co/240x240.png",
        banner: "https://placehold.co/1270x400.png",
        aliases: ["Test alias 1", "Test alias 2"],
        description: "Very long description" * 1000,
        advancedDescription: {
          for (int i = 1; i <= 1000; i++)
            "Test description key $i": "Test description value $i",
        },
        externalLinks: {
          "external link 1": Uri.parse("https://example.com/link1"),
          "external link 2": Uri.parse("https://example.com/link2"),
          "external link 3": Uri.parse("https://example.com/link3")
        },
        viewsTotal: 23773212,
        videosTotal: 114,
        subscribers: 573529,
        rank: 3746,
        rawHtml: Document()));
  }

  @override
  Future<Uri?> getAuthorUriFromID(String authorID) {
    return Future.value(Uri.parse("https://example.com/$authorID"));
  }

  @override
  Future<List<UniversalVideoPreview>> getAuthorVideos(String authorID, int page,
      [void Function(String body)? debugCallback]) async {
    return List.generate(
      50,
      (index) => UniversalVideoPreview(
        iD: "${(index * pi * 10000).toInt()}",
        title: "Test result video $index",
        plugin: this,
        thumbnail: "https://placehold.co/1280x720.png",
        previewVideo: Uri.parse(
            "https://docs.evostream.com/sample_content/assets/bunny.mp4"),
        duration: Duration(seconds: 120 + index * 10),
        viewsTotal: (index * pi * 1000000).toInt(),
        ratingsPositivePercent:
            int.tryParse((index * pi * 10000).toStringAsFixed(2)) ?? 50,
        maxQuality: 720,
        virtualReality: false,
        authorName: "Tester-author-same $index",
        authorID: "Tester-author-same $index",
        verifiedAuthor: index % 2 == 0,
        // Make every 4th video a fail
        scrapeFailMessage: index % 4 != 0 ? "Test fail scrape message" : null,
      ),
    );
  }
}
