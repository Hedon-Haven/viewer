import 'dart:async';
import 'dart:io';

import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fvp/fvp.dart' as fvp;
import 'package:secure_app_switcher/secure_app_switcher.dart';
import 'package:super_drag_and_drop/super_drag_and_drop.dart';

import '/services/database_manager.dart';
import '/services/icon_manager.dart';
import '/services/plugin_manager.dart';
import '/services/shared_prefs_manager.dart';
import '/services/update_manager.dart';
import '/ui/screens/fake_apps/fake_reminders.dart';
import '/ui/screens/fake_apps/fake_settings.dart';
import '/ui/screens/home.dart';
import '/ui/screens/library.dart';
import '/ui/screens/onboarding/onboarding_welcome.dart';
import '/ui/screens/settings/settings_main.dart';
import '/ui/utils/handle_desktop_events.dart';
import '/ui/utils/toast_notification.dart';
import '/ui/utils/update_dialog.dart';
import '/utils/global_vars.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  fvp.registerWith(options: {
    // fix audio cracking when seeking
    // FIXME: When enabling this, hw acceleration breaks
    //"player": {"audio.renderer": "AudioTrack"}
  });
  await initGlobalVars();
  logger.i("Initializing app");
  await setDefaultSettings();
  await initDb();
  await PluginManager.init();
  // Icons are not critical to startup -> don't await
  downloadPluginIcons();
  await processArgs();
  logger.i("Starting flutter process");
  runApp(const ViewerApp());
}

Future<void> processArgs() async {
  logger.i("Processing args");

  const skipOnboarding =
      bool.fromEnvironment("SKIP_ONBOARDING", defaultValue: false);
  if (skipOnboarding) {
    logger.w("Skipping onboarding");
    await sharedStorage.setBool("general_onboarding_completed", true);
  }
  const resetSettings =
      bool.fromEnvironment("RESET_SETTINGS", defaultValue: false);
  if (resetSettings) {
    logger.w("Resetting settings");
    setDefaultSettings(true);
  }

  logger.i("Finished processing args");
}

class ViewerApp extends StatefulWidget {
  const ViewerApp({super.key});

  @override
  ViewerAppState createState() => ViewerAppState();

  static ViewerAppState? of(BuildContext context) =>
      context.findAncestorStateOfType<ViewerAppState>();
}

class ViewerAppState extends State<ViewerApp> with WidgetsBindingObserver {
  // This is required to show the update dialog in the correct context
  final GlobalKey<NavigatorState> materialAppKey = GlobalKey<NavigatorState>();

  late final KeyEventCallback escapeHandler;

  /// Whether the app should stop showing a fake screen
  bool concealApp = true;
  bool updateAvailable = false;
  bool showSettingsBadge = false;
  UpdateManager updateManager = UpdateManager();

  Future<bool> onboardingCompleted = sharedStorage
      .getBool("general_onboarding_completed")
      .then((value) => value ?? false);
  Future<String> appearanceType = sharedStorage
      .getString("appearance_launcher_appearance")
      .then((value) => value ?? "Hedon Haven");
  Future<ThemeMode> themeMode = getThemeMode();

  /// This controls whether the preview should be currently blocked
  bool blockPreview = false;

  /// Tracks the hash of the currently hovered drop
  bool hoveringWithLink = false;
  int _selectedIndex = 0;
  static List<Widget> screenList = <Widget>[
    const HomeScreen(),
    //const SubscriptionsScreen(),
    const LibraryScreen(),
    const SettingsScreen(),
  ];

  @override
  void initState() {
    super.initState();

    initGlobalSetState(setStateMain);

    // Hide app preview by default
    // The desktops don't support app preview hiding at an OS level
    if (Platform.isAndroid || Platform.isIOS) {
      SecureAppSwitcher.on();
    }
    sharedStorage.getBool("privacy_hide_app_preview").then((value) {
      if (!value!) {
        // The desktops don't support app preview hiding at an OS level
        if (Platform.isAndroid || Platform.isIOS) {
          SecureAppSwitcher.off();
        }
      }
      setState(() => hidePreview = value);
    });

    // For detecting app state
    WidgetsBinding.instance.addObserver(this);

    // Add global key handling for desktop
    escapeHandler = (event) => handleEscape(event, materialAppKey);
    HardwareKeyboard.instance.addHandler(escapeHandler);

    // Enable badge when plugin update check finishes and updates are available
    pluginUpdatesAvailableEvent.stream
        .listen((value) => setState(() => showSettingsBadge = value != 0));

    performUpdate();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    HardwareKeyboard.instance.removeHandler(escapeHandler);
    super.dispose();
  }

  // This is only necessary for desktops, as the mobile platforms have that feature built in
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (hidePreview) {
      if (state == AppLifecycleState.paused ||
          state == AppLifecycleState.inactive) {
        if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
          logger.d("Blurring app");
          setState(() {
            blockPreview = true;
          });
        }
      } else if (state == AppLifecycleState.resumed) {
        if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
          logger.d("Unblurring app");
          setState(() {
            blockPreview = false;
          });
        }
      }
    }
  }

  Future<void> performUpdate() async {
    try {
      // Start getting update first, then wait for context to be available
      updateAvailable = await updateManager.updateAvailable();
      if (updateAvailable) {
        // Wait for the context to be available
        Timer.periodic(const Duration(milliseconds: 100), (timer) {
          if (materialAppKey.currentContext != null) {
            timer.cancel();
            showUpdateDialog(updateManager, materialAppKey.currentContext!);
          }
        });
      }
    } catch (e, stacktrace) {
      logger.e("Error checking for app update (waiting for context + 1 second "
          "before displaying to user): $e\n$stacktrace");
      // Wait for the context to be available
      Timer.periodic(const Duration(milliseconds: 100), (timer) async {
        if (materialAppKey.currentState?.overlay != null) {
          timer.cancel();
          // wait a bit more to make sure the message appears
          await Future.delayed(const Duration(seconds: 1));
          showToastViaOverlay("Error checking for app update: $e",
              materialAppKey.currentState!.overlay!, 5);
        }
      });
    }
  }

  void parentStopConcealing() {
    setState(() => concealApp = false);
  }

  void setStateMain() {
    logger.w("Global setState called");

    // reload ui vars to force a true reload
    onboardingCompleted = sharedStorage
        .getBool("general_onboarding_completed")
        .then((value) => value ?? false);
    appearanceType = sharedStorage
        .getString("appearance_launcher_appearance")
        .then((value) => value ?? "Hedon Haven");
    themeMode = getThemeMode();

    // Set current screen to home
    _selectedIndex = 0;

    // Clear navigation stack
    materialAppKey.currentState?.popUntil((route) => route.isFirst);

    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return DynamicColorBuilder(builder: (lightColorScheme, darkColorScheme) {
      return FutureBuilder<ThemeMode?>(
          future: themeMode,
          builder: (context, snapshot) {
            final isMobile = Platform.isAndroid || Platform.isIOS;
            return MaterialApp(
                title: "Hedon Haven",
                theme: ThemeData(
                  // Disable click
                  splashFactory: isMobile
                      ? InkRipple.splashFactory
                      : NoSplash.splashFactory,
                  // Try to use system colors first and fallback to Green
                  colorScheme: lightColorScheme ??
                      ColorScheme.fromSwatch(primarySwatch: Colors.green),
                ),
                darkTheme: ThemeData(
                  splashFactory: isMobile
                      ? InkRipple.splashFactory
                      : NoSplash.splashFactory,
                  colorScheme: darkColorScheme ??
                      ColorScheme.fromSwatch(
                          primarySwatch: Colors.green,
                          brightness: Brightness.dark),
                ),
                themeMode: snapshot.data ?? ThemeMode.system,
                navigatorKey: materialAppKey,
                home: DropRegion(
                  // Formats this region can accept.
                  formats: [Formats.uri],
                  hitTestBehavior: HitTestBehavior.opaque,
                  // Cannot properly test for https/http here due to callback nature of onDropOver
                  onDropOver: (event) {
                    return event.session.items.first.canProvide(Formats.uri)
                        ? DropOperation.copy
                        : DropOperation.none;
                  },
                  onDropEnter: (event) =>
                      setState(() => hoveringWithLink = true),
                  onDropLeave: (event) =>
                      setState(() => hoveringWithLink = false),
                  onPerformDrop: (event) async {
                    event.session.items.first.dataReader!.getValue(Formats.uri,
                        (value) {
                      // Only accept http and https links
                      if (value != null &&
                          (value.uri.scheme == "https" ||
                              value.uri.scheme == "http")) {
                        logger.i("Dropped link: ${value.uri.toString()}");
                      } else {
                        logger.w("Dropped non-http/https link");
                      }
                    }, onError: (error) {
                      logger.e("Error reading dropped link: $error");
                    });
                  },
                  child: Stack(children: [
                    FutureBuilder<bool?>(
                        future: onboardingCompleted,
                        builder: (context, snapshotParent) {
                          // Don't show anything until the future is done
                          if (snapshotParent.connectionState ==
                              ConnectionState.waiting) {
                            return const SizedBox();
                          }
                          return !snapshotParent.data!
                              ? WelcomeScreen()
                              : FutureBuilder<String?>(
                                  future: appearanceType,
                                  builder: (context, snapshot) {
                                    // Don't show anything until the future is done
                                    if (snapshot.connectionState ==
                                        ConnectionState.waiting) {
                                      return const SizedBox();
                                    }
                                    if (!concealApp) {
                                      logger.i(
                                          "App concealing was disabled, loading default app");
                                      return buildRealApp();
                                    }
                                    switch (snapshot.data!) {
                                      case "GSM Settings":
                                        return FakeSettingsScreen(
                                            parentStopConcealing:
                                                parentStopConcealing);
                                      case "Reminders":
                                        return FakeRemindersScreen(
                                            parentStopConcealing:
                                                parentStopConcealing);
                                      default:
                                        return buildRealApp();
                                    }
                                  });
                        }),
                    if (blockPreview) ...[
                      Positioned.fill(
                        child: Container(color: Colors.black),
                      ),
                    ]
                  ]),
                ));
          });
    });
  }

  Widget buildRealApp() {
    return Scaffold(
        bottomNavigationBar: NavigationBar(
            destinations: <Widget>[
              NavigationDestination(
                icon: _selectedIndex == 0
                    ? const Icon(Icons.home)
                    : const Icon(Icons.home_outlined),
                label: "Home",
              ),
              // NavigationDestination(
              //   icon: _selectedIndex == 1
              //       ? const Icon(Icons.subscriptions)
              //       : const Icon(Icons.subscriptions_outlined),
              //   label: "Subscriptions",
              // ),
              NavigationDestination(
                icon: _selectedIndex == 1
                    ? const Icon(Icons.video_library)
                    : const Icon(Icons.video_library_outlined),
                label: "Library",
              ),
              NavigationDestination(
                icon: Badge(
                  isLabelVisible: showSettingsBadge,
                  smallSize: 10,
                  alignment: AlignmentDirectional.centerEnd,
                  child: _selectedIndex == 2
                      ? const Icon(Icons.settings)
                      : const Icon(Icons.settings_outlined),
                ),
                label: "Settings",
              ),
            ],
            selectedIndex: _selectedIndex,
            onDestinationSelected: (index) {
              setState(() {
                _selectedIndex = index;
              });
            }),
        body: ClipRect(
          child: Stack(children: [
            ...screenList.asMap().entries.map((entry) => AnimatedSlide(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeInOut,
                  offset: entry.key == _selectedIndex
                      ? Offset.zero
                      : Offset(entry.key < _selectedIndex ? -1.0 : 1.0, 0),
                  child: entry.value,
                )),
            if (hoveringWithLink) ...[
              Positioned.fill(
                // Fixes wrong colorScheme being used (wrong context)
                child: Builder(
                    builder: (context) => Container(
                        color:
                            Theme.of(context).colorScheme.surfaceContainerHigh,
                        child: Padding(
                            padding: EdgeInsets.all(100),
                            child: Container(
                                color: Theme.of(context)
                                    .colorScheme
                                    .surfaceContainerHighest,
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    spacing: 50,
                                    children: [
                                      Text("Drop to open",
                                          style: Theme.of(context)
                                              .textTheme
                                              .headlineLarge!
                                              .copyWith(
                                                  fontWeight: FontWeight.bold,
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .onSurface)),
                                      Icon(Icons.open_in_browser, size: 70)
                                    ]))))),
              ),
            ]
          ]),
        ));
  }
}
