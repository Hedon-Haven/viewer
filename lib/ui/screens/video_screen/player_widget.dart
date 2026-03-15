import 'dart:async';
import 'dart:typed_data';

import 'package:audio_video_progress_bar/audio_video_progress_bar.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '/ui/screens/bug_report.dart';
import '/utils/global_vars.dart';
import '/utils/universal_formats.dart';

class VideoPlayerWidget extends StatefulWidget {
  UniversalVideoMetadata videoMetadata;
  List<Uint8List>? progressThumbnails;
  bool isFullScreen;
  final Function() toggleFullScreen;

  VideoPlayerWidget(
      {super.key,
      required this.videoMetadata,
      required this.progressThumbnails,
      required this.isFullScreen,
      required this.toggleFullScreen});

  @override
  State<VideoPlayerWidget> createState() => VideoPlayerWidgetState();
}

class VideoPlayerWidgetState extends State<VideoPlayerWidget> {
  int skipBy = 5;
  Timer? hideControlsTimer;
  bool showControls = false;
  bool hidePlayControls = false;
  bool firstPlay = true;
  bool showProgressThumbnail = false;
  bool enableProgressThumbnails = false;
  int selectedResolution = 0;
  List<int> sortedResolutions = [];
  VideoPlayerController controller =
      VideoPlayerController.networkUrl(Uri.parse(""));
  Uint8List timelineProgressThumbnail = Uint8List(0);
  Uint8List emptyImage = Uint8List(0);
  double progressThumbnailPosition = 0.0;
  String? videoPlayerError;
  double dragOffsetY = 0.0;

  @override
  void initState() {
    super.initState();

    sharedStorage.getBool("media_show_progress_thumbnails").then((value) {
      enableProgressThumbnails = value!;
    });

    sharedStorage.getInt("media_seek_duration").then((value) {
      skipBy = value!;
    });

    initVideoPlayer();
  }

  void initVideoPlayer() async {
    // read preferred video quality setting
    int preferredQuality =
        (await sharedStorage.getInt("media_preferred_video_quality"))!;
    selectedResolution = preferredQuality;

    if (widget.videoMetadata.virtualReality) {
      setState(
          () => videoPlayerError = "Virtual reality videos not yet supported");
    }

    if (widget.videoMetadata.m3u8Uris.length > 1) {
      // select the preferred quality, or the closest to it

      // Sort the available resolutions in ascending order
      sortedResolutions = widget.videoMetadata.m3u8Uris.keys.toList()..sort();

      // If the user's choice is not in the list, find the next highest resolution
      if (!sortedResolutions.contains(preferredQuality)) {
        int nextHighest = preferredQuality;
        for (int i = 0; i < sortedResolutions.length - 1; i++) {
          if (sortedResolutions[i] < preferredQuality) {
            nextHighest = sortedResolutions[i + 1];
          }
        }
        selectedResolution = nextHighest;
      }
    } else {
      selectedResolution = sortedResolutions[0];
    }
    // Check if m3u8 links exist and display toast message
    if (widget.videoMetadata.m3u8Uris[selectedResolution] == null) {
      setState(
          () => videoPlayerError = "Couldn't play video: M3U8 url not found");
    }
    initVideoController(widget.videoMetadata.m3u8Uris[selectedResolution]!);
  }

  @override
  void dispose() {
    controller.dispose();
    hideControlsTimer?.cancel();
    super.dispose();
  }

  void initVideoController(Uri url) {
    final bool isPlaying = controller.value.isPlaying;
    final oldPosition = controller.value.position;
    logger.d("Old position: $oldPosition");

    logger.i("Setting new url: $url");
    controller = VideoPlayerController.networkUrl(url,
        httpHeaders: widget.videoMetadata.playbackHttpHeaders ?? {});
    controller.initialize().then((value) async {
      await controller.seekTo(oldPosition);
      if (firstPlay) {
        logger.d("Video controller prepping for first play");
        firstPlay = false;
        if ((await sharedStorage.getBool("media_start_in_fullscreen"))!) {
          logger.i("Full-screening video as per settings");
          widget.toggleFullScreen.call();
        }
        if ((await sharedStorage.getBool("media_auto_play"))!) {
          logger.i("Auto-starting video as per settings");
          await controller.play();
          hideControlsOverlay();
          return; // return, so that controls arent automatically shown
        }
        // only show controls after controller is fully done initializing
        showControls = true;
      }
      if (isPlaying) {
        logger.i("Resuming video");
        await controller.play();
      }
      setState(() {});
    });

    // video_player sometimes just silently fails to init
    // -> add a timeout that will show an error to the user if the video fails to init in 15 seconds
    Timer? errorTimeout;
    errorTimeout ??= Timer(const Duration(seconds: 10), () {
      if (!controller.value.isInitialized &&
          !controller.value.isBuffering &&
          controller.value.position == Duration.zero) {
        logger.e("Video player initialization timed out");
        setState(() =>
            videoPlayerError = "Video player failed to initialize due to: "
                "${controller.value.errorDescription ?? "Timeout error"}");
      }
    });

    controller.addListener(() {
      final playerState = controller.value;

      if (playerState.hasError && !playerState.isCompleted) {
        errorTimeout?.cancel();
        logger.e("Video playback error: ${playerState.errorDescription}");
        setState(() => videoPlayerError =
            "Video player encountered error during playback: "
                "${playerState.errorDescription ?? "Unknown playback error"}");
        return;
      }

      // Cancel timeout if video starts playing or initializes
      if (playerState.position > Duration.zero || playerState.isInitialized) {
        errorTimeout?.cancel();
      }
    });

    controller.position.asStream().listen((_) {
      // rebuild tree when video position changes
      // make sure tree is still mounted
      if (mounted) setState(() {});
    });
  }

  void hideControlsOverlay() {
    hideControlsTimer?.cancel(); // stop any old timers
    hideControlsTimer = Timer(const Duration(seconds: 3), () {
      logger.d("Timer is completed");
      if (showProgressThumbnail) {
        // don't hide controls while progress thumbnail is shown
        logger.d("Progress thumbnail shown, not hiding controls");
        return;
      }
      setState(() {
        showControls = false;
      });
    });
  }

  void showControlsOverlay() {
    logger.d("Show controls triggered");
    if (firstPlay) {
      // refuse to show controls while video is initializing the first time
      return;
    }
    if (!(hideControlsTimer?.isActive ?? true) && controller.value.isPlaying) {
      logger.d("Timer not running, starting it");
      hideControlsOverlay();
    } else {
      logger.d("Timer is running, stopping it");
      hideControlsTimer?.cancel();
    }
    setState(() {
      showControls = !showControls;
      logger.d("showControls set to: $showControls");
    });
  }

  void playPausePlayer() async {
    if (controller.value.isPlaying) {
      controller.pause();
      WakelockPlus.disable();
      hideControlsTimer?.cancel();
    } else {
      controller.play();
      WakelockPlus.enable();
      hideControlsOverlay();
    }
    setState(() {});
  }

  void pausePlayer() async {
    if (controller.value.isPlaying) {
      controller.pause();
      WakelockPlus.disable();
      hideControlsTimer?.cancel();
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
        onPopInvoked: (goingToPop) {
          // immediately stop video if popping
          if (goingToPop) {
            logger.d("Stopping video on pop");
            controller.pause();
          }
        },
        child: GestureDetector(
            onLongPress: () {
              showModalBottomSheet(
                context: context,
                builder: (BuildContext context) {
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      ListTile(
                        leading: const Icon(Icons.bug_report),
                        title: const Text("Create bug report"),
                        onTap: () {
                          Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (context) => BugReportScreen(
                                              debugObject: [
                                                widget.videoMetadata.toMap()
                                              ])))
                              .then((value) => Navigator.of(context).pop());
                        },
                      )
                    ],
                  );
                },
              );
            },
            // pass taps to elements below
            behavior: HitTestBehavior.translucent,
            onTap: showControlsOverlay,
            onVerticalDragUpdate: (details) {
              setState(() {
                dragOffsetY = (dragOffsetY + details.delta.dy).clamp(
                  widget.isFullScreen ? 0.0 : -maxDrag,
                  widget.isFullScreen ? maxDrag : 0.0,
                );
              });
            },
            onVerticalDragEnd: (details) {
              final triggered = dragOffsetY.abs() >= maxDrag;
              setState(() => dragOffsetY = 0.0);
              if (triggered) widget.toggleFullScreen.call();
            },
            child: Stack(children: [
              OverflowBox(
                  maxHeight: double.infinity,
                  child: Transform.scale(
                      scale: widget.isFullScreen
                          ? 1.0 - (dragOffsetY.abs() / maxDrag) * 0.2
                          : 1.0 + (dragOffsetY.abs() / maxDrag) * 0.2,
                      alignment: Alignment.bottomCenter,
                      child: Container(
                          color: Colors.black,
                          child: SizedBox(
                              height: MediaQuery.of(context).orientation ==
                                      Orientation.landscape
                                  ? MediaQuery.of(context).size.height
                                  : MediaQuery.of(context).size.width * 9 / 16,
                              child: videoPlayerError != null
                                  ? buildErrorScreen()
                                  : Stack(
                                      alignment: Alignment.center,
                                      children: <Widget>[
                                        controller.value.isInitialized
                                            // This makes the video 16:9 while loading -> skeleton looks weird otherwise
                                            ? AspectRatio(
                                                aspectRatio: controller
                                                        .value.isInitialized
                                                    ? controller
                                                        .value.aspectRatio
                                                    : 16 / 9,
                                                child: VideoPlayer(controller))
                                            : const CircularProgressIndicator(
                                                color: Colors.white),
                                        // gray background to make buttons more visible when overlay is on
                                        OverlayWidget(
                                          showControls: showControls,
                                          child: Container(
                                            width: double.infinity,
                                            height: double.infinity,
                                            color: Colors.black
                                                .withValues(alpha: 0.5),
                                          ),
                                        ),
                                        buildSkipWidget(),
                                        OverlayWidget(
                                          showControls:
                                              showControls && !hidePlayControls,
                                          child: controller.value.isBuffering
                                              ? const CircularProgressIndicator(
                                                  color: Colors.white,
                                                )
                                              : CircleAvatar(
                                                  radius: 28,
                                                  backgroundColor: Colors.black
                                                      .withValues(alpha: 0.2),
                                                  child: IconButton(
                                                    splashColor:
                                                        Colors.transparent,
                                                    icon: Icon(
                                                      controller.value.isPlaying
                                                          ? Icons.pause
                                                          : Icons.play_arrow,
                                                      size: 40.0,
                                                      color: Colors.white,
                                                    ),
                                                    color: Colors.white,
                                                    onPressed: playPausePlayer,
                                                  ),
                                                ),
                                        ),
                                        Positioned(
                                            left: progressThumbnailPosition,
                                            bottom: 50,
                                            // TODO: Set size limits
                                            child: OverlayWidget(
                                                showControls: showControls,
                                                child: showProgressThumbnail
                                                    ? widget.progressThumbnails !=
                                                            null
                                                        ? Image.memory(
                                                            timelineProgressThumbnail,
                                                            width: 160,
                                                            height: 90)
                                                        : Container(
                                                            color: Colors.black,
                                                            width: 160,
                                                            height: 90,
                                                            child: const Center(
                                                                child: CircularProgressIndicator(
                                                                    color: Colors
                                                                        .white)))
                                                    : const SizedBox())),
                                        Positioned(
                                            top: 5,
                                            right: 10,
                                            child: buildQualityDropdown()),
                                        Positioned(
                                          bottom: 5.0,
                                          left: 20.0,
                                          right: 0.0,
                                          child: Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.start,
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.center,
                                              children: <Widget>[
                                                Expanded(
                                                  child: buildProgressBar(),
                                                ),
                                                OverlayWidget(
                                                    showControls: showControls,
                                                    child: IconButton(
                                                      icon: Icon(
                                                        widget.isFullScreen
                                                            ? Icons
                                                                .fullscreen_exit
                                                            : Icons.fullscreen,
                                                        color: Colors.white,
                                                        size: 30.0,
                                                      ),
                                                      onPressed: widget
                                                          .toggleFullScreen
                                                          .call,
                                                    )),
                                              ]),
                                        ),
                                      ],
                                    ))))),
              // overlay back button unless actively playing video
              if (!controller.value.isInitialized ||
                  showControls ||
                  videoPlayerError != null)
                Positioned(
                    top: 0, left: 0, child: BackButton(color: Colors.white)),
            ])));
  }

  Widget buildErrorScreen() {
    return Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Text(
          videoPlayerError == "Virtual reality videos not yet supported"
              ? "Virtual reality videos not yet supported"
              : "Video player error",
          style: const TextStyle(fontSize: 20),
          textAlign: TextAlign.center),
      if (videoPlayerError != "Virtual reality videos not yet supported") ...[
        SizedBox(height: 10),
        ElevatedButton(
            style: TextButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary),
            child: Text("Create bug report",
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(color: Theme.of(context).colorScheme.onPrimary)),
            onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (context) => BugReportScreen(
                        debugObject: [widget.videoMetadata.toMap()],
                        message: videoPlayerError,
                        issueType: "Functional issue"))))
      ]
    ]));
  }

  Widget buildQualityDropdown() {
    return OverlayWidget(
        showControls: showControls,
        // TODO: Force animation to always go downwards
        child: DropdownButton<String>(
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
          dropdownColor: Colors.black87,
          padding: const EdgeInsets.all(0.0),
          value: "${selectedResolution}p",
          underline: const SizedBox(),
          onChanged: (String? newValue) async {
            selectedResolution =
                int.parse(newValue!.substring(0, newValue.length - 1));
            initVideoController(
                widget.videoMetadata.m3u8Uris[selectedResolution]!);
          },
          items: sortedResolutions.map<DropdownMenuItem<String>>((int value) {
            return DropdownMenuItem<String>(
              value: "${value}p",
              child: Text("${value}p",
                  style: const TextStyle(color: Colors.white)),
            );
          }).toList(),
        ));
  }

  Widget buildProgressBar() {
    return OverlayWidget(
        showControls: showControls,
        child: ProgressBar(
            // The following drag functions are called after the user starts/stops/drags and the screen is updated
            // Therefore anything that is done in these functions wont have an immediate effect, unless something else also updates
            // Use setState to force an update
            onDragStart: !enableProgressThumbnails
                ? null
                : (_) {
                    // if the list is empty (i.e. the getProgressThumbnails function
                    // failed or the provider has no thumbnails), don't show the loading thumbnail
                    if (widget.progressThumbnails?.isNotEmpty ?? true) {
                      logger.d("Drag start, showing progress thumbnail");
                      setState(() {
                        hidePlayControls = true;
                        showProgressThumbnail = true;
                      });
                    } else {
                      logger.d(
                          "Drag start, not showing progress thumbnail because list is empty");
                    }
                  },
            onDragUpdate: !enableProgressThumbnails
                ? null
                : (position) {
                    if (widget.progressThumbnails?.isNotEmpty ?? false) {
                      timelineProgressThumbnail = widget
                          .progressThumbnails![position.timeStamp.inSeconds];
                    }

                    double screenWidth = MediaQuery.of(context).size.width;
                    // make sure the progress image stays within the screen bounds -20px
                    // but still moves with the thumbcursor when it can
                    if (position.globalPosition.dx > 100) {
                      if (position.globalPosition.dx > screenWidth - 100) {
                        progressThumbnailPosition = screenWidth - 180;
                      } else {
                        progressThumbnailPosition =
                            position.globalPosition.dx - 80;
                      }
                    } else {
                      progressThumbnailPosition = 20;
                    }

                    // FIXME: ProgressThumbnails flicker when loaded the first time from memory
                    // FIXME: Invalid image data when loading a real progress thumbnail for the first time
                    setState(() {});
                  },
            // This function is called when the user lets go
            onDragEnd: !enableProgressThumbnails
                ? null
                : () {
                    logger.d("Drag end, hiding progress image");
                    setState(() {
                      hidePlayControls = false;
                      showProgressThumbnail = false;
                    });
                    // start hiding the overlay
                    hideControlsOverlay();
                  },
            // TODO: Possibly make TimeLabels in Youtube style
            timeLabelLocation: TimeLabelLocation.sides,
            timeLabelTextStyle:
                const TextStyle(color: Colors.white, fontSize: 16),
            thumbGlowRadius: 0.0,
            // TODO: Find a way to increase the hitbox without increasing the thumb radius
            thumbRadius: 6.0,
            barCapShape: BarCapShape.square,
            barHeight: 2.0,
            // set baseBarColor to white, with low opacity
            baseBarColor: Colors.white.withValues(alpha: 0.2),
            progressBarColor: Theme.of(context).colorScheme.primary,
            bufferedBarColor: Colors.grey.withValues(alpha: 0.5),
            thumbColor: Theme.of(context).colorScheme.primary,
            progress: controller.value.position,
            buffered: controller.value.buffered.firstOrNull?.end,
            total: controller.value.duration,
            onSeek: (duration) => controller.seekTo(duration)));
  }

  Widget buildSkipWidget() {
    return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      Padding(
          padding: const EdgeInsets.only(right: 100),
          child: OverlayWidget(
              showControls: showControls && !hidePlayControls,
              child: CircleAvatar(
                radius: 23,
                backgroundColor: Colors.black.withValues(alpha: 0.2),
                child: IconButton(
                  splashColor: Colors.transparent,
                  icon: const Icon(
                    Icons.fast_rewind,
                    size: 30.0,
                    color: Colors.white,
                  ),
                  color: Colors.white,
                  onPressed: () {
                    final currentTime = controller.value.position;
                    Duration newTime = const Duration(seconds: 0);
                    // Skipping by a negative value leads to unexpected results
                    logger.d(currentTime.inSeconds);
                    logger.d("Skipping by: $skipBy");
                    if (currentTime.inSeconds > skipBy) {
                      // multiply by -1 to skip backwards
                      newTime = currentTime + Duration(seconds: skipBy * -1);
                    }
                    logger.d("Seeking to: $newTime");
                    controller.seekTo(newTime);
                  },
                ),
              ))),
      Padding(
          padding: const EdgeInsets.only(left: 100),
          child: OverlayWidget(
              showControls: showControls && !hidePlayControls,
              child: CircleAvatar(
                radius: 23,
                backgroundColor: Colors.black.withValues(alpha: 0.2),
                child: IconButton(
                  splashColor: Colors.transparent,
                  icon: const Icon(
                    Icons.fast_forward,
                    size: 30.0,
                    color: Colors.white,
                  ),
                  color: Colors.white,
                  onPressed: () {
                    final newTime =
                        controller.value.position + Duration(seconds: skipBy);
                    controller.seekTo(newTime);
                  },
                ),
              )))
    ]);
  }
}

class OverlayWidget extends StatelessWidget {
  final Widget child;
  bool showControls;

  OverlayWidget({
    super.key,
    required this.child,
    required this.showControls,
  });

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
        // TODO: Wait for animation to finish before ignoring touch input
        ignoring: !showControls,
        child: AnimatedOpacity(
            opacity: showControls ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 220),
            child: child));
  }
}
