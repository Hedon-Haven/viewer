import 'package:flutter/material.dart';

import '/utils/global_vars.dart';
import 'settings_about.dart';
import 'settings_appearance.dart';
import 'settings_comments.dart';
import 'settings_developer.dart';
import 'settings_history.dart';
import 'settings_media.dart';
import 'settings_plugins/settings_plugins.dart';
import 'settings_privacy.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool showPluginsBadge = false;

  @override
  void initState() {
    super.initState();

    // Enable badge when plugin update check finishes and updates are available
    pluginUpdatesAvailableEvent.stream
        .listen((value) => setState(() => showPluginsBadge = value != 0));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          iconTheme:
              IconThemeData(color: Theme.of(context).colorScheme.primary),
          title: Text("Settings",
              style: Theme.of(context).textTheme.headlineLarge),
        ),
        body: SafeArea(
          child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                children: <Widget>[
                  ListTile(
                    title: const Text("Plugins"),
                    subtitle: const Text(
                        "Enable/disable plugins, set plugin options"),
                    leading: Badge(
                        isLabelVisible: showPluginsBadge,
                        smallSize: 12,
                        alignment: AlignmentDirectional.centerEnd,
                        child: const Icon(Icons.extension)),
                    onTap: () {
                      Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (context) => const PluginsScreen()));
                    },
                  ),
                  ListTile(
                    title: const Text("Appearance"),
                    subtitle: const Text(
                        "Default theme, enable homepage, play previews"),
                    leading: const Icon(Icons.palette),
                    onTap: () {
                      Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (context) => const AppearanceScreen()));
                    },
                  ),
                  ListTile(
                    title: const Text("Media"),
                    subtitle: const Text(
                        "Resolution, seek duration, player behavior"),
                    leading: const Icon(Icons.headphones),
                    onTap: () {
                      Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (context) => const MediaScreen()));
                    },
                  ),
                  ListTile(
                    title: const Text("Comments"),
                    subtitle: const Text("Filters, show hidden/spam comments"),
                    leading: const Icon(Icons.comment),
                    onTap: () {
                      Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (context) => const CommentsScreen()));
                    },
                  ),
                  ListTile(
                    title: const Text("History"),
                    subtitle: const Text("Watch & Search history"),
                    leading: const Icon(Icons.history),
                    onTap: () {
                      Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (context) => const HistoryScreen()));
                    },
                  ),
                  ListTile(
                    title: const Text("Privacy"),
                    subtitle:
                        const Text("Hide app preview, Keyboard incognito mode"),
                    leading: const Icon(Icons.lock),
                    onTap: () {
                      Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (context) => const PrivacyScreen()));
                    },
                  ),
                  ListTile(
                    title: const Text("About"),
                    subtitle: const Text("About application"),
                    leading: const Icon(Icons.info),
                    onTap: () {
                      // The AboutScreen has an option to turn on dev settings -> setState on return to immediately show/hide dev settings
                      Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (context) => AboutScreen()))
                          .then((value) => setState(() {}));
                    },
                  ),
                  FutureBuilder<bool?>(
                      future:
                          sharedStorage.getBool("general_enable_dev_options"),
                      builder: (context, snapshot) {
                        // Don't show anything until the future is done
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const SizedBox();
                        }
                        return snapshot.data!
                            ? ListTile(
                                title: const Text("Developer options"),
                                subtitle: const Text("Dev/debug options"),
                                leading: const Icon(Icons.data_object),
                                onTap: () {
                                  Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                          builder: (context) =>
                                              const DeveloperScreen()));
                                },
                              )
                            : const SizedBox();
                      })
                ],
              )),
        ));
  }
}
