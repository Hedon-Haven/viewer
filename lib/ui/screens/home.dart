import 'package:flutter/material.dart';

import '/services/loading_handler.dart';
import '/services/plugin_manager.dart';
import '/ui/screens/scraping_report.dart';
import '/utils/global_vars.dart';
import '/utils/universal_formats.dart';
import 'search.dart';
import 'video_list.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Future<List<UniversalVideoPreview>?> videoResults = Future.value([]);
  LoadingHandler loadingHandler = LoadingHandler();
  bool isLoading = true;

  @override
  void initState() {
    super.initState();

    // Listen for changes to appearance_homepage_enabled setting
    reloadVideoListEvent.stream.listen((_) {
      sharedStorage.getBool("appearance_homepage_enabled").then((value) {
        if (value!) {
          loadingHandler = LoadingHandler();
          videoResults = loadingHandler.getHomePages(null).whenComplete(() {
            logger.d("ResultsIssues Map: ${loadingHandler.resultsIssues}");
            // Update the scraping report button
          });
        } else {
          videoResults = Future.value([]);
        }
        setState(() => isLoading = false);
      });
    });

    sharedStorage.getBool("appearance_homepage_enabled").then((value) {
      if (value!) {
        videoResults = loadingHandler.getHomePages(null).whenComplete(() {
          logger.d("ResultsIssues Map: ${loadingHandler.resultsIssues}");
          // Update the scraping report button
          setState(() => isLoading = false);
        });
      }
    });
  }

  Future<List<UniversalVideoPreview>?> loadMoreResults() async {
    setState(() => isLoading = true);
    var results = await loadingHandler.getHomePages(await videoResults);
    // Updates the scraping report button
    setState(() => isLoading = false);
    return results;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        iconTheme: IconThemeData(color: Theme.of(context).colorScheme.primary),
        actions: [
          if (loadingHandler.resultsIssues.isNotEmpty && !isLoading) ...[
            IconButton(
                icon: Icon(
                    color: Theme.of(context).colorScheme.error,
                    Icons.error_outline),
                onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (context) => ScrapingReportScreen(
                                multiProviderMap:
                                    loadingHandler.resultsIssues)))
                    .whenComplete(() => setState(() {})))
          ],
          Spacer(),
          IconButton(
            icon: Icon(
                color: Theme.of(context).colorScheme.primary, Icons.search),
            onPressed: () {
              Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (context) => SearchScreen(
                            previousSearch: UniversalSearchRequest(),
                          )));
            },
          ),
        ],
      ),
      body: SafeArea(
          child: FutureBuilder<bool?>(
              future: sharedStorage.getBool("appearance_homepage_enabled"),
              builder: (context, snapshot) {
                // Don't show anything until the future is done
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const SizedBox();
                }
                return snapshot.data!
                    ? CustomScrollView(slivers: [
                        VideoList(
                          videoList: videoResults,
                          scrollController: ScrollController(),
                          reloadInitialResults: () =>
                              loadingHandler.getHomePages(null),
                          loadMoreResults: loadMoreResults,
                          cancelLoadingHandler:
                              loadingHandler.cancelGetHomePages,
                          noResultsMessage:
                              "Empty homepage but no error. Please report this to developers",
                          noResultsErrorMessage: "Error loading homepage",
                          showScrapingReportButton: true,
                          scrapingReportMap: loadingHandler.resultsIssues,
                          ignoreInternetError: false,
                          noPluginsEnabled:
                              PluginManager.enabledHomepageProviders.isEmpty,
                          noPluginsMessage:
                              "No homepage providers enabled. Enable at least one plugin's homepage provider setting",
                        )
                      ])
                    : const Center(
                        child: Text(
                            "Homepage disabled in settings/appearance/enable homepage",
                            style: TextStyle(fontSize: 20, color: Colors.red)));
              })),
    );
  }
}
