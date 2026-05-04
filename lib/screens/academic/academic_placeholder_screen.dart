import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:studentboard/providers/app_state.dart';
import 'package:studentboard/widgets/app_shell.dart';
import 'package:studentboard/widgets/campus_refresh.dart';

/// Placeholder until registrar / LMS integrations exist.
class AcademicPlaceholderScreen extends StatelessWidget {
  const AcademicPlaceholderScreen({
    super.key,
    required this.title,
    required this.body,
    this.actionLabel,
    this.actionPath,
  });

  final String title;
  final String body;
  final String? actionLabel;
  final String? actionPath;

  @override
  Widget build(BuildContext context) {
    return AppShell(
      title: title,
      body: Consumer<AppState>(
        builder: (context, app, _) {
          return CampusRefreshIndicator(
            onRefresh: app.loadAll,
            child: ListView(
              physics: kCampusPullToRefreshPhysics,
              padding: const EdgeInsets.all(16),
              children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(body, style: Theme.of(context).textTheme.bodyLarge),
                  if (actionLabel != null && actionPath != null) ...[
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () => context.push(actionPath!),
                      child: Text(actionLabel!),
                    ),
                  ],
                ],
              ),
            ),
          ),
              ],
            ),
          );
        },
      ),
    );
  }
}
