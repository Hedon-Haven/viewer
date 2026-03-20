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

  /// Discover all plugins and load according to settings in sharedStorage
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
      if (await tempPlugin.initPlugin() == false) {
        // TODO: Show error to user and prompt user to uninstall plugin
        return;
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
        if (cacheDir.existsSync()) {
          cacheDir.deleteSync(recursive: true);
        }
        cacheDir.createSync(recursive: true);
        Link("${dir.path}/cache")
            .createSync("${cachePath.path}/plugins/${tempPlugin.codeName}");
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
      await plugin.initPlugin();
    } catch (e, stacktrace) {
      logger.e("Failed to initiate ${plugin.codeName}: $e\n$stacktrace");
      unavailablePlugins[plugin] = e as Exception;
    }
    logger.i("Plugin ${plugin.codeName} enabled successfully");
    enabledPlugins.add(plugin);
    await writePluginListToSettings();
    if (enableAllProviders) {
      logger.i("Enabling all providers for plugin ${plugin.codeName}");
      enabledResultsProviders.add(plugin);
      enabledHomepageProviders.add(plugin);
      enabledSearchSuggestionsProviders.add(plugin);
      await writeProvidersListToSettings("results");
      await writeProvidersListToSettings("homepage");
      await writeProvidersListToSettings("search_suggestions");
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

  static PluginInterface? getPluginByName(String? name) {
    if (name == null) {
      return null;
    }
    for (var plugin in allPlugins) {
      if (plugin.codeName == name) {
        return plugin;
      }
    }
    logger.e("Didn't find plugin with name: $name");
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

      // Check if plugin.yaml exists in the zip root before extracting
      final archive = ZipDecoder()
          .decodeBytes(File(pickedFile!.files.single.path!).readAsBytesSync());
      final hasPluginYaml =
          archive.any((file) => file.isFile && file.name == "plugin.yaml");

      if (!hasPluginYaml) {
        logger.e("No plugin.yaml found in zip root!");
        throw Exception("No plugin.yaml found in zip root!");
      }

      // Extract the contents of the zip file into the temp dir
      for (final file in ZipDecoder()
          .decodeBytes(File(pickedFile.files.single.path!).readAsBytesSync())) {
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
      YamlMap pluginConfig =
          loadYaml(File("${outputDir.path}/plugin.yaml").readAsStringSync());

      // Check if plugin is already installed
      logger.d("Checking if plugin is already installed");
      if (allPlugins.any((plugin) =>
          plugin.codeName == pluginConfig["metadata"]["codeName"])) {
        logger.w(
            "${pickedFile.files.single.path} is already installed as ${pluginConfig["metadata"]["codeName"]}");
        throw Exception(
            "AlreadyInstalled: ${pluginConfig["metadata"]["codeName"]}");
      }

      Map<String, dynamic> pluginConfigMap =
          Map<String, dynamic>.from(pluginConfig);
      pluginConfigMap["tempPluginPath"] = outputDir.path;
      return pluginConfigMap;
    } catch (e) {
      rethrow;
    }
  }

  static Future<bool> testExternalPlugin(Directory pluginDir) async {
    if (!pluginDir.existsSync()) {
      throw Exception("Plugin directory ${pluginDir.path} does not exist");
    }
    try {
      var tempPlugin = PluginInterface(pluginDir.path);
      return await tempPlugin.runFunctionalityTest();
    } catch (e, stacktrace) {
      logger.e("Failed to test plugin in ${pluginDir.path}: $e\n$stacktrace");
      return false;
    }
  }

  static Future<void> importPlugin(Map<String, dynamic> pluginConfig) async {
    // Create plugin dir
    String pluginCodeName = pluginConfig["metadata"]["codeName"];
    Directory appSupportDir = await getApplicationSupportDirectory();
    Directory pluginDir =
        Directory("${appSupportDir.path}/plugins/$pluginCodeName");
    Directory tempPluginPath = Directory(pluginConfig["tempPluginPath"]);
    if (pluginDir.existsSync()) {
      logger.w("Plugin directory ${pluginDir.path} for $pluginCodeName already"
          " exists! Deleting directory + contents!");
      pluginDir.deleteSync(recursive: true);
    }

    copyDirectory(tempPluginPath, pluginDir);
  }

  static Future<void> deletePlugin(PluginInterface plugin) async {
    if (plugin.isOfficialPlugin) {
      logger.w("Can't delete official plugins!");
      return;
    }

    await disablePlugin(plugin);

    Directory appSupportDir = await getApplicationSupportDirectory();
    Directory pluginDir =
        Directory("${appSupportDir.path}/plugins/${plugin.codeName}");
    if (pluginDir.existsSync()) {
      logger.d("Deleting plugin directory ${pluginDir.path}");
      pluginDir.deleteSync(recursive: true);
    } else {
      logger.w("Plugin directory ${pluginDir.path} does not exist; "
          "cannot delete plugin!");
    }

    await discoverAndLoadPlugins();
  }
}
