import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '/services/database_manager.dart';
import '/services/shared_prefs_manager_upgrades.dart';
import '/utils/global_vars.dart';

Future<void> setDefaultSettings([forceReset = false]) async {
  String? settingsVersion =
      await sharedStorage.getString("general_settings_version");
  if (settingsVersion != null && !forceReset) {
    if (settingsVersion == packageInfo.version) {
      logger.i("Settings already set and using latest settings version");
      return;
    }
  }
  // Attempt to upgrade settings
  if (settingsVersion != null &&
      !forceReset &&
      settingsVersion != packageInfo.version) {
    logger.w("Settings version changed from "
        "${(await sharedStorage.getString("general_settings_version"))} to "
        "${packageInfo.version}");

    // First, make sure this is not a downgrade
    List<int> currentVersion =
        settingsVersion.split(".").map((e) => int.parse(e)).toList();
    List<int> newVersion =
        packageInfo.version.split(".").map((e) => int.parse(e)).toList();
    if (currentVersion[0] > newVersion[0] ||
        (currentVersion[0] == newVersion[0] &&
            currentVersion[1] > newVersion[1]) ||
        (currentVersion[0] == newVersion[0] &&
            currentVersion[1] == newVersion[1] &&
            currentVersion[2] > newVersion[2])) {
      logger.e("Downgrade detected from from $currentVersion to $newVersion. "
          "Resetting all settings....");
      // Continue and reset to default
    }

    // Start upgrade chain
    if (await startUpgrade(settingsVersion)) {
      logger.w("Settings upgrade succeeded");
      await sharedStorage.setString(
          "general_settings_version", packageInfo.version);
      // prevent a force-reset
      return;
    } else {
      logger.w("Settings upgrade failed. Resetting settings to default");
      // Continue and reset to default
    }
  }
  logger.w("Setting default settings");
  await sharedStorage.setString(
      "general_settings_version", packageInfo.version);
  await sharedStorage.setInt("general_icon_cache_counter", 5);

  logger.i("Forcing a database reset");
  // Purge db, then immediately recreate it
  await purgeDatabase();
  await initDb();

  // Do not reset dev options, as this should only be done from the settings_about screen
  if (!forceReset) {
    // force enable in debug mode
    logger.i("Setting dev options to $kDebugMode");
    await sharedStorage.setBool("general_enable_dev_options", kDebugMode);
  }
  await sharedStorage.setBool("general_enable_logging", false);
  await sharedStorage.setBool("general_onboarding_completed", false);

  await _setPluginProviderSettings();
  await _setAppearanceSettings();
  await _setMediaSettings();
  await _setCommentsSettings();
  await _setHistorySettings();
  await _setPrivacySettings();
  await setDefaultFilterSettings();
}

Future<void> _setPluginProviderSettings() async {
  await sharedStorage.setStringList("plugins_homepage", []);
  await sharedStorage.setStringList("plugins_search_suggestions", []);
  await sharedStorage.setStringList("plugins_search_results", []);
  await sharedStorage.setStringList("plugins_external_link_handler", []);
}

Future<void> _setAppearanceSettings() async {
  // Whether the app is concealed ("reminders" or "fake_settings") or default appearance ("Hedon Haven")
  await sharedStorage.setString(
      "appearance_launcher_appearance", "Hedon Haven");
  // Fake reminders for app concealing
  await sharedStorage.setStringList("appearance_fake_reminders_list", [
    "Buy groceries",
    "Dentist appointment",
    "Pay electricity bill",
    "mom birthday"
  ]);
  // Fake gsm settings for app concealing
  await sharedStorage.setStringList(
      "appearance_fake_settings_list", ["1", "0", "0", "1", "1"]);

  await sharedStorage.setString("appearance_theme_mode", "Follow device theme");
  await sharedStorage.setString("appearance_list_view", "Card");
  await sharedStorage.setBool("appearance_play_previews", true);
  await sharedStorage.setBool("appearance_homepage_enabled", true);
}

Future<void> _setMediaSettings() async {
  await sharedStorage.setBool("media_start_in_fullscreen", false);
  await sharedStorage.setBool("media_auto_play", false);
  await sharedStorage.setBool("media_show_progress_thumbnails", true);
  await sharedStorage.setInt("media_preferred_video_quality", 2160); // 4K
  await sharedStorage.setInt("media_seek_duration", 10);
}

Future<void> _setCommentsSettings() async {
  await sharedStorage.setBool("comments_hide_hidden", false);
  await sharedStorage.setBool("comments_hide_negative", false);
  await sharedStorage.setBool("comments_filter_links", false);
  await sharedStorage.setBool("comments_filter_non_ascii", false);
}

Future<void> _setHistorySettings() async {
  await sharedStorage.setBool("history_watch", true);
  await sharedStorage.setBool("history_search", true);
}

Future<void> _setPrivacySettings() async {
  await sharedStorage.setBool("privacy_proxy_enabled", false);
  await sharedStorage.setString("privacy_proxy_address", "");
  await sharedStorage.setBool("privacy_hide_app_preview", true);
  await sharedStorage.setBool("privacy_keyboard_incognito_mode", true);
  await sharedStorage.setBool("privacy_show_external_link_warning", true);
}

Future<void> setDefaultFilterSettings() async {
  await sharedStorage.setString("filter_order", "Relevance");
  await sharedStorage.setBool("filter_reverse", false);
  await sharedStorage.setString("filter_date_range", "All time");
  await sharedStorage.setInt("filter_quality_min", 0);
  await sharedStorage.setInt("filter_quality_max", 2160);
  await sharedStorage.setInt("filter_duration_min", 0);
  await sharedStorage.setInt("filter_duration_max", 3600);
}

Future<ThemeMode> getThemeMode() async {
  switch ((await sharedStorage.getString("appearance_theme_mode"))!) {
    case "Follow device theme":
      return ThemeMode.system;
    case "Light theme":
      return ThemeMode.light;
    case "Dark theme":
      return ThemeMode.dark;
    default:
      return ThemeMode.system;
  }
}
