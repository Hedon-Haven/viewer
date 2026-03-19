import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:html/dom.dart';
import 'package:yaml/yaml.dart';

import '/utils/global_vars.dart';
import '/utils/universal_formats.dart';

class PluginInterface {
  /// This is overridden to true in official plugins
  final bool isOfficialPlugin = false;

  /// codeName must be a unique identifier for the plugin, to avoid conflicts,
  /// especially if the plugin overrides an official plugin. Cannot be empty
  /// Cannot contain spaces, special chars or non-latin characters, as its used
  /// as the directory name for the plugin.
  String codeName = "";

  /// prettyName must be the official, correctly cased name of the provider. Cannot be empty
  String prettyName = "";

  /// Plugin version
  double version = 0.0;

  /// UpdateUri is optional. If provided, it will be used to check for updates.
  Uri? updateUrl;

  /// Icon must point to a small icon of the website, preferably the favicon
  Uri iconUrl = Uri.parse("");

  /// The base website url of the plugin provider, as a string. Example: https://example.com
  String providerUrl = "";

  /// Initial homepage number
  int initialHomePage = 0;

  /// Initial search page number
  int initialSearchResultsPage = 0;

  /// Initial comment page number
  int initialCommentsPage = 0;

  /// Initial video suggestions page number
  int initialVideoSuggestionsPage = 0;

  /// Initial video suggestions page number
  int initialAuthorVideosPage = 0;

  // Internal variables
  /// The path to the root of the plugin
  // ignore: prefer_final_fields
  String _pluginPath = "";

  /// The path of the plugin binary to be executed.
  String _binaryPath = "";

  /// The path to the cache dir, which is usually a symlink to the Platforms cache dir for the app
  String _cachePath = "";

  PluginInterface(this._pluginPath) {
    _binaryPath = "$_pluginPath/bin/binaryLink";
    _cachePath = "$_pluginPath/cache";
    if (!_checkAndLoadFromConfig("$_pluginPath/plugin.yaml")) {
      throw Exception(
          "Failed to load from config file: $_pluginPath/plugin.yaml");
    }
  }

  bool _checkAndLoadFromConfig(String configPath) {
    try {
      var config = loadYaml(File(configPath).readAsStringSync());
      codeName = config["codeName"];
      prettyName = config["prettyName"];
      version = config["version"];
      updateUrl = Uri.parse(config["updateUrl"]);
      iconUrl = Uri.parse(config["iconUrl"]);
      providerUrl = config["providerUrl"];
      initialHomePage = config["initialHomePage"];
      initialSearchPage = config["initialSearchPage"];
      providesHomepage = config["providesHomepage"];
      providesResults = config["providesResults"];
      providesSearchSuggestions = config["providesSearchSuggestions"];
      providesVideo = config["providesVideo"];
      providesDownloads = config["providesDownloads"];
    } catch (e) {
      logger.e("Error loading configuration: $e");
      return false;
    }
    return true;
  }

  Future<Map<String, dynamic>> _runPlugin(
      String command, Map<String, dynamic> arguments) async {
    Process pluginProcess = await Process.start(_binaryPath, [command]);
    pluginProcess.stdin.write(jsonEncode(arguments));
    await pluginProcess.stdin.flush();
    pluginProcess.stdin.close();

    Map<String, dynamic> responseMap = {};
    pluginProcess.stdout.listen((List<int> list) {
      String? responseString;
      try {
        // Decode response into a String and then into a map
        responseString = utf8.decode(list).trim();
        responseMap = json.decode(responseString);
      } catch (e) {
        if (e is StateError && e.message == "No element") {
          logger.e("Received no response from process");
          throw Exception("No response from $codeName plugin");
        }
        // if the decoding fails at char 1 (i.e. its not a json at all, rather than a broken json)
        // treat it as an info log from the plugin
        else if (e is FormatException &&
            e.toString().startsWith(
                "FormatException: Unexpected character (at character 1)")) {
          if (responseString != null) {
            logger.i("$codeName: $responseString");
          }
        } else {
          rethrow;
        }
      }
    });

    pluginProcess.exitCode.then((value) {
      if (value != 0) {
        logger.e("Plugin process didn't exit cleanly, exit code: $value");
      }
    });

    // wait for plugin to finish
    await pluginProcess.exitCode;
    // TODO: Return exit code
    return responseMap;
  }

  /// Some plugins might need to be prepared before they can be used (e.g. fetch cookies)
  Future<bool> initPlugin([void Function(String body)? debugCallback]) async {
    try {
      await _runPlugin("getSearchResults", {});
    } catch (e) {
      return false;
    }
    return true;
  }

  /// Test full plugin functionality and return false if it fails
  //TODO: Set up proper Map<String, dynamic> testResults
  Future<bool> runFunctionalityTest() async {
    try {
      _runPlugin("runInitTest", {}).then((value) => testResults = value);
    } catch (e) {
      logger.i("Init test failed with: $e");
      return false;
    }
  }

  /// Return the homepage
  Future<List<UniversalVideoPreview>> getHomePage(int page,
      [void Function(String body)? debugCallback]) async {
    throw UnimplementedError();
  }

  /// This function returns the requested thumbnail as a blob
  Future<Uint8List> downloadThumbnail(Uri uri) async {
    throw UnimplementedError();
  }

  /// Some websites have custom search results with custom elements (e.g. preview images). Only return simple word based search suggestions
  Future<List<String>> getSearchSuggestions(String searchString,
      [void Function(String body)? debugCallback]) async {
    throw UnimplementedError();
  }

  /// Return list of search results
  Future<List<UniversalVideoPreview>> getSearchResults(
      UniversalSearchRequest sr, int page,
      [void Function(String body)? debugCallback]) async {
    throw UnimplementedError();
  }

  Uri? getVideoUriFromID(String videoID) {
    throw UnimplementedError();
  }

  /// Request video metadata and convert it to UniversalFormat<br>
  /// Errors from this function are caught by loadingHandler and do not need to be handled within it
  Future<UniversalVideoMetadata> getVideoMetadata(
      String videoID, UniversalVideoPreview uvp,
      [void Function(String body)? debugCallback]) async {
    throw UnimplementedError();
  }

  /// Get all progressThumbnails for a video and return them as a List
  Future<List<Uint8List>?> getProgressThumbnails(
      String videoID, Document rawHtml) {
    throw UnimplementedError();
  }

  void cancelGetProgressThumbnails() {
    throw UnimplementedError();
  }

  Future<Uri?> getCommentUriFromID(String commentID, String videoID) async {
    throw UnimplementedError();
  }

  /// Get comments for a video, per page
  Future<List<UniversalComment>> getComments(
      String videoID, Document rawHtml, int page,
      [void Function(String body)? debugCallback]) {
    throw UnimplementedError();
  }

  /// Get video suggestions for a video, per page
  Future<List<UniversalVideoPreview>> getVideoSuggestions(
      String videoID, Document rawHtml, int page,
      [void Function(String body)? debugCallback]) {
    throw UnimplementedError();
  }

  Future<Uri?> getAuthorUriFromID(String authorID) async {
    throw UnimplementedError();
  }

  /// Request author page and convert it to UniversalFormat
  Future<UniversalAuthorPage> getAuthorPage(String authorID,
      [void Function(String body)? debugCallback]) async {
    throw UnimplementedError();
  }

  /// Get video suggestions for a video, per page
  Future<List<UniversalVideoPreview>> getAuthorVideos(String authorID, int page,
      [void Function(String body)? debugCallback]) {
    throw UnimplementedError();
  }
}
