import 'package:flutter/material.dart';

import '/ui/screens/bug_report.dart';
import '/utils/global_vars.dart';
import '/utils/plugin_interface/plugin_interface.dart';

class ScrapingReportScreen extends StatefulWidget {
  final Map<PluginInterface, Map<String, List<dynamic>>> multiProviderMap;
  final Map<String, List<dynamic>> singleProviderMap;
  final String? singleMessage;
  final Map<String, dynamic>? singleDebugObject;

  ScrapingReportScreen(
      {super.key,
      Map<PluginInterface, Map<String, List<dynamic>>>? multiProviderMap,
      Map<String, List<dynamic>>? singleProviderMap,
      this.singleMessage,
      this.singleDebugObject})
      : multiProviderMap = multiProviderMap ?? {},
        singleProviderMap = singleProviderMap ?? {};

  @override
  State<ScrapingReportScreen> createState() => _ScrapingReportScreenState();
}

class _ScrapingReportScreenState extends State<ScrapingReportScreen> {
  /// Multi provider map (shortened name for better UI code readability)
  late Map<PluginInterface, Map<String, List<dynamic>>> mpm =
      widget.multiProviderMap;

  /// Single provider map (shortened name for better UI code readability)
  late Map<String, List<dynamic>> spm = widget.singleProviderMap;

  @override
  void initState() {
    super.initState();
    logger.d("Single provider map: ${spm.toString()}");
    logger.d("Multi-provider map: ${mpm.toString()}");
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
            iconTheme:
                IconThemeData(color: Theme.of(context).colorScheme.primary),
            title: Text("Scraping report",
                style: Theme.of(context).textTheme.headlineLarge),
            actions: [
              if (spm.isNotEmpty ||
                  mpm.isNotEmpty ||
                  (widget.singleMessage != null &&
                      widget.singleDebugObject != null)) ...[
                Padding(
                    padding: const EdgeInsets.only(right: 16),
                    child: IconButton(
                        icon:
                            Stack(alignment: Alignment.bottomRight, children: [
                          const Icon(Icons.send, size: 32),
                          if (spm.isNotEmpty || mpm.isNotEmpty) ...[
                            const Icon(Icons.done_all, size: 16)
                          ]
                        ]),
                        onPressed: () {
                          List<Map<String, dynamic>> combined = [];
                          if (mpm.isNotEmpty) {
                            for (int index = 0; index < mpm.length; index++) {
                              List<Map<String, dynamic>> errors = [];
                              for (var object in mpm[
                                  mpm.keys.elementAt(index)]!["Error"]!) {
                                errors.add(object.toMap());
                              }
                              List<Map<String, dynamic>> warnings = [];
                              for (var object in mpm[
                                  mpm.keys.elementAt(index)]!["Warning"]!) {
                                errors.add(object.toMap());
                              }
                              // Only add plugins with errors
                              if (!(mpm[mpm.keys.elementAt(index)]!["Critical"]!
                                      .isEmpty &&
                                  mpm[mpm.keys.elementAt(index)]!["Error"]!
                                      .isEmpty &&
                                  mpm[mpm.keys.elementAt(index)]!["Warning"]!
                                      .isEmpty)) {
                                combined.add({
                                  "pluginCodeName":
                                      mpm.keys.elementAt(index).codeName,
                                  "criticalErrors": mpm[
                                      mpm.keys.elementAt(index)]!["Critical"]!,
                                  "errors": errors,
                                  "warnings": warnings
                                });
                              }
                            }
                          } else if (spm.isNotEmpty) {
                            combined.add({
                              "criticalErrors": spm["Critical"],
                              "errors": spm["Error"]?.map((e) => e.toMap()),
                              "warnings": spm["Warning"]?.map((e) => e.toMap()),
                              "debugObject": widget.singleDebugObject ?? "null"
                            });
                          }

                          if (spm.isNotEmpty || mpm.isNotEmpty) {
                            Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                        builder: (context) => BugReportScreen(
                                            debugObject: combined,
                                            issueType: "Plugin issue")))
                                .then((value) {
                              if (value) {
                                // clear whole list
                                setState(() => mpm.clear());
                                setState(() => spm.clear());
                                // Go back a screen
                                Navigator.pop(context);
                              }
                            });
                          } else {
                            Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (context) => BugReportScreen(
                                            debugObject: [
                                              widget.singleDebugObject!
                                            ],
                                            message: widget.singleMessage,
                                            issueType: "Plugin issue")));
                          }
                        }))
              ]
            ]),
        body: SafeArea(
            child: ListView(
                padding: const EdgeInsets.all(8),
                children: List.generate(mpm.isEmpty ? 1 : mpm.length, (index) {
                  if (widget.singleMessage != null &&
                      widget.singleDebugObject != null) {
                    return Padding(
                        padding: const EdgeInsets.only(top: 50),
                        child: Center(
                            child: Text(
                                widget.singleMessage ?? "Unknown error message",
                                style:
                                    Theme.of(context).textTheme.titleLarge)));
                  } else if (spm.isEmpty && mpm.isEmpty) {
                    return Padding(
                        padding: const EdgeInsets.only(top: 50),
                        child: Center(
                            child: Text("No more scraping errors to report")));
                  } else if (spm.isNotEmpty) {
                    return Column(children: [
                      if (spm["Critical"]?.isNotEmpty ?? false) ...[
                        ExpansionTile(
                            title: Text("Critical errors",
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyLarge!
                                    .copyWith(
                                      color:
                                          Theme.of(context).colorScheme.error,
                                    )),
                            trailing: IconButton(
                                icon: Stack(
                                    alignment: Alignment.bottomRight,
                                    children: [
                                      const Icon(Icons.send, size: 30),
                                      const Icon(Icons.done, size: 16)
                                    ]),
                                color: Theme.of(context).colorScheme.error,
                                onPressed: () {
                                  Map<String, dynamic> debugObject = {
                                    "criticalErrors": spm["Critical"]!,
                                    "debugObject": widget.singleDebugObject
                                  };
                                  Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                          builder: (context) => BugReportScreen(
                                              debugObject: [debugObject],
                                              issueType: "Plugin issue"))).then(
                                      (value) {
                                    if (value) {
                                      // pop the whole section
                                      setState(() => spm["Critical"]!.clear());
                                    }
                                  });
                                }),
                            tilePadding:
                                const EdgeInsets.only(left: 16, right: 8),
                            controlAffinity: ListTileControlAffinity.leading,
                            // Remove white lines
                            collapsedShape: RoundedRectangleBorder(),
                            shape: RoundedRectangleBorder(),
                            initiallyExpanded: true,
                            expandedAlignment: Alignment.centerLeft,
                            childrenPadding: const EdgeInsets.only(left: 16),
                            children: [
                              Container(
                                  padding: const EdgeInsets.all(8),
                                  color: Theme.of(context)
                                      .colorScheme
                                      .surfaceVariant,
                                  child:
                                      Text(spm["Critical"]!.join("\n").trim()))
                            ])
                      ],
                      if (spm["Error"]?.isNotEmpty ?? false) ...[
                        buildMultiSection("Error", index)
                      ],
                      if (spm["Warning"]?.isNotEmpty ?? false) ...[
                        buildMultiSection("Warning", index)
                      ]
                    ]);
                  } else {
                    return !(mpm[mpm.keys.elementAt(index)]!["Critical"]!
                                .isEmpty &&
                            mpm[mpm.keys.elementAt(index)]!["Error"]!.isEmpty &&
                            mpm[mpm.keys.elementAt(index)]!["Warning"]!.isEmpty)
                        ? buildPluginTile(index)
                        : const SizedBox();
                  }
                }))));
  }

  Widget buildPluginTile(int index) {
    return ExpansionTile(
        title: Text(mpm.keys.elementAt(index).prettyName),
        controlAffinity: ListTileControlAffinity.leading,
        // Remove white lines
        collapsedShape: RoundedRectangleBorder(),
        shape: RoundedRectangleBorder(),
        trailing: IconButton(
            icon: const Icon(Icons.send),
            color: Theme.of(context).colorScheme.primary,
            onPressed: () {
              List<Map<String, dynamic>> errors = [];
              for (var object in mpm[mpm.keys.elementAt(index)]!["Error"]!) {
                errors.add(object.toMap());
              }
              List<Map<String, dynamic>> warnings = [];
              for (var object in mpm[mpm.keys.elementAt(index)]!["Warning"]!) {
                errors.add(object.toMap());
              }
              Map<String, dynamic> combined = {
                "pluginCodeName": mpm.keys.elementAt(index).codeName,
                "criticalErrors": mpm[mpm.keys.elementAt(index)]!["Critical"]!,
                "errors": errors,
                "warnings": warnings
              };
              Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (context) => BugReportScreen(
                          debugObject: [combined],
                          issueType: "Plugin issue"))).then((value) {
                if (value) {
                  // clear all sections
                  setState(() {
                    mpm[mpm.keys.elementAt(index)]!["Critical"]!.clear();
                    mpm[mpm.keys.elementAt(index)]!["Error"]!.clear();
                    mpm[mpm.keys.elementAt(index)]!["Warning"]!.clear();
                  });
                }
              });
            }),
        tilePadding: const EdgeInsets.only(left: 16, right: 8),
        childrenPadding: const EdgeInsets.only(left: 16.0),
        children: [
          Column(children: [
            if (mpm[mpm.keys.elementAt(index)]!["Critical"]!.isNotEmpty) ...[
              ExpansionTile(
                  title: Text("Critical errors",
                      style: Theme.of(context).textTheme.bodyLarge!.copyWith(
                            color: Theme.of(context).colorScheme.error,
                          )),
                  trailing: IconButton(
                      icon: Stack(alignment: Alignment.bottomRight, children: [
                        const Icon(Icons.send, size: 30),
                        const Icon(Icons.done, size: 16)
                      ]),
                      color: Theme.of(context).colorScheme.error,
                      onPressed: () {
                        Map<String, dynamic> debugObject = {
                          "pluginCodeName": mpm.keys.elementAt(index).codeName,
                          "criticalErrors":
                              mpm[mpm.keys.elementAt(index)]!["Critical"]!,
                        };
                        Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (context) => BugReportScreen(
                                    debugObject: [debugObject],
                                    issueType: "Plugin issue"))).then((value) {
                          if (value) {
                            // pop the whole section
                            setState(() =>
                                mpm[mpm.keys.elementAt(index)]!["Critical"]!
                                    .clear());
                          }
                        });
                      }),
                  tilePadding: const EdgeInsets.only(left: 16, right: 8),
                  controlAffinity: ListTileControlAffinity.leading,
                  // Remove white lines
                  collapsedShape: RoundedRectangleBorder(),
                  shape: RoundedRectangleBorder(),
                  initiallyExpanded: true,
                  expandedAlignment: Alignment.centerLeft,
                  childrenPadding: const EdgeInsets.only(left: 16),
                  children: [
                    Container(
                        padding: const EdgeInsets.all(8),
                        color: Theme.of(context).colorScheme.surfaceVariant,
                        child: Text(mpm[mpm.keys.elementAt(index)]!["Critical"]!
                            .join("\n")
                            .trim()))
                  ])
            ],
            if (mpm[mpm.keys.elementAt(index)]!["Error"]!.isNotEmpty) ...[
              buildMultiSection("Error", index)
            ],
            if (mpm[mpm.keys.elementAt(index)]!["Warning"]!.isNotEmpty) ...[
              buildMultiSection("Warning", index)
            ]
          ])
        ]);
  }

  Widget buildMultiSection(String sectionType, int index) {
    List<dynamic> objects = [];
    if (spm.isNotEmpty) {
      objects = spm[sectionType]!;
    } else {
      objects = mpm[mpm.keys.elementAt(index)]![sectionType]!;
    }
    return ExpansionTile(
        title: Text("${sectionType}s"),
        trailing: IconButton(
            icon: Stack(alignment: Alignment.bottomRight, children: [
              const Icon(Icons.send, size: 30),
              const Icon(Icons.done, size: 16)
            ]),
            color: Theme.of(context).colorScheme.tertiary,
            onPressed: () {
              List<Map<String, dynamic>> debugObjects = [];
              for (var object in objects) {
                debugObjects.add(object.toMap());
              }
              Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (context) => BugReportScreen(
                          debugObject: debugObjects,
                          issueType: "Plugin issue"))).then((value) {
                if (value) {
                  // pop the whole sectionType
                  setState(() {
                    if (spm.isNotEmpty) {
                      spm[sectionType]!.clear();
                    } else {
                      mpm[mpm.keys.elementAt(index)]![sectionType]!.clear();
                    }
                  });
                }
              });
            }),
        tilePadding: const EdgeInsets.only(left: 16, right: 8),
        controlAffinity: ListTileControlAffinity.leading,
        // Remove white lines
        collapsedShape: RoundedRectangleBorder(),
        shape: RoundedRectangleBorder(),
        childrenPadding: const EdgeInsets.only(left: 16),
        children: List.generate(
            objects.length,
            (i) => ExpansionTile(
                    title: Text(objects.elementAt(i).iD),
                    trailing: IconButton(
                        icon: const Icon(Icons.send),
                        color: Theme.of(context).colorScheme.tertiary,
                        onPressed: () {
                          Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (context) => BugReportScreen(
                                              debugObject: [
                                                objects.elementAt(i).toMap()
                                              ],
                                              issueType: "Plugin issue")))
                              .then((value) {
                            if (value) {
                              // pop the current item from the list to avoid reporting it again
                              setState(() {
                                if (spm.isNotEmpty) {
                                  spm[sectionType]!.removeAt(i);
                                } else {
                                  mpm[mpm.keys.elementAt(index)]![sectionType]!
                                      .removeAt(i);
                                }
                              });
                            }
                          });
                        }),
                    tilePadding: const EdgeInsets.only(left: 16, right: 8),
                    controlAffinity: ListTileControlAffinity.leading,
                    // Remove white lines
                    collapsedShape: RoundedRectangleBorder(),
                    shape: RoundedRectangleBorder(),
                    expandedAlignment: Alignment.centerLeft,
                    childrenPadding: const EdgeInsets.only(left: 32),
                    children: [
                      Container(
                          padding: const EdgeInsets.all(8),
                          color: Theme.of(context).colorScheme.surfaceVariant,
                          child: Text(
                              objects.elementAt(i).scrapeFailMessage!.trim()))
                    ])));
  }
}
