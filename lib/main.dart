  import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:studentboard/app/app_scroll_behavior.dart';
import 'package:studentboard/app/app_theme.dart';
import 'package:studentboard/app_router.dart';
import 'package:studentboard/providers/app_state.dart';
import 'package:studentboard/services/api_service.dart';
import 'package:studentboard/services/in_app_notification_toast.dart';
import 'package:studentboard/services/local_notifications.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp();
  } catch (_) {}
  await LocalNotifications.init();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppState(ApiService())),
      ],
      child: const CampusBoardApp(),
    ),
  );
}

class CampusBoardApp extends StatefulWidget {
  const CampusBoardApp({super.key});

  @override
  State<CampusBoardApp> createState() => _CampusBoardAppState();
}

class _CampusBoardAppState extends State<CampusBoardApp> {
  late final GoRouter _router;
  static bool _fcmForegroundWired = false;

  @override
  void initState() {
    super.initState();
    _router = createAppRouter();
    registerAppGoRouter(_router);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _fcmForegroundWired) return;
      _fcmForegroundWired = true;
      final app = Provider.of<AppState>(context, listen: false);
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        final title = message.notification?.title ?? "Campus Board";
        final body = message.notification?.body ?? "";
        final cat = message.data["notification_type"]?.toString();
        showCampusNotificationToast(
          title,
          body,
          category: cat?.isNotEmpty == true ? cat : null,
          onOpen: () => appNavigateTo("/notifications"),
        );
        // Also show a real system notification while the app is open.
        unawaited(LocalNotifications.show(title: title, body: body));
        unawaited(app.refreshNotifications(emitPop: false));
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: "Campus Board",
      theme: buildAppTheme(),
      scrollBehavior: const CampusScrollBehavior(),
      scaffoldMessengerKey: rootScaffoldMessengerKey,
      routerConfig: _router,
    );
  }
}
