import 'dart:convert';
import 'dart:isolate';

import 'package:flutter/services.dart';
import 'package:flutter_js/flutter_js.dart';
import 'package:html/dom.dart';
import 'package:html/parser.dart';
import 'package:html_unescape/html_unescape.dart';
import 'package:http/http.dart' as http;
import 'package:http/http.dart';
import 'package:image/image.dart';

import '/services/external_link_manager.dart';
import '/utils/exceptions.dart';
import '/utils/global_vars.dart';
import '/utils/official_plugin.dart';
import '/utils/plugin_interface/plugin_interface.dart';
import '/utils/try_parse.dart';
import '/utils/universal_formats.dart';

class PornhubPlugin extends OfficialPlugin implements PluginInterface {
  @override
  final bool isOfficialPlugin = true;
  @override
  bool isInitialized = false;
  @override
  String codeName = "com.hedon_haven.pornhub";
  @override
  String prettyName = "Pornhub.com";
  @override
  String developer = "Hedon Haven";
  @override
  String contactEmail = "contact@hedon-haven.top";
  @override
  String description = "Full account-less functionality for pornhub.com";
  @override
  Uri iconUrl = Uri.parse("https://www.pornhub.com/favicon.ico");
  @override
  String serviceUrl = "https://www.pornhub.com";
  @override
  List<String> handleUrls = [
    // Homepage
    "https://www.pornhub.com/",
    "https://www.pornhub.com/video",
    // Search page
    "https://www.pornhub.com/video/search",
    // Video page
    "https://www.pornhub.com/view_video.php",
    // Author page
    "https://www.pornhub.com/channels/",
    "https://www.pornhub.com/model/",
    "https://www.pornhub.com/pornstar/"
  ];
  @override
  int initialHomePage = 0;
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
  String version = "";

  // Set OfficialPlugin specific vars
  @override
  Map<String, dynamic> testingMap = {
    "ignoreScrapedErrors": {
      "homepage": [
        "thumbnailBinary",
        "ratingsPositivePercent",
        "maxQuality",
        "lastWatched",
        "addedOn"
      ],
      "searchResults": [
        "thumbnailBinary",
        "ratingsPositivePercent",
        "maxQuality",
        "lastWatched",
        "addedOn"
      ],
      "videoMetadata": ["chapters", "description", "ratingsNegativeTotal"],
      "videoSuggestions": [
        "thumbnailBinary",
        "ratingsPositivePercent",
        "lastWatched",
        "addedOn",
        "maxQuality"
      ],
      "authorVideos": [
        "thumbnailBinary",
        "ratingsPositivePercent",
        "maxQuality",
        "authorName",
        "authorID",
        "lastWatched",
        "addedOn"
      ],
      "comments": [
        "authorID",
        "countryID",
        "orientation",
        "ratingsPositiveTotal",
        "ratingsNegativeTotal",
      ],
      "authorPage": ["aliases", "videosTotal", "lastViewed", "addedOn"]
    },
    "testingVideos": [
      // This is the most watched video on pornhub (that is available in all regions)
      {"videoID": "ph5fa4d22a641bd", "progressThumbnailsAmount": 2025},
      // This is a more recent video
      {"videoID": "ph61eb1d353f1bd", "progressThumbnailsAmount": 2250}
    ],
    "testingAuthorPageIds": [
      // A channel-type author
      "vixen",
      // A model-type author
      "sweetie-fox",
      // A pornstar-type author
      "mia-khalifa"
    ]
  };

  // Private hardcoded vars
  final String _videoEndpoint =
      "https://www.pornhub.com/view_video.php?viewkey=";
  final String _searchEndpoint = "https://www.pornhub.com/video/search?search=";

  final String _channelEndpoint = "https://www.pornhub.com/channels/";
  final String _modelEndpoint = "https://www.pornhub.com/model/";
  final String _pornstarEndpoint = "https://www.pornhub.com/pornstar/";

  // Store session cookies created by init
  final Map<String, String> _sessionCookies = {
    "ss": "",
    "token": "",
    "KEY": ""
  };
  final Map<String, String> _sortingTypeMap = {
    "Relevance": "",
    "Upload date": "mr",
    "Views": "mv",
    "Rating": "tr",
    "Duration": "lg"
  };
  final Map<String, String> _dateRangeMap = {
    "All time": "",
    "Last year": "y",
    "Last month": "m",
    "Last week": "w",
    "Last day/Last 3 days/Latest": "t"
  };
  final Map<int, String> _minDurationMap = {
    0: "",
    300: "", // pornhub doesn't support 5 min -> use 0
    600: "10",
    1200: "20",
    1800: "30",
    3600: ""
  };
  final Map<int, String> _maxDurationMap = {
    0: "",
    300: "", // pornhub doesn't support 5 min -> use 0
    600: "10",
    1200: "20",
    1800: "30",
    3600: ""
  };

  Future<List<UniversalVideoPreview>> _parseVideoList(List<Element> resultsList,
      [bool authorPageMode = false]) async {
    logger
        .d("Parsing ${resultsList.length} video elements (some might be ads!)");
    // convert the divs into UniversalSearchResults
    List<UniversalVideoPreview> results = [];
    for (Element resultElement in resultsList) {
      Element resultDiv = resultElement.querySelector("div")!;
      Element? imageDiv = resultDiv.querySelector("a");

      String? iD = resultElement.attributes['data-video-vkey'];
      // the title field can have different names
      String? title = resultDiv
          .querySelector('div[class="title"]')
          ?.querySelector("a")
          ?.text
          .trim();

      // convert time string into int list
      // pornhub automatically converts hours into minutes -> no need to check
      Duration? duration;
      try {
        List<int>? durationList = resultDiv
            .querySelector('span[class*="time"]')
            ?.text
            .trim()
            .split(":")
            .map((e) => int.parse(e))
            .toList();
        duration = Duration(seconds: durationList![0] * 60 + durationList[1]);
      } catch (_) {}

      // determine video views
      int? views;
      try {
        // the div is called videoViews on the first homepage and just views on all others
        String viewsString = resultDiv
            .querySelector('div[class="videoViews"], div[class="views"]')!
            .text
            .replaceAll("Views", "")
            .trim();

        // just added means 0
        views = _convertHumanReadableStringToInt(viewsString);
      } catch (_) {}

      // TODO: determine video resolution
      // pornhub only offers up to 1080p

      // the author field can be a link or a span
      Element? authorDiv = resultDiv.querySelector('a[class*="uploaderLink"], '
          'span[class*="uploaderLink"]');

      UniversalVideoPreview uniResult = UniversalVideoPreview(
        // Don't enforce null safety here
        // treat error below in scrapeFailMessage instead
        iD: iD ?? "null",
        title: title ?? "null",
        plugin: this,
        thumbnail: imageDiv?.querySelector("img")?.attributes["src"],
        thumbnailHttpHeaders: {
          "User-Agent": httpUserAgent,
          "Referer": "https://www.pornhub.com/"
        },
        previewVideo:
            tryParse(() => Uri.parse(imageDiv!.attributes["data-webm"]!)),
        duration: duration,
        viewsTotal: views,
        ratingsPositivePercent: null,
        maxQuality: null,
        virtualReality: tryParse(() =>
            resultDiv
                .querySelector('span[class="hd-thumbnail vr-thumbnail"]') !=
            null),
        authorName: authorDiv?.text.trim(),
        authorID: authorDiv?.attributes["href"]?.split("/").last,
        // All authors on pornhub are verified
        verifiedAuthor: true,
      );

      // getHomepage, getSearchResults and getVideoSuggestions all use the same _parseVideoList
      // -> their ignore lists are the same
      // This will also set the scrapeFailMessage if needed
      uniResult.verifyScrapedData(
          codeName,
          authorPageMode
              ? testingMap["ignoreScrapedErrors"]["authorVideos"]
              : testingMap["ignoreScrapedErrors"]["homepage"]);

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

  /// Pornhub doesn't provide timestamps, only approximate human-readable strings. Convert them to DateTime objects to be more universal
  DateTime? _convertStringToDateTime(String? dateAsString) {
    DateTime? converted;
    if (dateAsString == null) {
      return null;
    }
    try {
      if (dateAsString.endsWith("seconds ago") ||
          dateAsString.endsWith("second ago")) {
        converted = DateTime.now()
            .subtract(Duration(seconds: int.parse(dateAsString[0])));
      } else if (dateAsString.endsWith("minutes ago") ||
          dateAsString.endsWith("minute ago")) {
        converted = DateTime.now()
            .subtract(Duration(minutes: int.parse(dateAsString[0])));
      } else if (dateAsString.endsWith("hours ago") ||
          dateAsString.endsWith("hour ago")) {
        converted = DateTime.now()
            .subtract(Duration(hours: int.parse(dateAsString[0])));
      } else if (dateAsString == "Yesterday") {
        converted = DateTime.now().subtract(const Duration(days: 1));
      } else if (dateAsString.endsWith("days ago")) {
        converted =
            DateTime.now().subtract(Duration(days: int.parse(dateAsString[0])));
      } else if (dateAsString.endsWith("weeks ago") ||
          dateAsString.endsWith("week ago")) {
        converted = DateTime.now()
            .subtract(Duration(days: int.parse(dateAsString[0]) * 7));
      } else if (dateAsString.endsWith("months ago") ||
          dateAsString.endsWith("month ago")) {
        converted = DateTime.now()
            .subtract(Duration(days: int.parse(dateAsString[0]) * 30));
      } else if (dateAsString.endsWith("years ago") ||
          dateAsString.endsWith("year ago")) {
        converted = DateTime.now()
            .subtract(Duration(days: int.parse(dateAsString[0]) * 365));
      } else {
        logger.w("Could not convert date string to DateTime: $dateAsString");
      }
    } catch (e, stacktrace) {
      logger.w("Error converting date string to DateTime: $e\n$stacktrace");
      return null;
    }
    return converted;
  }

  /// Convert human readable string (e.g. 300K) to full integer (-> 300000)
  int? _convertHumanReadableStringToInt(String intAsString) {
    int views = 0;
    if (intAsString != "just added") {
      if (intAsString.endsWith("K")) {
        if (intAsString.contains(".")) {
          views = int.parse(intAsString.split(".")[1][0]) * 100;
          // this is so that the normal step still works
          // ignore: prefer_interpolation_to_compose_strings
          intAsString = intAsString.split(".")[0] + " ";
        }
        views +=
            int.parse(intAsString.substring(0, intAsString.length - 1)) * 1000;
      } else if (intAsString.endsWith("M")) {
        if (intAsString.contains(".")) {
          views = int.parse(intAsString.split(".")[1][0]) * 100000;
          // this is so that the normal step still works
          // ignore: prefer_interpolation_to_compose_strings
          intAsString = intAsString.split(".")[0] + " ";
        }
        views += int.parse(intAsString.substring(0, intAsString.length - 1)) *
            1000000;
      } else if (intAsString.endsWith("B")) {
        if (intAsString.contains(".")) {
          views = int.parse(intAsString.split(".")[1][0]) * 1000000000;
          // this is so that the normal step still works
          // ignore: prefer_interpolation_to_compose_strings
          intAsString = intAsString.split(".")[0] + " ";
        }
        views += int.parse(intAsString.substring(0, intAsString.length - 1)) *
            1000000000;
      } else {
        views = int.parse(intAsString);
      }
    }
    return views;
  }

  // Since pornhub sometimes throws a compute check, wrap all requests
  Future<Response> _performGetRequest(Uri requestUri,
      {Map<String, String>? headers, int? recurseCount}) async {
    headers ??= {"Cookie": ""};
    if (headers["Cookie"] == null) {
      headers["Cookie"] = "";
    }
    recurseCount ??= 0;
    if (recurseCount > 5) {
      throw ("Compute check failed 5 times");
    }
    logger.d("_performGetRequest recurse count: $recurseCount");

    // Append already existing compute KEY to request
    headers["Cookie"] = "${headers["Cookie"]}; KEY=${_sessionCookies["KEY"]}";

    Response response = await client.get(requestUri, headers: headers);

    // Check if compute check was sent
    if (parse(response.body).body!.text.trim() == "Loading...") {
      logger.i("Compute check detected");
      // Get entire JS code from html
      String rawJS = parse(response.body).querySelector("script")!.text;
      logger.d("Extracted js compute check code: $rawJS");
      // modify the code so it returns the cookie
      rawJS = rawJS
          .replaceAll("document.cookie=", "return ")
          .replaceAll("document.location.reload(true);", "");
      rawJS += "\ngo();";
      // run the code and store result
      _sessionCookies["KEY"] = getJavascriptRuntime()
          .evaluate(rawJS)
          .stringResult
          .replaceAll(";path=/;", "");
      logger.i("New compute check cookie (KEY): ${_sessionCookies["KEY"]}");
      // replace cookie in headers
      // ignore: prefer_interpolation_to_compose_strings
      headers["Cookie"] =
          headers["Cookie"]!.split("KEY=").first + _sessionCookies["KEY"]!;
      // perform new request
      logger.d(
          "Performing new request to $requestUri with updated cookies: ${headers["Cookie"]}");
      response = await _performGetRequest(requestUri,
          headers: headers, recurseCount: recurseCount + 1);
    }
    return response;
  }

  @override
  Future<bool> init(String cachePath,
      [void Function(String body)? debugCallback]) async {
    if (isInitialized) {
      return true;
    }
    isInitialized = true;
    logger.i("Initializing $codeName plugin");
    // To be able to make search suggestion requests later, both a session cookie and a token are needed
    // Get the sessions cookie (called ss) from the response headers
    String? setCookies;
    http.Response response =
        await _performGetRequest(Uri.parse("https://www.pornhub.com"));
    if (response.statusCode != 200) {
      return Future.value(false);
    }
    setCookies = response.headers['set-cookie'];
    Document rawHtml = parse(response.body);

    debugCallback
        ?.call("Headers: ${response.headers}\n\nBody: ${response.body}");

    // Check for age blocks
    if (rawHtml.body!.classes.contains("apt-landing")) {
      throw AgeGateException();
    }

    if (setCookies != null) {
      List<String> cookiesList = setCookies.split(',');
      for (var i = 0; i < cookiesList.length; i++) {
        if (cookiesList[i].contains("ss=")) {
          _sessionCookies["ss"] =
              cookiesList[i].substring(3, cookiesList[i].indexOf(";"));
          logger.i("Session cookie: ${_sessionCookies["ss"]}");
        }
      }
    } else {
      logger.e("No set-cookies received; couldn't extract session cookie");
      return Future.value(false);
    }

    // From the same request get the token inside the html
    _sessionCookies["token"] =
        rawHtml.querySelector("#searchInput")!.attributes["data-token"]!;
    logger.i("Token: ${_sessionCookies["token"]}");
    if (_sessionCookies["token"] == null) {
      logger.e("No token received or found; couldn't extract token");
      return Future.value(false);
    }
    return Future.value(true);
  }

  @override
  Future<bool> runFunctionalityTest() {
    // There is no need to run functionality tests on official plugins
    // as they are not imported at any time in the app
    // Also, these plugins get checked for functionality via daily CIs
    return Future.value(true);
  }

  @override
  Future<ExternalLinkParsed> parseExternalLink(Uri uri) async {
    logger.i("Parsing ${uri.path}");
    switch (uri.path) {
      case "/" || "/video":
        return ExternalLinkParsed(
          type: ContentType.homePage,
          pageCount: int.parse(
              uri.queryParameters["page"] ?? initialHomePage.toString()),
        );

      case "/video/search":
        final args = uri.queryParameters;

        // Reverse-lookup using search Maps
        String sortingType = _sortingTypeMap.entries
            .firstWhere((entry) => entry.value == args["o"],
                orElse: () => const MapEntry("", ""))
            .key;
        String dateRange = _dateRangeMap.entries
            .firstWhere((entry) => entry.value == args["t"],
                orElse: () => const MapEntry("", ""))
            .key;
        int minDuration = _minDurationMap.entries
            .firstWhere((entry) => entry.value == args["min_duration"],
                orElse: () => const MapEntry(0, ""))
            .key;
        int maxDuration = _maxDurationMap.entries
            .firstWhere((entry) => entry.value == args["max_duration"],
                orElse: () => const MapEntry(3600, ""))
            .key;

        return ExternalLinkParsed(
          type: ContentType.searchResultsPage,
          searchRequest: UniversalSearchRequest(
            searchString: Uri.decodeQueryComponent(args["search"] ?? ""),
            sortingType: sortingType,
            dateRange: dateRange,
            minQuality: args["hd"] == '1' ? 720 : 0,
            // no maxQuality
            minDuration: minDuration,
            maxDuration: maxDuration,
            // rest are empty / not yet supported
          ),
          pageCount:
              int.parse(args["page"] ?? initialSearchResultsPage.toString()),
        );

      case "/view_video.php":
        return ExternalLinkParsed(
          type: ContentType.videoPage,
          iD: uri.queryParameters["viewkey"]!,
        );

      case "/channels/" || "/model/" || "/pornstar/":
        return ExternalLinkParsed(
          type: ContentType.authorPage,
          iD: uri.pathSegments.last,
        );

      default:
        return ExternalLinkParsed(type: ContentType.unknown);
    }
  }

  @override
  Future<List<UniversalVideoPreview>> getHomePage(int page,
      [void Function(String body)? debugCallback]) async {
    List<Element>? resultsList;
    // pornhub has a homepage and a separate page 1 video homepage
    // -> load main homepage first, then load first video homepage
    if (page == 0) {
      // page=0 returns a different page than requesting the base website
      logger.d("Requesting https://www.pornhub.com");
      var response =
          await _performGetRequest(Uri.parse("https://www.pornhub.com"),
              // Mobile video image previews are higher quality
              headers: {"Cookie": "platform=mobile"});
      debugCallback?.call(response.body);
      if (response.statusCode != 200) {
        logger.e(
            "Error downloading html: ${response.statusCode} - ${response.reasonPhrase}");
        throw Exception(
            "Error downloading html: ${response.statusCode} - ${response.reasonPhrase}");
      }
      // Filter out ads and non-video results
      List<Element>? unparsedResults = parse(response.body)
          // the base page has a different id for the video list
          .querySelector('#singleFeedSection')
          ?.querySelectorAll('li[data-video-vkey]');

      // Get rid of li's without content
      resultsList = unparsedResults!.where((element) {
        return element.children.isNotEmpty;
      }).toList();
    } else {
      logger.d("Requesting https://www.pornhub.com/video?page=$page");
      var response = await _performGetRequest(
          Uri.parse("https://www.pornhub.com/video?page=$page"),
          // Mobile video image previews are higher quality
          headers: {"Cookie": "platform=mobile"});
      debugCallback?.call(response.body);
      if (response.statusCode != 200) {
        logger.e(
            "Error downloading html: ${response.statusCode} - ${response.reasonPhrase}");
        throw Exception(
            "Error downloading html: ${response.statusCode} - ${response.reasonPhrase}");
      }
      // Filter out ads and non-video results
      List<Element>? unparsedResults = parse(response.body)
          // the base page has a different id for the video list
          .querySelector('ul[class^="videoList"]')
          ?.querySelectorAll('li[data-video-vkey]');

      // Get rid of li's without content
      resultsList = unparsedResults!.where((element) {
        return element.children.isNotEmpty;
      }).toList();
    }
    return _parseVideoList(resultsList);
  }

  // downloadThumbnail is implemented at the OfficialPlugin level

  @override
  Future<List<String>> getSearchSuggestions(String searchString,
      [void Function(String body)? debugCallback]) async {
    logger.d("Getting search suggestions for $searchString");
    final Uri requestUri = Uri.parse(
        "https://www.pornhub.com/api/v1/video/search_autocomplete?token=${_sessionCookies["token"]}&q=$searchString");
    logger
        .d("Request URI: $requestUri with ss cookie: ${_sessionCookies["ss"]}");
    final response = await _performGetRequest(requestUri,
        headers: {"Cookie": "ss=${_sessionCookies["ss"]}"});
    debugCallback?.call(response.body);
    Map<String, dynamic> data = jsonDecode(response.body);
    // The search results are just returned as key value pairs of numbers
    // e.g. {"0": "suggestion1", "1": "suggestion2", "2": "suggestion3"}
    // combine them into a simple list
    List<String> suggestions = [];
    data.forEach((key, value) {
      if (key != "isDdBannedWord" && key != "popularSearches") {
        suggestions.add(value);
      }
    });
    return suggestions;
  }

  @override
  Future<List<UniversalVideoPreview>> getSearchResults(
      UniversalSearchRequest request, int page,
      [void Function(String body)? debugCallback]) async {
    // Pornhub doesn't allow empty search queries
    if (request.searchString.isEmpty) {
      return [];
    }
    // @formatter:off
    // Pornhub does not accept redundant search parameters.
    // E.g. passing &min_duration=0 will result in a 404, even though technically 0 is the default duration in the website's ui
    String urlString = "$_searchEndpoint${Uri.encodeComponent(request.searchString)}"
        "&page=$page"
        "${request.sortingType != "Relevance" ? "&o=${_sortingTypeMap[request.sortingType]!}" : ""}"
        // only top rated and most views support sorting by date
        "${["Rating", "Views"].contains(request.dateRange) && request.dateRange != "All time" ? "&t=${_dateRangeMap[request.dateRange]}": ""}"
        "${request.minQuality >= 720 ? "&hd=1" : ""}"
        // maxQuality not supported
        "${![600, 1200, 1800].contains(request.minDuration) ? "" : "&min_duration=${_minDurationMap[request.minDuration]!}"}"
        "${![600, 1200, 1800].contains(request.maxDuration) ? "" : "&max_duration=${_maxDurationMap[request.maxDuration]!}"}"
        // min and max FPS not supported
        // virtual reality filter not supported
        // categories and keywords not yet implemented fully
    ;
    // @formatter:on

    logger.d("Requesting $urlString");
    var response = await _performGetRequest(Uri.parse(urlString),
        // Mobile video image previews are higher quality
        headers: {"Cookie": "platform=mobile"});
    debugCallback?.call(response.body);
    if (response.statusCode != 200) {
      // Differentiate between soft 404 (browser still shows a page) and hard 404 (network failure)
      if (response.body.contains("Error Page Not Found")) {
        throw NotFoundException();
      }
      logger.e(
          "Error downloading $urlString: ${response.statusCode} - ${response.reasonPhrase}");
      throw Exception(
          "Error downloading $urlString: ${response.statusCode} - ${response.reasonPhrase}");
    }
    Document resultHtml = parse(response.body);
    if (resultHtml.outerHtml == "<html><head></head><body></body></html>") {
      throw Exception("Received empty html");
    }
    // Filter out ads and non-video results
    List<Element>? resultsList = resultHtml
        .querySelector('ul[id="videoListSearchResults"]')
        ?.querySelectorAll('li[class^="videoSearchList_"]')
        .toList();
    return _parseVideoList(resultsList!);
  }

  @override
  Future<Uri?> getVideoUriFromID(String videoID) async {
    return Uri.parse(_videoEndpoint + videoID);
  }

  @override
  Future<UniversalVideoMetadata> getVideoMetadata(
      String videoId, UniversalVideoPreview uvp,
      [void Function(String body)? debugCallback]) async {
    Uri videoMetadata = Uri.parse(_videoEndpoint + videoId);
    logger.d("Requesting $videoMetadata");
    var response = await _performGetRequest(
      videoMetadata,
      // This header allows getting more data (such as recommended videos which are later used by getRecommendedVideos)
      headers: {"Cookie": "accessAgeDisclaimerPH=1; platform=mobile"},
    );
    debugCallback?.call(response.body);
    if (response.statusCode != 200) {
      logger.e(
          "Error downloading html: ${response.statusCode} - ${response.reasonPhrase}");
      throw Exception(
          "Error downloading html: ${response.statusCode} -l ${response.reasonPhrase}");
    }

    Document rawHtml = parse(response.body);

    // Get the video javascript and convert the main json into a map
    String jscript =
        rawHtml.querySelector("#mobileContainer > script:nth-child(1)")!.text;
    Map<String, dynamic> jscriptMap = jsonDecode(
        jscript.substring(jscript.indexOf("{"), jscript.indexOf('};') + 1));

    // get the application/ld+json
    Map<String, dynamic> JSONLD = jsonDecode(
        rawHtml.querySelector('script[type="application/ld+json"]')!.text);

    // ratings
    int? ratingsPositive;
    int? ratingsNegative;
    for (var interaction in JSONLD["interactionStatistic"]) {
      if (interaction["interactionType"] == "http://schema.org/LikeAction") {
        ratingsPositive = int.tryParse(
            interaction["userInteractionCount"].replaceAll(",", ""));
        break;
      }
    }
    int? ratingsTotal = ratingsPositive;

    // For some reason on mobile the full exact view amount is always shown
    int? viewsTotal;
    for (var interaction in JSONLD["interactionStatistic"]) {
      if (interaction["interactionType"] == "http://schema.org/WatchAction") {
        viewsTotal = int.tryParse(
            interaction["userInteractionCount"].replaceAll(",", ""));
        break;
      }
    }

    // author
    Element? authorRaw =
        rawHtml.querySelector(".userInfoContainer")?.querySelector("a");

    String? authorString = authorRaw?.text;
    String authorId = authorRaw!.attributes["href"]!.split("/").last;

    // actors
    List<String>? actors = [];
    List<Element>? actorsList = rawHtml
        .querySelector('div[class*="pornstarsWrapper"]')
        ?.querySelectorAll("a");
    if (actorsList != null) {
      for (Element element in actorsList) {
        actors.add(element.text);
      }
    }

    // categories
    List<String>? categories = [];
    List<Element>? categoriesList = rawHtml
        .querySelector('div[class*="categoriesWrapper"]')
        ?.querySelectorAll("a");
    if (categoriesList != null) {
      for (Element element in categoriesList) {
        categories.add(element.text);
      }
    }

    // tags
    List<String>? tags = [];
    List<Element>? tagsList = rawHtml
        .querySelector('div[class*="tagsWrapper"]')
        ?.querySelectorAll("a");
    if (tagsList != null) {
      for (Element element in tagsList) {
        tags.add(element.text);
      }
    }

    // Pornhub doesn't provide exact timestamps -> convert it
    DateTime? uploadDate = _convertStringToDateTime(
        rawHtml.querySelector('li[class="added"]')?.text.trim());

    Map<int, Uri> m3u8Map = {};
    for (Map<String, dynamic> video in jscriptMap["mediaDefinitions"]) {
      if (video["format"] == "hls") {
        // the last quality is a List of all qualities -> ignore it
        var quality = video["quality"];
        if (quality.runtimeType == String) {
          m3u8Map[int.parse(quality)] = Uri.parse(video["videoUrl"]);
        }
      }
    }

    UniversalVideoMetadata metadata = UniversalVideoMetadata(
        iD: videoId,
        m3u8Uris: m3u8Map,
        playbackHttpHeaders: {
          "User-Agent": httpUserAgent,
          "Referer": "https://www.pornhub.com/"
        },
        title: jscriptMap["video_title"]!,
        plugin: this,
        universalVideoPreview: uvp,
        authorID: authorId,
        authorName: authorString,
        authorSubscriberCount: _convertHumanReadableStringToInt(rawHtml
                .querySelector('span[class="subscribersCount"]')
                ?.text
                .replaceAll(" Subscribers", "") ??
            "0"),
        authorAvatar:
            rawHtml.querySelector('img[class="userAvatar"]')?.attributes["src"],
        actors: actors,
        description: rawHtml
            .querySelector(
                'div[class="categoryRow targetContainer displayNone clearfix"]')
            ?.querySelector("span")
            ?.text
            .trim(),
        viewsTotal: viewsTotal,
        tags: tags,
        categories: categories,
        uploadDate: uploadDate,
        ratingsPositiveTotal: ratingsPositive,
        ratingsNegativeTotal: ratingsNegative,
        ratingsTotal: ratingsTotal,
        virtualReality: jscriptMap["isVR"] == 1,
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

    // Not quite sure what this is needed for, but fails otherwise
    BackgroundIsolateBinaryMessenger.ensureInitialized(rootToken);
    try {
      // Get the video javascript
      String jscript =
          rawHtml.querySelector("#mobileContainer > script:nth-child(1)")!.text;
      Map<String, dynamic> jscriptMap = jsonDecode(
          jscript.substring(jscript.indexOf("{"), jscript.indexOf('};') + 1));

      // Extract the progressImage url from jscript
      List<String> imageUrls =
          jscriptMap["thumbs"]["spritePatterns"].cast<String>();
      logPort.send(["debug", "Image urls: $imageUrls"]);

      // Extract the sampling frequency
      int samplingFrequency = jscriptMap["thumbs"]["samplingFrequency"];
      logPort.send(["debug", "Sampling frequency: $samplingFrequency"]);

      // Newer video previews all have the same size (600x340) with a 5x5 layout
      int width = 120;
      int height = 68;
      // Check if video is using older thumbnail type with dynamic sizes
      if (imageUrls[0].endsWith(".jpg")) {
        width = int.parse(jscriptMap["thumbs"]["thumbWidth"]);
        height = int.parse(jscriptMap["thumbs"]["thumbHeight"]);
      }
      logPort.send(["debug", "Width: $width, Height: $height"]);
      logPort.send(["info", "Downloading and processing progress images"]);
      List<List<Uint8List>> allThumbnails =
          List.generate(imageUrls.length, (_) => []);
      List<Future<void>> imageFutures = [];

      for (int i = 0; i <= allThumbnails.length - 1; i++) {
        // Create a future for downloading and processing
        imageFutures.add(Future(() async {
          logPort.send(["debug", "Requesting download for ${imageUrls[i]}"]);

          // Request the main thread to fetch the image
          final responsePort = ReceivePort();
          fetchPort.send([Uri.parse(imageUrls[i]), responsePort.sendPort]);
          Uint8List image = await responsePort.first as Uint8List;
          responsePort.close();

          final decodedImage = decodeImage(image)!;
          List<Uint8List> thumbnails = [];
          for (int h = 0; h <= height * 4; h += height) {
            for (int w = 0; w <= width * 4; w += width) {
              // every progress image is for samplingFrequency (usually 4 or 9) seconds -> store the same image samplingFrequency times
              // To avoid overfilling the ram, create a temporary variable and store it in the list multiple times
              // As Lists contain references to data and not the data itself, this should reduce ram usage
              Uint8List firstThumbnail = Uint8List(0);
              for (int j = 0; j < samplingFrequency; j++) {
                if (j == 0) {
                  // Only encode and add the first image once
                  firstThumbnail = encodeJpg(copyCrop(decodedImage,
                      x: w, y: h, width: width, height: height));
                  thumbnails.add(firstThumbnail); // Add the first encoded image
                } else {
                  // Reuse the reference to the first thumbnail
                  thumbnails.add(firstThumbnail);
                }
              }
            }
          }
          allThumbnails[i] = thumbnails;
          logPort.send(["debug", "Completed processing ${imageUrls[i]}"]);
        }));
      }
      // Await all futures
      await Future.wait(imageFutures);

      // Combine all results into single, chronological list
      logPort.send(
          ["debug", "Combining all results into single, chronological list"]);
      List<Uint8List> completedProcessedImages =
          allThumbnails.expand((x) => x).toList();

      logPort.send(["info", "Completed processing all images"]);
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
    return Future.value(null);
  }

  @override
  Future<List<UniversalComment>> getComments(
      String videoID, Document rawHtml, int page,
      [void Function(String body)? debugCallback]) async {
    // Private functions
    UniversalComment parseComment(
        Element comment, String videoID, bool hidden) {
      Element tempComment = comment.children.first;

      String? author = tempComment
          .querySelector('img[class="commentAvatarImg avatarTrigger"]')
          ?.attributes["title"];
      String? commentBody = tempComment
          .querySelector("div[class=commentMessage]")
          ?.children
          .first
          .text
          .trim();

      String? iD = tryParse(
          () => comment.className.split(" ")[2].replaceAll("commentTag", ""));

      UniversalComment parsedComment = UniversalComment(
          // Don't enforce null safety here
          // treat error below in scrapeFailMessage instead
          iD: iD ?? "null",
          videoID: videoID,
          author: author ?? "null",
          commentBody: commentBody ?? "null",
          hidden: hidden,
          plugin: this,
          // Sometimes the authorID is "unknown" (not a link) -> allow null
          authorID: tempComment
              .querySelector('a[class="userLink clearfix"]')
              ?.attributes["href"]
              ?.substring(7),
          countryID: null,
          orientation: null,
          profilePicture: tempComment
              .querySelector('img[class="commentAvatarImg avatarTrigger"]')
              ?.attributes["src"],
          ratingsPositiveTotal: null,
          ratingsNegativeTotal: null,
          ratingsTotal: tryParse(() => int.parse(
              tempComment.querySelector('span[class*="voteTotal"]')!.text)),
          commentDate: _convertStringToDateTime(
              tempComment.querySelector('div[class="date"]')?.text.trim()),
          replyComments: []);

      // This will also set the scrapeFailMessage if needed
      parsedComment.verifyScrapedData(
          codeName, testingMap["ignoreScrapedErrors"]["comments"]);

      if (iD == null || author == null || commentBody == null) {
        parsedComment.scrapeFailMessage =
            "Error: Failed to scrape critical variable(s):"
            "${iD == null ? " iD" : ""}"
            "${author == null ? " author" : ""}"
            "${commentBody == null ? " commentBody" : ""}";
      }

      return parsedComment;
    }

    /// Recursive function
    // TODO: Parallelize, but keep in mind that reply comments need to be able to be added to the prev top-level comment
    Future<List<UniversalComment>> parseCommentList(
        Element parent, String videoID, bool hidden) async {
      List<UniversalComment> parsedComments = [];
      for (Element child in parent.children) {
        // normal / top-level comment
        if (child.className.startsWith("commentBlock")) {
          parsedComments.add(parseComment(child, videoID, hidden));
        }
        // hidden comments
        else if (child.id.startsWith("commentParentShow")) {
          // recursively parse hidden comments
          parsedComments.addAll(await parseCommentList(child, videoID, true));
        } else if (child.className.startsWith("nestedBlock")) {
          // reply comments
          List<UniversalComment> tempReplies = [];
          try {
            for (Element subChild in child.children) {
              if (subChild.className == "clearfix") {
                // replies can also have hidden comments, ignore the show button and directly parse the hidden comment
                if (subChild.children.length != 1) {
                  tempReplies.add(parseComment(
                      subChild.children.last.children.first, videoID, hidden));
                } else {
                  tempReplies.add(
                      parseComment(subChild.children.first, videoID, hidden));
                }
                // some comments are hidden with another load more button
                // Load and add them to the same list
              } else if (subChild.className ==
                  "commentBtn showMore viewRepliesBtn upperCase") {
                // the url is included in the button
                final repliesResponse = await _performGetRequest(
                    Uri.parse(
                        "https://www.pornhub.com${subChild.attributes["data-ajax-url"]!}"),
                    headers: {"Cookie": "KEY=${_sessionCookies["KEY"]}"});
                Document rawReplyComments = parse(repliesResponse.body);

                tempReplies.addAll(await parseCommentList(
                    rawReplyComments
                        .querySelector('div[class^="nestedBlock"]')!,
                    videoID,
                    hidden));
              }
            }
          } catch (e, stacktrace) {
            logger.w("Error parsing reply comments: $e\n$stacktrace");
            parsedComments.last.replyComments = null;
            parsedComments.last.scrapeFailMessage =
                "Failed to scrape: replyComments";
          }
          // Add replyComments to previous top-level comment
          parsedComments.last.replyComments = tempReplies;
        }
        // Ignore all other element types
      }

      return parsedComments;
    }

    // pornhub allows to get all comments in one go -> return empty list on second page
    if (page > 1) {
      debugCallback?.call(
          "Pornhub allows to get all comments in one go -> return empty list on second page");
      return Future.value([]);
    }
    logger.i("Getting all comments for $videoID");

    // Each video has another id for the comments.
    // Get the video javascript
    String jscript =
        rawHtml.querySelector("#mobileContainer > script:nth-child(1)")!.text;
    Map<String, dynamic> jscriptMap = jsonDecode(
        jscript.substring(jscript.indexOf("{"), jscript.indexOf('};') + 1));
    // While the id is usually a number, to make sure, convert it to String
    String internalCommentsID =
        jscriptMap["playbackTracking"]["video_id"].toString();

    Uri commentsUri = Uri.parse("https://www.pornhub.com/comment/show"
        "?id=$internalCommentsID"
        // not sure what exactly the upper limit is, but pornhub doesn't seem to throw an error
        "&limit=9999"
        // TODO: Implement comment sorting types
        "&popular=1"
        // This is required
        "&what=video"
        "&token=${_sessionCookies["token"]}");
    logger.d("Requesting comments URI: $commentsUri");
    final response = await _performGetRequest(commentsUri,
        headers: {"Cookie": "KEY=${_sessionCookies["KEY"]}"});

    if (response.statusCode != 200) {
      throw ("Http error for $commentsUri: ${response.statusCode} - ${response.reasonPhrase}");
    }
    debugCallback?.call(response.body);

    Document rawComments = parse(response.body);

    List<UniversalComment> parsedComments = await parseCommentList(
        rawComments.querySelector("#cmtContent")!, videoID, false);

    return parsedComments;
  }

  @override
  Future<List<UniversalVideoPreview>> getVideoSuggestions(
      String videoID, Document rawHtml, int page,
      [void Function(String body)? debugCallback]) async {
    // Pornhub doesn't allow loading more suggestions
    if (page > 1) {
      debugCallback?.call("Pornhub doesn't allow loading more suggestions");
      return Future.value([]);
    }
    debugCallback?.call(rawHtml.outerHtml);
    // Filter out ads and non-video results
    return await _parseVideoList(rawHtml
        .querySelector("#relatedVideos")!
        .querySelectorAll('li[data-video-vkey]')
        .toList());
  }

  @override
  Future<Uri?> getAuthorUriFromID(String authorID) async {
    logger.i("Getting author page URL of: $authorID");

    // Assume every author is a channel at first
    Uri authorPageLink = Uri.parse("$_channelEndpoint$authorID");

    logger.d("Checking http status of: $authorPageLink");
    var response = await client.head(authorPageLink,
        headers: {"Cookie": "KEY=${_sessionCookies["KEY"]}"});
    if (response.statusCode != 200) {
      // Try again for model author type
      authorPageLink = Uri.parse("$_modelEndpoint$authorID");

      logger.d(
          "Received non 200 status code -> Requesting model page: $authorPageLink");
      response = await client.head(authorPageLink,
          headers: {"Cookie": "KEY=${_sessionCookies["KEY"]}"});

      // make sure pornhub didn't redirect to the all pornstars page
      if (response.body.contains("Most Popular Pornstars And Models")) {
        authorPageLink = Uri.parse("$_pornstarEndpoint$authorID");
        logger.d("Detected redirect to all pornstars page, trying again with "
            "pornstar endpoint: $authorPageLink");
        response = await client.head(authorPageLink,
            headers: {"Cookie": "KEY=${_sessionCookies["KEY"]}"});
      }

      if (response.statusCode != 200) {
        logger.e(
            "Error downloading html (tried channel, model, pornstar): ${response.statusCode} - ${response.reasonPhrase}");
        throw Exception(
            "Error downloading html (tried channel, model, pornstar): ${response.statusCode} - ${response.reasonPhrase}");
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
    var response = await _performGetRequest(authorPageLink,
        // Mobile video image previews are higher quality
        headers: {"Cookie": "accessAgeDisclaimerPH=1; platform=mobile"});
    if (response.statusCode != 200) {
      // Try again for model author type
      authorPageLink = Uri.parse("$_modelEndpoint$authorID");
      logger.d(
          "Received non 200 status code -> Requesting model page: $authorPageLink");
      response = await _performGetRequest(authorPageLink,
          // Mobile video image previews are higher quality
          headers: {"Cookie": "accessAgeDisclaimerPH=1; platform=mobile"});

      // make sure pornhub didn't redirect to the all pornstars page
      if (response.body.contains("Most Popular Pornstars And Models")) {
        authorPageLink = Uri.parse("$_pornstarEndpoint$authorID");
        logger.d("Detected redirect to all pornstars page, trying again with "
            "pornstar endpoint: $authorPageLink");
        response = await _performGetRequest(authorPageLink,
            // Mobile video image previews are higher quality
            headers: {"Cookie": "accessAgeDisclaimerPH=1; platform=mobile"});
      }

      if (response.statusCode != 200) {
        logger.e(
            "Error downloading html (tried channel, model, pornstar): ${response.statusCode} - ${response.reasonPhrase}");
        throw Exception(
            "Error downloading html (tried channel, model, pornstar): ${response.statusCode} - ${response.reasonPhrase}");
      }
    }

    debugCallback?.call(response.body);

    Document pageHtml = parse(response.body);

    Map<String, String>? advancedDescription;
    try {
      List<Element>? descriptionElements = pageHtml
          .querySelector('div[class="readMoreDrawerContentTable"]')
          ?.children;
      // Channels don't have advanced descriptions
      if (descriptionElements != null) {
        advancedDescription = {};
        for (Element element in descriptionElements) {
          String key = element.text.split(":").first.trim();
          // This element needs special parsing if it has a "to Present" at the end
          if (key == "Career Start and End") {
            advancedDescription[key] = element.text
                .split(":")
                .last
                .trim()
                .replaceAll("\n", "")
                .replaceAll(
                    "to                                                Present",
                    "to Present");
          } else {
            advancedDescription[key] = element.text.split(":").last.trim();
          }
        }
      }
    } catch (e, stacktrace) {
      logger.w("Error parsing advanced description: $e\n$stacktrace");
    }

    String? authorName;
    String? description;
    try {
      if (pageHtml.querySelector('div[class="readMoreDrawerContentInner"]') !=
          null) {
        logger.d("Pornstar or model page detected");
        authorName = pageHtml
            .querySelector('span[class="title js-profile-header-title"]')!
            .text
            .trim();
        // If description is a "Featured in" block, add it to advanced description instead
        if (pageHtml
                .querySelector('span[class="readMoreDrawerContentTitle"]')
                ?.text
                .trim()
                .startsWith("Featured in") ??
            false) {
          logger.i(
              "Detected \"Featured in\" block. Adding to advanced description instead of normal");
          advancedDescription ??= {};
          for (Element element in pageHtml
              .querySelector('div[class="readMoreDrawerContentText"]')!
              .children) {
            advancedDescription["Featured in ${element.text.trim()}"] =
                element.attributes["href"] != null
                    ? "https://www.pornhub.com${element.attributes["href"]!}"
                    : "";
          }
          // Normal "About" description
        } else {
          description = pageHtml
              .querySelector('div[class="readMoreDrawerContentText"]')
              ?.text
              .trim();
        }
      } else {
        authorName =
            pageHtml.querySelector('div[class="channelName"]')!.text.trim();
        description = pageHtml
            .querySelector('div[class="wrapper"]')
            ?.text
            .replaceAll("About:", "")
            .trim();
      }
      if (description != null) {
        description = HtmlUnescape().convert(description);
      }
    } catch (e, stacktrace) {
      if (authorName == null) {
        logger.w("Error parsing author name: $e\n$stacktrace");
        rethrow;
      } else {
        logger.w("Error parsing simple description: $e\n$stacktrace");
      }
    }

    Map<String, Uri>? externalLinks;
    try {
      List<Element>? links =
          pageHtml.querySelector('ul[class="socialList"]')?.children;
      if (links != null) {
        externalLinks = {};
        for (Element link in links) {
          externalLinks[link.children.first.text.trim()] =
              Uri.parse(link.children.first.attributes["href"]!);
        }
      } else {
        List<Element>? links =
            pageHtml.querySelectorAll('a[class="descriptionLink"]');
        if (links.isNotEmpty) {
          externalLinks = {};
          externalLinks[links.first.text.trim()] =
              Uri.parse(links.first.attributes["href"]!);
          externalLinks["Channel owner page"] = Uri.parse(
              "https://www.pornhub.com${links.last.attributes["href"]!}");
        }
      }
    } catch (e, stacktrace) {
      logger.w("Error parsing external links: $e\n$stacktrace");
    }

    int? viewsTotal;
    int? subscribers;
    int? rank;
    int? videosTotal;
    try {
      String? ranks = pageHtml
          .querySelector('button[class*="mobileRanksButton"]')
          ?.text
          .trim();
      if (ranks != null) {
        List<String> ranksFirst = ranks.split("Model Rank");
        rank = _convertHumanReadableStringToInt(ranksFirst.first.trim());
        List<String> ranksSecond = ranksFirst.last.split("Views");
        viewsTotal = _convertHumanReadableStringToInt(ranksSecond.first.trim());
        subscribers = _convertHumanReadableStringToInt(
            ranksSecond.last.split("Subscribers").first.trim());
      } else {
        List<Element>? stats = pageHtml
            .querySelector('div[class="channelStats clearfix"]')
            ?.children
            .first
            .children;

        if (stats != null) {
          rank = _convertHumanReadableStringToInt(
              stats[0].text.replaceAll("Rank", "").trim());
          subscribers = _convertHumanReadableStringToInt(
              stats[1].text.replaceAll("Subscribers", "").trim());
          videosTotal = _convertHumanReadableStringToInt(
              stats[2].text.replaceAll("Videos", "").trim());
          viewsTotal = _convertHumanReadableStringToInt(
              stats[3].text.replaceAll("Views", "").trim());
        }
      }
    } catch (e, stacktrace) {
      logger.w("Error parsing viewsTotal/videosTotal/subscribers/currentRating:"
          " $e\n$stacktrace");
    }

    String? thumbnail;
    try {
      thumbnail = pageHtml.querySelector("#getAvatar")?.attributes["src"];
      // If still null, try again for channel pages
      thumbnail ??= pageHtml
          .querySelector('div[class="avatar"]')
          ?.children
          .first
          .attributes["src"];
    } catch (e, stacktrace) {
      logger.w("Error parsing thumbnail: $e\n$stacktrace");
    }

    String? banner;
    try {
      // imageWrapper for models, cover for channels
      banner = pageHtml
          .querySelector(".imageWrapper, .cover")
          ?.children
          .first
          .attributes["src"];
    } catch (e, stacktrace) {
      logger.w("Error parsing banner: $e\n$stacktrace");
    }

    UniversalAuthorPage authorPage = UniversalAuthorPage(
      iD: authorID,
      name: authorName,
      plugin: this,
      avatar: thumbnail,
      banner: banner,
      // Pornhub doesn't have aliases
      aliases: null,
      description: description,
      advancedDescription: advancedDescription,
      externalLinks: externalLinks,
      viewsTotal: viewsTotal,
      videosTotal: videosTotal,
      subscribers: subscribers,
      rank: rank,
      rawHtml: pageHtml,
    );

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

    logger.d("Requesting $authorPageLink/videos?page=$page");
    var response =
        await _performGetRequest(Uri.parse("$authorPageLink/videos?page=$page"),
            // Mobile video image previews are higher quality
            headers: {"Cookie": "platform=mobile"});
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
    return await _parseVideoList(
        resultHtml.querySelectorAll('ul[class*="videoList"]').last.children,
        true);
  }
}