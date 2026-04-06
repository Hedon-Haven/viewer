import 'dart:io';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import "package:path/path.dart" as p;
import 'package:path_provider/path_provider.dart';
import 'package:synchronized/synchronized.dart';
import 'package:yaml/yaml.dart';

import '/services/icon_manager.dart';
import '/utils/filesystem.dart';
import '/utils/global_vars.dart';
import '/utils/plugin_interface/plugin_interface.dart';
import 'official_plugins_tracker.dart';

enum ProviderType {
  homepage,
  searchSuggestions,
  searchResults,
}

class PluginManager {
  /// Class-wide lock to only allow one operation at a time
  static final Lock _lock = Lock();

  // Internal vars
  static Directory? _pluginsDir;
  static Directory? _pluginCacheDir;

  /// Contains all PluginInterfaces of all valid plugins in the plugins dir, no matter if enabled or not
  static final Set<PluginInterface> _allPlugins = {};

  /// All the currently enabled plugins (each plugin must serve as at least one provider), stored as PluginInterfaces and ready to be used
  static final Set<PluginInterface> _enabledPlugins = {};

  /// All the plugins that failed to initiate with the message to be displayed to the user
  static final Map<PluginInterface, (Exception, String)> _failedPlugins = {};

  /// All the currently enabled plugins grouped by the provider type they serve
  static final Map<ProviderType, Set<PluginInterface>> _providers = {
    ProviderType.homepage: {},
    ProviderType.searchSuggestions: {},
    ProviderType.searchResults: {},
  };

  /// Lock-safe function to re-discover all plugins and load according to settings in sharedStorage
  /// Called once at app startup, but may be called again if needed
  static Future<void> init() async {
    await _lock.synchronized(() async {
      // Set paths if not already set
      if (_pluginsDir == null) {
        Directory appSupportDir = await getApplicationSupportDirectory();
        _pluginsDir = Directory(p.join(appSupportDir.path, "plugins"));
      }
      if (_pluginCacheDir == null) {
        Directory appCacheDir = await getApplicationCacheDirectory();
        logger.i("Plugin cache dir: ${p.join(appCacheDir.path, "plugins")}");
        _pluginCacheDir = Directory(p.join(appCacheDir.path, "plugins"));
      }

      // Dispose all plugins before clearing
      for (var plugin in _allPlugins) {
        plugin.dispose();
      }

      // Clear plugin lists
      _allPlugins.clear();
      _enabledPlugins.clear();
      _failedPlugins.clear();
      for (var key in _providers.keys) {
        _providers[key]!.clear();
      }

      // Read lists of all enabled plugins in settings
      final Map<ProviderType, Set<String>> providerSettings = {
        ProviderType.homepage:
            (await sharedStorage.getStringList("plugins_homepage") ?? [])
                .toSet(),
        ProviderType.searchSuggestions:
            (await sharedStorage.getStringList("plugins_search_suggestions") ??
                    [])
                .toSet(),
        ProviderType.searchResults:
            (await sharedStorage.getStringList("plugins_search_results") ?? [])
                .toSet(),
      };
      final Set<String> pluginsToEnable =
          providerSettings.values.expand((e) => e).toSet();
      logger.d("Provider settings Map: $providerSettings");

      _allPlugins.addAll(await getAllOfficialPlugins());
      final officialPluginsCount = _allPlugins.length;
      logger.d("Official plugins found: $_allPlugins "
          "($officialPluginsCount)");

      // If pluginsDir doesn't exist, no need to check for third party plugins inside it
      logger.d("Looking for 3rd party plugins in ${_pluginsDir!.path}");
      if (!(await _pluginsDir!.exists())) {
        await _pluginsDir!.create();
      } else {
        await for (var dir
            in _pluginsDir!.list().where((e) => e is Directory)) {
          PluginInterface tempPlugin;
          try {
            tempPlugin = PluginInterface(dir.path);
          } catch (e, st) {
            logger
                .e("Failed to load 3rd party plugin from ${dir.path}: $e\n$st");
            if (e
                .toString()
                .startsWith("Exception: Failed to load from config file:")) {
              // TODO: Show error message to user since we cant put it into the unavailablePlugins map
            }
            continue;
          }

          if (!_allPlugins.add(tempPlugin)) {
            logger.w(
                "3rd party plugin '${tempPlugin.codeName}' conflicts with an "
                "existing plugin codeName — not adding!");
            continue;
          }
        }
      }
      logger.d("3rd party plugins found in $_pluginsDir: "
          "${_allPlugins.length - officialPluginsCount} "
          "(${_allPlugins.length} total)");

      // Init plugin only if its actually in use as a provider since keeping
      // a bunch of isolates for unused 3rd party plugins is wasteful
      // Also init in parallel
      await Future.wait(
        _allPlugins
            .where((plugin) => pluginsToEnable.contains(plugin.codeName))
            .map((plugin) async {
          // Build provider set from settings
          final providers = {
            for (final entry in providerSettings.entries)
              if (entry.value.contains(plugin.codeName)) entry.key,
          };
          try {
            await _enablePlugin(plugin);
            await _setAsProvider(plugin, providers);
          } catch (_) {
            // Ignore errors, already handled in the other functions
          }
        }),
      );
      await _writeProvidersSetsToSettings();

      logger.d("Finished reloading Plugins");
    });
  }

  /// Updates the providers list with the options for the passed plugin
  /// Will enable/disable the plugin if needed
  /// CAREFUL: Rethrows errors!
  static Future<void> setAsProvider(
      PluginInterface plugin, Set<ProviderType> provides) async {
    await _lock.synchronized(() async {
      await _setAsProvider(plugin, provides);
      await _writeProvidersSetsToSettings();
    });
  }

  /// NON-locked method that can only be called by other functions from this class
  /// CAREFUL: rethrows Exceptions and doesn't handle any of them!
  /// Will enable/disable plugin and add it to the correct provider Lists
  static Future<void> _setAsProvider(
      PluginInterface plugin, Set<ProviderType> provides) async {
    if (provides.isEmpty) {
      if (_enabledPlugins.contains(plugin)) {
        logger.i(
            "Disabling ${plugin.codeName} plugin due to empty providers set!");
        await _disablePlugin(plugin);
      } else {
        logger.i("Empty providers passed and ${plugin.codeName} is already "
            "disabled. Nothing to do.");
      }
      return;
    }

    if (!_enabledPlugins.contains(plugin)) {
      await _enablePlugin(plugin);
    }

    // Replace provider assignments
    for (var set in _providers.values) {
      set.remove(plugin);
    }
    for (final type in provides) {
      _providers[type]!.add(plugin);
    }
  }

  /// Fully enables the plugin and adds it to all provider Lists
  /// CAREFUL: rethrows Exceptions and doesn't handle any of them!
  static Future<void> enablePlugin(PluginInterface plugin) async {
    await _lock.synchronized(() async {
      await _enablePlugin(plugin);
      await _setAsProvider(plugin, {
        ProviderType.homepage,
        ProviderType.searchSuggestions,
        ProviderType.searchResults
      });
      await _writeProvidersSetsToSettings();
    });
  }

  /// NON-lock safe method for calling inside of this class
  static Future<void> _enablePlugin(PluginInterface plugin) async {
    Directory pluginCacheDir =
        Directory(p.join(_pluginCacheDir!.path, plugin.codeName));
    if (!(await pluginCacheDir.exists())) {
      await pluginCacheDir.create(recursive: true);
    }

    try {
      await plugin.init(pluginCacheDir.path);
    } catch (e, st) {
      logger.e("Failed to initiate ${plugin.codeName} plugin: $e\n$st");
      _failedPlugins[plugin] =
          (e is Exception ? e : Exception(e.toString()), st.toString());
      rethrow;
    }
    _enabledPlugins.add(plugin);
    _failedPlugins.remove(plugin);
    logger.d("Plugin ${plugin.codeName} initiated successfully");
  }

  /// Fully disables the plugin and removes it from all provider sets
  /// CAREFUL: rethrows Exceptions and doesn't handle any of them!
  static Future<void> disablePlugin(PluginInterface plugin) async {
    await _lock.synchronized(() async {
      await _disablePlugin(plugin);
      await _writeProvidersSetsToSettings();
    });
  }

  /// NON-lock safe method for calling inside of this class
  static Future<void> _disablePlugin(PluginInterface plugin) async {
    for (var set in _providers.values) {
      set.remove(plugin);
    }
    _enabledPlugins.remove(plugin);
    _failedPlugins.remove(plugin);
    plugin.dispose();
    logger.i("Plugin ${plugin.codeName} disabled successfully");
  }

  static Future<void> deletePlugin(PluginInterface plugin) async {
    if (plugin.isOfficialPlugin) {
      logger.w("Can't delete official plugin ${plugin.codeName}!");
      return;
    }
    await _lock.synchronized(() async {
      // Delete first to make sure that even if dispose fails,
      // the plugin is still gone
      await deleteDirectory(
          Directory(p.join(_pluginsDir!.path, plugin.codeName)));
      await _disablePlugin(plugin);
      _allPlugins.remove(plugin);
      await _writeProvidersSetsToSettings();
    });
  }

  static Future<Map<String, dynamic>> extractPlugin(
      FilePickerResult? pickedFile) async {
    // Check if plugin.yaml exists in the zip root before extracting
    final archive = ZipDecoder()
        .decodeBytes(await File(pickedFile!.files.single.path!).readAsBytes());
    final hasPluginYaml =
        archive.any((file) => file.isFile && file.name == "plugin.yaml");

    if (!hasPluginYaml) {
      logger.e("No plugin.yaml found in zip root!");
      throw Exception("No plugin.yaml found in zip root!");
    }

    final String tempPath = await getExtractTempDir();
    try {
      await extractZipTo(pickedFile.files.single.path!, tempPath);
    } catch (e, st) {
      await deleteDirectory(Directory(tempPath));
      logger.e("Failed to extract plugin: $e\n$st");
      throw Exception("Failed to extract plugin");
    }

    // Parse yaml
    YamlMap pluginConfig =
        loadYaml(await File(p.join(tempPath, "plugin.yaml")).readAsString());

    final codeName = pluginConfig["metadata"]!["codeName"]!;

    if (!PluginInterface.codeNameIsValid(codeName)) {
      await deleteDirectory(Directory(tempPath));
      logger.e("Invalid plugin codeName: $codeName");
      throw Exception("Invalid plugin codeName: $codeName");
    }

    return await _lock.synchronized(() async {
      // Check if plugin is already installed
      logger.d("Checking if plugin is already installed");
      if (_allPlugins.any((plugin) =>
          plugin.codeName == pluginConfig["metadata"]!["codeName"]!)) {
        await deleteDirectory(Directory(tempPath));
        logger.w("${pickedFile.files.single.path} is already installed as "
            "${pluginConfig["metadata"]["codeName"]}! Removed temp files!");
        throw Exception(
            "AlreadyInstalled: ${pluginConfig["metadata"]["codeName"]}");
      }

      Map<String, dynamic> pluginConfigMap =
          Map<String, dynamic>.from(pluginConfig);
      pluginConfigMap["tempPluginPath"] = tempPath;
      return pluginConfigMap;
    });
  }

  static Future<bool> test3rdPartyPlugin(Directory pluginDir) async {
    if (!(await pluginDir.exists())) {
      throw Exception("Plugin directory ${pluginDir.path} does not exist");
    }
    // Create temp cache dir for plugin
    Directory tempCacheDir = Directory("${pluginDir.path}/cache");
    logger.d("Creating cache dir ${tempCacheDir.path}");
    await tempCacheDir.create();

    bool testResult = false;
    PluginInterface? tempPlugin;
    try {
      tempPlugin = PluginInterface(pluginDir.path);
      await tempPlugin.init(tempCacheDir.path);
      testResult = await tempPlugin.runFunctionalityTest();
    } catch (e, st) {
      logger.e("Failed to test plugin in ${pluginDir.path}: $e\n$st");
    } finally {
      tempPlugin?.dispose();
      // remove cache dir to avoid copying it over if user decides to install
      await deleteDirectory(tempCacheDir);
    }
    logger.i("Functionality tests passed");
    return testResult;
  }

  /// Imports and fully enables the new plugin
  static Future<void> importPlugin(Map<String, dynamic> pluginConfig) async {
    final String installedPath =
        p.join(_pluginsDir!.path, pluginConfig["metadata"]["codeName"]);
    await _lock.synchronized(() async {
      try {
        await forceCopyDirectory(Directory(pluginConfig["tempPluginPath"]),
            Directory(installedPath));
        PluginInterface newPlugin = PluginInterface(installedPath);
        _allPlugins.add(newPlugin);
        await _enablePlugin(newPlugin);
        await _setAsProvider(newPlugin, {
          ProviderType.homepage,
          ProviderType.searchSuggestions,
          ProviderType.searchResults
        });
        await _writeProvidersSetsToSettings();
        await forceDownloadIconForPlugin(newPlugin);
      } catch (e, stacktrace) {
        await deleteDirectory(Directory(installedPath));
        logger.e("Failed to import plugin "
            "${pluginConfig["metadata"]["codeName"]} "
            "(all plugin files deleted): $e\n$stacktrace");
        rethrow;
      } finally {
        await deleteDirectory(Directory(pluginConfig["tempPluginPath"]));
      }
    });
  }

  /// NON-locked function that writes the current providers sets as ABC sorted Lists to settings
  static Future<void> _writeProvidersSetsToSettings() async {
    logger.d("Writing provider Sets to settings");
    await sharedStorage.setStringList(
      "plugins_homepage",
      _providers[ProviderType.homepage]!.map((p) => p.codeName).toList()
        ..sort(),
    );
    await sharedStorage.setStringList(
      "plugins_search_suggestions",
      _providers[ProviderType.searchSuggestions]!
          .map((p) => p.codeName)
          .toList()
        ..sort(),
    );
    await sharedStorage.setStringList(
      "plugins_search_results",
      _providers[ProviderType.searchResults]!.map((p) => p.codeName).toList()
        ..sort(),
    );
  }

  static Future<PluginInterface?> getPluginByName(String? name) async {
    if (name == null) {
      return null;
    }
    return _lock.synchronized(() {
      final plugin = _allPlugins.where((p) => p.codeName == name).firstOrNull;
      if (plugin == null) {
        logger.d("Didn't find plugin with name: $name");
      }
      return plugin;
    });
  }

  static Future<List<PluginInterface>> getAllPlugins() {
    return _lock.synchronized(() => List.from(_allPlugins));
  }

  static Future<List<PluginInterface>> getFailedPlugins() {
    return _lock.synchronized(() => _failedPlugins.keys.toList());
  }

  static Future<(Exception, String)?> getPluginError(PluginInterface plugin) {
    return _lock.synchronized(() => _failedPlugins[plugin]);
  }

  static Future<List<PluginInterface>> getEnabledPlugins() {
    return _lock.synchronized(() => List.from(_enabledPlugins));
  }

  static Future<List<PluginInterface>> getProviders(ProviderType type) {
    return _lock.synchronized(() => List.from(_providers[type]!));
  }

  /// Returns all the provider types the passed plugin is registered for
  static Future<Set<ProviderType>> getEnabledProviderTypesOf(
      PluginInterface plugin) {
    return _lock.synchronized(() => {
          for (final entry in _providers.entries)
            if (entry.value.contains(plugin)) entry.key,
        });
  }
}
