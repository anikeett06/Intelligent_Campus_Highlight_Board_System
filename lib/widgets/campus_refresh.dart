import 'package:flutter/material.dart';

/// Overscroll bounce so pull-to-refresh works like Instagram/Twitter even when the list
/// is shorter than the screen (plain [ListView] physics would not overscroll).
const ScrollPhysics kCampusPullToRefreshPhysics = AlwaysScrollableScrollPhysics(
  parent: BouncingScrollPhysics(),
);

/// Stronger, themed pull-to-refresh around scrollable [child] (must be scrollable).
class CampusRefreshIndicator extends StatelessWidget {
  const CampusRefreshIndicator({
    super.key,
    required this.onRefresh,
    required this.child,
  });

  final Future<void> Function() onRefresh;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return RefreshIndicator(
      onRefresh: onRefresh,
      color: scheme.primary,
      backgroundColor: scheme.surfaceContainerHighest,
      strokeWidth: 3,
      displacement: 52,
      triggerMode: RefreshIndicatorTriggerMode.onEdge,
      child: child,
    );
  }
}
