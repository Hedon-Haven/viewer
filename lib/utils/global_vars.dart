import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:logger/logger.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '/services/http_manager.dart';
import 'custom_logger.dart';

// Make these late-initialized to allow mocking them in tests
late SharedPreferencesAsync sharedStorage;
late Logger logger;
late PackageInfo packageInfo;
late http.Client client;
// Generic Windows Chrome user agent
String httpUserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
    "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.0.0 Safari/537.3";
late StreamController<void> reloadVideoListEvent;
late StreamController<int> pluginUpdatesAvailableEvent;

/// Global visual app reload. MUST be set from initGlobalSetState, NOT from the main initGlobalVars()
late void Function() globalSetState;

/// This stores the global setting of whether the preview should be hidden
bool hidePreview = true;

// Make this bool a global var, -> user only sees the warning once per session
bool thirdPartyPluginWarningShown = false;

// Each initialization is a separate function to allow mocking only some parts
// of the app
Future<void> initGlobalVars() async {
  await initSharedStorage();
  await initLogger();
  await initPackageInfo();
  await initHttpClient();
  await initEvents();
}

// This function is not called by the main initGlobalVars as it has to be set
// from the UI part of main, not the startup part
Future<void> initGlobalSetState(void Function() function) async {
  globalSetState = function;
}

Future<void> initSharedStorage() async {
  sharedStorage = SharedPreferencesAsync();
}

Future<void> initLogger() async {
  logger = Logger(
    printer: BetterSimplePrinter(),
    filter: VariableFilter(),
  );
}

Future<void> initPackageInfo() async {
  packageInfo = await PackageInfo.fromPlatform();
}

Future<void> initHttpClient() async {
  logger.i("Initializing http client");
  String? proxy = await sharedStorage.getString("privacy_proxy_address");
  logger.i("Using proxy: ${proxy?.isEmpty ?? true ? "None" : proxy}");
  client = getHttpClient(proxy);
}

Future<void> initEvents() async {
  logger.i("Initializing stream controllers");
  reloadVideoListEvent = StreamController<void>.broadcast();
  pluginUpdatesAvailableEvent = StreamController<int>.broadcast();
}
