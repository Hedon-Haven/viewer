import 'package:dynamic_app_icon_flutter/dynamic_app_icon.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:page_transition/page_transition.dart';

import '/ui/screens/settings/settings_plugins.dart';
import '/ui/utils/toast_notification.dart';
import '/ui/widgets/alert_dialog.dart';
import '/utils/global_vars.dart';

class LauncherAppearance extends StatefulWidget {
  final bool partOfOnboarding;

  const LauncherAppearance({super.key, this.partOfOnboarding = false});

  @override
  State<LauncherAppearance> createState() => _LauncherAppearanceScreenState();
}

class _LauncherAppearanceScreenState extends State<LauncherAppearance> {
  // the actual default icon is called "stock" everywhere except here
  final List<String> list = ["default", "fake_settings", "reminders"];

  void handleOptionChange(String? value) async {
    if (value != null) {
      // show dialog explaining the option if needed
      if (value != "Hedon Haven") {
        await showDialog(
            context: context,
            builder: (BuildContext context) {
              return ThemedDialog(
                primaryText: "Ok",
                onPrimary: Navigator.of(context).pop,
                content: Text(
                    value == "Reminders"
                        ? "Create a new reminder called \"Stop concealing\" to exit reminders mode."
                        : "Press and hold \"Show signal strength in advanced mode\" for 5 seconds to exit GSM Settings mode",
                    style: Theme.of(context).textTheme.titleMedium),
              );
            });
      }
      setState(() {});
      showDialog(
          context: context,
          builder: (BuildContext context) {
            // running setupAppIcon will force the app to quit. Ask user to confirm first
            return ThemedDialog(
                content: Text(
                    "App will now close and can be found again as \"$value\" in the launcher.",
                    style: Theme.of(context).textTheme.titleMedium),
                primaryText: widget.partOfOnboarding
                    ? "Complete onboarding"
                    : "Close app",
                onPrimary: () async {
                  if (kDebugMode || kProfileMode) {
                    // FIXME: Report bug upstream or fix myself
                    showToast(
                        "Doesn't work in Debug or Profile versions", context);
                    Navigator.of(context).pop();
                    return;
                  }
                  if (widget.partOfOnboarding) {
                    logger.i("Onboarding completed");
                    await sharedStorage.setBool(
                        "general_onboarding_completed", true);
                  }
                  // close popup
                  Navigator.pop(context);
                  sharedStorage.setString(
                      "appearance_launcher_appearance", value);
                  switch (value) {
                    case "Hedon Haven":
                      logger.i("Changing to stock icon");
                      DynamicAppIcon.setupAppIcon(
                          iconName: "default", iconList: list);
                      break;
                    case "GSM Settings":
                      logger.i("Changing to GSM settings icon");
                      DynamicAppIcon.setupAppIcon(
                          iconName: "fake_settings", iconList: list);
                      break;
                    case "Reminders":
                      logger.i("Changing to reminders icon");
                      DynamicAppIcon.setupAppIcon(
                          iconName: "reminders", iconList: list);
                      break;
                  }
                },
                secondaryText: "Cancel",
                onSecondary: Navigator.of(context).pop);
          });
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          // Hide back button in onboarding
          automaticallyImplyLeading: !widget.partOfOnboarding,
          iconTheme:
              IconThemeData(color: Theme.of(context).colorScheme.primary),
          title: widget.partOfOnboarding
              ? Center(child: Text("Launcher appearance"))
              : const Text("Launcher appearance"),
        ),
        body: SafeArea(
            child: Column(children: [
          SingleChildScrollView(
              child: FutureBuilder<String?>(
                  future:
                      sharedStorage.getString("appearance_launcher_appearance"),
                  builder: (context, snapshot) {
                    // Don't show anything until the future is done
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const SizedBox();
                    }
                    return Padding(
                        padding: const EdgeInsets.all(8),
                        child: Column(
                          children: [
                            ListTile(
                                title: const Text("Hedon Haven"),
                                leading: CircleAvatar(
                                    backgroundColor: Colors.white,
                                    child: ClipOval(
                                      child: Padding(
                                        padding:
                                            const EdgeInsets.all(20 * 0.20),
                                        child: Image.asset(
                                            "assets/launcher-icon/stock.png"),
                                      ),
                                    )),
                                onTap: () => handleOptionChange("Hedon Haven"),
                                trailing: Radio(
                                  value: "Hedon Haven",
                                  groupValue: snapshot.data!,
                                  onChanged: handleOptionChange,
                                )),
                            const SizedBox(height: 10),
                            ListTile(
                                title: const Text("GSM Settings"),
                                leading: CircleAvatar(
                                    backgroundColor: Colors.white,
                                    child: ClipOval(
                                      child: Padding(
                                        padding:
                                            const EdgeInsets.all(20 * 0.20),
                                        child: Image.asset(
                                            "assets/launcher-icon/fake_settings.png"),
                                      ),
                                    )),
                                onTap: () => handleOptionChange("GSM Settings"),
                                trailing: Radio(
                                  value: "GSM Settings",
                                  groupValue: snapshot.data!,
                                  onChanged: handleOptionChange,
                                )),
                            const SizedBox(height: 10),
                            ListTile(
                              title: const Text("Reminders"),
                              leading: CircleAvatar(
                                backgroundColor:
                                    const Color.fromARGB(255, 51, 181, 229),
                                child: ClipOval(
                                  child: Padding(
                                    padding: const EdgeInsets.all(20 * 0.20),
                                    child: Image.asset(
                                        "assets/launcher-icon/reminders.png"),
                                  ),
                                ),
                              ),
                              onTap: () => handleOptionChange("Reminders"),
                              trailing: Radio(
                                value: "Reminders",
                                groupValue: snapshot.data!,
                                onChanged: handleOptionChange,
                              ),
                            )
                          ],
                        ));
                  })),
          if (widget.partOfOnboarding) ...[
            Spacer(),
            Padding(
                padding: EdgeInsets.all(12),
                child: Row(children: [
                  Align(
                      alignment: Alignment.bottomLeft,
                      child: ElevatedButton(
                          style: TextButton.styleFrom(
                              backgroundColor:
                                  Theme.of(context).colorScheme.surfaceVariant),
                          onPressed: () => Navigator.push(
                              context,
                              PageTransition(
                                  type: PageTransitionType.leftToRightJoined,
                                  childCurrent: widget,
                                  child:
                                      PluginsScreen(partOfOnboarding: true))),
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
                              backgroundColor:
                                  Theme.of(context).colorScheme.primary),
                          onPressed: () async {
                            logger.i("Onboarding completed");
                            await sharedStorage.setBool(
                                "general_onboarding_completed", true);
                            // Force redraw of main screen to exit onboarding
                            globalSetState();
                            // Go back to main screen
                            await Navigator.pushNamedAndRemoveUntil(
                                context, "/", (route) => false);
                          },
                          child: Text("Finish onboarding",
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onPrimary))))
                ]))
          ]
        ])));
  }
}
