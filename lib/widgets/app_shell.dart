import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:studentboard/providers/app_state.dart';
import 'package:studentboard/widgets/campus_board_logo.dart';

class AppShell extends StatelessWidget {
  const AppShell({
    super.key,
    required this.title,
    required this.body,
    this.appBarActions,
    this.floatingActionButton,
    this.floatingActionButtonLocation,
  });
  final String title;
  final Widget body;
  final List<Widget>? appBarActions;
  final Widget? floatingActionButton;
  final FloatingActionButtonLocation? floatingActionButtonLocation;

  @override
  Widget build(BuildContext context) {
    final currentPath = GoRouterState.of(context).uri.path;
    final selectedIndex = _shellIndexForPath(currentPath);
    final app = context.watch<AppState>();
    final cs = Theme.of(context).colorScheme;
    final showModeToggle =
        currentPath == "/dashboard" || currentPath.startsWith("/academic");
    final modeActions = <Widget>[];
    if (showModeToggle) {
      modeActions.add(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Tooltip(
            message: app.dashboardAcademicMode
                ? "Academic: timetables, exams, notices"
                : "Non-academic: highlights, clubs, campus life",
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  app.dashboardAcademicMode ? "Academic" : "Non-academic",
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: cs.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 6),
                Switch(
                  value: app.dashboardAcademicMode,
                  onChanged: (v) => app.setDashboardAcademicMode(v),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ],
            ),
          ),
        ),
      );
    }
    if (appBarActions != null) {
      modeActions.addAll(appBarActions!);
    }
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 12,
        title: const CampusBoardAppBarTitle(),
        actions: modeActions,
      ),
      floatingActionButton: floatingActionButton,
      floatingActionButtonLocation: floatingActionButtonLocation,
      body: SafeArea(child: body),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Material(
          elevation: 4,
          shadowColor: cs.shadow.withValues(alpha: 0.12),
          color: cs.surface,
          borderRadius: BorderRadius.circular(22),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: cs.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
            child: NavigationBar(
              height: 68,
              selectedIndex: selectedIndex,
              backgroundColor: Colors.transparent,
              elevation: 0,
              surfaceTintColor: Colors.transparent,
              labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
              onDestinationSelected: (index) {
                if (index == 4) {
                  _openMenuSheet(context);
                  return;
                }
                final path = _pathForShellIndex(index);
                if (path == currentPath) {
                  return;
                }
                context.go(path);
              },
              destinations: [
                const NavigationDestination(
                  icon: Icon(Icons.dashboard_outlined),
                  selectedIcon: Icon(Icons.dashboard),
                  label: "Dashboard",
                ),
                const NavigationDestination(
                  icon: Icon(Icons.event_note_outlined),
                  selectedIcon: Icon(Icons.event_note),
                  label: "Event",
                ),
                const NavigationDestination(
                  icon: Icon(Icons.groups_outlined),
                  selectedIcon: Icon(Icons.groups),
                  label: "Clubs & community",
                ),
                NavigationDestination(
                  icon: _bellWithDot(Icons.notifications_none, showDot: app.unreadNotificationCount > 0),
                  selectedIcon: _bellWithDot(Icons.notifications, showDot: app.unreadNotificationCount > 0),
                  label: "Notification",
                ),
                const NavigationDestination(
                  icon: Icon(Icons.person_outline),
                  selectedIcon: Icon(Icons.person),
                  label: "Menu",
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static Widget _bellWithDot(IconData icon, {required bool showDot}) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(icon),
        if (showDot)
          Positioned(
            right: -1,
            top: -1,
            child: Container(
              width: 9,
              height: 9,
              decoration: const BoxDecoration(
                color: Color(0xFFE53935),
                shape: BoxShape.circle,
              ),
            ),
          ),
      ],
    );
  }

  int _shellIndexForPath(String path) {
    if (path.startsWith("/academic")) return 0;
    if (path.startsWith("/events")) return 1;
    if (path.startsWith("/communities")) return 2;
    if (path.startsWith("/notifications")) return 3;
    if (path.startsWith("/profile") || path.startsWith("/lost-found")) return 4;
    return 0;
  }

  String _pathForShellIndex(int index) {
    switch (index) {
      case 1:
        return "/events";
      case 2:
        return "/communities";
      case 3:
        return "/notifications";
      case 4:
        return "/profile";
      case 0:
      default:
        return "/dashboard";
    }
  }

  void _openMenuSheet(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: Icon(
                    Icons.account_circle_outlined,
                    color: cs.primary,
                  ),
                  title: const Text("Profile"),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    context.go("/profile");
                  },
                ),
                ListTile(
                  leading: Icon(
                    Icons.upload_file_outlined,
                    color: cs.secondary,
                  ),
                  title: const Text("Upload lost item"),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    context.go("/lost-found");
                  },
                ),
                ListTile(
                  leading: Icon(
                    Icons.settings_outlined,
                    color: cs.onSurfaceVariant,
                  ),
                  title: const Text("Settings"),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text("Settings screen will be added next."),
                      ),
                    );
                  },
                ),
                ListTile(
                  leading: Icon(Icons.logout, color: cs.error),
                  title: Text(
                    "Logout",
                    style: TextStyle(
                      color: cs.error,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  onTap: () async {
                    Navigator.of(sheetContext).pop();
                    await context.read<AppState>().logout();
                    if (context.mounted) {
                      context.go("/");
                    }
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
