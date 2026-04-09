import 'package:flutter/material.dart';

import '/services/loading_handler.dart';
import '/services/plugin_manager.dart';
import '/ui/screens/scraping_report.dart';
import '/utils/global_vars.dart';
import '/utils/plugin_interface/plugin_interface.dart';
import '/utils/universal_formats.dart';
import 'search.dart';
import 'video_list.dart';

class HomeScreen extends StatefulWidget {
  /// Only used to open a specific homepage from an external link
  final PluginInterface? provider;

  /// Only used when opening external links
  final int? pageCount;

  const HomeScreen({super.key, this.provider, this.pageCount});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Future<List<UniversalVideoPreview>?> videoResults = Future.value([]);
  LoadingHandler loadingHandler = LoadingHandler();
  bool isLoading = true;
  bool noPluginsEnabled = false;

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

    if (widget.provider != null && widget.pageCount != null) {
      videoResults = loadingHandler
          .getHomePages(null, [widget.provider!]).whenComplete(() {
        logger.d("ResultsIssues Map: ${loadingHandler.resultsIssues}");
        // Update the scraping report button
        setState(() => isLoading = false);
      });
    } else {
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

    PluginManager.getProviders(ProviderType.homepage).then((value) {
      if (value.isEmpty) {
        setState(() => noPluginsEnabled = true);
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
            onPressed: () => Navigator.push(
              context,
              PageRouteBuilder(
                pageBuilder: (context, animation, _) =>
                    SearchScreen(previousSearch: UniversalSearchRequest()),
                transitionsBuilder: (context, animation, _, child) {
                  final curved = CurvedAnimation(
                      parent: animation, curve: Curves.easeInOut);
                  final topOffset =
                      kToolbarHeight + MediaQuery.of(context).padding.top;
                  final screenHeight = MediaQuery.of(context).size.height;

                  return AnimatedBuilder(
                    animation: curved,
                    child: child,
                    builder: (_, child) => Stack(
                      children: [
                        Positioned(
                          top: 0,
                          left: 0,
                          right: 0,
                          height: topOffset +
                              curved.value * (screenHeight - topOffset),
                          child: ClipRect(
                            child: ShaderMask(
                              blendMode: BlendMode.dstIn,
                              shaderCallback: (rect) => LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                // AppBar region fades in, body stays fully opaque
                                colors: [
                                  Colors.black.withValues(alpha: curved.value),
                                  Colors.black
                                ],
                                stops: [
                                  topOffset / rect.height,
                                  topOffset / rect.height
                                ],
                              ).createShader(rect),
                              child: OverflowBox(
                                alignment: Alignment.topCenter,
                                maxHeight: screenHeight,
                                child: child,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
                transitionDuration: const Duration(milliseconds: 300),
              ),
            ),
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
                          noResultsMessage:
                              "Empty homepage but no error. Please report this to developers",
                          noResultsErrorMessage: "Error loading homepage",
                          showScrapingReportButton: true,
                          scrapingReportMap: loadingHandler.resultsIssues,
                          ignoreInternetError: false,
                          noPluginsEnabled: noPluginsEnabled,
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
