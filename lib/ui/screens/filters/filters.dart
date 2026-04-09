import 'package:flutter/material.dart';

import '/ui/utils/toast_notification.dart';
import '/ui/widgets/options_dialog.dart';
import '/ui/widgets/options_switch.dart';
import '/utils/universal_formats.dart';

class FilterScreen extends StatefulWidget {
  final UniversalSearchRequest searchRequest;

  const FilterScreen({super.key, required this.searchRequest});

  @override
  State<FilterScreen> createState() => _FilterScreenState();
}

class _FilterScreenState extends State<FilterScreen> {
  String searchString = "";
  String sortingType = "";
  String dateRange = "";
  double minFps = 0;
  double maxFps = 60;

  double minQualityIndex = 0;
  double maxQualityIndex = 8;
  final List<int> qualities = [0, 144, 240, 360, 480, 720, 1080, 1440, 2160];

  double minDurationIndex = 0;
  double maxDurationIndex = 5;

  // 0, 5, 10, 20, 30, 60 min
  final List<int> durationsInSeconds = [0, 300, 600, 1200, 1800, 3600];

  @override
  void initState() {
    super.initState();
    setFiltersFrom(widget.searchRequest);
    setState(() {});
  }

  void setFiltersFrom(UniversalSearchRequest request) {
    searchString = request.searchString;
    sortingType = request.sortingType;
    dateRange = request.dateRange;
    minFps = request.minFramesPerSecond.toDouble();
    maxFps = request.maxFramesPerSecond.toDouble();
    minQualityIndex = qualities.indexOf(request.minQuality).toDouble();
    maxQualityIndex = qualities.indexOf(request.maxQuality).toDouble();
    minDurationIndex =
        durationsInSeconds.indexOf(request.minDuration).toDouble();
    maxDurationIndex =
        durationsInSeconds.indexOf(request.maxDuration).toDouble();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
            title: const Text("Search filters"),
            iconTheme:
                IconThemeData(color: Theme.of(context).colorScheme.primary),
            actions: [
              IconButton(
                color: Theme.of(context).colorScheme.primary,
                onPressed: () async {
                  setFiltersFrom(
                      UniversalSearchRequest(searchString: searchString));
                  setState(() {});
                  showToast("Filters reset to default", context);
                },
                icon: const Icon(Icons.restart_alt),
              ),
              IconButton(
                  color: Theme.of(context).colorScheme.primary,
                  onPressed: () => Navigator.of(context).pop(
                      UniversalSearchRequest(
                          searchString: searchString,
                          sortingType: sortingType,
                          dateRange: dateRange,
                          minQuality: qualities[minQualityIndex.toInt()],
                          maxQuality: qualities[maxQualityIndex.toInt()],
                          minDuration:
                              durationsInSeconds[minDurationIndex.toInt()],
                          maxDuration:
                              durationsInSeconds[maxDurationIndex.toInt()],
                          minFramesPerSecond: minFps.toInt(),
                          maxFramesPerSecond: maxFps.toInt(),
                          virtualReality: false)),
                  icon: const Icon(Icons.check))
            ]),
        body: SafeArea(
            child: SingleChildScrollView(
          child: Column(children: [
            OptionsTile(
                title: "Sort by",
                subtitle: sortingType,
                options: const [
                  "Relevance",
                  "Upload date",
                  "Views",
                  "Rating",
                  "Duration"
                ],
                selectedOption: sortingType,
                onSelected: (value) {
                  setState(() {
                    sortingType = value;
                  }); // Update the widget
                }),
            OptionsTile(
                title: "Date range",
                subtitle: dateRange,
                options: const [
                  "All time",
                  "Last year",
                  "Last month",
                  "Last week",
                  "Last day/Last 3 days/Latest"
                  // aka last 3 days or latest on some websites
                ],
                selectedOption: dateRange,
                onSelected: (value) {
                  setState(() {
                    dateRange = value;
                  }); // Update the widget
                }),
            ListTile(
                title: const Text("Categories"),
                subtitle: const Text("Categories to be included/excluded"),
                onTap: () {
                  showToast("Categories are not yet implemented", context);
                }),
            ListTile(
                title: const Text("Keywords"),
                subtitle: const Text("Keywords to be included/excluded"),
                onTap: () {
                  showToast("Keywords are not yet implemented", context);
                }),
            Padding(
                padding: const EdgeInsets.only(left: 16, right: 20),
                child: Column(children: [
                  Row(
                      mainAxisSize: MainAxisSize.max,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const SizedBox(width: 80, child: Text("Quality:")),
                        Expanded(
                            child: RangeSlider(
                          min: 0,
                          max: 8,
                          divisions: 8,
                          labels: RangeLabels(
                            // display actual resolutions, not the slider values
                            "${qualities[minQualityIndex.toInt()]}p",
                            "${qualities[maxQualityIndex.toInt()]}p",
                          ),
                          values: RangeValues(minQualityIndex, maxQualityIndex),
                          onChanged: (values) {
                            setState(() {
                              minQualityIndex = values.start;
                              maxQualityIndex = values.end;
                            });
                          },
                        ))
                      ]),
                  Row(
                      mainAxisSize: MainAxisSize.max,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const SizedBox(width: 80, child: Text("Duration:")),
                        Expanded(
                            child: RangeSlider(
                          min: 0,
                          max: 5,
                          divisions: 5,
                          labels: RangeLabels(
                            // display actual resolutions, not the slider values
                            // .toStringAsFixed(0) removes the .0 at the end
                            "${(durationsInSeconds[minDurationIndex.toInt()] / 60).toStringAsFixed(0)} min",
                            maxDurationIndex <= 4
                                ? "${(durationsInSeconds[maxDurationIndex.toInt()] / 60).toStringAsFixed(0)} min"
                                : "60+ min",
                          ),
                          values:
                              RangeValues(minDurationIndex, maxDurationIndex),
                          onChanged: (values) {
                            setState(() {
                              minDurationIndex = values.start;
                              maxDurationIndex = values.end;
                            });
                          },
                        ))
                      ]),
                  Row(
                      mainAxisSize: MainAxisSize.max,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const SizedBox(width: 80, child: Text("FPS:")),
                        Expanded(
                            child: RangeSlider(
                          min: 0,
                          max: 60,
                          divisions: 2,
                          labels: RangeLabels(
                            // display actual resolutions, not the slider values
                            minFps == 0 ? "0/unknown fps" : "$minFps fps",
                            maxFps == 60 ? "60+ fps" : "$maxFps fps",
                          ),
                          values: RangeValues(minFps, maxFps),
                          onChanged: (values) {
                            setState(() {
                              minFps = values.start;
                              maxFps = values.end;
                            });
                          },
                        ))
                      ]),
                  OptionsSwitch(
                      title: "Virtual reality",
                      subTitle: "Include virtual reality videos",
                      reduceBorders: true,
                      nonInteractive: true,
                      switchState: false,
                      onToggled: (value) {
                        showToast("VR is not yet implemented", context);
                        //setState(() => virtualReality = false);
                      }),
                  OptionsSwitch(
                      title: "Reverse order",
                      subTitle: "Display results in reverse order",
                      reduceBorders: true,
                      nonInteractive: true,
                      switchState: false,
                      onToggled: (value) {
                        showToast(
                            "Reverse search is not yet implemented", context);
                        //setState(() => reverseOrder = false);
                      })
                ])),
          ]),
        )));
  }
}
