import 'dart:io';

import 'package:animations/animations.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:skeletonizer/skeletonizer.dart';
import 'package:video_player/video_player.dart';

import '/services/database_manager.dart';
import '/ui/screens/author_page.dart';
import '/ui/screens/bug_report.dart';
import '/ui/screens/scraping_report.dart';
import '/ui/screens/video_screen/video_screen.dart';
import '/ui/utils/toast_notification.dart';
import '/ui/widgets/external_link_warning.dart';
import '/utils/convert.dart';
import '/utils/global_vars.dart';
import '/utils/plugin_interface/plugin_interface.dart';
import '/utils/try_parse.dart';
import '/utils/universal_formats.dart';
import 'settings/settings_plugins/settings_plugins.dart';

class VideoList extends StatefulWidget {
  Future<List<UniversalVideoPreview>?> videoList;

  final ScrollController scrollController;

  /// Called just before transitioning to VideoPlayerScreen
  final VoidCallback? onVideoTap;

  /// Function to recreate the videoList as it was initially loaded.
  /// Only required if noPluginsEnabled can be true
  final Future<List<UniversalVideoPreview>?> Function()? reloadInitialResults;

  final Future<List<UniversalVideoPreview>?> Function()? loadMoreResults;

  final void Function()? cancelLoadingHandler;

  /// When set to not null, allows the user to delete videos from the list
  final Future<void> Function(UniversalVideoPreview result)? deleteVideo;

  /// Message to show when there are no results, but also no errors
  final String noResultsMessage;

  /// Message to show when failed to load any results
  final String noResultsErrorMessage;

  final UniversalSearchRequest? searchRequest;

  /// Ignore internet connected error, e.g. on history screen
  final bool ignoreInternetError;

  /// Whether no plugins for the current screen are enabled
  final bool noPluginsEnabled;

  /// Message to show when no plugins are enabled
  final String noPluginsMessage;

  /// Show scraping report button when there was an error getting any results
  final bool showScrapingReportButton;

  /// Can be either a singleProviderMap or multiProviderMap
  Map<dynamic, dynamic>? scrapingReportMap;

  /// Don't pad the video list (other padding might still apply)
  final bool noListPadding;

  /// Force a particular list view type no matter the user-preferred type
  final String? overrideListViewTo;

  /// Don't show Author button
  final bool hideAuthors;

  /// Don't show favorite button. This button will be overriden with the
  /// delete button if deleteVideo is set
  final bool hideFavoriteButton;
  final bool playPreviews;

  /// Load thumbnails from the network instead of trying to use thumbnailBinary data
  final bool useNetworkThumbnails;

  final Map<String, dynamic>? singleProviderDebugObject;

  VideoList(
      {super.key,
      required this.videoList,
      this.onVideoTap,
      required this.scrollController,
      this.searchRequest,
      this.reloadInitialResults,
      this.loadMoreResults,
      this.cancelLoadingHandler,
      this.deleteVideo,
      required this.noResultsMessage,
      required this.noResultsErrorMessage,
      this.showScrapingReportButton = false,
      this.scrapingReportMap,
      this.ignoreInternetError = true,
      this.noPluginsEnabled = false,
      this.noPluginsMessage = "",
      this.noListPadding = false,
      this.overrideListViewTo,
      this.hideAuthors = false,
      this.hideFavoriteButton = false,
      this.playPreviews = true,
      this.useNetworkThumbnails = true,
      this.singleProviderDebugObject});

  @override
  State<VideoList> createState() => _VideoListState();
}

class _VideoListState extends State<VideoList> {
  VideoPlayerController previewVideoController =
      VideoPlayerController.networkUrl(Uri.parse(""));
  int? _tappedChildIndex;
  int _previewLoopCount = 0;
  Duration _lastPreviewPosition = Duration.zero;
  bool isLoadingResults = true;
  bool isLoadingMoreResults = false;
  bool isInternetConnected = true;
  bool isMobile = true;

  Directory? cacheDir;

  // List with 10 empty UniversalSearchResults
  // Needed as below some objects will try to read the values from it, even while loading
  List<UniversalVideoPreview>? videoList =
      List.filled(12, UniversalVideoPreview.skeleton());

  @override
  void initState() {
    super.initState();
    logger.i("Initiating VideoList");

    // Listen for changes to the plugins list/settings
    reloadVideoListEvent.stream.listen((_) {
      if (widget.reloadInitialResults != null) {
        widget.videoList =
            widget.reloadInitialResults?.call() ?? Future.value(null);
        loadVideoResults();
      }
    });

    widget.scrollController.addListener((scrollListener));
    getApplicationCacheDirectory().then((value) {
      cacheDir = Directory("${value.path}/icons");
    });
    loadVideoResults();

    logger.i("Finished initializing screen");
  }

  @override
  void dispose() {
    logger.i("Disposing of VideoList");
    previewVideoController
        .pause()
        .then((_) => previewVideoController.dispose());
    widget.scrollController.removeListener(scrollListener);
    widget.cancelLoadingHandler?.call();
    super.dispose();
  }

  void loadVideoResults() async {
    if (!mounted) return;
    setState(() => isLoadingResults = true);
    videoList = await widget.videoList;
    // If Connectivity contains ConnectivityResult.none -> no internet connection -> revert results
    isInternetConnected = !(await (Connectivity().checkConnectivity()))
        .contains(ConnectivityResult.none);
    logger.d("Internet connected: $isInternetConnected");
    // Make sure context is still mounted
    if (mounted) setState(() => isLoadingResults = false);
  }

  void scrollListener() async {
    if (!isLoadingMoreResults &&
        widget.scrollController.position.pixels >=
            0.95 * widget.scrollController.position.maxScrollExtent) {
      logger.i("Loading additional results");
      setState(() => isLoadingMoreResults = true);
      Future<List<UniversalVideoPreview>?> newVideoResults = Future.value([]);
      if (widget.loadMoreResults == null) {
        logger.d(
            "List type doesn't support loading more results. Not loading anything...");
        newVideoResults = Future.value(videoList);
      } else {
        newVideoResults = widget.loadMoreResults!();
      }

      videoList = await newVideoResults;
      logger.i("Finished getting more results");
      setState(() => isLoadingMoreResults = false);
    }
  }

  void setPreviewSource(int index) {
    if (videoList![index].previewVideo == null) {
      logger.i("Preview URI empty, not playing");
      return;
    }
    previewVideoController.dispose();
    previewVideoController =
        VideoPlayerController.networkUrl(videoList![index].previewVideo!);
    previewVideoController.initialize().then((value) async {
      // To stop after looping 3 times
      previewVideoController.addListener(() async {
        final current = previewVideoController.value.position;
        // Detect wrap: current is small (near zero) and last was near duration
        if (current < const Duration(milliseconds: 100) &&
            _lastPreviewPosition >
                previewVideoController.value.duration -
                    const Duration(milliseconds: 200)) {
          _previewLoopCount++;
          if (_previewLoopCount >= 3) {
            previewVideoController.setLooping(false);
            previewVideoController.pause();
            _previewLoopCount = 0;
            setState(() => _tappedChildIndex = null);
          }
        }
        _lastPreviewPosition = current;
      });

      await previewVideoController.setVolume(0.0);
      await previewVideoController.setLooping(true);
      await previewVideoController.play();
      setState(() {});
    });
  }

  void showPreview(int index) async {
    if (isLoadingResults) {
      logger.i("Still loading results, not playing");
      return;
    }
    if (!widget.playPreviews) {
      logger.i("Previews disabled by parent");
      return;
    } else if ((await sharedStorage.getBool("appearance_play_previews"))! ==
        false) {
      logger.i("Previews disabled by user settings, not playing");
      return;
    }
    // if user clicks the same preview again, don't reload
    else if (_tappedChildIndex != index) {
      setState(() {
        _tappedChildIndex = index;
        setPreviewSource(index);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    isMobile = MediaQuery.of(context).size.width < 600;
    // If the list is null -> error
    // If the list is empty -> no results, but no error getting them either
    if ((videoList?.isEmpty ?? true) && !isLoadingResults) {
      return SliverToBoxAdapter(
          child: Center(child: Builder(builder: (context) {
        final double width = MediaQuery.of(context).size.width;
        return Padding(
            padding: EdgeInsets.only(
                left: width * 0.05, right: width * 0.05, bottom: 50),
            child: Column(children: [
              Padding(
                  padding: const EdgeInsets.only(top: 50, bottom: 30),
                  child: Text(
                      // Null means error
                      videoList == null
                          ? widget.noPluginsEnabled
                              ? widget.noPluginsMessage
                              : (isInternetConnected &&
                                      !widget.ignoreInternetError)
                                  ? widget.noResultsErrorMessage
                                  : "No internet connection"
                          // non-null but empty means no results
                          : widget.noResultsMessage,
                      style: const TextStyle(fontSize: 20),
                      textAlign: TextAlign.center)),
              if (videoList == null &&
                  isInternetConnected &&
                  !widget.noPluginsEnabled &&
                  widget.showScrapingReportButton) ...[
                ElevatedButton(
                    style: TextButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.primary),
                    child: Text("Open scraping report",
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(
                                color:
                                    Theme.of(context).colorScheme.onPrimary)),
                    onPressed: () {
                      if (widget.singleProviderDebugObject != null) {
                        Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => ScrapingReportScreen(
                                  singleProviderMap: tryParse(() =>
                                      widget.scrapingReportMap
                                          as Map<String, List<dynamic>>),
                                  singleDebugObject:
                                      widget.singleProviderDebugObject),
                            ));
                      } else {
                        Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => ScrapingReportScreen(
                                multiProviderMap: tryParse(() =>
                                    widget.scrapingReportMap as Map<
                                        PluginInterface,
                                        Map<String, List<dynamic>>>),
                              ),
                            ));
                      }
                    })
              ],
              if (widget.noPluginsEnabled) ...[
                ElevatedButton(
                    style: TextButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.primary),
                    child: Text("Open plugin settings",
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(
                                color:
                                    Theme.of(context).colorScheme.onPrimary)),
                    onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => PluginsScreen(),
                        )))
              ]
            ]));
      }))); // keep existing empty/error content unchanged, just wrap in SliverToBoxAdapter
    }

    return FutureBuilder<String?>(
        future: widget.overrideListViewTo != null
            ? Future.value(widget.overrideListViewTo)
            : sharedStorage.getString("appearance_list_view"),
        builder: (context, listViewType) {
          if (listViewType.data == null) {
            return SliverToBoxAdapter(child: Container());
          }
          return SliverPadding(
              padding: widget.noListPadding
                  ? EdgeInsets.zero
                  : const EdgeInsets.only(right: 15, left: 15),
              sliver: SliverMasonryGrid.count(
                crossAxisCount: listViewType.data! == "Grid" ? 2 : 1,
                crossAxisSpacing: 15,
                mainAxisSpacing: 15,
                childCount: videoList?.length ?? 0,
                itemBuilder: (context, index) {
                  return OpenContainer(
                      closedElevation: 0,
                      openElevation: 0,
                      closedColor: Colors.transparent,
                      openColor: Theme.of(context).colorScheme.surface,
                      transitionDuration: const Duration(milliseconds: 400),
                      openBuilder: (context, _) => VideoPlayerScreen(
                            videoMetadata: videoList![index]
                                .plugin!
                                .getVideoMetadata(
                                    videoList![index].iD, videoList![index]),
                            videoID: videoList![index].iD,
                          ),
                      closedBuilder: (context, openContainer) => MouseRegion(
                          onEnter: (_) => showPreview(index),
                          child: GestureDetector(
                              onLongPress: () {
                                showModalBottomSheet(
                                    context: context,
                                    builder: (BuildContext context) {
                                      // Use stateful builder to allow calling setState on the modal itself
                                      return StatefulBuilder(builder:
                                          (BuildContext context,
                                              StateSetter setModalState) {
                                        return Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: <Widget>[
                                              ListTile(
                                                leading:
                                                    const Icon(Icons.person),
                                                title: const Text(
                                                    "Go to author page"),
                                                onTap: () => Navigator.push(
                                                    context,
                                                    MaterialPageRoute(
                                                        builder: (context) =>
                                                            AuthorPageScreen(
                                                                authorPage: videoList![
                                                                        index]
                                                                    .plugin!
                                                                    .getAuthorPage(
                                                                        videoList![index].authorID!)))).then(
                                                    (value) =>
                                                        Navigator.of(context)
                                                            .pop()),
                                              ),
                                              FutureBuilder<bool?>(
                                                future: isInFavorites(
                                                    videoList![index].iD),
                                                builder: (context, snapshot) {
                                                  return ListTile(
                                                    leading: Icon(snapshot
                                                                .data ??
                                                            false
                                                        ? Icons.favorite
                                                        : Icons
                                                            .favorite_border),
                                                    title: Text(snapshot.data ??
                                                            false
                                                        ? "Remove from favorites"
                                                        : "Add to favorites"),
                                                    onTap: () async {
                                                      if (snapshot.data ==
                                                          null) {
                                                        return;
                                                      }
                                                      if (snapshot.data!) {
                                                        await removeFromFavorites(
                                                            videoList![index]);
                                                      } else {
                                                        await addToFavorites(
                                                            videoList![index]);
                                                      }
                                                      // Update favorites icon in video list
                                                      setState(() {});
                                                      // Rebuild the modal's UI
                                                      setModalState(() {});
                                                    },
                                                  );
                                                },
                                              ),
                                              ListTile(
                                                leading:
                                                    const Icon(Icons.share),
                                                title: const Text("Share"),
                                                onTap: () async {
                                                  // Windows and linux don't have share implementations
                                                  // -> Copy to clipboard and show warning instead
                                                  if (Platform.isWindows ||
                                                      Platform.isLinux) {
                                                    Clipboard.setData(ClipboardData(
                                                        text: videoList![index]
                                                            .plugin!
                                                            .getVideoUriFromID(
                                                                videoList![
                                                                        index]
                                                                    .iD)
                                                            .toString()));
                                                    showToast(
                                                        "Share not available on "
                                                        "${Platform.isWindows ? "Windows" : "Linux"}. "
                                                        "Copied link to clipboard instead",
                                                        context);
                                                  }
                                                  Share.shareUri(
                                                      (await videoList![index]
                                                          .plugin!
                                                          .getVideoUriFromID(
                                                              videoList![index]
                                                                  .iD))!);
                                                },
                                              ),
                                              ListTile(
                                                leading: const Icon(
                                                    Icons.open_in_new),
                                                title: const Text(
                                                    "Open in browser"),
                                                onTap: () async {
                                                  openExternalLinkWithWarningDialog(
                                                      context,
                                                      (await videoList![index]
                                                          .plugin!
                                                          .getVideoUriFromID(
                                                              videoList![index]
                                                                  .iD))!);
                                                },
                                              ),
                                              ListTile(
                                                leading: const Icon(
                                                    Icons.bug_report),
                                                title: const Text(
                                                    "Create bug report"),
                                                onTap: () => Navigator.push(
                                                  context,
                                                  MaterialPageRoute(
                                                    builder: (context) =>
                                                        BugReportScreen(
                                                      debugObject: [
                                                        videoList![index]
                                                            .toMap()
                                                      ],
                                                      plugin: videoList?[index]
                                                          .plugin,
                                                    ),
                                                  ),
                                                ).then((value) =>
                                                    Navigator.of(context)
                                                        .pop()),
                                              ),
                                            ]);
                                      });
                                    });
                              },
                              onTapDown: (_) => showPreview(index),
                              onTap: () async {
                                // stop playback of preview
                                previewVideoController.pause().then(
                                    (_) => previewVideoController.dispose());
                                _tappedChildIndex = null;
                                if (videoList![index].virtualReality) {
                                  showToast("Virtual reality not yet supported",
                                      context);
                                  return;
                                }
                                addToWatchHistory(videoList![index]);
                                widget.onVideoTap?.call();
                                openContainer();
                              },
                              child: Skeletonizer(
                                enabled: isLoadingResults ||
                                    index >= videoList!.length,
                                child: LayoutBuilder(
                                  builder: (context, constraints) {
                                    return IntrinsicHeight(
                                        child: Flex(
                                      mainAxisSize: MainAxisSize.min,
                                      direction: listViewType.data! == "List"
                                          ? Axis.horizontal
                                          : Axis.vertical,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        buildImageWidgets(constraints, index,
                                            listViewType.data!),
                                        buildDescription(index),
                                      ],
                                    ));
                                  },
                                ),
                              ))));
                },
              ));
        });
  }

  Widget buildImageWidgets(
      BoxConstraints constraints, int index, String listViewType) {
    // ClipRect contains the shadow spreads to just the preview
    return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Stack(children: [
          SizedBox(
              // make the image smaller for list view mode
              width: constraints.maxWidth / (listViewType == "List" ? 2 : 1),
              height: constraints.maxWidth *
                  9 /
                  16 /
                  (listViewType == "List" ? 2 : 1),
              child: Skeleton.replace(
                // TODO: Detect if video is not visible and stop playing
                child: previewVideoController.value.isInitialized == true &&
                        _tappedChildIndex == index
                    ? VideoPlayer(previewVideoController)
                    : (videoList![index].thumbnail ?? "") == "mockThumbnail"
                        ? Container(
                            // same color as the default shimmer effect
                            color: Color(0xFF3A3A3A))
                        : widget.useNetworkThumbnails
                            ? Image.network(
                                videoList![index].thumbnail ??
                                    "Thumbnail url is null",
                                headers: videoList![index].thumbnailHttpHeaders,
                                errorBuilder: (context, error, stackTrace) {
                                if (!error
                                    .toString()
                                    .contains("mockThumbnail")) {
                                  logger.e(
                                      "Failed to load network video thumbnail: $error\n$stackTrace");
                                }
                                return Icon(
                                  Icons.error,
                                  color: Theme.of(context).colorScheme.error,
                                );
                              }, fit: BoxFit.fill)
                            : Image.memory(videoList![index].thumbnailBinary,
                                errorBuilder: (context, error, stackTrace) {
                                logger.e(
                                    "Failed to load binary thumbnail: $error\n$stackTrace");
                                return Icon(
                                  Icons.nearby_error,
                                  color: Theme.of(context).colorScheme.error,
                                );
                              }, fit: BoxFit.fill),
              )),
          // Show previewVideo loading progress
          // TODO: Maybe find a way to show the actual progress of the download
          if (previewVideoController.value.isInitialized == false &&
              _tappedChildIndex == index) ...[
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(seconds: 2),
              builder: (context, value, child) {
                return LinearProgressIndicator(value: value);
              },
            )
          ],
          // show video quality
          if (videoList![index].maxQuality != null) ...[
            Positioned(
                left: 8,
                bottom: 8,
                child: Container(
                    padding: const EdgeInsets.only(left: 2.0, right: 2.0),
                    decoration: BoxDecoration(
                        color: isLoadingResults
                            ? Colors.transparent
                            : Colors.black.withOpacity(0.6),
                        borderRadius: BorderRadius.circular(4.0)),
                    child: Text(
                      !videoList![index].virtualReality
                          ? "${videoList![index].maxQuality}p"
                          : "VR",
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                      ),
                    )))
          ],
          Positioned(
              right: 8,
              bottom: 8,
              child: Container(
                  padding: const EdgeInsets.only(left: 2.0, right: 2.0),
                  decoration: BoxDecoration(
                      color: isLoadingResults
                          ? Colors.transparent
                          : Colors.black.withOpacity(0.6),
                      borderRadius: BorderRadius.circular(4.0)),
                  child: Text(
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                      ),
                      videoList![index].duration?.inMinutes == null
                          ? "??:??"
                          : videoList![index].duration!.inMinutes < 61
                              ? "${(videoList![index].duration!.inMinutes % 60).toString().padLeft(2, '0')}:${(videoList![index].duration!.inSeconds % 60).toString().padLeft(2, '0')}"
                              : "1h+"))),
          Positioned(
              left: 8,
              top: 8,
              child: Skeleton.replace(
                  child: !isLoadingResults
                      ? Image.file(
                          File(
                              "${cacheDir?.path}/${videoList![index].plugin?.codeName}"),
                          errorBuilder: (context, error, stackTrace) =>
                              const Icon(Icons.question_mark),
                          width: 20,
                          height: 20)
                      // TODO: Fix skeletonizer not showing
                      : const Placeholder())),
          if (widget.deleteVideo != null) ...[
            Positioned(
                right: 0,
                top: 0,
                child: IconButton(
                    onPressed: isLoadingResults
                        ? null
                        : () async {
                            await widget.deleteVideo!(videoList![index]);
                            videoList!.removeAt(index);
                            showToast("Video deleted", context);
                            setState(() {});
                          },
                    icon: Icon(Icons.delete_forever,
                        color: Theme.of(context).colorScheme.primary)))
          ],
          if (widget.deleteVideo == null && !widget.hideFavoriteButton) ...[
            FutureBuilder<bool?>(
              future: isInFavorites(videoList![index].iD),
              builder: (context, snapshot) {
                return Positioned(
                    right: 0,
                    top: 0,
                    child: IconButton(
                      onPressed: () async {
                        if (snapshot.data == null) return;
                        if (snapshot.data!) {
                          await removeFromFavorites(videoList![index]);
                        } else {
                          await addToFavorites(videoList![index]);
                        }
                        // Rebuild the modal's UI
                        setState(() {});
                      },
                      icon: Stack(
                        alignment: Alignment.center,
                        children: [
                          Icon(Icons.favorite,
                              color:
                                  Theme.of(context).colorScheme.surfaceVariant),
                          Icon(
                              snapshot.data ?? false
                                  ? Icons.favorite
                                  : Icons.favorite_border,
                              color: Theme.of(context).colorScheme.primary),
                        ],
                      ),
                    ));
              },
            )
          ]
        ]));
  }

  Widget buildDescription(int index) {
    TextStyle smallTextStyle = Theme.of(context)
        .textTheme
        .bodyMedium!
        .copyWith(color: Theme.of(context).colorScheme.tertiary);
    return Expanded(
        child: Padding(
            padding: const EdgeInsets.only(right: 6, left: 6, top: 3),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                // make sure the text is at least 2 lines, so that other widgets dont move up
                videoList![index].title,
                overflow: TextOverflow.ellipsis,
                maxLines: 2,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (videoList![index].viewsTotal != null ||
                  videoList![index].ratingsPositivePercent != null) ...[
                Row(children: [
                  if (videoList![index].viewsTotal != null) ...[
                    Text(
                        convertNumberIntoHumanReadable(
                            videoList![index].viewsTotal!),
                        maxLines: 1,
                        style: smallTextStyle),
                    const SizedBox(width: 5),
                    Skeleton.shade(
                        child: Icon(
                            size: 16,
                            color: Theme.of(context).colorScheme.secondary,
                            Icons.remove_red_eye))
                  ],
                  const SizedBox(width: 5),
                  if (videoList![index].ratingsPositivePercent != null) ...[
                    Text(
                        "${videoList![index].viewsTotal != null ? " | " : ""}${videoList![index].ratingsPositivePercent}%",
                        maxLines: 1,
                        style: smallTextStyle),
                    const SizedBox(width: 5),
                    Skeleton.shade(
                        child: Icon(
                            size: 16,
                            color: Theme.of(context).colorScheme.secondary,
                            Icons.thumb_up))
                  ]
                ])
              ],
              if (!widget.hideAuthors) ...[
                OpenContainer(
                    closedElevation: 0,
                    openElevation: 0,
                    closedColor: Colors.transparent,
                    openColor: Theme.of(context).colorScheme.surface,
                    transitionDuration: const Duration(milliseconds: 400),
                    openBuilder: (context, _) => AuthorPageScreen(
                        authorPage: videoList![index]
                            .plugin!
                            .getAuthorPage(videoList![index].authorID!)),
                    closedBuilder: (context, openContainer) => TextButton(
                        onPressed: videoList![index].authorID == null
                            ? () => showToast(
                                "${videoList![index].authorName}: Cant open author page (no authorID). "
                                "Click the video and then try going to the author page from that screen",
                                context,
                                7)
                            : () {
                                openContainer();
                              },
                        style: ButtonStyle(
                          padding: WidgetStateProperty.all(
                              EdgeInsets.symmetric(vertical: 5)),
                          minimumSize: WidgetStateProperty.all(Size.zero),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: Row(children: [
                          Skeleton.shade(
                              child: Stack(children: [
                            Icon(
                                color: Theme.of(context).colorScheme.secondary,
                                Icons.person),
                            videoList![index].verifiedAuthor
                                ? const Positioned(
                                    right: -2,
                                    bottom: -2,
                                    child: Icon(
                                        size: 14,
                                        color: Colors.blue,
                                        Icons.verified))
                                : const SizedBox(),
                          ])),
                          const SizedBox(width: 5),
                          Text(videoList![index].authorName ?? "Unknown author",
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: smallTextStyle)
                        ])))
              ]
            ])));
  }
}
