import 'dart:async';
import 'dart:io';

import 'package:animations/animations.dart';
import 'package:auto_orientation/auto_orientation.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:skeletonizer/skeletonizer.dart';
import 'package:window_manager/window_manager.dart';

import '/services/database_manager.dart';
import '/services/loading_handler.dart';
import '/ui/screens/author_page.dart';
import '/ui/screens/bug_report.dart';
import '/ui/screens/scraping_report.dart';
import '/ui/screens/settings/settings_comments.dart';
import '/ui/screens/video_list.dart';
import '/ui/screens/video_screen/player_widget.dart';
import '/ui/utils/toast_notification.dart';
import '/ui/widgets/alert_dialog.dart';
import '/ui/widgets/external_link_warning.dart';
import '/ui/widgets/sliver_header.dart';
import '/utils/convert.dart';
import '/utils/global_vars.dart';
import '/utils/universal_formats.dart';

class VideoPlayerScreen extends StatefulWidget {
  final Future<UniversalVideoMetadata> videoMetadata;

  /// Pass videoID to be able to pass it to BugReport screen in case
  /// the videoMetadata fails to load completely
  final String videoID;

  const VideoPlayerScreen(
      {super.key, required this.videoMetadata, required this.videoID});

  @override
  State<VideoPlayerScreen> createState() => VideoPlayerScreenState();
}

class VideoPlayerScreenState extends State<VideoPlayerScreen> {
  ScrollController commentsScrollController = ScrollController();
  ScrollController screenScrollController = ScrollController();
  bool showControls = false;
  bool isMobile = true;
  LoadingHandler loadingHandler = LoadingHandler();
  final videoPlayerWidgetKey = GlobalKey<VideoPlayerWidgetState>();

  List<Uint8List>? progressThumbnails;
  Timer? hideControlsTimer;
  bool isFullScreen = false;
  String? failedToLoadReason;
  String? detailedFailReason;
  bool firstPlay = true;
  bool isLoadingMetadata = true;
  bool loadedCommentsOnce = false;
  bool isLoadingComments = true;
  bool isLoadingMoreComments = false;
  int commentsAmount = 0;
  bool showCommentSection = false;
  bool showReplySection = false;
  bool animateReplySection = true;
  int replyCommentIndex = 0;
  bool descriptionExpanded = false;
  int selectedResolution = 0;
  List<int> sortedResolutions = [];

  // Fill with garbage for skeleton
  List<UniversalComment>? comments = List.generate(
    10,
    (index) => UniversalComment.skeleton(),
  );
  UniversalVideoMetadata videoMetadata = UniversalVideoMetadata.skeleton();

  Future<List<UniversalVideoPreview>?> videoSuggestions =
      Future.value(List.filled(12, UniversalVideoPreview.skeleton()));

  @override
  void initState() {
    super.initState();

    commentsScrollController.addListener((commentsScrollListener));

    Connectivity().checkConnectivity().then((value) {
      if (value.contains(ConnectivityResult.none)) {
        logger.e("No internet connection");
        setState(() {
          failedToLoadReason = "No internet connection";
        });
      }
    });

    widget.videoMetadata.whenComplete(() async {
      videoMetadata = await widget.videoMetadata;

      // Start loading video suggestions, but don't wait for them
      videoSuggestions = loadingHandler.getVideoSuggestions(
          videoMetadata.plugin!, videoMetadata.iD, videoMetadata.rawHtml, null);

      // Pre-load images so they are immediately available when the skeletonizer stops
      await precacheImage(
          NetworkImage(videoMetadata.authorAvatar ?? "Avatar url is null"),
          context);

      setState(() {
        isLoadingMetadata = false;
      });

      // Update screen after progress thumbnails are loaded
      sharedStorage.getBool("media_show_progress_thumbnails").then((value) {
        if (value!) {
          videoMetadata.plugin!
              .getProgressThumbnails(videoMetadata.iD, videoMetadata.rawHtml)
              .then((value) {
            setState(() => progressThumbnails = value);
          });
        }
      });
    }).catchError((e, stacktrace) {
      logger.e("Error getting video metadata: $e\n$stacktrace");
      if (failedToLoadReason != "No internet connection") {
        setState(() {
          failedToLoadReason = e.toString();
          detailedFailReason = stacktrace.toString();
        });
      }
    });
  }

  @override
  void dispose() {
    commentsScrollController.dispose();
    videoMetadata.plugin?.cancelGetProgressThumbnails();
    super.dispose();
  }

  void openComments() async {
    logger.d("Opening comment section");
    if (isMobile) {
      setState(() => showCommentSection = true);
    }
    if (!loadedCommentsOnce && !isLoadingMetadata) {
      logger.d("Getting comments for the first time");
      setState(() => isLoadingComments = true);
      comments = await loadingHandler.getCommentResults(
          videoMetadata.plugin!, videoMetadata.iD, videoMetadata.rawHtml, null);
      commentsAmount = comments?.length ?? 0;
      setState(() => isLoadingComments = false);
      logger.d("Finished getting comments");
      loadedCommentsOnce = true;

      if (comments?.isNotEmpty ?? false) {
        // Ensure the frame has been rendered before checking maxScrollExtent, as
        // it otherwise throws "ScrollController not attached to any scroll views"
        WidgetsBinding.instance.addPostFrameCallback((_) {
          // If list is too short user will be unable to scroll and load more
          // comments -> check beforehand and automatically load another page
          if (commentsScrollController.hasClients &&
              commentsScrollController.position.maxScrollExtent == 0.0) {
            commentsScrollListener(forceLoad: true);
          }
        });
      }
    }
  }

  void openCommentSettings() async {
    // Navigate to settings page of comments
    logger.i("Opening comment settings");
    await Navigator.push(context,
        MaterialPageRoute(builder: (context) => const CommentsScreen()));
    logger.i("Refreshing comments");
    loadingHandler.commentsPageCounter = 0;
    loadedCommentsOnce = false;
    openComments();
  }

  void commentsScrollListener({bool forceLoad = false}) async {
    if (!isLoadingMoreComments &&
            commentsScrollController.position.pixels >=
                0.95 * commentsScrollController.position.maxScrollExtent ||
        forceLoad) {
      logger.i(forceLoad
          ? "Force loading additional results to make list scrollable"
          : "Loading additional results");
      setState(() => isLoadingMoreComments = true);
      comments = await loadingHandler.getCommentResults(videoMetadata.plugin!,
          videoMetadata.iD, videoMetadata.rawHtml, comments);
      commentsAmount = comments?.length ?? 0;
      logger.i("Finished getting more results");
      // This also updates the scraping report button
      setState(() => isLoadingMoreComments = false);
    }
  }

  void openCommentAvatarInFullscreen(UniversalComment comment) {
    showDialog(
        context: context,
        builder: (BuildContext context) => ThemedDialog(
            title: "Avatar image",
            primaryText: "Close",
            onPrimary: () => Navigator.pop(context),
            secondaryText: "Go to author page",
            onSecondary: () {
              // pause video
              videoPlayerWidgetKey.currentState?.pausePlayer();
              Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) => AuthorPageScreen(
                              authorPage: comment.plugin!
                                  .getAuthorPage(comment.authorID!))))
                  .then((value) => Navigator.of(context).pop());
            },
            content: SingleChildScrollView(
                child: Image.network(
                    comment.profilePicture ?? "Avatar url is null",
                    errorBuilder: (context, error, stackTrace) {
              if (!error.toString().contains("mockAvatar")) {
                logger.e("Failed to load network avatar: $error\n$stackTrace");
              }
              return Icon(Icons.error,
                  color: Theme.of(context).colorScheme.error);
            }, fit: BoxFit.contain))));
  }

  void toggleFullScreen() {
    isFullScreen = !isFullScreen;
    if (isFullScreen) {
      if (Platform.isLinux || Platform.isMacOS || Platform.isWindows) {
        windowManager.setFullScreen(true);
      }
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      AutoOrientation.landscapeAutoMode(forceSensor: true);
    } else {
      if (Platform.isLinux || Platform.isMacOS || Platform.isWindows) {
        windowManager.setFullScreen(false);
      }
      // TODO: Get rid of visual bug due to system not resizing quick enough
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      AutoOrientation.portraitAutoMode();
    }
  }

  Future<List<UniversalVideoPreview>?> loadMoreResults() async {
    var results = loadingHandler.getVideoSuggestions(videoMetadata.plugin!,
        videoMetadata.iD, videoMetadata.rawHtml, await videoSuggestions);
    // Update warnings/errors button
    setState(() {});
    return results;
  }

  @override
  Widget build(BuildContext context) {
    isMobile = MediaQuery.of(context).size.width < 1100;
    if (!isMobile) {
      openComments();
    }
    return Scaffold(
        body: SafeArea(
            top: !isFullScreen,
            bottom: !isFullScreen,
            left: !isFullScreen,
            right: !isFullScreen,
            child: PopScope(
                // only allow pop if not in fullscreen
                canPop:
                    !isFullScreen && !showCommentSection && !showReplySection,
                onPopInvokedWithResult: (_, __) {
                  // restore upright orientation
                  if (isFullScreen) {
                    toggleFullScreen();
                    return;
                  }
                  if (showReplySection && isMobile) {
                    setState(() {
                      showReplySection = false;
                    });
                    return;
                  }
                  if (showCommentSection && isMobile) {
                    setState(() {
                      showCommentSection = false;
                    });
                  }
                },
                child: Stack(children: [
                  failedToLoadReason != null
                      ? Center(
                          child: Padding(
                              padding: EdgeInsets.only(
                                  left: MediaQuery.of(context).size.width * 0.1,
                                  right:
                                      MediaQuery.of(context).size.width * 0.1,
                                  top:
                                      MediaQuery.of(context).size.height * 0.1),
                              child: Column(children: [
                                Text(
                                    failedToLoadReason ==
                                            "No internet connection"
                                        ? "No internet connection"
                                        : "Failed to scrape video page",
                                    style: const TextStyle(fontSize: 20),
                                    textAlign: TextAlign.center),
                                if (failedToLoadReason !=
                                    "No internet connection") ...[
                                  SizedBox(height: 10),
                                  ElevatedButton(
                                      style: TextButton.styleFrom(
                                          backgroundColor: Theme.of(context)
                                              .colorScheme
                                              .primary),
                                      child: Text("Open scraping report",
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleMedium
                                              ?.copyWith(
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .onPrimary)),
                                      onPressed: () {
                                        Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (context) =>
                                                  ScrapingReportScreen(
                                                      singleProviderMap: {
                                                    // Pass videoID from widget in case the entire videoMetadata failed to scrape
                                                    "Critical": [
                                                      "Failed to load ${widget.videoID}: $failedToLoadReason"
                                                          "\n$detailedFailReason"
                                                    ]
                                                  },
                                                      singleDebugObject:
                                                          videoMetadata
                                                              .toMap()),
                                            ));
                                      })
                                ]
                              ])))
                      : Skeletonizer(
                          enabled: isLoadingMetadata,
                          child: Row(children: [
                            Expanded(
                                flex: 3,
                                child: Column(children: <Widget>[
                                  LayoutBuilder(
                                      builder: (context, constraints) =>
                                          SizedBox(
                                              width: constraints.maxWidth,
                                              height: isFullScreen
                                                  ? MediaQuery.of(context)
                                                      .size
                                                      .height
                                                  : constraints.maxWidth *
                                                      9 /
                                                      16,
                                              child: Skeleton.shade(
                                                  child: isLoadingMetadata
                                                      // to show a skeletonized box, display a container with a color
                                                      // Does NOT work if the container has no color
                                                      ? Container(
                                                          color: Colors.black)
                                                      : VideoPlayerWidget(
                                                          key:
                                                              videoPlayerWidgetKey,
                                                          videoMetadata:
                                                              videoMetadata,
                                                          progressThumbnails:
                                                              progressThumbnails,
                                                          toggleFullScreen:
                                                              toggleFullScreen,
                                                          isFullScreen:
                                                              isFullScreen,
                                                        )))),
                                  // only show the following widgets if not in fullscreen
                                  if (!isFullScreen) ...[
                                    Expanded(
                                        child: Stack(children: [
                                      Padding(
                                          padding: const EdgeInsets.only(
                                              left: 10,
                                              right: 10,
                                              bottom: 10,
                                              top: 5),
                                          child: Column(
                                              spacing: 10,
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: <Widget>[
                                                buildDetailsSection()
                                              ])),
                                      // After
                                      if (isMobile)
                                        AnimatedSlide(
                                          offset: showCommentSection
                                              ? Offset.zero
                                              : const Offset(0, 1),
                                          duration:
                                              const Duration(milliseconds: 200),
                                          curve: Curves.easeInOut,
                                          child: IgnorePointer(
                                            ignoring: !showCommentSection,
                                            child: buildCommentSection(),
                                          ),
                                        ),
                                    ]))
                                  ]
                                ])),
                            if (!isMobile && !isFullScreen)
                              Expanded(
                                  flex: 1,
                                  child: CustomScrollView(
                                      controller: screenScrollController,
                                      slivers: buildVideoSuggestions()))
                          ])),
                  // overlay back button while loading or on error
                  if (isLoadingMetadata || failedToLoadReason != null)
                    Positioned(
                        top: 0,
                        left: 0,
                        child: BackButton(
                            color: Theme.of(context).colorScheme.primary)),
                ]))));
  }

  Widget buildVideoDetails() {
    return Column(
        spacing: 10,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
              width: double.infinity,
              child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                      onTap: () => setState(() {
                            descriptionExpanded = !descriptionExpanded;
                          }),
                      onLongPress: () {
                        Clipboard.setData(
                            ClipboardData(text: videoMetadata.title));
                        // TODO: Add vibration feedback for mobile
                        showToast("Copied video title to clipboard", context);
                      },
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                              child: AnimatedSize(
                                  duration: const Duration(milliseconds: 200),
                                  curve: Curves.easeInOut,
                                  alignment: Alignment.topLeft,
                                  child: Text(
                                      // Most videos result in a 2-line title, but mock usually displays only one causing jumps
                                      isLoadingMetadata
                                          ? "${videoMetadata.title}\n${videoMetadata.title}"
                                          : videoMetadata.title,
                                      style: const TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.bold),
                                      overflow: TextOverflow.ellipsis,
                                      maxLines: descriptionExpanded ? 10 : 2))),
                          Icon(
                            descriptionExpanded
                                ? Icons.keyboard_arrow_up
                                : Icons.keyboard_arrow_down,
                            color: Colors.white,
                            size: 30.0,
                          )
                        ],
                      )))),
          if (isMobile) buildMetadataSection(),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            alignment: Alignment.topLeft,
            child: descriptionExpanded
                ? Text(videoMetadata.description ?? "No description available",
                    style: Theme.of(context).textTheme.bodyMedium!)
                : const SizedBox.shrink(),
          ),
          isMobile
              ? buildAuthorPreview()
              : Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                      IntrinsicHeight(child: buildAuthorPreview()),
                      buildMetadataSection()
                    ]),
          buildActionButtonsRow(),
          if (isMobile)
            SizedBox(
                width: double.infinity,
                child: Skeleton.shade(
                    child: TextButton(
                        style: TextButton.styleFrom(
                            foregroundColor:
                                Theme.of(context).colorScheme.onPrimary,
                            backgroundColor:
                                Theme.of(context).colorScheme.primary),
                        onPressed:
                            isLoadingMetadata ? null : () => openComments(),
                        child: Text("Comments"))))
          // buildCommentSection()
        ]);
  }

  Widget buildAuthorPreview() {
    return OpenContainer(
        closedElevation: 0,
        openElevation: 0,
        closedColor: Colors.transparent,
        openColor: Theme.of(context).colorScheme.surface,
        transitionDuration: const Duration(milliseconds: 400),
        openBuilder: (context, _) => AuthorPageScreen(
            authorPage:
                videoMetadata.plugin!.getAuthorPage(videoMetadata.authorID)),
        closedBuilder: (context, openContainer) => TextButton(
            style: ButtonStyle(
                padding: WidgetStateProperty.all(EdgeInsets.symmetric(
                    horizontal: 5, vertical: isMobile ? 5 : 15))),
            onPressed: () {
              // pause video
              videoPlayerWidgetKey.currentState?.pausePlayer();
              openContainer();
            },
            child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  Skeleton.replace(
                    width: 50,
                    height: 50,
                    replacement: ClipRRect(
                      borderRadius: BorderRadius.circular(255),
                      child: ColoredBox(
                          color: Theme.of(context).colorScheme.surface),
                    ),
                    child: ClipOval(
                        child: Container(
                      width: 50,
                      height: 50,
                      color: Theme.of(context).colorScheme.tertiary,
                      child: Image.network(
                        videoMetadata.authorAvatar ?? "Avatar url is null",
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          if (!error.toString().contains("mockAvatar")) {
                            logger.e(
                                "Failed to load network avatar: $error\n$stackTrace");
                          }
                          return FittedBox(
                              fit: BoxFit.cover,
                              child: Icon(Icons.person,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onTertiary));
                        },
                      ),
                    )),
                  ),
                  SizedBox(width: 20),
                  SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(videoMetadata.authorName ?? "-",
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(fontWeight: FontWeight.bold)),
                            Text(
                                "Subscribers: ${convertNumberIntoHumanReadable(videoMetadata.authorSubscriberCount ?? 0)}",
                                style: Theme.of(context).textTheme.titleSmall)
                          ])),
                  isMobile ? Spacer() : SizedBox(width: 50),
                  FutureBuilder<bool?>(
                      // TODO: Add call to check subscription here
                      future: Future.value(false), // subscribed
                      builder: (context, snapshot) {
                        return ElevatedButton(
                            style: ElevatedButton.styleFrom(
                                foregroundColor:
                                    Theme.of(context).colorScheme.onPrimary,
                                backgroundColor:
                                    Theme.of(context).colorScheme.primary),
                            onPressed: isLoadingMetadata
                                ? null
                                : () =>
                                    showToast("Not yet implemented", context),
                            child: Row(children: [
                              Icon(
                                  size: 20,
                                  color:
                                      Theme.of(context).colorScheme.onPrimary,
                                  snapshot.data ?? false
                                      ? Icons.notifications_off_outlined
                                      : Icons.notification_add),
                              Text(snapshot.data ?? false
                                  ? " Unsubscribe"
                                  : " Subscribe")
                            ]));
                      }),
                ])));
  }

  Widget buildMetadataSection() {
    TextStyle mediumTextStyle = Theme.of(context)
        .textTheme
        .bodyLarge!
        .copyWith(color: Theme.of(context).colorScheme.onSurface);
    return Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        spacing: 20,
        children: [
          Row(children: [
            Text(
                isLoadingMetadata
                    ? "3000 "
                    : videoMetadata.viewsTotal == null
                        ? "-"
                        : descriptionExpanded
                            ? "${formatWithDots(videoMetadata.viewsTotal!)} "
                            : "${convertNumberIntoHumanReadable(videoMetadata.viewsTotal!)} ",
                maxLines: 1,
                style: mediumTextStyle),
            Skeleton.shade(
                child: Icon(
                    size: 16,
                    color: Theme.of(context).colorScheme.secondary,
                    Icons.remove_red_eye))
          ]),
          Row(children: [
            Text(
                isLoadingMetadata
                    ? "Xw ago"
                    : videoMetadata.uploadDate == null
                        ? "-"
                        : descriptionExpanded
                            ? DateFormat("dd-MMM-yyyy")
                                .format(videoMetadata.uploadDate!)
                            : "${getTimeDeltaInHumanReadable(videoMetadata.uploadDate!)} ago ",
                maxLines: 1,
                style: mediumTextStyle),
            Skeleton.shade(
                child: Icon(
                    size: 16,
                    color: Theme.of(context).colorScheme.secondary,
                    Icons.upload))
          ]),
          Row(children: [
            Skeleton.shade(
                child: Icon(
                    size: 16,
                    color: Theme.of(context).colorScheme.secondary,
                    Icons.thumb_up)),
            const SizedBox(width: 5),
            Text(
                isLoadingMetadata
                    ? "3000 | 300"
                    : "${videoMetadata.ratingsPositiveTotal == null ? "-" : descriptionExpanded ? "${videoMetadata.ratingsPositiveTotal!}" : convertNumberIntoHumanReadable(videoMetadata.ratingsPositiveTotal!)} "
                        "| ${videoMetadata.ratingsNegativeTotal == null ? "-" : descriptionExpanded ? "${videoMetadata.ratingsNegativeTotal!}" : convertNumberIntoHumanReadable(videoMetadata.ratingsNegativeTotal!)}",
                maxLines: 1,
                style: mediumTextStyle),
            const SizedBox(width: 5),
            Skeleton.shade(
                child: Icon(
                    size: 16,
                    color: Theme.of(context).colorScheme.secondary,
                    Icons.thumb_down))
          ])
        ]);
  }

  Widget buildActionButtonsRow() {
    return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
            mainAxisAlignment: MainAxisAlignment.start,
            spacing: 10,
            children: [
              SizedBox(
                  child: FutureBuilder<bool?>(
                future: isInFavorites(videoMetadata.iD),
                builder: (context, snapshot) {
                  return ElevatedButton(
                      style: ElevatedButton.styleFrom(
                          foregroundColor:
                              Theme.of(context).colorScheme.onSecondary,
                          backgroundColor:
                              Theme.of(context).colorScheme.secondary),
                      child: Row(children: [
                        Icon(
                            size: 20,
                            color: Theme.of(context).colorScheme.onSecondary,
                            snapshot.data ?? false
                                ? Icons.favorite
                                : Icons.favorite_border),
                        Text(snapshot.data ?? false
                            ? " Remove from favorites"
                            : " Add to favorites")
                      ]),
                      onPressed: () async {
                        if (snapshot.data == null) return;
                        if (snapshot.data!) {
                          await removeFromFavorites(
                              videoMetadata.universalVideoPreview);
                        } else {
                          await addToFavorites(
                              videoMetadata.universalVideoPreview);
                        }
                        setState(() {});
                      });
                },
              )),
              SizedBox(
                  child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.onSecondary,
                    backgroundColor: Theme.of(context).colorScheme.secondary),
                child: Row(children: [
                  Icon(
                      size: 20,
                      color: Theme.of(context).colorScheme.onSecondary,
                      Icons.share),
                  Text(" Share")
                ]),
                onPressed: () async {
                  // Windows and linux don't have share implementations
                  // -> Copy to clipboard and show warning instead
                  if (Platform.isWindows || Platform.isLinux) {
                    Clipboard.setData(ClipboardData(
                        text: videoMetadata.plugin!
                            .getVideoUriFromID(videoMetadata.iD)
                            .toString()));
                    showToast(
                        "Share not available on "
                        "${Platform.isWindows ? "Windows" : "Linux"}. "
                        "Copied link to clipboard instead",
                        context);
                  }
                  Share.shareUri((await videoMetadata.plugin!
                      .getVideoUriFromID(videoMetadata.iD))!);
                },
              )),
              SizedBox(
                  child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.onSecondary,
                    backgroundColor: Theme.of(context).colorScheme.secondary),
                child: Row(children: [
                  Icon(
                      size: 20,
                      color: Theme.of(context).colorScheme.onSecondary,
                      Icons.open_in_new),
                  Text(" Open in browser")
                ]),
                onPressed: () async {
                  openExternalLinkWithWarningDialog(
                      context,
                      (await videoMetadata.plugin!
                          .getVideoUriFromID(videoMetadata.iD))!);
                },
              )),
              SizedBox(
                  child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.onSecondary,
                    backgroundColor: Theme.of(context).colorScheme.secondary),
                child: Row(children: [
                  Icon(
                      size: 20,
                      color: Theme.of(context).colorScheme.onSecondary,
                      Icons.bug_report),
                  Text(" Report bug")
                ]),
                onPressed: () {
                  Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) => BugReportScreen(
                              debugObject: [videoMetadata.toMap()],
                              plugin: videoMetadata.plugin)));
                },
              ))
            ]));
  }

  Widget buildCommentSection() {
    return Stack(children: [
      Positioned.fill(child: buildTopLevelCommentSection()),
      Positioned.fill(
        child: AnimatedSlide(
          offset: showReplySection ? Offset.zero : const Offset(1, 0),
          duration: Duration(milliseconds: animateReplySection ? 200 : 0),
          curve: Curves.easeInOut,
          child: IgnorePointer(
            ignoring: !showReplySection,
            child: buildReplyCommentSection(replyCommentIndex),
          ),
        ),
      )
    ]);
  }

  Widget buildTopLevelCommentSection() {
    return Container(
        decoration: BoxDecoration(
          // While surfaceVariant is deprecated, the suggested replacement
          // surfaceContainerHighest is the same color as surface, which is
          // used to highlight the top level comment
          // TODO: Figure out if the bug is upstream or in dynamic_color and fix it
          color: isMobile
              ? Theme.of(context).colorScheme.surfaceVariant
              : Theme.of(context).colorScheme.surface,
          // Set the background color of the container
          borderRadius:
              BorderRadius.circular(isMobile ? 25 : 0), // Set the border radius
        ),
        // build as many widgets as there are in the list
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
              padding: isMobile
                  ? const EdgeInsets.only(
                      left: 20, right: 10, top: 10, bottom: 5)
                  : EdgeInsets.zero,
              child: Row(children: [
                Text("Comments (${isLoadingComments ? "?" : commentsAmount}) ",
                    style: Theme.of(context).textTheme.titleLarge!.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w500)),
                const Spacer(),
                if (loadingHandler.commentsIssues.isNotEmpty &&
                    !isLoadingComments &&
                    !isLoadingMoreComments) ...[
                  IconButton(
                    icon: Icon(
                        color: Theme.of(context).colorScheme.error,
                        Icons.error_outline),
                    onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (context) => ScrapingReportScreen(
                                    singleProviderMap:
                                        loadingHandler.commentsIssues,
                                    singleDebugObject: videoMetadata.toMap())))
                        .whenComplete(() => setState(() {})),
                  )
                ],
                IconButton(
                    onPressed: () => openCommentSettings(),
                    icon: Icon(Icons.filter_alt,
                        color: Theme.of(context).colorScheme.onSurfaceVariant)),
                if (isMobile)
                  IconButton(
                      onPressed: () =>
                          setState(() => showCommentSection = false),
                      icon: Icon(Icons.close,
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant))
              ])),
          Divider(
              height: 0,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              thickness: 1),
          Expanded(
              child: Skeletonizer(
                  enabled: isLoadingComments,
                  child: comments?.isEmpty ?? true
                      ? Column(children: [
                          Padding(
                              padding:
                                  const EdgeInsets.only(top: 50, bottom: 10),
                              child: Text(
                                  comments == null
                                      ? "Failed to load comments"
                                      : "No comments",
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineSmall!
                                      .copyWith(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurfaceVariant),
                                  textAlign: TextAlign.center)),
                          if (comments == null) ...[
                            ElevatedButton(
                                style: TextButton.styleFrom(
                                    backgroundColor:
                                        Theme.of(context).colorScheme.primary),
                                child: Text("Open scraping report",
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onPrimary)),
                                onPressed: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                        builder: (context) =>
                                            ScrapingReportScreen(
                                                singleProviderMap:
                                                    loadingHandler
                                                        .commentsIssues,
                                                singleDebugObject:
                                                    videoMetadata.toMap()))))
                          ]
                        ])
                      : ListView.builder(
                          controller: commentsScrollController,
                          physics: AlwaysScrollableScrollPhysics(),
                          itemCount: comments!.length +
                              (isLoadingMoreComments ? 1 : 0),
                          itemBuilder: (context, index) {
                            return index == comments!.length
                                ? Center(
                                    child: Padding(
                                        padding:
                                            const EdgeInsets.only(bottom: 10),
                                        child: CircularProgressIndicator(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onSurfaceVariant)))
                                : Padding(
                                    padding: EdgeInsets.only(
                                        top: 10, left: isMobile ? 15 : 5),
                                    child: buildComment(comments!, index));
                          },
                        )))
        ]));
  }

  // Use separate widget for the reply comment section
  // If the main section was to be used for reply comments too, this would
  // necessitate keeping track of the scroll position
  Widget buildReplyCommentSection(int replyCommentIndex) {
    return Container(
        decoration: BoxDecoration(
          // While surfaceVariant is deprecated, the suggested replacement
          // surfaceContainerHighest is the same color as surface, which is
          // used to highlight the top level comment
          // TODO: Figure out if the bug is upstream or in dynamic_color and fix it
          color: isMobile
              ? Theme.of(context).colorScheme.surfaceVariant
              : Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(isMobile ? 25 : 0),
        ),
        // build as many widgets as there are in the list
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
              padding: isMobile
                  ? const EdgeInsets.only(
                      left: 5, right: 10, top: 10, bottom: 5)
                  : EdgeInsets.zero,
              child: Row(mainAxisAlignment: MainAxisAlignment.start, children: [
                IconButton(
                    onPressed: () => setState(() => showReplySection = false),
                    icon: Icon(Icons.arrow_back,
                        color: Theme.of(context).colorScheme.onSurfaceVariant)),
                Text(
                    "Replies (${comments![replyCommentIndex].replyComments?.length ?? "No reply comments?"})",
                    style: Theme.of(context).textTheme.titleLarge!.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w500)),
                if (isMobile) ...[
                  const Spacer(),
                  IconButton(
                      onPressed: () => setState(() {
                            animateReplySection = false;
                            showReplySection = false;
                            showCommentSection = false;
                          }),
                      icon: Icon(Icons.close,
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant))
                ]
              ])),
          Divider(
              height: 0,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              thickness: 1),
          Expanded(
              child: comments![replyCommentIndex].replyComments?.isEmpty ?? true
                  ? Center(
                      child: Text("No reply comments? Report this",
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall!
                              .copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant),
                          textAlign: TextAlign.center),
                    )
                  : ListView.builder(
                      physics: AlwaysScrollableScrollPhysics(),
                      itemCount:
                          comments![replyCommentIndex].replyComments!.length +
                              1,
                      itemBuilder: (context, index) {
                        return Container(
                            decoration: BoxDecoration(
                                color: index == 0
                                    ? isMobile
                                        ? Theme.of(context).colorScheme.surface
                                        : Theme.of(context)
                                            .colorScheme
                                            .surfaceVariant
                                    : Colors.transparent,
                                borderRadius:
                                    BorderRadius.circular(isMobile ? 0 : 25)),
                            child: Padding(
                                // only insert some space at the top for the first ListTile
                                padding: EdgeInsets.only(
                                    top: 10, left: isMobile ? 15 : 5),
                                child: index == 0
                                    ? buildComment(comments!, replyCommentIndex)
                                    : buildComment(
                                        comments![replyCommentIndex]
                                            .replyComments!,
                                        index - 1)));
                      },
                    ))
        ]));
  }

  Widget buildComment(List<UniversalComment> commentsList, int index) {
    return GestureDetector(
        onLongPress: () {
          showModalBottomSheet(
              context: context,
              builder: (BuildContext context) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    ListTile(
                        leading: const Icon(Icons.copy_all),
                        title: const Text("Copy comment text"),
                        onTap: () {
                          Clipboard.setData(ClipboardData(
                              text: commentsList[index].commentBody));
                          // TODO: Add vibration feedback for mobile
                          showToast(
                              "Copied comment text to clipboard", context);
                        }),
                    ListTile(
                        leading: const Icon(Icons.share),
                        title: const Text("Share link to comment"),
                        onTap: () async {
                          Uri? commentUri = await commentsList[index]
                              .plugin!
                              .getCommentUriFromID(
                                  commentsList[index].iD, videoMetadata.iD);
                          if (commentUri == null) {
                            showToast("Could not get link to comment", context);
                            return;
                          }
                          // Windows and linux don't have share implementations
                          // -> Copy to clipboard and show warning instead
                          if (Platform.isWindows || Platform.isLinux) {
                            Clipboard.setData(
                                ClipboardData(text: commentUri.toString()));
                            showToast(
                                "Share not available on "
                                "${Platform.isWindows ? "Windows" : "Linux"}. "
                                "Copied link to clipboard instead",
                                context);
                          }
                          SharePlus.instance
                              .share(ShareParams(uri: commentUri));
                        }),
                    ListTile(
                      leading: const Icon(Icons.person),
                      title: const Text("Go to author page"),
                      onTap: () {
                        // pause video
                        videoPlayerWidgetKey.currentState?.pausePlayer();
                        Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (context) => AuthorPageScreen(
                                        authorPage: commentsList[index]
                                            .plugin!
                                            .getAuthorPage(commentsList[index]
                                                .authorID!))))
                            .then((value) => Navigator.of(context).pop());
                      },
                    ),
                    ListTile(
                        leading: const Icon(Icons.bug_report),
                        title: const Text("Create bug report"),
                        onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (context) => BugReportScreen(
                                          debugObject: [
                                            commentsList[index].toMap()
                                          ],
                                          plugin: commentsList[index].plugin,
                                        )))
                            .then((value) => Navigator.of(context).pop()))
                  ],
                );
              });
        },
        child: ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: Skeleton.shade(
            child: ClipOval(
              child: Container(
                width: 40,
                height: 40,
                color: Theme.of(context).colorScheme.tertiary,
                child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                        onTap: () =>
                            openCommentAvatarInFullscreen(commentsList[index]),
                        child: Image.network(
                          commentsList[index].profilePicture ?? "",
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) => Icon(
                            Icons.person,
                            color: Theme.of(context).colorScheme.onTertiary,
                          ),
                        ))),
              ),
            ),
          ),
          title: Text(
              "${commentsList[index].hidden ? "(hidden comment) " : ""}${commentsList[index].author} • ${getTimeDeltaInHumanReadable(commentsList[index].commentDate)} ago",
              style: Theme.of(context).textTheme.labelSmall!.copyWith(
                    color: commentsList[index].hidden
                        ? Theme.of(context).colorScheme.error
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  )),
          subtitle:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              commentsList[index].commentBody,
              style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 5),
            Row(children: [
              Row(children: [
                Skeleton.shade(
                    child: Icon(
                        size: 16,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        Icons.thumb_up)),
                const SizedBox(width: 5),
                Text(
                    isLoadingComments
                        ? "3000 | 300"
                        : commentsList[index].ratingsPositiveTotal != null &&
                                commentsList[index].ratingsNegativeTotal != null
                            ? "${convertNumberIntoHumanReadable(commentsList[index].ratingsPositiveTotal!)} "
                                "| ${convertNumberIntoHumanReadable(commentsList[index].ratingsNegativeTotal!)}"
                            : "${commentsList[index].ratingsTotal}",
                    maxLines: 1,
                    style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant)),
                const SizedBox(width: 5),
                Skeleton.shade(
                    child: Icon(
                        size: 16,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        Icons.thumb_down))
              ]),
              if (commentsList[index].replyComments?.isNotEmpty ?? false) ...[
                const SizedBox(width: 15),
                TextButton(
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.all(0),
                      minimumSize: const Size(0, 0),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Row(children: [
                      Skeleton.shade(
                          child: Icon(
                              size: 16,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                              Icons.comment)),
                      const SizedBox(width: 5),
                      Text(
                          isLoadingComments
                              ? "10"
                              : convertNumberIntoHumanReadable(
                                  commentsList[index].replyComments!.length),
                          maxLines: 1,
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium!
                              .copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant)),
                    ]),
                    onPressed: () => setState(() {
                          animateReplySection = true;
                          replyCommentIndex = index;
                          showReplySection = true;
                        })),
              ],
            ])
          ]),
          isThreeLine: true,
        ));
  }

  Widget buildDetailsSection() {
    return FutureBuilder<UniversalVideoMetadata?>(
      future: widget.videoMetadata,
      builder: (context, _) {
        return Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
              child: CustomScrollView(
                  physics: isMobile
                      ? const ScrollPhysics()
                      : const NeverScrollableScrollPhysics(),
                  controller: isMobile ? screenScrollController : null,
                  slivers: [
                FloatingDynamicSliverHeader(
                    backgroundColor: Theme.of(context).colorScheme.surface,
                    child: buildVideoDetails()),
                if (!isMobile)
                  SliverPadding(
                    padding: EdgeInsets.only(top: 20),
                    sliver: SliverFillRemaining(child: buildCommentSection()),
                  ),
                if (isMobile) ...buildVideoSuggestions()
              ]))
        ]));
      },
    );
  }

  List<Widget> buildVideoSuggestions() {
    return [
      FloatingDynamicSliverHeader(
          pinned: true,
          backgroundColor: Theme.of(context).colorScheme.surface,
          child: Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(
                    "Related videos from ${videoMetadata.plugin?.prettyName ?? ""}:",
                    style: isMobile
                        ? Theme.of(context).textTheme.titleMedium!
                        : Theme.of(context).textTheme.bodyMedium!),
                Spacer(),
                if (loadingHandler.videoSuggestionsIssues.isNotEmpty &&
                    !isLoadingMetadata) ...[
                  IconButton(
                      constraints: const BoxConstraints(),
                      padding: EdgeInsets.zero,
                      icon: Icon(
                          color: Theme.of(context).colorScheme.error,
                          Icons.error_outline),
                      onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (context) => ScrapingReportScreen(
                                    singleProviderMap:
                                        loadingHandler.videoSuggestionsIssues,
                                    singleDebugObject: videoMetadata.toMap(),
                                  ))).whenComplete(() => setState(() {})))
                ]
              ]))),
      VideoList(
          videoList: videoSuggestions,
          scrollController: screenScrollController,
          onVideoTap: () => videoPlayerWidgetKey.currentState?.pausePlayer(),
          loadMoreResults: loadMoreResults,
          noResultsMessage: "No video suggestions found",
          noResultsErrorMessage: "Error getting video suggestions",
          showScrapingReportButton: true,
          scrapingReportMap: loadingHandler.videoSuggestionsIssues,
          ignoreInternetError: false,
          noListPadding: true,
          overrideListViewTo: "Card",
          singleProviderDebugObject: videoMetadata.toMap())
    ];
  }
}
