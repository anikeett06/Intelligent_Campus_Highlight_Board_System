import 'package:go_router/go_router.dart';

import 'package:studentboard/screens/admin/admin_campus_users_screen.dart';
import 'package:studentboard/screens/admin/admin_event_editor_screen.dart';
import 'package:studentboard/screens/admin/admin_event_registrations_screen.dart';
import 'package:studentboard/screens/admin/admin_student_profile_screen.dart';
import 'package:studentboard/screens/academic/academic_placeholder_screen.dart';
import 'package:studentboard/screens/auth/login_screen.dart';
import 'package:studentboard/screens/clubs/communities_screen.dart';
import 'package:studentboard/screens/clubs/community_detail_screen.dart';
import 'package:studentboard/screens/dashboard/dashboard_screen.dart';
import 'package:studentboard/screens/events/event_detail_screen.dart';
import 'package:studentboard/screens/events/event_registration_screen.dart';
import 'package:studentboard/screens/events/events_screen.dart';
import 'package:studentboard/screens/menu/lost_found_screen.dart';
import 'package:studentboard/screens/menu/profile_screen.dart';
import 'package:studentboard/screens/notifications/notifications_screen.dart';

GoRouter? _registeredRouter;

void registerAppGoRouter(GoRouter router) {
  _registeredRouter = router;
}

void appNavigateTo(String location) {
  _registeredRouter?.go(location);
}

GoRouter createAppRouter() {
  return GoRouter(
    routes: [
      GoRoute(path: "/", builder: (context, state) => const LoginScreen()),
      GoRoute(path: "/dashboard", builder: (context, state) => const DashboardScreen()),
      GoRoute(path: "/events", builder: (context, state) => const EventsScreen()),
      GoRoute(
        path: "/events/:eventId",
        builder: (context, state) {
          final raw = state.pathParameters["eventId"];
          final id = int.tryParse(raw ?? "") ?? 0;
          return EventDetailScreen(eventId: id);
        },
      ),
      GoRoute(
        path: "/events/:eventId/register",
        builder: (context, state) {
          final raw = state.pathParameters["eventId"];
          final id = int.tryParse(raw ?? "") ?? 0;
          return EventRegistrationScreen(eventId: id);
        },
      ),
      GoRoute(path: "/admin/events/new", builder: (context, state) => const AdminEventEditorScreen()),
      GoRoute(
        path: "/admin/events/:eventId/edit",
        builder: (context, state) {
          final raw = state.pathParameters["eventId"];
          final id = int.tryParse(raw ?? "") ?? 0;
          return AdminEventEditorScreen(eventId: id);
        },
      ),
      GoRoute(path: "/communities", builder: (context, state) => const CommunitiesScreen()),
      GoRoute(
        path: "/communities/:communityId",
        builder: (context, state) {
          final id = int.tryParse(state.pathParameters["communityId"] ?? "") ?? 0;
          return CommunityDetailScreen(communityId: id);
        },
      ),
      GoRoute(
        path: "/admin/events/:eventId/registrations",
        builder: (context, state) {
          final id = int.tryParse(state.pathParameters["eventId"] ?? "") ?? 0;
          return AdminEventRegistrationsScreen(eventId: id);
        },
      ),
      GoRoute(path: "/admin/campus-users", builder: (context, state) => const AdminCampusUsersScreen()),
      GoRoute(
        path: "/admin/users/:userId",
        builder: (context, state) {
          final id = int.tryParse(state.pathParameters["userId"] ?? "") ?? 0;
          return AdminStudentProfileScreen(userId: id);
        },
      ),
      GoRoute(
        path: "/academic/timetable",
        builder: (context, state) => const AcademicPlaceholderScreen(
          title: "Time table",
          body:
              "Your class timetable will appear here once connected to your registrar or LMS. Use campus notices for interim schedule changes.",
        ),
      ),
      GoRoute(
        path: "/academic/exam-schedule",
        builder: (context, state) => const AcademicPlaceholderScreen(
          title: "Exam schedule",
          body:
              "Official exam windows and seating are usually published as academic events and notices. Open the list below to see everything currently posted.",
          actionLabel: "Browse academic & exam events",
          actionPath: "/events",
        ),
      ),
      GoRoute(path: "/lost-found", builder: (context, state) => const LostFoundScreen()),
      GoRoute(path: "/notifications", builder: (context, state) => const NotificationsScreen()),
      GoRoute(path: "/profile", builder: (context, state) => const ProfileScreen()),
    ],
  );
}
