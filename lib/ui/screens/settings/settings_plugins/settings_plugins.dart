import 'package:flutter/material.dart';
import 'package:page_transition/page_transition.dart';

import '/services/plugin_manager.dart';
import '/ui/screens/bug_report.dart';
import '/ui/screens/onboarding/onboarding_disclaimers.dart';
import '/ui/screens/settings/settings_launcher_appearance.dart';
import '/ui/screens/settings/settings_plugins/install_3rd_party_plugin.dart';
import '/ui/utils/toast_notification.dart';
import '/ui/widgets/alert_dialog.dart';
import '/ui/widgets/options_switch.dart';
import '/utils/exceptions.dart';
import '/utils/global_vars.dart';
import '/utils/plugin_interface/plugin_interface.dart';

class PluginsScreen extends StatefulWidget {
  final bool partOfOnboarding;

  const PluginsScreen({super.key, this.partOfOnboarding = false});

  @override
  State<PluginsScreen> createState() => _PluginsScreenState();
}

class _PluginsScreenState extends State<PluginsScreen> {
  /// To avoid sending multiple events if multiple plugins/settings are changed
  bool sendPluginsChangedEvent = false;
  bool checkingForUpdatesInProgress = false;
  String? pluginCodeNameInProgress;

  // Cached lists from PluginManager
  List<PluginInterface> _allPlugins = [];
  List<PluginInterface> _enabledPlugins = [];
  List<PluginInterface> _failedPlugins = [];
  List<PluginInterface> _updatablePlugins = [];

  Future<void> _loadPluginLists() async {
    final (all, enabled, failed, updatable) = await (
      PluginManager.getAllPlugins(),
      PluginManager.getEnabledPlugins(),
      PluginManager.getFailedPlugins(),
      PluginManager.getUpdatablePlugins()
    ).wait;
    if (context.mounted) {
      setState(() {
        _allPlugins = all;
        _enabledPlugins = enabled;
        _failedPlugins = failed;
        _updatablePlugins = updatable;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _loadPluginLists();

    // Reload plugin lists if updates become available
    pluginUpdatesAvailableEvent.stream.listen((_) => _loadPluginLists());
  }

  void handleNextButton() async {
    // Check if user enabled at least one plugin
    if ((await PluginManager.getEnabledPlugins()).isNotEmpty) {
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

  /// TODO: Prompt user to delete plugin if not official plugin
  void _togglePlugin(PluginInterface plugin, bool newState) async {
    if (newState) {
      try {
        await PluginManager.enablePlugin(plugin);
      } catch (e, st) {
        showToast(
            "Failed to enable ${plugin.prettyName} due to $e\n$st", context);
      }
    } else {
      try {
        await PluginManager.disablePlugin(plugin);
      } catch (e, st) {
        showToast(
            "Failed to disable ${plugin.prettyName} due to $e\n$st", context);
      }
    }
    sendPluginsChangedEvent = true;
    _loadPluginLists();
  }

  void _setAsProvider(PluginInterface plugin, Set<ProviderType> provides,
      ProviderType updateType, bool newState) async {
    // we can directly modify provides, since it'll be thrown away on setState call
    if (newState) {
      provides.add(updateType);
    } else {
      provides.remove(updateType);
    }
    await PluginManager.setAsProvider(plugin, provides);
    sendPluginsChangedEvent = true;
    _loadPluginLists();
  }

  /// Manages updating one plugin at a time
  Future<void> _updateSinglePlugin(PluginInterface plugin) async {
    setState(() => pluginCodeNameInProgress = plugin.codeName);
    try {
      await PluginManager.updatePlugin(plugin);
    } catch (e, st) {
      showErrorDialog("Failed to update ${plugin.prettyName}",
          "Failed to update ${plugin.prettyName} due to $e\n$st");
    }
    setState(() => pluginCodeNameInProgress = null);
  }

  void showErrorDialog(String title, String message) async {
    await showDialog(
        context: context,
        builder: (BuildContext context) {
          return ThemedDialog(
            title: title,
            primaryText: "Ok",
            onPrimary: () {
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

  void _showPluginInitErrorDialog(PluginInterface plugin) {
    showDialog(
        context: context,
        builder: (BuildContext context) => FutureBuilder<(Exception, String)?>(
            future: PluginManager.getPluginError(plugin),
            builder: (context, snapshot) {
              final bool customException = snapshot.data != null
                  ? isCustomException(snapshot.data?.$1)
                  : false;
              final String errorMessage = snapshot.data != null
                  ? snapshot.data!.$1.toString() + snapshot.data!.$2
                  : "Unknown error!?";
              return ThemedDialog(
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
                                      plugin: plugin,
                                      message: errorMessage,
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
                            "The ${plugin.prettyName} plugin failed to initialize with the following error:",
                            style: Theme.of(context).textTheme.titleMedium),
                        SizedBox(height: 5),
                        TextFormField(
                            initialValue: errorMessage,
                            readOnly: true,
                            maxLines: null,
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.onSurface),
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
                      ]));
            }));
  }

  void showPluginUpdateDialog(PluginInterface plugin) {
    showDialog(
        context: context,
        builder: (BuildContext context) => FutureBuilder<UpdateInfo?>(
            future: PluginManager.getUpdateInfoFor(plugin),
            builder: (context, snapshot) {
              // Don't show anything until the future is done
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const SizedBox();
              }
              final UpdateInfo updateInfo = snapshot.data!;
              final String details = "Codename: ${plugin.codeName}\n"
                  "Provides: ${plugin.providerUrl}\n\n"
                  "Changelog for ${plugin.version} -> ${updateInfo.newVersion}:\n"
                  "${updateInfo.changelog.map((s) => "• $s").join("\n")}\n\n"
                  "Download URL: ${updateInfo.downloadUrl}";
              return ThemedDialog(
                  title: "Update ${plugin.prettyName}",
                  primaryText: "Download and install",
                  onPrimary: () {
                    // Start update but don't wait for it to finish and immediately close dialog
                    _updateSinglePlugin(plugin);
                    Navigator.of(context).pop();
                  },
                  secondaryText: "Cancel",
                  onSecondary: Navigator.of(context).pop,
                  content: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(
                        "An update is available for ${plugin.prettyName}. Update now?"),
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        borderRadius: BorderRadius.circular(5.0),
                      ),
                      padding: const EdgeInsets.all(5.0),
                      child: SelectableText(details,
                          style: Theme.of(context).textTheme.bodySmall),
                    ),
                  ]));
            }));
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
                actions: buildAdditionalOptionsButton()),
            body: SafeArea(
                child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Column(children: [
                      Expanded(
                          child: ListView.builder(
                        itemCount: _allPlugins.length,
                        itemBuilder: (context, index) {
                          PluginInterface plugin = _allPlugins[index];
                          return OptionsSwitch(
                              // TODO: MAYBE: rework this UI Widget to make it more obvious to why its there and what it means
                              leadingWidget:
                                  buildOptionsSwitchLeadingWidget(plugin),
                              trailingWidget: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (_updatablePlugins.contains(plugin))
                                      pluginCodeNameInProgress ==
                                              plugin.codeName
                                          ? CircularProgressIndicator()
                                          : IconButton(
                                              onPressed:
                                                  pluginCodeNameInProgress !=
                                                          null
                                                      ? null
                                                      : () =>
                                                          showPluginUpdateDialog(
                                                              plugin),
                                              icon: Icon(
                                                Icons.download,
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .error,
                                              )),
                                    IconButton(
                                        onPressed:
                                            pluginCodeNameInProgress != null
                                                ? null
                                                : () {
                                                    showDialog(
                                                        context: context,
                                                        builder: (BuildContext
                                                                context) =>
                                                            buildPluginOptions(
                                                                plugin));
                                                  },
                                        icon: const Icon(Icons.settings))
                                  ]),
                              title: plugin.prettyName,
                              subTitle: plugin.providerUrl,
                              switchState: _enabledPlugins.contains(plugin),
                              nonInteractive:
                                  pluginCodeNameInProgress != null ||
                                      _failedPlugins.contains(plugin),
                              reduceHorizontalBordersOnly: true,
                              onToggled: (toggleValue) =>
                                  _togglePlugin(plugin, toggleValue));
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

  List<Widget> buildAdditionalOptionsButton() {
    if (checkingForUpdatesInProgress) {
      return [CircularProgressIndicator(padding: const EdgeInsets.all(10))];
    }
    return [
      PopupMenuButton<String>(
          enabled: pluginCodeNameInProgress == null,
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
                        size: 18, color: Theme.of(context).colorScheme.surface),
                    Icon(Icons.add, size: 18),
                  ],
                ),
              ),
            ],
          ),
          offset: Offset(0, 50),
          color: Theme.of(context).colorScheme.surfaceVariant,
          itemBuilder: (context) => [
                PopupMenuItem(
                    onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (context) =>
                                    Install3rdPartyPluginScreen())).then((_) {
                          _loadPluginLists();
                        }),
                    child: Row(spacing: 10, children: [
                      Icon(Icons.add),
                      Text("Install new plugin")
                    ])),
                PopupMenuItem(
                    onTap: () async {
                      setState(() => checkingForUpdatesInProgress = true);
                      await PluginManager.checkForPluginUpdates();
                      setState(() => checkingForUpdatesInProgress = false);
                    },
                    child: Row(spacing: 10, children: [
                      Icon(Icons.update),
                      Text("Check for plugin updates")
                    ])),
                PopupMenuItem(
                    onTap: () => showToast(
                        "Not yet implemented, please click each update manually",
                        context),
                    child: Row(spacing: 10, children: [
                      Icon(Icons.system_update_alt),
                      Text("Update all plugins")
                    ])),
              ])
    ];
  }

  Widget buildOptionsSwitchLeadingWidget(PluginInterface plugin) {
    return _failedPlugins.contains(plugin)
        ? IconButton(
            color: Theme.of(context).colorScheme.primary,
            onPressed: () => _showPluginInitErrorDialog(plugin),
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
                    title: plugin.isOfficialPlugin
                        ? "Official plugin"
                        : "Third party plugin",
                    primaryText: "Ok",
                    onPrimary: () => Navigator.pop(context),
                    content: SingleChildScrollView(
                        child: Text(plugin.isOfficialPlugin
                            ? "This plugin was developed and tested by the official Hedon Haven developers."
                            : "This plugin is from the third party developer ${plugin.developer}")))),
            icon: Icon(
                size: 30,
                color: plugin.isOfficialPlugin
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.tertiary,
                plugin.isOfficialPlugin ? Icons.verified : Icons.extension));
  }

  Widget buildPluginOptions(PluginInterface plugin) {
    return FutureBuilder<Set<ProviderType>>(
        future: PluginManager.getEnabledProviderTypesOf(plugin),
        builder: (context, snapshot) {
          // Don't show anything until the future is done
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const SizedBox();
          }
          final Set<ProviderType> provides = snapshot.data!;
          return ThemedDialog(
              title: "${plugin.prettyName} options",
              primaryText: "Apply",
              onPrimary: Navigator.of(context).pop,
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  OptionsSwitch(
                      title: "Search results provider",
                      subTitle:
                          "Use this plugin to provide video search results",
                      switchState:
                          provides.contains(ProviderType.searchResults),
                      onToggled: (newState) => _setAsProvider(plugin, provides,
                          ProviderType.searchResults, newState)),
                  OptionsSwitch(
                      title: "Homepage provider",
                      subTitle: "Show this plugins results on the homepage",
                      switchState: provides.contains(ProviderType.homepage),
                      onToggled: (newState) => _setAsProvider(
                          plugin, provides, ProviderType.homepage, newState)),
                  OptionsSwitch(
                      title: "Search suggestions provider",
                      subTitle: "Use this plugin to provide search suggestions",
                      switchState:
                          provides.contains(ProviderType.searchSuggestions),
                      onToggled: (newState) => _setAsProvider(plugin, provides,
                          ProviderType.searchSuggestions, newState)),
                  if (!plugin.isOfficialPlugin)
                    ListTile(
                        trailing: const Icon(Icons.delete_forever,
                            size: 40, color: Colors.red),
                        contentPadding: EdgeInsets.only(left: 16, right: 8),
                        title: const Text("Delete third-party plugin"),
                        subtitle: Text(
                            "Permanently delete all plugin files and configs"),
                        onTap: () async {
                          await PluginManager.deletePlugin(plugin);
                          _loadPluginLists();
                          Navigator.of(context).pop();
                        }),
                ],
              ));
        });
  }
}
