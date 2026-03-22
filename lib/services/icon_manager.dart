import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '/utils/global_vars.dart';
import '/utils/plugin_interface/plugin_interface.dart';
import 'plugin_manager.dart';

/// Including plugin images in the app itself (or inside the third party plugin) might break copyright law
/// -> download at runtime and store in cache
Future<void> downloadPluginIcons({bool force = false}) async {
  int counter = (await sharedStorage.getInt("general_icon_cache_counter"))!;
  if (counter != 5 && !force) {
    logger.i("Icon cache counter is $counter (not 5). Skipping icon download.");
    sharedStorage.setInt("general_icon_cache_counter", counter + 1);
    return;
  }
  if (force) {
    logger.i("Force downloading plugin icons");
  }
  logger.i("Icon cache counter is 5. Downloading plugin icons");
  Directory sysCache = await getApplicationCacheDirectory();
  Directory cacheDir = Directory("${sysCache.path}/icons");
  // Create icon cache dir if it doesn't exist
  if (!cacheDir.existsSync()) {
    cacheDir.create();
  }
  logger.d("Enabled plugins: ${PluginManager.enabledPlugins}");
  for (PluginInterface plugin in PluginManager.enabledPlugins) {
    try {
      http.Response response = await client.get(plugin.iconUrl);
      if (response.statusCode == 200) {
        logger.d(
            "Saving icon for ${plugin.codeName} to ${cacheDir.path}/${plugin.codeName}");
        await File("${cacheDir.path}/${plugin.codeName}")
            .writeAsBytes(response.bodyBytes);
      } else {
        logger.w(
            "Error downloading icon: ${response.statusCode} - ${response.reasonPhrase}");
      }
    } catch (e) {
      logger.w("Error downloading icon: $e");
    }
  }
  logger.i("Resetting icon cache counter");
  await sharedStorage.setInt("general_icon_cache_counter", 0);
}
