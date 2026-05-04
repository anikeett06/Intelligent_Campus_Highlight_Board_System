import 'package:flutter/material.dart';

/// Root [MaterialApp] must set `scaffoldMessengerKey: rootScaffoldMessengerKey`.
final GlobalKey<ScaffoldMessengerState> rootScaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

/// Floating snackbar for dashboard / events / clubs / lost-item style alerts.
void showCampusNotificationToast(
  String title,
  String body, {
  String? category,
  VoidCallback? onOpen,
}) {
  final messenger = rootScaffoldMessengerKey.currentState;
  if (messenger == null) return;
  final ctx = rootScaffoldMessengerKey.currentContext;
  final muted = ctx != null ? Theme.of(ctx).colorScheme.onSurfaceVariant : const Color(0xFF666666);
  final trimmed = body.trim();
  final short = trimmed.length > 180 ? "${trimmed.substring(0, 177)}..." : trimmed;
  final cat = category?.trim();
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          if (cat != null && cat.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2, bottom: 2),
              child: Text(cat, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: muted)),
            ),
          if (short.isNotEmpty) Text(short),
        ],
      ),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 5),
      action: onOpen != null ? SnackBarAction(label: "Open", onPressed: onOpen) : null,
    ),
  );
}

/// Short floating feedback after saves, deletes, and other mutations (clear success vs error styling).
void showCampusOperationSnackBar(BuildContext context, String message, {bool isError = false}) {
  final cs = Theme.of(context).colorScheme;
  ScaffoldMessenger.of(context).hideCurrentSnackBar();
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        message,
        style: TextStyle(color: isError ? cs.onError : cs.onInverseSurface),
      ),
      behavior: SnackBarBehavior.floating,
      duration: Duration(seconds: isError ? 5 : 3),
      backgroundColor: isError ? cs.error : cs.inverseSurface,
    ),
  );
}
