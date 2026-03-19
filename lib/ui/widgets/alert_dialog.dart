import 'package:flutter/material.dart';

class ThemedDialog extends StatefulWidget {
  final String? title;
  final String? primaryText;
  final String? secondaryText;
  final void Function()? onPrimary;
  final void Function()? onSecondary;
  final Widget? content;

  const ThemedDialog({
    super.key,
    this.content,
    this.primaryText,
    this.secondaryText,
    this.onPrimary,
    this.onSecondary,
    this.title,
  });

  @override
  State<ThemedDialog> createState() => _ThemedAlertDialogState();
}

class _ThemedAlertDialogState extends State<ThemedDialog> {
  /// Make sure to wrap this in a showDialog if not acting as a widget
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Theme.of(context).colorScheme.surfaceVariant,
      title: widget.title == null ? null : Center(child: Text(widget.title!)),
      actionsAlignment: MainAxisAlignment.spaceEvenly,
      actionsOverflowAlignment: OverflowBarAlignment.center,
      actions: <Widget>[
        if (widget.secondaryText != null && widget.onSecondary != null) ...[
          ElevatedButton(
              style: TextButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.surface),
              child: Text(widget.secondaryText!,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurface)),
              onPressed: () => widget.onSecondary!())
        ],
        if (widget.primaryText != null && widget.onPrimary != null) ...[
          ElevatedButton(
            style: TextButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary),
            child: Text(widget.primaryText!,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(color: Theme.of(context).colorScheme.onPrimary)),
            onPressed: () => widget.onPrimary!(),
          )
        ]
      ],
      content: widget.content,
    );
  }
}
