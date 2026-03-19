import 'dart:io';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:yaml/yaml.dart';

import '/utils/global_vars.dart';
import '/utils/plugin_interface.dart';
import 'icon_manager.dart';
import 'official_plugins_tracker.dart';

class PluginManager {
  // make the plugin manager a singleton.
  // This way any part of the app can access the plugins, without having to re-initialize them
  static final PluginManager _instance = PluginManager._init();

  PluginManager._init() {
    discoverAndLoadPlugins();
  }

  factory PluginManager() {
    return _instance;
  }

  /// Contains all PluginInterfaces of all valid plugins in the plugins dir, no matter if enabled or not
  static List<PluginInterface> allPlugins = [];

  /// List of all the currently enabled plugins (each plugin must serve as at least one provider), stored as PluginInterfaces and ready to be used
  static List<PluginInterface> enabledPlugins = [];

  /// Map of all the plugins that failed to execute initPlugin() with the message to be displayed to the user
  static Map<PluginInterface, Exception> unavailablePlugins = {};

  /// List of all the currently enabled homepage providing plugins, stored as PluginInterfaces and ready to be used
  static List<PluginInterface> enabledHomepageProviders = [];

  /// List of all the currently enabled results providing plugins, stored as PluginInterfaces and ready to be used
  static List<PluginInterface> enabledResultsProviders = [];

  /// List of all the currently enabled search suggestions providing plugins, stored as PluginInterfaces and ready to be used
  static List<PluginInterface> enabledSearchSuggestionsProviders = [];
  static Directory pluginsDir = Directory("");

  /// Map string names to the corresponding list of plugins
  static final Map<String, List<PluginInterface>> _providerMap = {
    "results": enabledResultsProviders,
    "homepage": enabledHomepageProviders,
    "search_suggestions": enabledSearchSuggestionsProviders
  };

  /// Recursive function to copy a directory into another
  /// Source: https://stackoverflow.com/a/76166248
  static void copyDirectory(Directory source, Directory destination) {
    /// create destination folder if not exist
    if (!destination.existsSync()) {
      destination.createSync(recursive: true);
    }

    /// get all files from source (recursive: false is important here)
    source.listSync(recursive: false).forEach((entity) {
      final newPath = destination.path +
          Platform.pathSeparator +
          entity.path.split(Platform.pathSeparator).last;
      if (entity is File) {
        entity.copySync(newPath);
      } else if (entity is Directory) {
        copyDirectory(entity, Directory(newPath));
      }
    });
  }

  /// Discover all plugins and loading according to settings in sharedStorage
  static Future<void> discoverAndLoadPlugins() async {
    logger.i("Discovering and loading plugins");
    // Set pluginsDir if not already set
    if (pluginsDir.path.isEmpty) {
      // set pluginPath for the whole manager
      Directory appSupportDir = await getApplicationSupportDirectory();
      pluginsDir = Directory("${appSupportDir.path}/plugins");
    }

    // Get cache path
    Directory cachePath = await getApplicationCacheDirectory();

    // Empty plugin lists
    allPlugins = [];
    enabledPlugins = [];
    enabledResultsProviders = [];
    enabledHomepageProviders = [];
    enabledSearchSuggestionsProviders = [];

    // get list of all enabled plugins in settings
    List<String> enabledResultsProvidersFromSettings =
        await sharedStorage.getStringList("plugins_results") ?? [];
    List<String> enabledHomepageProvidersFromSettings =
        await sharedStorage.getStringList("plugins_homepage") ?? [];
    List<String> enabledSearchSuggestionsProvidersFromSettings =
        await sharedStorage.getStringList("plugins_search_suggestions") ?? [];
    logger.d(
        "Enabled results providers from settings: $enabledResultsProvidersFromSettings");
    logger.d(
        "Enabled homepage providers from settings: $enabledHomepageProvidersFromSettings");
    logger.d(
        "Enabled search suggestions providers from settings: $enabledSearchSuggestionsProvidersFromSettings");

    // Init official plugins first
    logger.i("Discovering official plugins");
    for (var plugin in await getAllOfficialPlugins()) {
      allPlugins.add(plugin);
      if (enabledResultsProvidersFromSettings.contains(plugin.codeName) ||
          enabledHomepageProvidersFromSettings.contains(plugin.codeName) ||
          enabledSearchSuggestionsProvidersFromSettings
              .contains(plugin.codeName)) {
        try {
          if (await plugin.initPlugin()) {
            enabledPlugins.add(plugin);
          }
        } catch (e, stacktrace) {
          logger.e("Failed to initiate previously enabled "
              "${plugin.codeName}: $e\n$stacktrace");
          unavailablePlugins[plugin] = e as Exception;
        }

        // create a separate cache dir for each plugin
        Directory cacheDir =
            Directory("${cachePath.path}/plugins/${plugin.codeName}");
        if (!cacheDir.existsSync()) {
          cacheDir.create(recursive: true);
        }
      }
      if (enabledResultsProvidersFromSettings.contains(plugin.codeName)) {
        enabledResultsProviders.add(plugin);
      }
      if (enabledHomepageProvidersFromSettings.contains(plugin.codeName)) {
        enabledHomepageProviders.add(plugin);
      }
      if (enabledSearchSuggestionsProvidersFromSettings
          .contains(plugin.codeName)) {
        enabledSearchSuggestionsProviders.add(plugin);
      }
    }
    logger.d("All loaded official plugins: $allPlugins");
    logger.d("Enabled official plugins: $enabledPlugins");

    // If pluginsDir doesn't exist, no need to check for third party plugins inside it
    if (!pluginsDir.existsSync()) {
      pluginsDir.createSync();
      return;
    }

    // find third party plugins and load them
    logger.i("Discovering third party plugins");
    for (var dir in pluginsDir.listSync().whereType<Directory>()) {
      // Check if dir is a valid plugin by trying to create a pluginInterface at that path
      PluginInterface tempPlugin;
      try {
        tempPlugin = PluginInterface(dir.path);
      } catch (e) {
        if (e
            .toString()
            .startsWith("Exception: Failed to load from config file:")) {
          // TODO: Show error to user and prompt user to uninstall plugin
          logger.e(e);
        } else {
          rethrow;
        }
        continue;
      }
      allPlugins.add(tempPlugin);
      if (enabledResultsProvidersFromSettings.contains(tempPlugin.codeName) ||
          enabledHomepageProvidersFromSettings.contains(tempPlugin.codeName) ||
          enabledSearchSuggestionsProvidersFromSettings
              .contains(tempPlugin.codeName)) {
        enabledPlugins.add(tempPlugin);
        // create a separate cache dir for each plugin and symlink it to the plugin dir
        Directory cacheDir =
            Directory("${cachePath.path}/plugins/${tempPlugin.codeName}");
        if (!cacheDir.existsSync()) {
          cacheDir.create(recursive: true);
          Link("${dir.path}/cache")
              .createSync("${cachePath.path}/plugins/${tempPlugin.codeName}");
        }
      }
      if (enabledResultsProvidersFromSettings.contains(tempPlugin.codeName)) {
        enabledResultsProviders.add(tempPlugin);
      }
      if (enabledHomepageProvidersFromSettings.contains(tempPlugin.codeName)) {
        enabledHomepageProviders.add(tempPlugin);
      }
      if (enabledSearchSuggestionsProvidersFromSettings
          .contains(tempPlugin.codeName)) {
        enabledSearchSuggestionsProviders.add(tempPlugin);
      }
    }
    logger.d("All plugins after loading third party: $allPlugins");
    logger.d("Enabled plugins after loading third party: $enabledPlugins");
  }

  static Future<bool> enablePlugin(PluginInterface plugin,
      [bool enableAllProviders = true]) async {
    try {
      plugin.initPlugin();
    } catch (e, stacktrace) {
      logger.e("Failed to initiate ${plugin.codeName}: $e\n$stacktrace");
      unavailablePlugins[plugin] = e as Exception;
    }
    logger.i("Plugin ${plugin.codeName} enabled successfully");
    enabledPlugins.add(plugin);
    writePluginListToSettings();
    if (enableAllProviders) {
      logger.i("Enabling all providers for plugin ${plugin.codeName}");
      enabledResultsProviders.add(plugin);
      enabledHomepageProviders.add(plugin);
      enabledSearchSuggestionsProviders.add(plugin);
      writeProvidersListToSettings("results");
      writeProvidersListToSettings("homepage");
      writeProvidersListToSettings("search_suggestions");
    }
    return true;
  }

  static Future<void> disablePlugin(PluginInterface plugin) async {
    enabledPlugins.remove(plugin);
    enabledResultsProviders.remove(plugin);
    enabledHomepageProviders.remove(plugin);
    enabledSearchSuggestionsProviders.remove(plugin);
    logger.i("Plugin ${plugin.codeName} disabled successfully");
    writePluginListToSettings();
    writeProvidersListToSettings("results");
    writeProvidersListToSettings("homepage");
    writeProvidersListToSettings("search_suggestions");
  }

  /// ProviderType can be one of "results", "homepage" or "search_suggestions"
  static Future<void> enableProvider(
      PluginInterface plugin, String providerType) async {
    // Check if provider is missing from all provider lists and need to be added to enabledPlugins
    if (!_providerMap["results"]!.contains(plugin) &&
        !_providerMap["homepage"]!.contains(plugin) &&
        !_providerMap["search_suggestions"]!.contains(plugin)) {
      enablePlugin(plugin, false);
    }
    if (_providerMap.containsKey(providerType)) {
      _providerMap[providerType]!.add(plugin);
    } else {
      throw Exception("Invalid provider type: $providerType");
    }
    logger.i("$providerType provider ${plugin.codeName} enabled successfully");
    writeProvidersListToSettings(providerType);
  }

  /// ProviderType can be one of "results", "homepage" or "search_suggestions"
  static Future<void> disableProvider(
      PluginInterface plugin, String providerType) async {
    if (_providerMap.containsKey(providerType)) {
      _providerMap[providerType]!.remove(plugin);
      // Check if plugin is missing from all provider lists
      if (!_providerMap["results"]!.contains(plugin) &&
          !_providerMap["homepage"]!.contains(plugin) &&
          !_providerMap["search_suggestions"]!.contains(plugin)) {
        disablePlugin(plugin);
        return; // the disable plugin function will write the plugin list to settings automatically
      }
    } else {
      throw Exception("Invalid provider type: $providerType");
    }
    logger.i("$providerType provider ${plugin.codeName} disabled successfully");
    writeProvidersListToSettings(providerType);
  }

  static Future<void> writePluginListToSettings() async {
    List<String> settingsList = [];
    for (var plugin in enabledPlugins) {
      settingsList.add(plugin.codeName);
    }
    logger.d("Writing plugins list to settings");
    logger.d(settingsList);
    sharedStorage.setStringList('enabled_plugins', settingsList);
    // download plugin icons if they don't yet exist
    downloadPluginIcons(force: true);
  }

  static Future<void> writeProvidersListToSettings(String providerType) async {
    List<String> settingsList = [];
    for (var plugin in _providerMap[providerType]!) {
      settingsList.add(plugin.codeName);
    }
    logger.d("Writing $providerType providers list to settings");
    logger.d(settingsList);
    sharedStorage.setStringList("plugins_$providerType", settingsList);
    // download plugin icons if they don't yet exist
    downloadPluginIcons(force: true);
  }

  static PluginInterface? getPluginByName(String name) {
    // For database manager
    if (name == "null") {
      return null;
    }
    for (var plugin in allPlugins) {
      if (plugin.codeName == name) {
        return plugin;
      }
    }
    logger.e("Didnt find plugin with name: $name");
    return null;
  }

  static Future<Map<String, dynamic>> extractPlugin(
      FilePickerResult? pickedFile) async {
    try {
      // Create a temporary directory with random name to process the zip file
      final tempDir = await getTemporaryDirectory();
      final outputDir = Directory("${tempDir.path}/extracted_plugin");
      logger.d("Deleting and recreating temp dir at ${outputDir.path}");
      if (outputDir.existsSync()) {
        outputDir.deleteSync(recursive: true);
      }
      await outputDir.create(recursive: true);

      // Extract the contents of the zip file into the temp dir
      for (final file in ZipDecoder().decodeBytes(
          File(pickedFile!.files.single.path!).readAsBytesSync())) {
        if (file.isFile) {
          logger.d(
              "Unpacking file ${file.name} to ${outputDir.path}/${file.name}");
          final data = file.content as List<int>;
          File("${outputDir.path}/${file.name}")
            ..createSync(recursive: true)
            ..writeAsBytesSync(data);
        } else {
          Directory("${outputDir.path}/${file.name}").create(recursive: true);
        }
      }

      // Parse yaml
      if (!File("${outputDir.path}/plugin.yaml").existsSync()) {
        return {
          "codeName": "Error",
          "error":
              "${pickedFile.files.single.path} is not a valid plugin (plugin.yaml not found)"
        };
      }
      YamlMap pluginConfig =
          loadYaml(File("${outputDir.path}/plugin.yaml").readAsStringSync());

      // Check if plugin is already installed
      logger.d("Checking if plugin is already installed");
      if (allPlugins
          .any((plugin) => plugin.codeName == pluginConfig["codeName"])) {
        return {"codeName": "Error", "error": "Plugin already installed"};
      }

      // Check if current platform is supported by plugin
      logger.d("Checking if platform is supported by plugin");
      Map<String, List<String>> platformMap = {
        for (var item in pluginConfig["supportedPlatforms"])
          item.keys.first: List<String>.from(item.values.first)
      };
      if (platformMap[Platform.operatingSystem] != null) {
        // Get platform architecture
        String platformString = Platform.version;
        String platformArch = platformString.substring(
            platformString.lastIndexOf("_") + 1, platformString.length - 1);
        if (!platformMap[Platform.operatingSystem]!.contains(platformArch)) {
          return {
            "codeName": "Error",
            "error":
                "Your device is not supported by the plugin (Unsupported architecture: $platformArch)"
          };
        }
      } else {
        return {
          "codeName": "Error",
          "error":
              "Your device is not supported by the plugin (Unsupported platform: ${Platform.operatingSystem})"
        };
      }
      Map<String, dynamic> pluginMap = Map<String, dynamic>.from(pluginConfig);
      pluginMap["tempPluginPath"] = outputDir.path;
      return pluginMap;
    } catch (e) {
      rethrow;
    }
  }

  Future<bool> importAndTestPlugin(
      String tempPluginPath, String pluginCodeName) async {
  static Future<bool> testExternalPlugin(Directory pluginDir) async {
    // Create plugin dir
    Directory appSupportDir = await getApplicationSupportDirectory();
    Directory pluginDir =
        Directory("${appSupportDir.path}/plugins/$pluginCodeName");
    if (pluginDir.existsSync()) {
      // TODO: Prompt user on what to do?
      logger.w(
          "Plugin directory for codename $pluginCodeName already exists! Deleting and recreating");
      pluginDir.deleteSync(recursive: true);
      pluginDir.createSync(recursive: true);
    }

    // Copy bin dir
    copyDirectory(
        Directory("$tempPluginPath/bin"), Directory("${pluginDir.path}/bin"));

    // symlink "binary" to the platform appropriate binary inside ./bin
    String platformString = Platform.version;
    String platformArch = platformString.substring(
        platformString.lastIndexOf("_") + 1, platformString.length - 1);
    try {
      // make binary executable
      final result = await Process.run('chmod', [
        '555',
        "${pluginDir.path}/bin/${Platform.operatingSystem}-$platformArch"
      ]);
      if (result.exitCode != 0) {
        throw Exception('Failed to make binary executable: ${result.stderr}');
      }
    } catch (e) {
      logger.e("Failed to make binary executable: $e");
      return false;
    }
    try {
      Link("${pluginDir.path}/bin/binaryLink")
          .createSync("./${Platform.operatingSystem}-$platformArch");
    } catch (e) {
      if (e is PathExistsException) {
        logger.e(
            "Cannot symlink to correct platform binary, aborting plugin install");
        return false;
      }
    }
  static Future<void> deletePlugin(PluginInterface plugin) async {

    // conf dir is optional
    if (Directory("$tempPluginPath/conf").existsSync()) {
      copyDirectory(Directory("$tempPluginPath/conf"),
          Directory("${pluginDir.path}/conf"));
    } else {
      logger.i("Conf dir not found inside plugin zip");
    }

    // copy plugin.yaml
    logger.d(
        "Copying $tempPluginPath/plugin.yaml to ${pluginDir.path}/plugin.yaml");
    File("$tempPluginPath/plugin.yaml")
        .copySync("${pluginDir.path}/plugin.yaml");

    logger.i("Attempting to initialize plugin $pluginCodeName");
    try {
      PluginInterface tempPlugin = PluginInterface(pluginDir.path);
      tempPlugin.runFunctionalityTest();
    } catch (e) {
      logger.e("Failed to initialize plugin $pluginCodeName: $e");
      return false;
    }
    logger.i("Plugin initialization successful");

    logger.i("Reinitializing all plugins");

    discoverAndLoadPlugins();

    return true;
  }
}
