import 'dart:convert';
import 'dart:isolate';

import 'package:flutter/services.dart';
import 'package:html/dom.dart';
import 'package:html/parser.dart';
import 'package:html_unescape/html_unescape_small.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart';

import '/utils/exceptions.dart';
import '/utils/global_vars.dart';
import '/utils/official_plugin.dart';
import '/utils/plugin_interface/plugin_interface.dart';
import '/utils/try_parse.dart';
import '/utils/universal_formats.dart';

class XHamsterPlugin extends OfficialPlugin implements PluginInterface {
  @override
  final bool isOfficialPlugin = true;
  @override
  bool isInitialized = false;
  @override
  String codeName = "xhamster-official";
  @override
  String prettyName = "xHamster.com";
  @override
  Uri iconUrl = Uri.parse("https://xhamster.com/favicon.ico");
  @override
  String providerUrl = "https://xhamster.com";
  @override
  int initialHomePage = 1;
  @override
  int initialSearchResultsPage = 1;
  @override
  int initialCommentsPage = 1;
  @override
  int initialVideoSuggestionsPage = 1;
  @override
  int initialAuthorVideosPage = 1;

  // The following fields are inherited from PluginInterface, but not needed due to this class not actually being an interface
  @override
  Uri? updateUrl;
  @override
  double version = 1.0;

  // Set OfficialPlugin specific vars
  @override
  Map<String, dynamic> testingMap = {
    "ignoreScrapedErrors": {
      "homepage": [
        "previewVideo",
        "authorID",
        "thumbnailHttpHeaders",
        "thumbnailBinary",
        "ratingsPositivePercent",
        "maxQuality",
        "lastWatched",
        "addedOn"
      ],
      "searchResults": [
        "previewVideo",
        "authorID",
        "thumbnailHttpHeaders",
        "thumbnailBinary",
        "ratingsPositivePercent",
        "maxQuality",
        "lastWatched",
        "addedOn"
      ],
      "videoMetadata": ["playbackHttpHeaders", "chapters"],
      "videoSuggestions": [
        "previewVideo",
        "authorID",
        "thumbnailHttpHeaders",
        "thumbnailBinary",
        "ratingsPositivePercent",
        "maxQuality",
        "lastWatched",
        "addedOn"
      ],
      "authorVideos": [
        "thumbnailHttpHeaders",
        "thumbnailBinary",
        "previewVideo",
        "ratingsPositivePercent",
        "maxQuality",
        "authorName",
        "authorID",
        "lastWatched",
        "addedOn"
      ],
      "comments": [
        "ratingsPositiveTotal",
        "ratingsNegativeTotal",
        "countryID",
        "orientation",
        "profilePicture",
        "ratingsTotal"
      ],
      "authorPage": ["banner", "description", "rank", "lastViewed", "addedOn"]
    },
    "testingVideos": [
      // This is the most watched video on xhamster in 2024
      {"videoID": "xhnQh7b", "progressThumbnailsAmount": 839},
      // This is a more recent video from the homepage
      {"videoID": "xhZiTRT", "progressThumbnailsAmount": 779}
    ],
    "testingAuthorPageIds": [
      // A channel-type author
      "vixen",
      // A creator-type author
      "cumatozz",
      // A user-type author
      "dsfilmation"
    ]
  };

  // Private vars
  final String _videoEndpoint = "https://xhamster.com/videos/";
  final String _searchEndpoint = "https://xhamster.com/search/";
  final String _creatorEndpoint = "https://xhamster.com/creators/";
  final String _channelEndpoint = "https://xhamster.com/channels/";
  final String _userEndpoint = "https://xhamster.com/users/";

  Future<List<UniversalVideoPreview>> _parseVideoList(
      List<Element> resultsList) async {
    // convert the divs into UniversalSearchResults
    List<UniversalVideoPreview> results = [];
    for (Element resultDiv in resultsList) {
      // each result has 2 sub-divs
      List<Element>? subElements = resultDiv.children;

      String? iD = tryParse<String?>(
          () => subElements[0].attributes['href']?.split("/").last);
      String? title = tryParse<String?>(
          () => subElements[1].querySelector('a')?.attributes['title']);

      // Recently xhamster started including picture-videos instead of proper mp4s
      // On newer videos previews are not available
      String? previewVideo = tryParse<String?>(
          () => subElements[0].attributes['data-previewvideo']);

      // Scrape author
      String? authorName = "Unknown amateur author";
      String? authorID;
      try {
        Element? uploaderElement = subElements[1]
            .querySelector('div[class="video-thumb-uploader"]')
            ?.children[0];
        if (uploaderElement != null) {
          // Amateur videos don't have an uploader on the results page
          if (!(uploaderElement.children.length == 1 &&
              uploaderElement.children[0].className == "video-thumb-views")) {
            Element? authorElement = uploaderElement
                .querySelector('a[class="video-uploader__name"]');
            authorName = authorElement?.text.trim();
            authorID = authorElement?.attributes['href']
                ?.replaceAll("/videos", "")
                .split("/")
                .last;
          }
        }
      } catch (_) {}

      // convert time string into int list
      Duration? duration;
      try {
        List<int> durationList = subElements[0]
            .querySelector('div[class="thumb-image-container__duration"]')!
            .text
            .trim()
            .split(":")
            .map((e) => int.parse(e))
            .toList();
        if (durationList.length == 2) {
          duration = Duration(seconds: durationList[0] * 60 + durationList[1]);
          // if there is an hour in the duration
        } else if (durationList.length == 3) {
          duration = Duration(
              seconds: durationList[0] * 3600 +
                  durationList[1] * 60 +
                  durationList[2]);
        }
      } catch (_) {}

      // determine video resolution
      bool virtualReality = false;
      int? resolution;
      try {
        if (subElements[0].querySelector('i[class^="xh-icon"]') != null) {
          switch (subElements[0]
              .querySelector('i[class^="xh-icon"]')!
              .attributes['class']!
              .split(" ")[1]) {
            case "beta-thumb-hd":
              resolution = 720;
            // TODO: Maybe somehow determine 1080p support?
            case "beta-thumb-uhd":
              resolution = 2160;
            case "beta-thumb-vr":
              virtualReality = true;
          }
        }
      } catch (_) {}

      // determine video views
      int? views;
      try {
        String? viewsString = subElements[1]
            .querySelector("div[class='video-thumb-views']")
            ?.text
            .trim()
            .split(" views")[0];
        // just added means 0
        if (viewsString == "just added") {
          views = 0;
        } else if (viewsString != null) {
          views = 0;
          if (viewsString.endsWith("K")) {
            if (viewsString.contains(".")) {
              views = int.parse(viewsString.split(".")[1][0]) * 100;
              // this is so that the normal step still works
              // ignore: prefer_interpolation_to_compose_strings
              viewsString = viewsString.split(".")[0] + " ";
            }
            views +=
                int.parse(viewsString.substring(0, viewsString.length - 1)) *
                    1000;
          } else if (viewsString.endsWith("M")) {
            if (viewsString.contains(".")) {
              views = int.parse(viewsString.split(".")[1][0]) * 100000;
              // this is so that the normal step still works
              // ignore: prefer_interpolation_to_compose_strings
              viewsString = viewsString.split(".")[0] + " ";
            }
            views +=
                int.parse(viewsString.substring(0, viewsString.length - 1)) *
                    1000000;
          } else {
            views = int.tryParse(viewsString);
          }
        }
      } catch (_) {}

      UniversalVideoPreview uniResult = UniversalVideoPreview(
        // Don't enforce null safety here
        // treat error below in scrapeFailMessage instead
        iD: iD ?? "null",
        title: title ?? "null",
        plugin: this,
        thumbnail: tryParse<String?>(
            () => subElements[0].querySelector('img')?.attributes['src']),
        previewVideo: tryParse(() => Uri.parse(previewVideo!)),
        duration: duration,
        viewsTotal: views,
        ratingsPositivePercent: null,
        maxQuality: resolution,
        virtualReality: virtualReality,
        authorName: authorName,
        authorID: authorID,
        verifiedAuthor:
            authorName != null && authorName != "Unknown amateur author",
      );

      // getHomepage and getSearchResults use the same _parseVideoList
      // -> their ignore lists are the same
      // This will also set the scrapeFailMessage if needed
      uniResult.verifyScrapedData(
          codeName, testingMap["ignoreScrapedErrors"]["homepage"]);

      if (iD == null || title == null) {
        uniResult.scrapeFailMessage =
            "Error: Failed to scrape critical variable(s):"
            "${iD == null ? " ID" : ""}"
            "${title == null ? " title" : ""}";
      }

      results.add(uniResult);
    }

    return results;
  }

  @override
  Future<bool> init(String cachePath,
      [void Function(String body)? debugCallback]) async {
    if (isInitialized) {
      return true;
    }
    isInitialized = true;
    // Request main page to check for age gate / banned country
    http.Response response = await client.get(Uri.parse(providerUrl));
    if (response.statusCode != 200) {
      return Future.value(false);
    }

    debugCallback
        ?.call("Headers: ${response.headers}\n\nBody: ${response.body}");

    // Check for age blocks
    if (parse(response.body).body!.classes.contains("xh-scroll-disabled")) {
      throw AgeGateException();
    }
    return true;
  }

  @override
  Future<bool> runFunctionalityTest() {
    // There is no need to run functionality tests on official plugins
    // as they are not imported at any time in the app
    // Also, these plugins get checked for functionality via daily CIs
    return Future.value(true);
  }

  @override
  Future<List<UniversalVideoPreview>> getHomePage(int page,
      [void Function(String body)? debugCallback]) async {
    logger.d("Requesting $providerUrl/$page");
    var response = await client.get(Uri.parse("$providerUrl/$page"));
    debugCallback?.call(response.body);
    if (response.statusCode != 200) {
      logger.e(
          "Error downloading html: ${response.statusCode} - ${response.reasonPhrase}");
      throw Exception(
          "Error downloading html: ${response.statusCode} - ${response.reasonPhrase}");
    }
    Document resultHtml = parse(response.body);
    if (resultHtml.outerHtml == "<html><head></head><body></body></html>") {
      throw Exception("Received empty html");
    }
    // Filter out ads and non-video results
    return _parseVideoList(resultHtml
        .querySelector('div[data-block="mono"]')!
        .querySelector(".thumb-list")!
        .querySelectorAll('div[data-video-type="video"]')
        .toList());
  }

  // downloadThumbnail is implemented at the OfficialPlugin level

  @override
  Future<List<String>> getSearchSuggestions(String searchString,
      [void Function(String body)? debugCallback]) async {
    List<String> parsedMap = [];
    var response = await client.get(Uri.parse(
        "https://xhamster.com/api/front/search/suggest?searchValue=$searchString"));
    debugCallback?.call(response.body);
    if (response.statusCode == 200) {
      for (var item in jsonDecode(response.body).cast<Map>()) {
        if (item["type2"] == "search") {
          parsedMap.add(item["plainText"]);
        }
      }
    } else {
      throw Exception(
          "Error downloading json list: ${response.statusCode} - ${response.reasonPhrase}");
    }
    return parsedMap;
  }

  @override
  Future<List<UniversalVideoPreview>> getSearchResults(
      UniversalSearchRequest request, int page,
      [void Function(String body)? debugCallback]) async {
    String encodedSearchString = Uri.encodeComponent(request.searchString);
    logger.d("Requesting $_searchEndpoint$encodedSearchString?page=$page");
    var response = await client
        .get(Uri.parse("$_searchEndpoint$encodedSearchString?page=$page"));
    debugCallback?.call(response.body);
    if (response.statusCode != 200) {
      logger.e(
          "Error downloading html: ${response.statusCode} - ${response.reasonPhrase}");
      throw Exception(
          "Error downloading html: ${response.statusCode} - ${response.reasonPhrase}");
    }
    Document resultHtml = parse(response.body);
    // Filter out ads and non-video results
    return _parseVideoList(resultHtml
        .querySelector('div[data-block="trending"]')!
        .querySelector(".thumb-list")!
        .querySelectorAll('div[data-video-type="video"]')
        .toList());
  }

  @override
  Future<Uri?> getVideoUriFromID(String videoID) async {
    return Uri.parse(_videoEndpoint + videoID);
  }

  @override
  Future<UniversalVideoMetadata> getVideoMetadata(
      String videoId, UniversalVideoPreview uvp,
      [void Function(String body)? debugCallback]) async {
    logger.d("Requesting ${_videoEndpoint + videoId}");
    var response = await client.get(Uri.parse(_videoEndpoint + videoId));
    debugCallback?.call(response.body);
    if (response.statusCode != 200) {
      logger.e(
          "Error downloading html: ${response.statusCode} - ${response.reasonPhrase}");
      throw Exception(
          "Error downloading html: ${response.statusCode} - ${response.reasonPhrase}");
    }

    Document rawHtml = parse(response.body);
    String jscript = rawHtml.querySelector('#initials-script')!.text;
    Map<String, dynamic> jscriptMap = jsonDecode(
        jscript.substring(jscript.indexOf("{"), jscript.indexOf('};') + 1));

    // ratings
    int? ratingsPositive =
        jscriptMap["ratingComponent"]?["ratingModel"]?["likes"];
    int? ratingsNegative =
        jscriptMap["ratingComponent"]?["ratingModel"]?["dislikes"];
    int? ratingsTotal;
    if (ratingsPositive != null && ratingsNegative != null) {
      ratingsTotal = ratingsPositive + ratingsNegative;
    }

    // Extract tags, categories and actors from jscriptMap
    List<String>? tags = [];
    List<String>? categories = [];
    List<String>? actors = [];
    try {
      for (Map<String, dynamic> element
          in jscriptMap["videoTagsComponent"]!["tags"]!) {
        if (element["isCategory"]!) {
          categories.add(element["name"]!);
        } else if (element["isPornstar"]!) {
          actors.add(element["name"]!);
        } else if (element["isTag"]!) {
          tags.add(element["name"]!);
        } else {
          logger.d("Skipping element: ${element["name"]!}");
        }
      }
    } catch (e, stacktrace) {
      logger.w("Failed to parse actors/tags/categories (but continuing "
          "anyways): $e\n$stacktrace");
    }

    if (actors.isEmpty) {
      actors = null;
    }
    if (tags.isEmpty) {
      actors = null;
    }
    if (categories.isEmpty) {
      categories = null;
    }

    // Use the tooltip as video upload date
    DateTime? date;
    String? dateString = rawHtml
        .querySelector(
            'div[class="entity-info-container__date tooltip-nocache"]')
        ?.attributes["data-tooltip"]!;
    // 2022-05-06 12:33:41 UTC
    if (dateString != null) {
      // Convert to a format that DateTime can read
      // Convert to 20120227T132700 format
      dateString = dateString
          .replaceAll("-", "")
          .replaceFirst(" ", "T")
          .replaceAll(":", "")
          .replaceAll(" UTC", "");
      date = DateTime.tryParse(dateString);
    }

    // convert master m3u8 to list of media m3u8
    // TODO: Maybe check if the m3u8 is a master m3u8
    var videoM3u8 = rawHtml.querySelector(
        'link[rel="preload"][href*=".m3u8"][as="fetch"][crossorigin]');
    Map<int, Uri> m3u8Map =
        await parseM3U8(Uri.parse(videoM3u8!.attributes["href"]!));

    String? authorID;
    String? authorName;
    int? authorSubscriberCount;
    String? authorAvatar;
    if (jscriptMap["xplayerPluginSettings"]?["subscribe"]?["link"] != null) {
      authorID = jscriptMap["xplayerPluginSettings"]!["subscribe"]!["link"]!
          .replaceAll("/videos", "")!
          .split("/")!
          .last;
      authorName = jscriptMap["xplayerPluginSettings"]?["subscribe"]?["title"];
      authorSubscriberCount =
          jscriptMap["xplayerPluginSettings"]?["subscribe"]?["subscribers"];
      authorAvatar = jscriptMap["xplayerPluginSettings"]?["subscribe"]?["logo"];
    } else {
      authorID = jscriptMap["videoModel"]?["author"]?["pageURL"]
          ?.replaceAll("/videos", "")!
          .split("/")!
          .last;
      authorName = jscriptMap["videoModel"]?["author"]?["name"];
      authorSubscriberCount = jscriptMap["videoTagsComponent"]
          ?["subscriptionModel"]?["subscribers"];
      authorAvatar = jscriptMap["videoTagsComponent"]?["tags"]?[0]?["thumbUrl"];
    }

    UniversalVideoMetadata metadata = UniversalVideoMetadata(
        iD: videoId,
        m3u8Uris: m3u8Map,
        title: jscriptMap["videoModel"]!["title"]!,
        plugin: this,
        universalVideoPreview: uvp,
        authorID: authorID!,
        authorName: authorName,
        authorSubscriberCount: authorSubscriberCount,
        authorAvatar: authorAvatar,
        actors: actors,
        description: jscriptMap["videoModel"]?["description"],
        viewsTotal: jscriptMap["videoTitle"]?["views"],
        tags: tags,
        categories: categories,
        uploadDate: date,
        ratingsPositiveTotal: ratingsPositive,
        ratingsNegativeTotal: ratingsNegative,
        ratingsTotal: ratingsTotal,
        virtualReality: jscriptMap["videoModel"]?["isVR"],
        chapters: null,
        rawHtml: rawHtml);

    // This will also set the scrapeFailMessage if needed
    metadata.verifyScrapedData(
        codeName, testingMap["ignoreScrapedErrors"]["videoMetadata"]);

    return metadata;
  }

  // getProgressThumbnails is implemented at the OfficialPlugin level

  @override
  Future<void> isolateGetProgressThumbnails(SendPort sendPort) async {
    // Receive data from the main isolate
    final receivePort = ReceivePort();
    sendPort.send(receivePort.sendPort);
    final message = await receivePort.first as List;
    final rootToken = message[0] as RootIsolateToken;
    final resultsPort = message[1] as SendPort;
    final logPort = message[2] as SendPort;
    final fetchPort = message[3] as SendPort;
    //final videoID = message[4] as String;
    final rawHtml = message[5] as Document;

    try {
      // Not quite sure what this is needed for, but fails otherwise
      BackgroundIsolateBinaryMessenger.ensureInitialized(rootToken);

      // Get the video javascript
      String jscript = rawHtml.querySelector("#initials-script")!.text;

      // Extract the progressImage url from jscript
      int startIndex = jscript.indexOf('"template":"') + 12;
      int endIndex = jscript.substring(startIndex).indexOf('","');
      String imageUrl = jscript.substring(startIndex, startIndex + endIndex);
      String imageBuildUrl = imageUrl.replaceAll("\\/", "/");
      logPort.send(["debug", imageBuildUrl]);

      // Extract the video duration
      int startIndexDuration = jscript.lastIndexOf('"duration":') + 11;
      int endIndexDuration =
          jscript.substring(startIndexDuration).indexOf(',"');
      String durationInString = jscript.substring(
          startIndexDuration, startIndexDuration + endIndexDuration);
      logPort.send([
        "debug",
        "Trying to parse video length in seconds to an int: $durationInString"
      ]);
      int duration = int.parse(durationInString);

      // Extract the width of the individual preview image from the baseUrl
      String imageWidthString = imageBuildUrl.split("/").last.split(".")[0];
      // New format has the width only, old format has width x height
      int imageWidth = int.parse(imageWidthString.contains("x")
          ? imageWidthString.split("x").first
          : imageWidthString);

      // Assume old format
      String suffix = "";
      String baseUrl = imageBuildUrl;
      // Old format has 50 preview thumbnails for the entire video
      int samplingFrequency = (duration / 50).floor();
      // only one combined image in old format
      int lastImageIndex = 0;
      bool isOldFormat = true;

      // determine kind of preview images
      logPort.send(["debug", "Checking whether video uses new preview format"]);
      if (imageBuildUrl.endsWith("%d.webp")) {
        isOldFormat = false;
        suffix = ".${imageBuildUrl.split(".").last}";
        logPort.send(["debug", suffix]);
        baseUrl = imageBuildUrl.split("%d").first;
        logPort.send(["debug", baseUrl]);
        // from limited testing it seems as if the sampling frequency is always 4 in the new format, but have this just in case
        // Although usually the sampling frequency is not 4.0, but rather something like 4.003
        // For some reason xhamster just ignores that and uses a whole number resulting in drift at the end in long videos.
        samplingFrequency =
            int.parse(imageBuildUrl.split("/").last.split(".")[1]);
        logPort.send(["debug", "Sampling frequency: $samplingFrequency"]);
        // Each combined image contains 50 images
        lastImageIndex = duration ~/ samplingFrequency ~/ 50;
      }
      logPort.send(["debug", "Is old format: $isOldFormat"]);
      logPort.send(["debug", "Sampling frequency: $samplingFrequency"]);

      logPort.send(["info", "Downloading and processing progress images"]);
      logPort.send(["debug", "lastImageIndex: $lastImageIndex"]);
      List<List<Uint8List>> allThumbnails =
          List.generate(lastImageIndex + 1, (_) => []);
      List<Future<void>> imageFutures = [];

      for (int i = 0; i <= lastImageIndex; i++) {
        // Create a future for downloading and processing
        imageFutures.add(Future(() async {
          String url = isOldFormat ? baseUrl : "$baseUrl$i$suffix";
          logPort.send(["debug", "Requesting download for $url"]);

          // Request the main thread to fetch the image
          final responsePort = ReceivePort();
          fetchPort.send([Uri.parse(url), responsePort.sendPort]);
          Uint8List image = await responsePort.first as Uint8List;
          responsePort.close();

          final decodedImage = decodeImage(image)!;
          List<Uint8List> thumbnails = [];
          for (int w = 0; w < decodedImage.width; w += imageWidth) {
            // XHamster has a set amount of thumbnails (usually multiples of 50) for the whole video.
            // every progress image is for samplingFrequency (usually 4) seconds -> store the same image samplingFrequency times
            // To avoid overfilling the ram, create a temporary variable and store it in the list multiple times
            // As Lists contain references to data and not the data itself, this should reduce ram usage
            Uint8List firstThumbnail = Uint8List(0);
            for (int j = 0; j < samplingFrequency; j++) {
              if (j == 0) {
                // Only encode and add the first image once
                firstThumbnail = encodeJpg(copyCrop(decodedImage,
                    x: w,
                    y: 0,
                    width: imageWidth,
                    height: decodedImage.height));
                thumbnails.add(firstThumbnail); // Add the first encoded image
              } else {
                // Reuse the reference to the first thumbnail
                thumbnails.add(firstThumbnail);
              }
            }
          }
          allThumbnails[i] = thumbnails;
        }));
      }
      // Await all futures
      await Future.wait(imageFutures);

      // Combine all results into single, chronological list
      List<Uint8List> completedProcessedImages =
          allThumbnails.expand((x) => x).toList();

      // Add 55 seconds more of the last thumbnail
      // This is done as the sampling frequency is floored. 0.99*50 = 49.5, means in theory we could be off by 50 seconds
      Uint8List lastImage = completedProcessedImages.last;
      for (int j = 0; j < 55; j++) {
        completedProcessedImages.add(lastImage);
      }

      logPort.send(["info", "Completed processing all images"]);
      logPort.send([
        "debug",
        "Total memory consumption apprx: ${completedProcessedImages[0].lengthInBytes * completedProcessedImages.length / 1024 / 1024} mb"
      ]);
      // return the completed processed images through the separate resultsPort
      logPort.send([
        "debug",
        "Sending ${completedProcessedImages.length} progress images to main process"
      ]);
      resultsPort.send(completedProcessedImages);
    } catch (e, stackTrace) {
      logPort.send(
          ["error", "Error in isolateGetProgressThumbnails: $e\n$stackTrace"]);
      resultsPort.send(null);
    }
  }

  // cancelGetProgressThumbnails is implemented at the OfficialPlugin level

  @override
  Future<Uri?> getCommentUriFromID(String commentID, String videoID) {
    // Pornhub doesn't have comment links
    return Future.value(
        Uri.parse("$_videoEndpoint/$videoID#comment-$commentID"));
  }

  @override
  Future<List<UniversalComment>> getComments(
      String videoID, Document rawHtml, int page,
      [void Function(String body)? debugCallback]) async {
    List<UniversalComment> commentList = [];

    // find the video's entity-id in the json inside the html
    String jscript = rawHtml.querySelector("#initials-script")!.text;
    Map<String, dynamic> jscriptMap = jsonDecode(
        jscript.substring(jscript.indexOf("{"), jscript.indexOf('};') + 1));

    // use the entity id from the comment section specifically
    // Its usually an integer -> convert it to a string, just in case
    String entityID = jscriptMap["commentsComponent"]["commentsList"]["target"]
            ["id"]
        .toString();
    logger.d("Video comment entity ID: $entityID");

    final commentUri = Uri.parse('https://xhamster.com/x-api?r='
        '[{"name":"entityCommentCollectionFetch",'
        '"requestData":{"page":$page,"entity":{"entityModel":"videoModel","entityID":$entityID}}}]');
    logger.d("Comment URI (page: $page): $commentUri");
    final response = await client.get(
      commentUri,
      // For some reason this header is required, otherwise the request 404s.
      headers: {
        "X-Requested-With": "XMLHttpRequest",
      },
    );
    if (response.statusCode != 200) {
      throw Exception(
          "Error downloading json: ${response.statusCode} - ${response.reasonPhrase}");
    }
    debugCallback?.call(response.body);
    final commentsJson = jsonDecode(response.body)[0]["responseData"];
    if (commentsJson == null) {
      logger.w("No comments found for $videoID");
      return [];
    }

    for (var comment in commentsJson) {
      String? iD = comment["id"];
      String? author = comment["author"]?["name"];
      String? commentBody;
      if (comment["text"] != null) {
        commentBody = HtmlUnescape().convert(comment["text"]!).trim();
      }

      UniversalComment uniComment = UniversalComment(
        // Don't enforce null safety here
        // treat error below in scrapeFailMessage instead
        iD: iD ?? "null",
        videoID: videoID,
        author: author ?? "null",
        // The comment body includes html chars like &amp and &nbsp, which need to be cleaned up
        commentBody: commentBody ?? "null",
        hidden: false,
        plugin: this,
        authorID: comment["userId"]?.toString(),
        countryID: comment["author"]?["personalInfo"]?["geo"]?["countryCode"],
        orientation: comment["author"]?["personalInfo"]?["orientation"]
            ?["name"],
        profilePicture: comment["author"]?["thumbUrl"],
        ratingsPositiveTotal: null,
        ratingsNegativeTotal: null,
        // null in the json means 0
        ratingsTotal: comment["likes"] ?? 0,
        commentDate: tryParse(() =>
            DateTime.fromMillisecondsSinceEpoch(comment["created"] * 1000)),
        replyComments: [],
      );

      // This will also set the scrapeFailMessage if needed
      uniComment.verifyScrapedData(
          codeName, testingMap["ignoreScrapedErrors"]["comments"]);

      if (iD == null || author == null || commentBody == null) {
        uniComment.scrapeFailMessage =
            "Error: Failed to scrape critical variable(s):"
            "${iD == null ? " iD" : ""}"
            "${author == null ? " author" : ""}"
            "${commentBody == null ? " commentBody" : ""}";
      }

      commentList.add(uniComment);
    }

    if (commentList.length != commentsJson.length) {
      logger.w("${commentsJson.length - commentList.length} comments "
          "failed to parse.");
      if (commentList.length < commentsJson.length * 0.5) {
        throw Exception("More than 50% of the results failed to parse.");
      }
    }

    return commentList;
  }

  @override
  Future<List<UniversalVideoPreview>> getVideoSuggestions(
      String videoID, Document rawHtml, int page,
      [void Function(String body)? debugCallback]) async {
    // find the video's relatedID in the json inside the html
    String jscript = rawHtml.querySelector("#initials-script")!.text;
    // use the relatedID from the related videos section specifically
    int startIndex =
        jscript.indexOf('"relatedVideosComponent":{"videoId":') + 36;
    int endIndex = jscript.substring(startIndex).indexOf(',');
    String relatedID = jscript.substring(startIndex, startIndex + endIndex);
    logger.d("Video relatedID: $relatedID");

    // Xhamster has an api
    final suggestionsUri =
        Uri.parse('https://xhamster.com/api/front/video/related'
            '?params={"videoId":$relatedID,"page":$page,"nativeSpotsCount":1}');
    print("Parsed URI: $suggestionsUri");
    final response = await client.get(suggestionsUri);
    if (response.statusCode != 200) {
      throw Exception(
          "Failed to get suggestions: ${response.statusCode} - ${response.reasonPhrase}");
    }
    debugCallback?.call(response.body);

    List<UniversalVideoPreview> relatedVideos = [];
    for (var result in jsonDecode(response.body)["videoThumbProps"]) {
      String? title = tryParse(() => result["title"]);

      UniversalVideoPreview relatedVideo = UniversalVideoPreview(
        // Don't enforce null safety here
        // treat error below in scrapeFailMessage instead
        iD: tryParse(() => result["pageURL"].trim().split("/").last) ?? "null",
        title: title ?? "null",
        plugin: this,
        thumbnail: result["thumbURL"],
        previewVideo: tryParse<Uri?>(() => Uri.parse(result["trailerURL"])),
        duration: tryParse(() => Duration(seconds: result["duration"])),
        viewsTotal: result["views"],
        ratingsPositivePercent: null,
        maxQuality: tryParse<int?>(() => result["isUHD"] != null ? 2160 : null),
        virtualReality: null,
        authorName: result["landing"]?["name"] ?? "Unknown amateur author",
        authorID: result["landing"]?["link"]
            ?.replaceAll("/videos", "")
            ?.split("/")
            ?.last,
        verifiedAuthor: result["landing"]?["name"] != null,
      );

      // This will also set the scrapeFailMessage if needed
      relatedVideo.verifyScrapedData(
          codeName, testingMap["ignoreScrapedErrors"]["videoSuggestions"]);

      if (title == null) {
        relatedVideo.scrapeFailMessage =
            "Error: Failed to scrape critical variable: title";
      }

      relatedVideos.add(relatedVideo);
    }
    return relatedVideos;
  }

  @override
  Future<Uri?> getAuthorUriFromID(String authorID) async {
    logger.i("Getting author page URL of: $authorID");

    // Assume every author is a channel at first
    Uri authorPageLink = Uri.parse("$_channelEndpoint$authorID");

    logger.d("Checking http status of: $authorPageLink");
    var response = await client.head(authorPageLink);
    if (response.statusCode != 200) {
      // Try again for creator author type
      authorPageLink = Uri.parse("$_creatorEndpoint$authorID");

      logger.d(
          "Received non 200 status code -> Requesting creator page: $authorPageLink");
      response = await client.head(authorPageLink);

      if (response.statusCode != 200) {
        // Try again for user author type
        authorPageLink = Uri.parse("$_userEndpoint$authorID");
        logger.d(
            "Received non 200 status code -> Requesting user page: $authorPageLink");
        response = await client.get(authorPageLink);
        if (response.statusCode != 200) {
          logger.e(
              "Error downloading html (tried channel, creator, user): ${response.statusCode} - ${response.reasonPhrase}");
          throw Exception(
              "Error downloading html (tried channel, creator, user): ${response.statusCode} - ${response.reasonPhrase}");
        }
      }
    }
    return authorPageLink;
  }

  @override
  Future<UniversalAuthorPage> getAuthorPage(String authorID,
      [void Function(String body)? debugCallback]) async {
    // Assume every author is a channel at first
    Uri authorPageLink = Uri.parse("$_channelEndpoint$authorID");
    logger.d("Requesting channel page: $authorPageLink");
    var response = await client.get(authorPageLink);
    if (response.statusCode != 200) {
      // Try again for creator author type
      authorPageLink = Uri.parse("$_creatorEndpoint$authorID");
      logger.d(
          "Received non 200 status code -> Requesting creator page: $authorPageLink");
      response = await client.get(authorPageLink);

      if (response.statusCode != 200) {
        // Try again for user author type
        authorPageLink = Uri.parse("$_userEndpoint$authorID");
        logger.d(
            "Received non 200 status code -> Requesting user page: $authorPageLink");
        response = await client.get(authorPageLink);

        if (response.statusCode != 200) {
          logger.e(
              "Error downloading html (tried channel, creator, user): ${response.statusCode} - ${response.reasonPhrase}");
          throw Exception(
              "Error downloading html (tried channel, creator, user): ${response.statusCode} - ${response.reasonPhrase}");
        }
      }
    }

    debugCallback?.call(response.body);
    Document pageHtml = parse(response.body);
    String jscript = pageHtml.querySelector('#initials-script')!.text;
    Map<String, dynamic> jscriptMap = jsonDecode(
        jscript.substring(jscript.indexOf("{"), jscript.indexOf('};') + 1));

    // normal description
    String? shortDescription;
    if (jscriptMap["aboutMeComponent"]?["text"] != null) {
      shortDescription = jscriptMap["aboutMeComponent"]["text"].trim();
      shortDescription = HtmlUnescape().convert(shortDescription!);
    }

    Map<String, Uri>? externalLinks;
    Map<String, String>? advancedDescription;
    try {
      Map<dynamic, dynamic>? infoMap = jscriptMap["infoComponent"]
              ?["displayUserModel"]?["personalInfo"] ??
          jscriptMap["displayUserModel"]?["personalInfo"];
      if (infoMap != null) {
        advancedDescription = {};
        infoMap.forEach((key, item) {
          if (item == null) {
            return;
          }
          switch (key) {
            case "gender":
            case "orientation":
            case "ethnicity":
            case "body":
            case "hairLength":
            case "hairColor":
            case "eyeColor":
            case "relations":
            case "kids":
            case "education":
            case "religion":
            case "smoking":
            case "alcohol":
            case "star_sign":
            case "income":
            case "seekingOrientation":
            case "seekingGender":
              advancedDescription![key] = item["label"];
              break;
            case "allLanguages":
              advancedDescription![key] = item.join(", ");
              break;
            case "height":
              advancedDescription![key] =
                  "${item["cm"]}cm (${item["feet"]}ft ${item["in"] == null ? "" : "${item["in"]}in"})";
              break;
            case "social":
              externalLinks ??= {};
              if (item.isNotEmpty) {
                item.forEach((key, value) {
                  externalLinks![key] = Uri.parse(value);
                });
              }
              break;
            case "website":
              externalLinks ??= {};
              externalLinks!["website"] = Uri.parse(item["URL"]);
              break;
            case "geo":
              advancedDescription ??= {};
              advancedDescription!["country"] = "${item["countryName"]}"
                  "${item?["region"]?["label"] != null ? ", ${item["region"]["label"]}" : ""}";
              break;
            // These are not shown in the xhamster UI or are irrelevant/obsolete
            case "birthday":
            case "score":
            case "modelName":
            case "userID":
            case "fullName":
            case "iAm":
            case "langs_other":
            case "languages":
            case "interests":
              break;
            default:
              logger.d("Adding as unknown as String: $key: $item ");
              advancedDescription![key] = item.toString();
          }
        });
      }
      if (jscriptMap["aboutMeComponent"]?["personalInfoList"] != null) {
        advancedDescription ??= {};
        advancedDescription!["Interests and fetishes"] =
            jscriptMap["aboutMeComponent"]["personalInfoList"][2]["value"];
      }
      if (jscriptMap["pagesCategoryComponent"]?["channelLandingInfoProps"]
              ?["showJoinButton"] !=
          null) {
        externalLinks ??= {};
        externalLinks!["Official site"] = Uri.parse(
            jscriptMap["pagesCategoryComponent"]["channelLandingInfoProps"]
                ["showJoinButton"]["url"]);
      }
    } catch (e, stacktrace) {
      logger.w(
          "Error parsing advanced description or external links: $e\n$stacktrace");
    }

    String? name;
    if (jscriptMap["infoComponent"]?["pageTitle"] != null) {
      name = jscriptMap["infoComponent"]["pageTitle"];
    } else if (jscriptMap["pagesCategoryComponent"]?["channelLandingInfoProps"]
            ?["pageTitle"] !=
        null) {
      // For some reason xhamster adds a " Porn Videos: website.com" to all
      // channel titles (even in the official UI)
      name = jscriptMap["pagesCategoryComponent"]["channelLandingInfoProps"]
              ["pageTitle"]
          .split(" Porn Videos: ")
          .first;
    } else {
      name = jscriptMap["displayUserModel"]?["modelName"];
    }

    String? thumbnail;
    if (jscriptMap["infoComponent"]?["pornstarTop"]?["thumbUrl"] != null) {
      thumbnail = jscriptMap["infoComponent"]["pornstarTop"]["thumbUrl"];
    } else if (jscriptMap["pagesCategoryComponent"]?["channelLandingInfoProps"]
            ?["sponsorChannel"]?["siteLogoURL"] !=
        null) {
      thumbnail = jscriptMap["pagesCategoryComponent"]
          ?["channelLandingInfoProps"]?["sponsorChannel"]?["siteLogoURL"];
    } else {
      thumbnail = jscriptMap["displayUserModel"]?["thumbURL"];
    }

    int? viewsTotal;
    int? videosTotal;
    int? subscribers;
    int? rank;
    Map<String, dynamic>? infoMap;
    if (jscriptMap["infoComponent"] != null) {
      infoMap = jscriptMap["infoComponent"]?["pornstarTop"];
      subscribers = jscriptMap["infoComponent"]?["subscribeButtonsProps"]
          ?["subscribeButtonProps"]?["subscribers"];
      viewsTotal = infoMap?["viewsCount"];
      videosTotal = infoMap?["videoCount"];
      rank = infoMap?["rating"];
    } else if (jscriptMap["pagesCategoryComponent"]
            ?["channelLandingInfoProps"] !=
        null) {
      infoMap = jscriptMap["pagesCategoryComponent"]?["channelLandingInfoProps"]
          ?["sponsorChannel"];
      subscribers = jscriptMap["pagesCategoryComponent"]
              ?["channelLandingInfoProps"]?["subscribeButtonsProps"]
          ?["subscribeButtonProps"]?["subscribers"];
      viewsTotal = infoMap?["viewsCount"];
      videosTotal = infoMap?["videoCount"];
      rank = infoMap?["rating"];
    } else {
      logger.d(
          "Trying to scrape views, videosTotal, subscribers and rank from html");
      // some users don't have this info in the jsonmap -> scrape from html
      try {
        videosTotal = int.tryParse(pageHtml
            .querySelector('a[class="followable videos"]')!
            .children
            .first
            .text);
        viewsTotal = int.tryParse(pageHtml
            .querySelector('div[class="user-details"]')!
            .children[3]
            .querySelector("span")!
            .attributes["data-tooltip"]!
            .replaceAll(",", "")
            .trim());
        subscribers = int.tryParse(pageHtml
            .querySelector('div[class="user-details"]')!
            .children[4]
            .querySelector("span")!
            .attributes["data-tooltip"]!
            .replaceAll(",", "")
            .trim());
        // users don't have ranks
      } catch (e, stacktrace) {
        logger.w(
            "Error parsing views/videosTotal/subscribers/rank: $e\n$stacktrace");
      }
    }

    UniversalAuthorPage authorPage = UniversalAuthorPage(
        iD: authorID,
        name: name!,
        plugin: this,
        avatar: thumbnail,
        // xhamster doesn't have banners
        banner: null,
        aliases: jscriptMap["infoComponent"]?["aliases"]?.split(", "),
        description: shortDescription,
        advancedDescription: advancedDescription,
        externalLinks: externalLinks,
        viewsTotal: viewsTotal,
        videosTotal: videosTotal,
        subscribers: subscribers,
        rank: rank,
        rawHtml: pageHtml);

    // This will also set the scrapeFailMessage if needed
    authorPage.verifyScrapedData(
        codeName, testingMap["ignoreScrapedErrors"]["authorPage"]);

    return authorPage;
  }

  @override
  Future<List<UniversalVideoPreview>> getAuthorVideos(String authorID, int page,
      [void Function(String body)? debugCallback]) async {
    // First get the author page URI
    Uri authorPageLink = (await getAuthorUriFromID(authorID))!;

    // differentiate between creators/channels and users
    Uri? videosLink;
    if (authorPageLink.toString().contains("user")) {
      videosLink = Uri.parse("$authorPageLink/videos/$page");
    } else {
      videosLink = Uri.parse("$authorPageLink/best/$page");
    }

    logger.d("Requesting $videosLink");
    var response = await client.get(videosLink);
    if (response.statusCode != 200) {
      // 404 means both error and no videos in this case
      // -> return empty list instead of throwing exception
      if (response.statusCode == 404) {
        logger.w("Error downloading html: ${response.statusCode} "
            "- ${response.reasonPhrase}"
            " - Treating as no more videos found");
        return [];
      }
      logger.e(
          "Error downloading html: ${response.statusCode} - ${response.reasonPhrase}");
      throw Exception(
          "Error downloading html: ${response.statusCode} - ${response.reasonPhrase}");
    }
    debugCallback?.call(response.body);
    Document resultHtml = parse(response.body);

    if (authorPageLink.toString().contains("user")) {
      return _parseVideoList(resultHtml
          .querySelector('div[data-role="thumb-list-videos"]')!
          .querySelectorAll('div[data-video-type="video"]')
          .toList());
    } else {
      return _parseVideoList(resultHtml
          .querySelector('div[data-role="video-section-content-role"]')!
          .children
          .first
          .querySelectorAll('div[data-video-type="video"]')
          .toList());
    }
  }
}
