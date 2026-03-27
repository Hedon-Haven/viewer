import 'dart:io';

import 'package:http/http.dart' as http;
import "package:path/path.dart" as p;
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
  Directory cacheDir =
      Directory(p.join((await getApplicationCacheDirectory()).path, "icons"));
  // Create icon cache dir if it doesn't exist
  if (!(await cacheDir.exists())) {
    await cacheDir.create();
  }
  for (PluginInterface plugin in await PluginManager.getAllPlugins()) {
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

Future<void> forceDownloadIconForPlugin(PluginInterface plugin) async {
  logger.d("Downloading plugin icon for ${plugin.codeName}");

  Directory cacheDir =
      Directory(p.join((await getApplicationCacheDirectory()).path, "icons"));
  // Create icon cache dir if it doesn't exist
  if (!(await cacheDir.exists())) {
    await cacheDir.create();
  }

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

  logger.d("Finished downloading plugin icon for ${plugin.codeName}");
}
