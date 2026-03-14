import 'package:flutter/material.dart';
import 'package:page_transition/page_transition.dart';

import '/ui/screens/settings/settings_plugins.dart';
import 'onboarding_welcome.dart';

class DisclaimersScreen extends StatelessWidget {
  const DisclaimersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
            title: const Center(child: Text("Disclaimers")),
            // Don't show back button
            automaticallyImplyLeading: false),
        body: SafeArea(
            child: Padding(
                padding: EdgeInsets.all(20),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                          width: double.infinity,
                          // Make the box slightly bigger than the Text
                          padding: EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surfaceVariant,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                              "This app is developed and maintained by a "
                              "single developer and is provided \"as is\" without "
                              "any warranties, express or implied. The developer "
                              "assumes no responsibility for any issues, damages, "
                              "or losses resulting from its use.",
                              style: Theme.of(context).textTheme.bodyLarge)),
                      // this is padding around the entire widget
                      Padding(
                          padding: const EdgeInsets.only(top: 20),
                          child: Container(
                              width: double.infinity,
                              // Make the box slightly bigger than the Text
                              padding: EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Theme.of(context)
                                    .colorScheme
                                    .surfaceVariant,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                  "This app is not affiliated with, endorsed "
                                  "by, or connected to any external platforms, whether "
                                  "accessed through built-in plugins or user-installed"
                                  " ones.",
                                  style:
                                      Theme.of(context).textTheme.bodyLarge))),
                      // this is padding around the entire widget
                      Padding(
                          padding: const EdgeInsets.only(top: 20),
                          child: Container(
                              width: double.infinity,
                              // Make the box slightly bigger than the Text
                              padding: EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Theme.of(context)
                                    .colorScheme
                                    .surfaceVariant,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                  "This app aggregates content from external providers, "
                                  "some of which may have Terms of Service (TOS) "
                                  "that prohibit scraping or automated access. By "
                                  "default, nothing is accessed without user consent."
                                  " Users are responsible for reviewing the TOS of "
                                  "each website before enabling the corresponding "
                                  "plugin, as these terms vary by country and "
                                  "jurisdiction. It is the user's responsibility to "
                                  "ensure compliance with the relevant laws and TOS.",
                                  style:
                                      Theme.of(context).textTheme.bodyLarge))),
                      Spacer(),
                      Row(children: [
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
                                        childCurrent: this,
                                        child: WelcomeScreen())),
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
                                onPressed: () => Navigator.push(
                                    context,
                                    PageTransition(
                                        type: PageTransitionType
                                            .rightToLeftJoined,
                                        childCurrent: this,
                                        child: PluginsScreen(
                                            partOfOnboarding: true))),
                                child: Text("Confirm",
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onPrimary))))
                      ])
                    ]))));
  }
}
