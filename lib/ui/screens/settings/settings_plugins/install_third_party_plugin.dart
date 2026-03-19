import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '/services/plugin_manager.dart';
import '/ui/widgets/alert_dialog.dart';
import '/utils/global_vars.dart';
import '/utils/plugin_interface.dart';

class ThirdPartyPluginInstallScreen extends StatefulWidget {
  final bool partOfOnboarding;

  const ThirdPartyPluginInstallScreen(
      {super.key, this.partOfOnboarding = false});

  @override
  State<ThirdPartyPluginInstallScreen> createState() =>
      _ThirdPartyPluginInstallScreenState();
}

class _ThirdPartyPluginInstallScreenState
    extends State<ThirdPartyPluginInstallScreen> {
  String? fileName;
  Map<String, dynamic>? pluginConfigMap;
  String? configFormatted;
  bool? isTestingPlugin;
  bool funcTestFailed = false;
  bool? isImportingPlugin;
  bool allowPop = false;

  @override
  void initState() {
    super.initState();
    if (!thirdPartyPluginWarningShown) {
      logger.d("Showing third party warning");
      WidgetsBinding.instance
          .addPostFrameCallback((_) => showThirdPartyWarning());
    }
  }

  void resetProgress() {
    setState(() {
      fileName = null;
      pluginConfigMap = null;
      configFormatted = null;
      isTestingPlugin = null;
      funcTestFailed = false;
      isImportingPlugin = null;
    });
  }

  void showThirdPartyWarning() async {
    await showDialog(
        context: context,
        builder: (BuildContext context) {
          return PopScope(
              canPop: false,
              child: ThemedDialog(
                title: "Third party warning",
                primaryText: "Accept risks and continue",
                onPrimary: () {
                  Navigator.pop(context);
                  thirdPartyPluginWarningShown = true;
                },
                secondaryText: "Cancel",
                onSecondary: () {
                  Navigator.of(context).pop();
                  Navigator.of(context).pop();
                },
                content: const Text(
                    "Importing plugins from untrusted sources may put your device at risk! "
                    "The developers of Hedon Haven take no responsibility for any damage or "
                    "unintended consequences of using plugins from untrusted sources.",
                    style: TextStyle(fontWeight: FontWeight.bold)),
              ));
        });
  }

  void showFunctionalityFailWarning() async {
    await showDialog(
        context: context,
        builder: (BuildContext context) {
          return PopScope(
              canPop: false,
              child: ThemedDialog(
                title: "Functionality tests failed",
                primaryText: "Import anyway",
                onPrimary: () {
                  Navigator.pop(context);
                  importPlugin();
                },
                secondaryText: "Cancel import",
                onSecondary: () {
                  resetProgress();
                  Navigator.of(context).pop();
                },
                content: const Text(
                    "Some functionality tests failed. The plugin might not "
                    "fully work as intended.",
                    style: TextStyle(fontWeight: FontWeight.bold)),
              ));
        });
  }

  void showErrorDialog(String title, String message) async {
    await showDialog(
        context: context,
        builder: (BuildContext context) {
          return ThemedDialog(
            title: title,
            primaryText: "Ok",
            onPrimary: () {
              resetProgress();
              Navigator.pop(context);
            },
            content: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(5.0),
              ),
              padding: const EdgeInsets.all(5.0),
              child: Text(message.trim(),
                  style: Theme.of(context).textTheme.bodyMedium),
            ),
          );
        });
  }

  void extractPlugin() async {
    resetProgress();
    try {
      var selectedFile = await FilePicker.platform
          .pickFiles(type: FileType.custom, allowedExtensions: ["zip"]);
      pluginConfigMap = await PluginManager.extractPlugin(selectedFile);
      configFormatted = "Name: ${pluginConfigMap!["metadata"]["prettyName"]} "
          "(${pluginConfigMap!["metadata"]["codeName"]})"
          "\nProvider: ${pluginConfigMap!["providerData"]["providerUrl"]}"
          "\nVersion: ${pluginConfigMap!["metadata"]["version"]}"
          "\nDeveloper: ${pluginConfigMap!["metadata"]["developer"]}"
          "\nDescription: ${pluginConfigMap!["metadata"]["description"]}"
          "\nUpdate URL: ${pluginConfigMap!["metadata"]["updateUrl"] ?? "Auto-updates unsupported"}";
      setState(() => fileName = selectedFile?.files.first.name);
    } catch (e, stacktrace) {
      if (e.toString().contains("AlreadyInstalled")) {
        showErrorDialog(
            "Duplicate plugin detected",
            "A plugin with the codename: "
                "${e.toString().split(":").last.trim()} is already installed! "
                "Please uninstall it first!");
        return;
      }
      logger.w("Error extracting plugin: $e\n$stacktrace");
      showErrorDialog("Not a valid plugin zip file!", "$e\n$stacktrace");
      setState(() => fileName = null);
    }
  }

  void testPlugin() async {
    setState(() => isTestingPlugin = true);
    try {
      final passed = await PluginManager.testExternalPlugin(
          Directory(pluginConfigMap!["tempPluginPath"]));
      if (!passed) {
        setState(() {
          isTestingPlugin = false;
          funcTestFailed = true;
        });
        showFunctionalityFailWarning();
      } else {
        setState(() => isTestingPlugin = false);
        importPlugin();
      }
    } catch (e, stacktrace) {
      logger.e("Failed to run functionality tests: $e\n$stacktrace");
      showErrorDialog("Failed to run functionality tests", "$e\n$stacktrace");
      setState(() {
        funcTestFailed = true;
        isTestingPlugin = false;
      });
    }
  }

  void importPlugin() async {
    setState(() => isImportingPlugin = true);
    try {
      await PluginManager.importPlugin(pluginConfigMap!);
      await PluginManager.discoverAndLoadPlugins();
      PluginInterface? newPlugin = PluginManager.getPluginByName(
          pluginConfigMap!["metadata"]["codeName"]);
      if (newPlugin == null) {
        throw Exception(
            "PluginManager did not find the newly installed plugin by codename");
      }
      PluginManager.enablePlugin(newPlugin);
      setState(() => isImportingPlugin = false);
    } catch (e, stacktrace) {
      logger.e("Failed to import plugin: $e\n$stacktrace");
      showErrorDialog("Failed to import plugin", "$e\n$stacktrace");
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
        canPop: allowPop ||
            isImportingPlugin == isTestingPlugin && isImportingPlugin != true,
        onPopInvokedWithResult: (goingToPop, __) {
          if (!goingToPop) {
            showDialog(
                context: context,
                builder: (BuildContext context) {
                  return ThemedDialog(
                    title: "Cancel plugin installation?",
                    primaryText: "Continue installing",
                    onPrimary: Navigator.of(context).pop,
                    secondaryText: "Cancel installation",
                    onSecondary: () {
                      allowPop = true;
                      // close popup
                      Navigator.pop(context);
                      // Go back a screen
                      Navigator.of(context).pop(false);
                    },
                  );
                });
          }
        },
        child: Scaffold(
            appBar: AppBar(
              iconTheme:
                  IconThemeData(color: Theme.of(context).colorScheme.primary),
              title: Text("Third party plugin installation"),
            ),
            body: SafeArea(
                child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                        mainAxisAlignment: MainAxisAlignment.start,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        spacing: 20,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                  fileName != null
                                      ? "$fileName"
                                      : "Select zip file: ",
                                  style:
                                      Theme.of(context).textTheme.titleMedium),
                              ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                      foregroundColor: Theme.of(context)
                                          .colorScheme
                                          .onPrimary,
                                      backgroundColor: Theme.of(context)
                                          .colorScheme
                                          .primary),
                                  onPressed: isTestingPlugin != null
                                      ? null
                                      : () => extractPlugin(),
                                  child: Row(children: [
                                    Text("Select "),
                                    Icon(size: 20, Icons.open_in_new),
                                  ]))
                            ],
                          ),
                          if (configFormatted != null) ...[
                            Column(
                              mainAxisAlignment: MainAxisAlignment.start,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              spacing: 5,
                              children: [
                                Text("Plugin details:",
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium),
                                Container(
                                  width: double.infinity,
                                  decoration: BoxDecoration(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .surfaceVariant,
                                    borderRadius: BorderRadius.circular(5.0),
                                  ),
                                  padding: const EdgeInsets.all(5.0),
                                  child: Text(configFormatted!,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium),
                                )
                              ],
                            ),
                            if (isTestingPlugin == null)
                              Row(mainAxisSize: MainAxisSize.max, children: [
                                Spacer(),
                                ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                        foregroundColor: Theme.of(context)
                                            .colorScheme
                                            .onPrimary,
                                        backgroundColor: Theme.of(context)
                                            .colorScheme
                                            .primary),
                                    onPressed: () => testPlugin(),
                                    child: Text("Test and Import")),
                                Spacer()
                              ])
                          ],
                          if (isTestingPlugin != null)
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Text("Functionality tests:",
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium),
                                isTestingPlugin!
                                    ? SizedBox(
                                        width: 30,
                                        height: 30,
                                        child: CircularProgressIndicator())
                                    : Icon(
                                        funcTestFailed
                                            ? Icons.error
                                            : Icons.check_circle,
                                        size: 30,
                                        color: funcTestFailed
                                            ? Theme.of(context)
                                                .colorScheme
                                                .error
                                            : Theme.of(context)
                                                .colorScheme
                                                .primary)
                              ],
                            ),
                          if (isImportingPlugin != null) ...[
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Text("Importing plugin:",
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium),
                                isImportingPlugin!
                                    ? SizedBox(
                                        width: 30,
                                        height: 30,
                                        child: CircularProgressIndicator())
                                    : Icon(Icons.check_circle,
                                        size: 30,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primary)
                              ],
                            ),
                            if (!isImportingPlugin!)
                              Row(mainAxisSize: MainAxisSize.min, children: [
                                Spacer(),
                                ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                        foregroundColor: Theme.of(context)
                                            .colorScheme
                                            .onPrimary,
                                        backgroundColor: Theme.of(context)
                                            .colorScheme
                                            .primary),
                                    onPressed: () =>
                                        Navigator.of(context).pop(),
                                    child: Text("Done")),
                                Spacer()
                              ])
                          ]
                        ])))));
  }
}
