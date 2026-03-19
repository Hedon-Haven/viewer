import 'package:flutter/material.dart';
import 'package:page_transition/page_transition.dart';

import '/services/plugin_manager.dart';
import '/ui/screens/bug_report.dart';
import '/ui/screens/onboarding/onboarding_disclaimers.dart';
import '/ui/screens/settings/settings_launcher_appearance.dart';
import '/ui/screens/settings/settings_plugins/install_third_party_plugin.dart';
import '/ui/utils/toast_notification.dart';
import '/ui/widgets/alert_dialog.dart';
import '/ui/widgets/options_switch.dart';
import '/utils/exceptions.dart';
import '/utils/global_vars.dart';

class PluginsScreen extends StatefulWidget {
  final bool partOfOnboarding;

  const PluginsScreen({super.key, this.partOfOnboarding = false});

  @override
  State<PluginsScreen> createState() => _PluginsScreenState();
}

class _PluginsScreenState extends State<PluginsScreen> {
  /// To avoid sending multiple events if multiple plugins/settings are changed
  bool sendPluginsChangedEvent = false;

  void handleNextButton() {
    // Check if user enabled at least one plugin
    if (PluginManager.enabledPlugins.isNotEmpty) {
      Navigator.push(
          context,
          PageTransition(
              type: PageTransitionType.rightToLeftJoined,
              childCurrent: widget,
              child: LauncherAppearance(partOfOnboarding: true)));
    } else {
      showDialog(
          context: context,
          builder: (BuildContext context) {
            return ThemedDialog(
                title: "No plugins enabled",
                primaryText: "Go back",
                onPrimary: Navigator.of(context).pop,
                secondaryText: "Continue anyways",
                onSecondary: () => Navigator.push(
                    context,
                    PageTransition(
                        type: PageTransitionType.rightToLeftJoined,
                        childCurrent: widget,
                        child: LauncherAppearance(partOfOnboarding: true))),
                content: Text(
                    "Are you sure you want to continue without enabling any plugins?"));
          });
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
        onPopInvoked: (_) =>
            sendPluginsChangedEvent ? reloadVideoListEvent.add(null) : null,
        child: Scaffold(
            appBar: AppBar(
              // Hide back button in onboarding
              automaticallyImplyLeading: !widget.partOfOnboarding,
              iconTheme:
                  IconThemeData(color: Theme.of(context).colorScheme.primary),
              title: widget.partOfOnboarding
                  ? Center(child: Text("Plugins"))
                  : const Text("Plugins"),
              actions: [
                IconButton(
                  icon: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Icon(Icons.extension),
                      Positioned(
                        right: -8,
                        bottom: -8,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Icon(Icons.circle,
                                size: 18,
                                color: Theme.of(context).colorScheme.surface),
                            Icon(Icons.add, size: 18),
                          ],
                        ),
                      ),
                    ],
                  ),
                  onPressed: () {
                    Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (context) =>
                                ThirdPartyPluginInstallScreen())).then((_) {
                      setState(() {});
                    });
                  },
                ),
              ],
            ),
            body: SafeArea(
                child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Column(children: [
                      Expanded(
                          child: ListView.builder(
                        itemCount: PluginManager.allPlugins.length,
                        itemBuilder: (context, index) {
                          String title =
                              PluginManager.allPlugins[index].prettyName;
                          String subTitle =
                              PluginManager.allPlugins[index].providerUrl;
                          return OptionsSwitch(
                            // TODO: MAYBE: rework this UI to make it more obvious to why its there and what it means
                            leadingWidget:
                                buildOptionsSwitchLeadingWidget(index),
                            title: title,
                            subTitle: subTitle,
                            switchState: PluginManager.enabledPlugins
                                .contains(PluginManager.allPlugins[index]),
                            nonInteractive: PluginManager
                                .unavailablePlugins.keys
                                .contains(PluginManager.allPlugins[index]),
                            showExtraSettingsButton: true,
                            onToggled: (toggleValue) {
                              if (toggleValue) {
                                PluginManager.enablePlugin(
                                        PluginManager.allPlugins[index])
                                    .then((initValue) {
                                  if (!initValue) {
                                    showToast(
                                        "Failed to enable ${PluginManager.allPlugins[index].prettyName}",
                                        context);
                                    PluginManager.disablePlugin(
                                        PluginManager.allPlugins[index]);
                                  }
                                });
                              } else {
                                PluginManager.disablePlugin(
                                    PluginManager.allPlugins[index]);
                              }
                              sendPluginsChangedEvent = true;
                              setState(() {});
                            },
                            onPressedSettingsButton: () {
                              // open popup with options
                              showDialog(
                                  context: context,
                                  builder: (BuildContext context) {
                                    return buildPluginOptions(title, index);
                                  });
                              sendPluginsChangedEvent = true;
                            },
                          );
                        },
                      )),
                      if (widget.partOfOnboarding) ...[
                        Spacer(),
                        Padding(
                            padding: EdgeInsets.all(12),
                            child: Row(children: [
                              Align(
                                  alignment: Alignment.bottomLeft,
                                  child: ElevatedButton(
                                      style: TextButton.styleFrom(
                                          backgroundColor: Theme.of(context)
                                              .colorScheme
                                              .surfaceVariant),
                                      onPressed: () => Navigator.push(
                                          context,
                                          PageTransition(
                                              type: PageTransitionType
                                                  .leftToRightJoined,
                                              childCurrent: widget,
                                              child: DisclaimersScreen())),
                                      child: Text("Back",
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleMedium
                                              ?.copyWith(
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .onSurfaceVariant)))),
                              Spacer(),
                              Align(
                                  alignment: Alignment.bottomRight,
                                  child: ElevatedButton(
                                      style: TextButton.styleFrom(
                                          backgroundColor: Theme.of(context)
                                              .colorScheme
                                              .primary),
                                      onPressed: () => handleNextButton(),
                                      child: Text("Next",
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleMedium
                                              ?.copyWith(
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .onPrimary))))
                            ]))
                      ]
                    ])))));
  }

  Widget buildOptionsSwitchLeadingWidget(int index) {
    bool customException = isCustomException(
        PluginManager.unavailablePlugins[PluginManager.allPlugins[index]]);
    return PluginManager.unavailablePlugins.keys
            .contains(PluginManager.allPlugins[index])
        ? IconButton(
            color: Theme.of(context).colorScheme.primary,
            onPressed: () => showDialog(
                context: context,
                builder: (BuildContext context) => ThemedDialog(
                    title: "Plugin initialization error",
                    // TODO: Add a link to proxy settings in case of AgeGateException or BannedCountryException
                    primaryText: customException ? "Ok" : "Report bug",
                    onPrimary: () {
                      if (customException) {
                        Navigator.pop(context);
                      } else {
                        Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (context) => BugReportScreen(
                                        debugObject: [],
                                        message: PluginManager
                                            .unavailablePlugins[
                                                PluginManager.allPlugins[index]]
                                            .toString(),
                                        issueType: "Plugin issue")))
                            .then((value) => Navigator.pop(context));
                      }
                    },
                    secondaryText: customException ? null : "Close",
                    onSecondary: () =>
                        customException ? null : Navigator.pop(context),
                    content: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                              "The ${PluginManager.allPlugins[index].prettyName} plugin failed to initialize with the following error:",
                              style: Theme.of(context).textTheme.titleMedium),
                          SizedBox(height: 5),
                          TextFormField(
                              initialValue: PluginManager.unavailablePlugins[
                                      PluginManager.allPlugins[index]]
                                  .toString(),
                              readOnly: true,
                              maxLines: null,
                              style: TextStyle(
                                  color:
                                      Theme.of(context).colorScheme.onSurface),
                              textAlignVertical: TextAlignVertical.top,
                              decoration: InputDecoration(
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide.none,
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                      vertical: 10, horizontal: 10),
                                  filled: true,
                                  fillColor:
                                      Theme.of(context).colorScheme.surface,
                                  hoverColor:
                                      Theme.of(context).colorScheme.surface))
                        ]))),
            icon: Icon(
                size: 30,
                color: Theme.of(context).colorScheme.error,
                Icons.report_problem),
          )
        : IconButton(
            color: Theme.of(context).colorScheme.primary,
            onPressed: () => showDialog(
                context: context,
                builder: (BuildContext context) => ThemedDialog(
                    title: PluginManager.allPlugins[index].isOfficialPlugin
                        ? "Official plugin"
                        : "Third party plugin",
                    primaryText: "Ok",
                    onPrimary: () => Navigator.pop(context),
                    content: SingleChildScrollView(
                        child: Text(PluginManager
                                .allPlugins[index].isOfficialPlugin
                            ? "This plugin was developed and tested by the official Hedon Haven developers."
                            : "This plugin is from an unaffiliated third party.")))),
            icon: Icon(
                size: 30,
                color: Theme.of(context).colorScheme.primary,
                PluginManager.allPlugins[index].isOfficialPlugin
                    ? Icons.verified
                    : Icons.extension),
          );
  }

  Widget buildPluginOptions(String title, int index) {
    return ThemedDialog(
        title: "$title options",
        primaryText: "Apply",
        onPrimary: Navigator.of(context).pop,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            OptionsSwitch(
                title: "Results provider",
                subTitle: "Use this plugin to provide video results",
                switchState: PluginManager.enabledResultsProviders
                    .contains(PluginManager.allPlugins[index]),
                onToggled: (value) {
                  if (value) {
                    PluginManager.enableProvider(
                        PluginManager.allPlugins[index], "results");
                  } else {
                    PluginManager.disableProvider(
                        PluginManager.allPlugins[index], "results");
                  }
                  setState(() {});
                }),
            OptionsSwitch(
                title: "Homepage provider",
                subTitle: "Show this plugins results on the homepage",
                switchState: PluginManager.enabledHomepageProviders
                    .contains(PluginManager.allPlugins[index]),
                onToggled: (value) {
                  if (value) {
                    PluginManager.enableProvider(
                        PluginManager.allPlugins[index], "homepage");
                  } else {
                    PluginManager.disableProvider(
                        PluginManager.allPlugins[index], "homepage");
                  }
                  setState(() {});
                }),
            OptionsSwitch(
                title: "Search suggestions provider",
                subTitle: "Use this plugin to provide search suggestions",
                switchState: PluginManager.enabledSearchSuggestionsProviders
                    .contains(PluginManager.allPlugins[index]),
                onToggled: (value) {
                  if (value) {
                    PluginManager.enableProvider(
                        PluginManager.allPlugins[index], "search_suggestions");
                  } else {
                    PluginManager.disableProvider(
                        PluginManager.allPlugins[index], "search_suggestions");
                  }
                  setState(() {});
                })
          ],
        ));
  }
}
