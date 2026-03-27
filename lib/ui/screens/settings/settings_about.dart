import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '/services/official_plugins_tracker.dart';
import '/services/plugin_manager.dart';
import '/services/update_manager.dart';
import '/ui/screens/bug_report.dart';
import '/ui/utils/toast_notification.dart';
import '/ui/utils/update_dialog.dart';
import '/utils/global_vars.dart';

class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  int devSettingsCounter = 0;

  String returnAppType() {
    logger.d(packageInfo.packageName);
    if (packageInfo.packageName.split(".").last == "debug") {
      return "debug";
    } else if (packageInfo.packageName.split(".").last == "viewer" &&
        packageInfo.packageName.split(".").length == 3) {
      return "release";
    } else if (packageInfo.packageName.split(".").last == "profile") {
      return "profile";
    } else {
      // TODO: Add desktop versions
      return "UNKNOWN TYPE; PLEASE REPORT THIS TO THE DEVELOPERS";
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          iconTheme:
              IconThemeData(color: Theme.of(context).colorScheme.primary),
          title: const Text("About"),
        ),
        body: SafeArea(
            child: SizedBox(
                child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      children: <Widget>[
                        ListTile(
                            leading: const Icon(Icons.abc_outlined),
                            title: const Text("App name"),
                            subtitle: Text(packageInfo.appName),
                            onTap: () async {
                              if (devSettingsCounter == 6) {
                                if (kDebugMode) {
                                  logger.w(
                                      "Dev settings permanently enabled in debug releases. Refusing to toggle");
                                  showToast(
                                      "Dev settings permanently enabled in debug releases. Refusing to toggle",
                                      context);
                                  return;
                                }
                                bool devSettingsEnabled = (await sharedStorage
                                    .getBool("general_enable_dev_options"))!;
                                if (devSettingsEnabled) {
                                  // disable tester plugin if leaving debug mode
                                  PluginManager.disablePlugin(
                                      (await getOfficialPluginByName(
                                          "tester-official"))!);
                                }

                                devSettingsEnabled = !devSettingsEnabled;
                                sharedStorage.setBool(
                                    "general_enable_dev_options",
                                    devSettingsEnabled);
                                // reload plugins to show TesterPlugin in release versions too
                                await PluginManager.init();
                                showToast(
                                    "Dev settings ${devSettingsEnabled ? "enabled" : "disabled"}",
                                    context);
                                devSettingsCounter = 0;
                              } else {
                                devSettingsCounter++;
                              }
                            }),
                        ListTile(
                          leading: const Icon(Icons.info),
                          trailing: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                                backgroundColor:
                                    Theme.of(context).colorScheme.primary),
                            onPressed: () async {
                              if (Platform.isLinux ||
                                  Platform.isMacOS ||
                                  Platform.isWindows ||
                                  Platform.isIOS) {
                                showToast(
                                    "Auto-updates not yet supported for ${Platform.operatingSystem}",
                                    context);
                              } else {
                                try {
                                  UpdateManager updateManager = UpdateManager();
                                  if (await updateManager.updateAvailable() ==
                                      true) {
                                    showUpdateDialog(updateManager, context);
                                    setState(() {});
                                  } else {
                                    showToast("No update available", context);
                                  }
                                } catch (e, stacktrace) {
                                  logger.e(
                                      "Failed to manually check for update: $e\n$stacktrace");
                                  showToast(
                                      "Failed to manually check for update: $e",
                                      context);
                                }
                              }
                            },
                            child: Text("Check for update",
                                style: Theme.of(context)
                                    .textTheme
                                    .labelLarge
                                    ?.copyWith(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onPrimary)),
                          ),
                          title: const Text("Version"),
                          subtitle: Text(
                              "${packageInfo.version} - ${returnAppType()}"),
                        ),
                        ListTile(
                          leading: const Icon(Icons.key),
                          title: const Text("Build signature"),
                          // TODO: Update source code link
                          subtitle: Text(packageInfo.buildSignature != ""
                              ? packageInfo.buildSignature
                              : "None"),
                        ),
                        ListTile(
                            leading: const Icon(Icons.code),
                            title: const Text("Source code"),
                            // TODO: Update source code link
                            subtitle:
                                const Text("https://source.hedon-haven.top"),
                            onTap: () {
                              launchUrl(
                                  Uri.parse("https://source.hedon-haven.top"));
                            }),
                        ListTile(
                            leading: const Icon(Icons.text_snippet),
                            title: const Text("Show licenses"),
                            subtitle: const Text(
                                "Show all licenses included in this app"),
                            onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (context) => LicensePage(
                                          applicationName: "Hedon Haven",
                                        )))),
                        ListTile(
                            leading: const Icon(Icons.bug_report),
                            title: const Text("Report bug"),
                            subtitle: const Text(
                                "Long press anything in the app to report a bug"),
                            onTap: () {
                              Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (context) =>
                                          BugReportScreen(debugObject: [])));
                            }),
                        ListTile(
                            leading: const Icon(Icons.person),
                            title: const Text("Contributors"),
                            subtitle: const Text("View all contributors"),
                            onTap: () {
                              // This is a rather non-critical link, therefore its not
                              // url-linked via the hedon-haven.top domain
                              launchUrl(Uri.parse(
                                  "https://github.com/Hedon-Haven/Hedon-Haven/graphs/contributors"));
                            }),
                        ListTile(
                            leading: const Icon(Icons.attach_money),
                            title: const Text("Donate"),
                            subtitle: const Text("Support the development"),
                            onTap: () => launchUrl(Uri.parse(
                                "https://donations.hedon-haven.top"))),
                      ],
                    )))));
  }
}
