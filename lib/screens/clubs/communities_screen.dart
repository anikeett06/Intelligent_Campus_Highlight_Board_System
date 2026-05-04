import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:studentboard/providers/app_state.dart';
import 'package:studentboard/widgets/app_shell.dart';
import 'package:studentboard/widgets/campus_clubs_section.dart';
import 'package:studentboard/widgets/campus_refresh.dart';

class CommunitiesScreen extends StatelessWidget {
  const CommunitiesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return AppShell(
      title: "Communities & Clubs",
      body: CampusRefreshIndicator(
        onRefresh: app.loadAll,
        child: ListView(
          physics: kCampusPullToRefreshPhysics,
          padding: const EdgeInsets.all(12),
          children: [
            CampusClubsSection(showTopDivider: false),
          ],
        ),
      ),
    );
  }
}
