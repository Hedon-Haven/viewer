import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import "package:path/path.dart" as p;
import 'package:path_provider/path_provider.dart';
import 'package:synchronized/synchronized.dart';
import 'package:yaml/yaml.dart';

import '/services/icon_manager.dart';
import '/services/update_manager.dart';
import '/utils/filesystem.dart';
import '/utils/global_vars.dart';
import '/utils/plugin_interface/plugin_interface.dart';
import 'official_plugins_tracker.dart';

enum ProviderType {
  homepage,
  searchSuggestions,
  searchResults,
}

typedef UpdateInfo = ({
  String newVersion,
  Uri downloadUrl,
  String sha256Sum,
  List<String> changelog,
});

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

  /// All the plugins that failed to initiate with the message to be displayed to the user
  static final Map<PluginInterface, UpdateInfo> _updatablePlugins = {};

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
      _updatablePlugins.clear();
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

    // Trigger update check, but don't wait for it
    checkForPluginUpdates();
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
    // Directly replace old plugin instance (if present) with new one
    _enabledPlugins
      ..removeWhere((e) => e == plugin)
      ..add(plugin);
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
      _updatablePlugins.remove(plugin);
      await _writeProvidersSetsToSettings();
    });
  }

  /// Extracts the plugin to a temp dir and returns parsed plugin.yaml Map with temp dir path
  /// Also makes sure the plugin is not already installed
  static Future<Map<String, dynamic>> extractNewPlugin(
      String pickedFilePath) async {
    final Map<String, dynamic> pluginMap =
        await _extractPluginZip(pickedFilePath);

    // Check if plugin is already installed
    await _lock.synchronized(() async {
      logger.d("Checking if plugin is already installed");
      if (_allPlugins.any(
          (plugin) => plugin.codeName == pluginMap["metadata"]!["codeName"]!)) {
        await deleteDirectory(Directory(pluginMap["tempPluginPath"]));
        logger.w("$pickedFilePath is already installed as "
            "${pluginMap["metadata"]["codeName"]}! Removed temp files!");
        throw Exception(
            "AlreadyInstalled: ${pluginMap["metadata"]["codeName"]}");
      }
    });
    return pluginMap;
  }

  /// Extracts the plugin to a temp dir and returns parsed plugin.yaml Map with temp dir path
  static Future<Map<String, dynamic>> _extractPluginZip(
      String pickedFilePath) async {
    // Check if plugin.yaml exists in the zip root before extracting
    final archive =
        ZipDecoder().decodeBytes(await File(pickedFilePath).readAsBytes());
    final hasPluginYaml =
        archive.any((file) => file.isFile && file.name == "plugin.yaml");
    if (!hasPluginYaml) {
      logger.e("No plugin.yaml found in zip root!");
      throw Exception("No plugin.yaml found in zip root!");
    }

    final String tempPath = await getExtractTempDir();
    try {
      await extractZipTo(pickedFilePath, tempPath);
    } catch (e, st) {
      await deleteDirectory(Directory(tempPath));
      logger.e("Failed to extract plugin: $e\n$st");
      throw Exception("Failed to extract plugin");
    }

    // Parse yaml
    YamlMap pluginConfig =
        loadYaml(await File(p.join(tempPath, "plugin.yaml")).readAsString());
    Map<String, dynamic> pluginConfigMap =
        Map<String, dynamic>.from(pluginConfig);
    pluginConfigMap["tempPluginPath"] = tempPath;

    // Validate plugin codename
    final codeName = pluginConfig["metadata"]!["codeName"]!;
    if (!PluginInterface.codeNameIsValid(codeName)) {
      await deleteDirectory(Directory(tempPath));
      logger.e("Invalid plugin codeName: $codeName");
      throw Exception("Invalid plugin codeName: $codeName");
    }

    return pluginConfigMap;
  }

  /// Fully tests an externally stored plugin
  /// 1. Create a PluginInterface -> tests plugin.yaml validity
  /// 2. Runs .init() -> tests both isolate functionality (e.g. the javascript runtime)
  /// and the plugins internal init function
  /// 3. Runs .runFunctionalityTest() -> tests basic plugins functionality
  static Future<bool> testExternalPlugin(Directory pluginDir) async {
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
  static Future<void> importNewPlugin(Map<String, dynamic> pluginConfig) async {
    final String installedPath =
        p.join(_pluginsDir!.path, pluginConfig["metadata"]["codeName"]);
    await _lock.synchronized(() async {
      try {
        PluginInterface newPlugin =
            await _importPlugin(pluginConfig["tempPluginPath"], installedPath);
        await _enablePlugin(newPlugin);
        await _setAsProvider(newPlugin, {
          ProviderType.homepage,
          ProviderType.searchSuggestions,
          ProviderType.searchResults
        });
        await _writeProvidersSetsToSettings();
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

  /// Imports the plugin from temp directory into the passed path
  static Future<PluginInterface> _importPlugin(
      String tempDir, String installPath) async {
    await forceCopyDirectory(Directory(tempDir), Directory(installPath));
    PluginInterface newPlugin = PluginInterface(installPath);
    // Directly replace old plugin with new one
    _allPlugins
      ..removeWhere((e) => e == newPlugin)
      ..add(newPlugin);
    await forceDownloadIconForPlugin(newPlugin);
    return newPlugin;
  }

  /// Check all plugins for updates
  static Future<void> checkForPluginUpdates() async {
    List<PluginInterface>? plugins;
    await _lock.synchronized(() {
      plugins = List.from(_allPlugins);
    });

    // Process all plugins in parallel
    // Only acquire lock when writing the _updatablePlugins map
    await Future.wait(plugins!.map((plugin) async {
      final updateInfo = await _fetchUpdateInfo(plugin);
      if (updateInfo != null) {
        await _lock.synchronized(() {
          _updatablePlugins[plugin] = updateInfo;
        });
      }
    }));

    // Notify listeners of amount of plugin updates available
    await _lock.synchronized(
        () => pluginUpdatesAvailableEvent.add(_updatablePlugins.length));
  }

  static Future<UpdateInfo?> _fetchUpdateInfo(PluginInterface plugin) async {
    logger.d("Checking if ${plugin.codeName} can be updated");
    if (plugin.updateUrl == null) {
      logger.i("${plugin.codeName} has no update URL, stopping check.");
      return null;
    }
    final response = await client.get(plugin.updateUrl!);
    if (response.statusCode != 200) {
      logger.e("Failed to get update.yaml from ${plugin.updateUrl}");
      return null;
    }

    YamlMap updateYaml;
    try {
      updateYaml = loadYaml(response.body);
    } catch (e, st) {
      logger.e("Failed to parse valid yaml from response body: $e\n$st");
      return null;
    }

    // Check and parse yaml
    final UpdateInfo updateInfo;
    try {
      // Make sure the url is https
      final Uri resolvedUri = Uri.parse(updateYaml["downloadUrl"]! as String);
      if (resolvedUri.scheme != "https") {
        throw Exception("Update URL must be https");
      }

      updateInfo = (
        newVersion: updateYaml["version"]! as String,
        downloadUrl: resolvedUri,
        sha256Sum: updateYaml["sha256Sum"]! as String,
        changelog: List<String>.from(updateYaml['changelog']),
      );
    } catch (e, st) {
      logger.e("Failed to parse update.yaml: $e\n$st");
      return null;
    }

    if (!newVersionIsHigher(plugin.version, updateInfo.newVersion)) {
      logger.i("${plugin.codeName} is up to date");
      return null;
    }
    logger.i("${plugin.codeName} can be updated to ${updateInfo.newVersion}");
    return updateInfo;
  }

  /// Update a single plugin
  /// The new plugin will be fully tested, however this process is technically
  /// not fully atomic / reversible if an error occurs after testExternalPlugin
  static Future<void> updatePlugin(PluginInterface oldPlugin) async {
    logger.i("Updating plugin ${oldPlugin.codeName}");

    if (oldPlugin.isOfficialPlugin) {
      throw Exception("Official plugins cannot be updated");
    }

    UpdateInfo? updateInfo;
    String? codename;
    Set<ProviderType>? providers;

    // Lock plugin manager to cache values
    await _lock.synchronized(() {
      updateInfo = _updatablePlugins[oldPlugin];
      providers = _providers.entries
          .where((entry) => entry.value.contains(oldPlugin))
          .map((entry) => entry.key)
          .toSet();
      codename = oldPlugin.codeName;
    });

    // Store outside try block for cleanup in finally block
    final tempFile = await getTempFile();
    String? tempDir;

    try {
      // Perform heavier ops without lock
      if (updateInfo == null) {
        throw Exception("Missing updateInfo for ${oldPlugin.codeName}!");
      }
      final response = await client.get(updateInfo!.downloadUrl);
      if (response.statusCode != 200) {
        throw Exception(
            "Failed to download zip update for ${oldPlugin.codeName}");
      }

      await File(tempFile).writeAsBytes(response.bodyBytes);

      String bytesChecksum = sha256.convert(response.bodyBytes).toString();
      if (updateInfo!.sha256Sum != bytesChecksum) {
        logger.e("Checksums do not match, aborting plugin update");
        throw Exception("Checksums do not match, "
            "expected: ${updateInfo!.sha256Sum} calculated: $bytesChecksum");
      }

      final Map<String, dynamic> pluginConfig =
          await _extractPluginZip(tempFile);

      if (pluginConfig["metadata"]["codeName"] != codename!) {
        throw Exception(
            "New codename: ${pluginConfig["metadata"]["codeName"]} does not match old codename: $codename");
      }

      tempDir = pluginConfig["tempPluginPath"];

      // Test plugin loading and functionality.
      // If this succeeds we assume the new plugin is fully valid and
      // replace the old plugin with it
      if (!(await testExternalPlugin(Directory(tempDir!)))) {
        throw Exception("3rd party plugin functionality tests failed");
      }

      // Re-acquire lock to update plugin files
      await _lock.synchronized(() async {
        oldPlugin.dispose();
        PluginInterface newPlugin =
            await _importPlugin(tempDir!, p.join(_pluginsDir!.path, codename!));
        // Re-enable plugin if needed
        if (providers!.isNotEmpty) {
          await _enablePlugin(newPlugin);
          await _setAsProvider(newPlugin, providers!);
          await _writeProvidersSetsToSettings();
        }
      });
    } catch (e, st) {
      logger.e("Failed to update plugin: $e\n$st");
      rethrow;
    } finally {
      // Perform cleanup no matter the outcome
      await File(tempFile).delete();
      if (tempDir != null) {
        await Directory(tempDir).delete(recursive: true);
      }
    }

    // Update listeners of amount of plugin updates available
    await _lock.synchronized(() {
      _updatablePlugins.removeWhere((p, _) => p.codeName == codename);
      pluginUpdatesAvailableEvent.add(_updatablePlugins.length);
    });

    logger.i("Finished updating plugin ${oldPlugin.codeName} successfully");
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

  static Future<List<PluginInterface>> getUpdatablePlugins() {
    return _lock.synchronized(() => List.from(_updatablePlugins.keys));
  }

  static Future<UpdateInfo?> getUpdateInfoFor(PluginInterface plugin) {
    return _lock.synchronized(() => _updatablePlugins[plugin]);
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
