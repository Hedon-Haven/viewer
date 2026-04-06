import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '/ui/utils/toast_notification.dart';

class OptionsSwitch extends StatefulWidget {
  final String title;
  late String? subTitle;
  late bool switchState;
  late bool reduceBorders;
  late bool reduceHorizontalBordersOnly;

  /// Make toggle visual only
  late bool nonInteractive;
  late bool disableLongPressAction;
  late Widget? leadingWidget;
  late Widget? trailingWidget;
  final void Function(bool) onToggled;

  OptionsSwitch(
      {super.key,
      required this.title,
      required this.switchState,
      required this.onToggled,
      bool? reduceBorders,
      bool? reduceHorizontalBordersOnly,
      bool? nonInteractive,
      bool? disableLongPressAction,
      // can be just null
      this.leadingWidget,
      this.trailingWidget,
      this.subTitle})
      : reduceBorders = reduceBorders ?? false,
        reduceHorizontalBordersOnly = reduceHorizontalBordersOnly ?? false,
        nonInteractive = nonInteractive ?? false,
        disableLongPressAction = disableLongPressAction ?? false;

  @override
  State<OptionsSwitch> createState() => _OptionsSwitchWidgetState();
}

class _OptionsSwitchWidgetState extends State<OptionsSwitch> {
  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
            child: MouseRegion(
                // FIXME: Cursor doesn't change on desktop
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onLongPress: widget.disableLongPressAction
                      ? null
                      : () {
                          if (widget.subTitle != null) {
                            Clipboard.setData(
                                ClipboardData(text: widget.subTitle!));
                            // TODO: Add vibration feedback for mobile
                            showToast("Copied subtext to clipboard", context);
                          } else {
                            Clipboard.setData(
                                ClipboardData(text: widget.title));
                            // TODO: Add vibration feedback for mobile
                            showToast("Copied text to clipboard", context);
                          }
                        },
                  child: ListTile(
                    leading: widget.leadingWidget,
                    trailing: widget.trailingWidget,
                    title: Text(widget.title),
                    subtitle: widget.subTitle != null
                        ? Text(widget.subTitle!,
                            maxLines: 1, overflow: TextOverflow.ellipsis)
                        : null,
                    visualDensity: widget.reduceBorders
                        ? const VisualDensity(horizontal: 0, vertical: -4)
                        : null,
                    contentPadding: widget.reduceBorders ||
                            widget.reduceHorizontalBordersOnly
                        ? EdgeInsets.zero
                        : widget.leadingWidget != null
                            // remove right inset and keep only the default 16px left inset
                            ? EdgeInsets.only(left: 16)
                            : null,
                  ),
                ))),
        Switch(
          value: widget.switchState,
          // Set onChanged function to null if nonInteractive
          // This will also make the button grayed out
          onChanged: widget.nonInteractive
              ? null
              : (value) {
                  widget.onToggled(value);
                  // The user provided function completes after the setState below
                  // is called -> value is written to settings successfully,
                  // but widget is not updated visually
                  // -> Manually temporarily change switchState to the new value
                  setState(() {
                    widget.switchState = value;
                  });
                },
        ),
      ],
    );
  }
}
