import 'package:flutter/material.dart';

import '/services/loading_handler.dart';
import '/services/plugin_manager.dart';
import '/ui/screens/author_page.dart';
import '/ui/screens/home.dart';
import '/ui/screens/results.dart';
import '/ui/screens/video_screen/video_screen.dart';
import '/ui/widgets/alert_dialog.dart';
import '/utils/global_vars.dart';
import '/utils/plugin_interface/plugin_interface.dart';
import '/utils/universal_formats.dart';

enum ContentType {
  homePage,
  searchResultsPage,
  videoPage,
  authorPage,
  unknown;

  static ContentType fromString(String value) {
    switch (value) {
      case 'homePage':
        return homePage;
      case 'searchResultsPage':
        return searchResultsPage;
      case 'videoPage':
        return videoPage;
      case 'authorPage':
        return authorPage;
      default:
        return unknown;
    }
  }
}

class ExternalLinkParsed {
  final ContentType type;
  final String? iD;
  final UniversalSearchRequest? searchRequest;
  final int? pageCount;

  const ExternalLinkParsed({
    required this.type,
    this.iD,
    this.searchRequest,
    this.pageCount,
  });
}

Future<void> handleExternalLink(Uri passedUri, BuildContext context) async {
  // Create map of all plugins and the links they can handle
  Map<PluginInterface, List<String>> pluginLinks = {};
  for (PluginInterface plugin in await PluginManager.getAllPlugins()) {
    pluginLinks[plugin] = plugin.handleUrls;
  }

  // Check which plugins can handle the passed Uri
  Set<PluginInterface> possibleHandlers = {};
  for (final entry in pluginLinks.entries) {
    for (final pattern in entry.value) {
      if (passedUri.toString().startsWith(pattern)) {
        possibleHandlers.add(entry.key);
      }
    }
  }

  if (possibleHandlers.isEmpty) {
    throw Exception("No plugins can handle: ${passedUri.toString()}");
  }

  late final PluginInterface handlerPlugin;
  if (possibleHandlers.length > 1) {
    logger.i(
        "Multiple plugins can handle external link, prompting user to select one");
    final userSelectedPlugin = await showDialog<PluginInterface>(
      context: context,
      builder: (BuildContext context) {
        final selectablePlugins = possibleHandlers.toList();
        return ThemedDialog(
            title: "Select plugin to handle external link",
            primaryText: "Cancel",
            onPrimary: () => Navigator.of(context).pop(),
            content: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: 0.6 * MediaQuery.of(context).size.height,
                ),
                child: SingleChildScrollView(
                    child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(
                    selectablePlugins.length,
                    (index) {
                      final plugin = selectablePlugins[index];
                      return ListTile(
                        title: Text(plugin.prettyName),
                        subtitle: Text(plugin.serviceUrl),
                        onTap: () => Navigator.of(context).pop(plugin),
                      );
                    },
                  ),
                ))));
      },
    );
    if (userSelectedPlugin == null) {
      throw Exception("No plugin selected selected by user");
    }
    handlerPlugin = userSelectedPlugin;
  } else {
    handlerPlugin = possibleHandlers.first;
  }

  final bool pluginDisabled =
      !(await PluginManager.getEnabledPlugins()).contains(handlerPlugin);
  final bool pluginNotHandler =
      !(await PluginManager.getProviders(ProviderType.externalLinkHandler))
          .contains(handlerPlugin);
  if (pluginDisabled || pluginNotHandler) {
    final bool? userDecision = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        final selectablePlugins = possibleHandlers.toList();
        return ThemedDialog(
          title: pluginDisabled ? "Enable Plugin?" : "Set as Handler?",
          primaryText: pluginDisabled ? "Enable Plugin" : "Set as Handler",
          onPrimary: () => Navigator.of(context).pop(true),
          secondaryText: "Cancel",
          onSecondary: () => Navigator.of(context).pop(false),
          content: Text(
              pluginDisabled
                  ? "${handlerPlugin.prettyName} plugin is currently disabled "
                      "and cannot handle external links. Enable and allow it "
                      "to process external links?"
                  : "${handlerPlugin.prettyName} plugin is not set as an "
                      "external link handler. Allow it to process external "
                      "links?",
              textAlign: TextAlign.center),
        );
      },
    );
    if (!(userDecision ?? true)) {
      throw Exception(
          "User refused to enable ${handlerPlugin.codeName} as externalLinksHandler");
    }
    Set<ProviderType> newProviderTypes = {ProviderType.externalLinkHandler};
    // Avoid overriding existing provider types
    if (pluginNotHandler) {
      newProviderTypes
          .addAll(await PluginManager.getEnabledProviderTypesOf(handlerPlugin));
    }
    await PluginManager.setAsProvider(handlerPlugin, newProviderTypes);
  }

  // let the plugin parse the link
  logger.i("Parsing shared link with ${handlerPlugin.codeName}");
  final parsedLink = await handlerPlugin.parseExternalLink(passedUri);
  logger.i("parsedLink.type: ${parsedLink.type}");

  switch (parsedLink.type) {
    case ContentType.homePage:
      Navigator.of(context).push(MaterialPageRoute(
        builder: (context) => HomeScreen(
            provider: handlerPlugin, pageCount: parsedLink.pageCount),
      ));
      break;
    case ContentType.searchResultsPage:
      LoadingHandler searchHandler = LoadingHandler();
      Navigator.of(context).push(MaterialPageRoute(
        builder: (context) => ResultsScreen(
          videoResults: searchHandler.getSearchResults(
              parsedLink.searchRequest!, null, [handlerPlugin]),
          searchRequest: parsedLink.searchRequest!,
          loadingHandler: searchHandler,
          openedFromExternalLink: true,
        ),
      ));
      break;
    case ContentType.videoPage:
      Navigator.of(context).push(MaterialPageRoute(
          builder: (context) => VideoPlayerScreen(
                // FIXME: Pass a proper uvp or make passing it optional
                videoMetadata: handlerPlugin.getVideoMetadata(
                    parsedLink.iD!, UniversalVideoPreview.skeleton()),
                videoID: parsedLink.iD!,
              )));
      break;
    case ContentType.authorPage:
      Navigator.of(context).push(MaterialPageRoute(
          builder: (context) => AuthorPageScreen(
              authorPage: handlerPlugin.getAuthorPage(parsedLink.iD!))));
      break;
    case ContentType.unknown:
      throw Exception("Unknown content type");
  }
}
