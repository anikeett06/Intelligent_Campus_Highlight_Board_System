import 'package:flutter/material.dart';

/// Keeps scrolling and pull-to-refresh, but does not paint the thick Material 3
/// scrollbar track (common on desktop / web) so lists look like a native mobile app.
class CampusScrollBehavior extends MaterialScrollBehavior {
  const CampusScrollBehavior();

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return child;
  }
}
