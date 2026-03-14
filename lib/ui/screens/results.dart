import 'package:flutter/material.dart';

import '/services/loading_handler.dart';
import '/services/plugin_manager.dart';
import '/ui/screens/scraping_report.dart';
import '/ui/screens/search.dart';
import '/ui/screens/video_list.dart';
import '/utils/global_vars.dart';
import '/utils/universal_formats.dart';
import 'filters/filters.dart';

class ResultsScreen extends StatefulWidget {
  Future<List<UniversalVideoPreview>?> videoResults;
  final LoadingHandler loadingHandler;
  UniversalSearchRequest searchRequest;

  ResultsScreen(
      {super.key,
      required this.videoResults,
      required this.searchRequest,
      required this.loadingHandler});

  @override
  State<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends State<ResultsScreen> {
  Key videoListKey = UniqueKey();
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    widget.videoResults.whenComplete(() {
      logger.d("ResultsIssues Map: ${widget.loadingHandler.resultsIssues}");
      // Update the scraping report button
      setState(() => isLoading = false);
    });
  }

  Future<List<UniversalVideoPreview>?> loadMoreResults() async {
    setState(() => isLoading = true);
    logger.i("Loading additional results");
    var results = widget.loadingHandler
        .getSearchResults(widget.searchRequest, await widget.videoResults);
    // Updates the scraping report button
    setState(() => isLoading = false);
    return results;
  }

  void popAllScreens() {
    // Silently remove SearchScreen from the stack (no animation)
    Navigator.of(context).removeRouteBelow(ModalRoute.of(context)!);
    // Pop ResultsScreen with a single reverse animation directly to home
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
        canPop: false,
        onPopInvoked: (goingToPop) {
          if (!goingToPop) {
            popAllScreens();
          }
        },
        child: Scaffold(
            appBar: AppBar(
              automaticallyImplyLeading: false,
              titleSpacing: 0,
              title: Padding(
                  padding: const EdgeInsets.only(left: 15, bottom: 6, top: 1),
                  child: GestureDetector(
                    onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => SearchScreen(
                              previousSearch: widget.searchRequest),
                        )),
                    child: Material(
                      borderRadius: const BorderRadius.horizontal(
                          left: Radius.circular(25),
                          right: Radius.circular(25)),
                      color: Theme.of(context).colorScheme.surfaceVariant,
                      child: Row(children: [
                        IconButton(
                            icon: const Icon(Icons.arrow_back),
                            onPressed: () => popAllScreens()),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(right: 15),
                            child: Text(
                              widget.searchRequest.searchString,
                              overflow: TextOverflow.clip,
                              textAlign: TextAlign.left,
                              style: const TextStyle(fontSize: 16),
                            ),
                          ),
                        ),
                      ]),
                    ),
                  )),
              actions: [
                if (widget.loadingHandler.resultsIssues.isNotEmpty &&
                    !isLoading)
                  IconButton(
                      icon: Icon(
                          color: Theme.of(context).colorScheme.error,
                          Icons.error_outline),
                      onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (context) => ScrapingReportScreen(
                                      multiProviderMap:
                                          widget.loadingHandler.resultsIssues)))
                          .whenComplete(() => setState(() {}))),
                IconButton(
                  color: Theme.of(context).colorScheme.primary,
                  icon: const Icon(Icons.filter_alt),
                  onPressed: () {
                    Navigator.of(context)
                        .push(MaterialPageRoute(
                            builder: (context) => FilterScreen(
                                searchRequest: widget.searchRequest)))
                        .then((value) {
                      if (value != null) {
                        logger.i("Getting new results with new filters");
                        widget.searchRequest = value;
                        widget.videoResults = widget.loadingHandler
                            .getSearchResults(widget.searchRequest);
                        // Force rebuild of VideoList by changing the key and forcing flutter to create a new VideoList
                        setState(() => videoListKey = UniqueKey());
                      } else {
                        logger
                            .i("Filters not changed, not getting new results");
                      }
                    });
                  },
                ),
              ],
            ),
            body: CustomScrollView(slivers: [
              VideoList(
                  scrollController: ScrollController(),
                  // This key is needed to completely rebuild the VideoList widget
                  key: videoListKey,
                  videoList: widget.videoResults,
                  searchRequest: widget.searchRequest,
                  reloadInitialResults: () => widget.loadingHandler
                      .getSearchResults(widget.searchRequest),
                  loadMoreResults: loadMoreResults,
                  cancelLoadingHandler:
                      widget.loadingHandler.cancelGetSearchResults,
                  noResultsMessage: "No results found",
                  noResultsErrorMessage: "Error loading results",
                  showScrapingReportButton: true,
                  scrapingReportMap: widget.loadingHandler.resultsIssues,
                  ignoreInternetError: false,
                  noPluginsEnabled:
                      PluginManager.enabledResultsProviders.isEmpty,
                  noPluginsMessage:
                      "No result providers enabled. Enable at least one plugin's result provider setting")
            ])));
  }
}
