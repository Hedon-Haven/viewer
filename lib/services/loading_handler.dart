import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:html/dom.dart';
import 'package:linkify/linkify.dart';

import '/services/database_manager.dart';
import '/services/plugin_manager.dart';
import '/utils/global_vars.dart';
import '/utils/plugin_interface/plugin_interface.dart';
import '/utils/universal_formats.dart';

/// Handles various loading sections, including search and comments
class LoadingHandler {
  Map<PluginInterface, int> resultsPageCounter = {};
  int commentsPageCounter = 0;
  int videoSuggestionsPageCounter = 0;
  int authorVideosPageCounter = 0;

  Map<PluginInterface, Map<String, List<dynamic>>> resultsIssues = {};
  Map<String, List<dynamic>> commentsIssues = {};
  Map<String, List<dynamic>> videoSuggestionsIssues = {};
  Map<String, List<dynamic>> authorVideosIssues = {};

  Future<List<UniversalVideoPreview>?> getSearchResults(
      UniversalSearchRequest searchRequest,
      [List<UniversalVideoPreview>? previousResults,
      List<PluginInterface> plugins = const []]) async {
    // read plugins from settings if not passed to this function
    if (plugins.isEmpty) {
      plugins = await PluginManager.getProviders(ProviderType.searchResults);
      // This should not happen
      if (plugins.isEmpty) {
        logger.e(
            "No results providers passed to getSearchResults or configured in settings");
        return null;
      }
    }

    return _getResults(plugins, searchRequest, previousResults);
  }

  Future<List<UniversalVideoPreview>?> getHomePages(
      List<UniversalVideoPreview>? previousResults,
      [List<PluginInterface> plugins = const []]) async {
    // read plugins from settings if not passed to this function
    if (plugins.isEmpty) {
      // if search request empty -> homepage request
      plugins = await PluginManager.getProviders(ProviderType.homepage);
      // This should not happen
      if (plugins.isEmpty) {
        logger.e(
            "No results providers passed to getHomePages or configured in settings");
        return null;
      }
    }

    return _getResults(plugins, null, previousResults);
  }

  /// Pass empty searchRequest to get Homepage results
  Future<List<UniversalVideoPreview>?> _getResults(
      List<PluginInterface> plugins,
      UniversalSearchRequest? searchRequest,
      List<UniversalVideoPreview>? previousResults) async {
    List<UniversalVideoPreview>? combinedResults = [];
    if (previousResults != null) {
      combinedResults = previousResults;
    }

    // Check if connected to the internet
    if ((await (Connectivity().checkConnectivity()))
        .contains(ConnectivityResult.none)) {
      logger.w("No internet connection, canceling search");
      return null;
    } else {
      logger.d("Internet connection present");
    }

    if (searchRequest != null) {
      // After internet and plugin check have passed, add request to search history
      addToSearchHistory(searchRequest, plugins);
    }

    // if previousResults is empty -> new search -> populate pluginPageCounter
    if (previousResults == null) {
      logger.i("No prev results, populating pluginPageCounter");
      for (var plugin in plugins) {
        resultsPageCounter[plugin] = searchRequest == null
            ? plugin.initialHomePage
            : plugin.initialSearchResultsPage;
      }
    }

    // Search each plugin for results and store them in a map
    Map<String, List<UniversalVideoPreview>> pluginResults = {};
    for (var plugin in plugins) {
      // Init resultsIssues if needed
      if (!resultsIssues.containsKey(plugin)) {
        resultsIssues[plugin] = {
          // Critical means issue with entire request
          "Critical": [],
          // Error means a uvp failed to scrape completely and cannot be shown to user
          "Error": [],
          // Warning means a uvp partially failed scrape but can still be shown to user
          "Warning": []
        };
      }
      if (resultsPageCounter[plugin] != -1) {
        List<UniversalVideoPreview>? results;
        try {
          if (searchRequest == null) {
            logger.i("Search request is null, getting homepage");
            results = await plugin.getHomePage(resultsPageCounter[plugin]!);
          } else {
            logger.i("Search request is not null, getting search results");
            results = await plugin.getSearchResults(
                searchRequest, resultsPageCounter[plugin]!);
          }
        } catch (e, stacktrace) {
          switch (e.runtimeType.toString()) {
            case "AgeGateException":
              logger.e("Age gate detected for results from "
                  "${plugin.codeName}: $e\n$stacktrace");
              resultsIssues[plugin]!["Critical"]!.add(
                  "Age gate encountered. Try setting a proxy in settings / privacy");
            case "BannedCountry":
              logger.e("Banned country detected for results from "
                  "${plugin.codeName}: $e\n$stacktrace");
              resultsIssues[plugin]!["Critical"]!.add(
                  "Banned country encountered. Try setting a proxy in settings / privacy");
            case "UnreachableException":
              logger.e(
                  "Couldn't connect to ${plugin.serviceUrl} to get search results:"
                  " $e\n$stacktrace");
              resultsIssues[plugin]!["Critical"]!.add(
                  "Couldn't connect to ${plugin.serviceUrl} to get search results");
            case "NotFoundException":
              logger.e(
                  "No results from ${plugin.codeName}. Soft 404, NOT adding to resultsIssuesMap");
              results = [];
            default:
              logger.e("Error getting search results from ${plugin.codeName}:"
                  " $e\n$stacktrace");
              resultsIssues[plugin]!["Critical"]!.add("$e\n$stacktrace");
          }
        }

        if (results != null) {
          pluginResults[plugin.codeName] = results;
          if (results.isNotEmpty) {
            logger.i(
                "Got results from ${plugin.codeName} for page ${resultsPageCounter[plugin]}");
            resultsPageCounter[plugin] = resultsPageCounter[plugin]! + 1;
          } else {
            if (previousResults == null) {
              logger.w("No results at all from ${plugin.codeName}");
            } else {
              logger.w("No more results from ${plugin.codeName}");
            }
            resultsPageCounter[plugin] = -1;
          }
        }
      }
    }

    if (pluginResults.isEmpty) {
      logger.w("No results from any enabled providers");
      combinedResults = null;
    } else {
      // Combine individual plugin results into one list in a round-robin fashion
      bool resultsRemaining = true;
      int currentIndex = 0;
      while (resultsRemaining) {
        resultsRemaining = false;
        for (var plugin in plugins) {
          // Check if the plugin has results and if there is a result at the current index
          if (pluginResults.containsKey(plugin.codeName) &&
              pluginResults[plugin.codeName]!.length > currentIndex) {
            // Don't show to user and add to error list
            if (pluginResults[plugin.codeName]![currentIndex]
                        .scrapeFailMessage !=
                    null &&
                (pluginResults[plugin.codeName]![currentIndex]
                        .scrapeFailMessage
                        ?.startsWith("Error") ??
                    false)) {
              resultsIssues[plugin]!["Error"]!
                  .add(pluginResults[plugin.codeName]![currentIndex]);
            } else {
              // Add to warning list
              if (pluginResults[plugin.codeName]![currentIndex]
                      .scrapeFailMessage !=
                  null) {
                resultsIssues[plugin]!["Warning"]!
                    .add(pluginResults[plugin.codeName]![currentIndex]);
              }
              // Show to user
              combinedResults
                  .add(pluginResults[plugin.codeName]![currentIndex]);
              resultsRemaining = true;
            }
          }
        }
        currentIndex++;
      }
    }

    // remove plugins without issues from the map
    for (var plugin in plugins) {
      if (resultsIssues[plugin]!["Critical"]!.isEmpty &&
          resultsIssues[plugin]!["Error"]!.isEmpty &&
          resultsIssues[plugin]!["Warning"]!.isEmpty) {
        resultsIssues.remove(plugin);
      }
    }

    logger.d("Prev res amount: ${previousResults?.length}");
    logger.d("New res amount: ${combinedResults?.length}");
    return combinedResults;
  }

  Future<List<UniversalSearchRequest>?> getSearchSuggestions(
      String query) async {
    // Check if connected to the internet
    if ((await (Connectivity().checkConnectivity()))
        .contains(ConnectivityResult.none)) {
      logger.w("No internet connection, canceling search");
      return null;
    } else {
      logger.d("Internet connection present");
    }

    // check if there are any enabled search suggestions providers
    if ((await PluginManager.getProviders(ProviderType.searchSuggestions))
        .isEmpty) {
      logger.e("No search suggestions providers configured in settings");
      return null;
    }

    // Simultaneously start queries for all enabled plugins
    List<Future<List<String>>> futures = [];
    for (var plugin
        in await PluginManager.getProviders(ProviderType.searchSuggestions)) {
      futures.add(plugin.getSearchSuggestions(query));
    }

    // Wait for all queries to finish
    List<List<String>?> allResults = [];
    for (var future in futures) {
      try {
        allResults.add(await future);
      } catch (e, stacktrace) {
        print(
            "Failed to get search suggestions from a plugin: $e\n$stacktrace");
        allResults.add(null);
      }
    }

    // Check if all queries failed
    if (allResults.every((element) => element == null)) {
      logger.w("All search suggestion queries failed");
      return null;
    }

    // Count the frequency of each suggestion (case insensitive)
    Map<String, int> frequency = {};
    for (var list in allResults) {
      if (list == null) continue;
      for (var suggestion in list) {
        String lowerSuggestion = suggestion.toLowerCase();
        frequency[lowerSuggestion] = (frequency[lowerSuggestion] ?? 0) + 1;
      }
    }

    // Separate singular suggestions from frequent ones
    List<String> frequentSuggestions = [];
    List<List<String>> singularSuggestions =
        List.generate(allResults.length, (_) => []);
    for (int i = 0; i < allResults.length; i++) {
      if (allResults[i] == null) continue;
      for (var suggestion in allResults[i]!) {
        String lowerSuggestion = suggestion.toLowerCase();
        if (frequency[lowerSuggestion]! > 1) {
          if (!frequentSuggestions.contains(lowerSuggestion)) {
            frequentSuggestions.add(lowerSuggestion);
          }
        } else {
          singularSuggestions[i].add(lowerSuggestion);
        }
      }
    }

    // Sort frequent suggestions by frequency (most common first)
    frequentSuggestions.sort((a, b) => frequency[b]!.compareTo(frequency[a]!));

    // Interleave singular suggestions in round-robin fashion
    List<String> finalList = List.from(frequentSuggestions);
    bool singularsRemaining = true;
    int i = 0;
    while (singularsRemaining) {
      singularsRemaining = false;
      for (var list in singularSuggestions) {
        if (i < list.length) {
          finalList.add(list[i]);
          singularsRemaining = true;
        }
      }
      i++;
    }

    // Capitalize the first letter of each suggestion directly in the final list
    finalList =
        finalList.map((s) => s[0].toUpperCase() + s.substring(1)).toList();

    // Convert the list to a list of UniversalSearchRequests
    return finalList
        .map((s) => UniversalSearchRequest(searchString: s))
        .toList();
  }

  Future<List<UniversalComment>?> getCommentResults(
      PluginInterface plugin, String videoID, Document rawHtml,
      [List<UniversalComment>? previousResults]) async {
    List<UniversalComment>? combinedResults = [];

    // init commentsIssues if needed
    if (commentsIssues.isEmpty) {
      commentsIssues = {
        // Critical means issue with entire request
        "Critical": [],
        // Error means a comment failed to scrape completely and cannot be shown to user
        "Error": [],
        // Warning means a comment partially failed scrape but can still be shown to user
        "Warning": []
      };
    }

    if (previousResults != null) {
      combinedResults = previousResults;
    }

    // Check if connected to the internet
    if ((await (Connectivity().checkConnectivity()))
        .contains(ConnectivityResult.none)) {
      logger.w("No internet connection, canceling comment request");
      return null;
    }

    // if previousResults is empty -> new search -> set pluginPageCounter
    if (previousResults == null) {
      commentsPageCounter = plugin.initialCommentsPage;
      logger.i(
          "No prev comment results, setting commentsPageCounter to $commentsPageCounter");
    }

    List<UniversalComment>? newResults;
    if (commentsPageCounter != -1) {
      logger.i(
          "Getting comments from ${plugin.codeName} for page $commentsPageCounter");
      try {
        newResults =
            await plugin.getComments(videoID, rawHtml, commentsPageCounter);
        logger.i(
            "Got ${newResults.length} comments from ${plugin.codeName} for page $commentsPageCounter");
      } catch (e, stacktrace) {
        switch (e.runtimeType.toString()) {
          case "AgeGateException":
            logger.e("Age gate detected for results from "
                "${plugin.codeName}: $e\n$stacktrace");
            commentsIssues["Critical"]!.add(
                "Age gate encountered. Try setting a proxy in settings / privacy");
          case "BannedCountry":
            logger.e("Banned country detected for results from "
                "${plugin.codeName}: $e\n$stacktrace");
            commentsIssues["Critical"]!.add(
                "Banned country encountered. Try setting a proxy in settings / privacy");
          case "UnreachableException":
            logger.e(
                "Couldn't connect to ${plugin.serviceUrl} to get comments: $e\n$stacktrace");
            commentsIssues["Critical"]!.add(
                "Couldn't connect to ${plugin.serviceUrl} to get comments");
          case "NotFoundException":
            logger.e(
                "No comments from ${plugin.codeName}. Soft 404, NOT adding to commentsIssuesMap");
            newResults = [];
          default:
            logger.e("Error getting comments from ${plugin.codeName}:"
                " $e\n$stacktrace");
            commentsIssues["Critical"]!.add("$e\n$stacktrace");
        }
      }
      if (newResults?.isNotEmpty ?? false) {
        List<UniversalComment> filteredComments = [];

        /// To show correct amount of comments that were filtered by the app
        int totalValidComments = newResults!.length;
        for (var comment in newResults) {
          // Don't show to user
          if (comment.scrapeFailMessage != null &&
              (comment.scrapeFailMessage?.startsWith("Error") ?? false)) {
            commentsIssues["Error"]!.add(comment);
            // Failure to scrape != filtered comment
            // -> reduce total amount of to-be filtered comments
            totalValidComments--;
            continue;
          }
          if (comment.scrapeFailMessage != null) {
            commentsIssues["Warning"]!.add(comment);
          }

          if ((await sharedStorage.getBool("comments_hide_hidden"))!) {
            if (comment.hidden) {
              logger.d(
                  "Filtered comment: ${comment.iD}; Cause: hidden by platform");
              continue;
            }
          } else if ((await sharedStorage.getBool("comments_hide_negative"))!) {
            if ((comment.ratingsNegativeTotal ?? 0) < 0) {
              logger
                  .d("Filtered comment: ${comment.iD}; Cause: negative rating");
              continue;
            }
          } else if ((await sharedStorage.getBool("comments_filter_links"))!) {
            if (linkify(comment.commentBody)
                .any((element) => element is LinkableElement)) {
              logger.d("Filtered comment: ${comment.iD}; Cause: contains link");
              continue;
            }
          } else if ((await sharedStorage
              .getBool("comments_filter_non_ascii"))!) {
            // Unicode is a superset of ASCII
            // -> Unicode 0-127 is equivalent to ASCII
            if (comment.commentBody.runes.any((code) => code > 127)) {
              logger.d(
                  "Filtered comment: ${comment.iD}; Cause: contains non-ascii text");
              continue;
            } else {
              logger.d("Did not filter: ${comment.iD}");
            }
          }
          filteredComments.add(comment);
        }
        logger.d(
            "Filtered ${totalValidComments - filteredComments.length} comments");
        newResults = filteredComments;

        combinedResults.addAll(newResults);
        logger.i("Added ${newResults.length} comments");
        commentsPageCounter++;
      } else if (newResults?.isEmpty ?? false) {
        if (previousResults == null) {
          logger.w("No comments found at all for $videoID");
        } else {
          logger.i("No more comments found for $videoID");
        }
        commentsPageCounter = -1;
      } else {
        // In case of error
        combinedResults = null;
      }
    }

    // delete empty lists from issues map
    commentsIssues.removeWhere((key, value) => value.isEmpty);

    logger.d("Prev comment res amount: ${previousResults?.length}");
    logger.d("New comment res amount: ${combinedResults?.length}");
    return combinedResults;
  }

  Future<List<UniversalVideoPreview>?> getVideoSuggestions(
      PluginInterface plugin, String videoID, Document rawHtml,
      [List<UniversalVideoPreview>? previousResults]) async {
    // init videoSuggestionsIssues if needed
    if (videoSuggestionsIssues.isEmpty) {
      videoSuggestionsIssues = {
        // Critical means issue with entire request
        "Critical": [],
        // Error means a video suggestion failed to scrape completely and cannot be shown to user
        "Error": [],
        // Warning means a video suggestion partially failed scrape but can still be shown to user
        "Warning": []
      };
    }

    List<UniversalVideoPreview>? combinedResults = [];
    if (previousResults != null) {
      combinedResults = previousResults;
    }

    // Check if connected to the internet
    if ((await (Connectivity().checkConnectivity()))
        .contains(ConnectivityResult.none)) {
      logger.w("No internet connection, canceling video suggestions request");
      return [];
    }

    // if previousResults is empty -> new search -> set pluginPageCounter
    if (previousResults == null) {
      videoSuggestionsPageCounter = plugin.initialVideoSuggestionsPage;
      logger.i(
          "No prev video suggestions results, setting videoSuggestionsPageCounter to $videoSuggestionsPageCounter");
    }

    List<UniversalVideoPreview>? newResults;
    if (videoSuggestionsPageCounter != -1) {
      logger.i(
          "Getting video suggestions from ${plugin.codeName} for page $videoSuggestionsPageCounter");
      try {
        newResults = await plugin.getVideoSuggestions(
            videoID, rawHtml, videoSuggestionsPageCounter);
        logger.i(
            "Got ${newResults.length} video suggestions from ${plugin.codeName} for page $videoSuggestionsPageCounter");
      } catch (e, stacktrace) {
        switch (e.runtimeType.toString()) {
          case "AgeGateException":
            logger.e("Age gate detected for results from "
                "${plugin.codeName}: $e\n$stacktrace");
            videoSuggestionsIssues["Critical"]!.add(
                "Age gate encountered. Try setting a proxy in settings / privacy");
          case "BannedCountry":
            logger.e("Banned country detected for results from "
                "${plugin.codeName}: $e\n$stacktrace");
            videoSuggestionsIssues["Critical"]!.add(
                "Banned country encountered. Try setting a proxy in settings / privacy");
          case "UnreachableException":
            logger.e(
                "Couldn't connect to ${plugin.serviceUrl} get video suggestions: "
                "$e\n$stacktrace");
            videoSuggestionsIssues["Critical"]!.add(
                "Couldn't connect to ${plugin.serviceUrl} to get video suggestions");
          case "NotFoundException":
            logger.e(
                "No video suggestions from ${plugin.codeName}. Soft 404, NOT adding to commentsIssuesMap");
            newResults = [];
          default:
            logger.e("Error getting video suggesting from ${plugin.codeName}:"
                " $e\n$stacktrace");
            videoSuggestionsIssues["Critical"]!.add("$e\n$stacktrace");
        }
      }
      if (newResults?.isNotEmpty ?? false) {
        for (var video in newResults!) {
          if (video.scrapeFailMessage != null &&
              (video.scrapeFailMessage?.startsWith("Error") ?? false)) {
            videoSuggestionsIssues["Error"]!.add(video);
            continue;
          } else if (video.scrapeFailMessage != null) {
            videoSuggestionsIssues["Warning"]!.add(video);
          }
          combinedResults.add(video);
        }
        logger.i("Added ${newResults.length} video suggestions");
        videoSuggestionsPageCounter++;
      } else {
        if (newResults?.isEmpty ?? false) {
          if (previousResults == null) {
            logger.w("No video suggestions found at all for $videoID");
          } else {
            logger.i("No more video suggestions found for $videoID");
          }
        } else {
          // Error
          combinedResults = null;
        }
        videoSuggestionsPageCounter = -1;
      }
    }

    // delete empty lists from issues map
    videoSuggestionsIssues.removeWhere((key, value) => value.isEmpty);

    logger.d("Prev video suggestions amount: ${previousResults?.length}");
    logger.d("New video suggestions amount: ${combinedResults?.length}");
    return combinedResults;
  }

  Future<List<UniversalVideoPreview>?> getAuthorVideos(
      PluginInterface plugin, String authorID,
      [List<UniversalVideoPreview>? previousResults]) async {
    // init authorVideosIssues if needed
    if (authorVideosIssues.isEmpty) {
      authorVideosIssues = {
        // Critical means issue with entire request
        "Critical": [],
        // Error means a video preview failed to scrape completely and cannot be shown to user
        "Error": [],
        // Warning means a video preview partially failed scrape but can still be shown to user
        "Warning": []
      };
    }

    List<UniversalVideoPreview>? combinedResults = previousResults;
    combinedResults ??= [];

    // Check if connected to the internet
    if ((await (Connectivity().checkConnectivity()))
        .contains(ConnectivityResult.none)) {
      logger.w("No internet connection, canceling author videos request");
      return [];
    }

    // if previousResults is empty -> new search -> set pluginPageCounter
    if (previousResults == null) {
      authorVideosPageCounter = plugin.initialAuthorVideosPage;
      logger.i(
          "No prev author video results, setting initialAuthorVideosPage to $authorVideosPageCounter");
    }

    List<UniversalVideoPreview>? newResults;
    if (authorVideosPageCounter != -1) {
      logger.i(
          "Getting author video results from ${plugin.codeName} for page $authorVideosPageCounter");
      try {
        newResults =
            await plugin.getAuthorVideos(authorID, authorVideosPageCounter);
        logger.i(
            "Got ${newResults.length} author videos from ${plugin.codeName} for page $authorVideosPageCounter");
      } catch (e, stacktrace) {
        switch (e.runtimeType.toString()) {
          case "AgeGateException":
            logger.e("Age gate detected for results from "
                "${plugin.codeName}: $e\n$stacktrace");
            authorVideosIssues["Critical"]!.add(
                "Age gate encountered. Try setting a proxy in settings / privacy");
          case "BannedCountry":
            logger.e("Banned country detected for results from "
                "${plugin.codeName}: $e\n$stacktrace");
            authorVideosIssues["Critical"]!.add(
                "Banned country encountered. Try setting a proxy in settings / privacy");
          case "UnreachableException":
            logger.e(
                "Couldn't connect to ${plugin.serviceUrl} to get author videos: "
                "$e\n$stacktrace");
            authorVideosIssues["Critical"]!.add(
                "Couldn't connect to ${plugin.serviceUrl} to get author videos");
          default:
            logger.e("Error getting author videos from ${plugin.codeName}:"
                " $e\n$stacktrace");
            authorVideosIssues["Critical"]!.add("$e\n$stacktrace");
        }
      }
      if (newResults?.isNotEmpty ?? false) {
        for (var video in newResults!) {
          if (video.scrapeFailMessage != null &&
              (video.scrapeFailMessage?.startsWith("Error") ?? false)) {
            authorVideosIssues["Error"]!.add(video);
            continue;
          } else if (video.scrapeFailMessage != null) {
            authorVideosIssues["Warning"]!.add(video);
          }
          combinedResults.add(video);
        }
        logger.i("Added ${newResults.length} author video");
        authorVideosPageCounter++;
      } else {
        if (newResults?.isEmpty ?? false) {
          if (previousResults == null) {
            logger.w("No author videos found at all for $authorID");
          } else {
            logger.i("No more author videos found for $authorID");
          }
        } else {
          // Error
          combinedResults = null;
        }
        authorVideosPageCounter = -1;
      }
    }

    // delete empty lists from issues map
    authorVideosIssues.removeWhere((key, value) => value.isEmpty);

    logger.d("Prev author videos amount: ${previousResults?.length}");
    logger.d("New author videos amount: ${combinedResults?.length}");
    return combinedResults;
  }
}
