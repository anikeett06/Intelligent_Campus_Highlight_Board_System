import 'dart:async';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/material.dart';

import 'package:studentboard/app_router.dart';
import 'package:studentboard/services/api_service.dart';
import 'package:studentboard/services/in_app_notification_toast.dart';
import 'package:studentboard/utils/api_user_message.dart';
import 'package:studentboard/utils/json_helpers.dart';

class AppState extends ChangeNotifier {
  AppState(this.api);
  final ApiService api;

  static String _dioUserMessage(DioException e) => mapDioToUserMessage(e);

  static String _anyUserMessage(Object e) => userMessageFromUnknown(e);

  String? accessToken;
  Map<String, dynamic>? profile;
  List<dynamic> events = [];
  Map<String, dynamic> dashboard = {};
  List<dynamic> communities = [];
  List<dynamic> myCommunities = [];
  /// Club IDs where this user is an appointed club manager (post/edit that club only).
  final Set<int> moderatingCommunityIds = {};
  /// Clubs the current student follows (for notifications + read access).
  List<dynamic> myFollowedCommunities = [];
  List<dynamic> polls = [];
  List<dynamic> lostFound = [];
  List<dynamic> notifications = [];
  final Set<int> _seenNotificationIds = {};
  Timer? _notificationPollTimer;
  bool _loadInProgress = false;

  /// True while [loadAll] is running (first paint or pull-to-refresh).
  bool get loadInProgress => _loadInProgress;

  int get unreadNotificationCount {
    var n = 0;
    for (final row in notifications) {
      if (row is! Map) continue;
      final r = row["is_read"];
      if (r == false || r == 0) {
        n++;
      }
    }
    return n;
  }
  List<dynamic> myRegistrations = [];
  Map<int, List<dynamic>> lostFoundComments = {};
  Map<String, dynamic> campusShortcuts = {};
  List<dynamic> academicNotices = [];

  bool get isAdmin => (profile?["role"]?.toString() ?? "student") == "admin";
  bool get isFaculty => (profile?["role"]?.toString() ?? "student") == "faculty";
  bool get isStudent => (profile?["role"]?.toString() ?? "student") == "student";
  /// Faculty: campus admin must enable before they can post academic dashboard content.
  bool get academicPostingAllowed => profile?["academic_posting_allowed"] == true;
  /// Student appointed to help run non-academic campus content (never the academic board).
  bool get isStudentAdmin => profile?["student_admin"] == true;

  /// Event editor, polls, broadcasts — not plain faculty until [academicPostingAllowed].
  bool get canManageEvents =>
      isAdmin || (isFaculty && academicPostingAllowed) || (isStudent && isStudentAdmin);

  /// Academic shortcut files on the dashboard — admin or granted faculty only.
  bool get canManageCampusShortcuts => isAdmin || (isFaculty && academicPostingAllowed);

  /// New clubs are non-academic — campus admin or student campus lead.
  bool get canCreateClubs => isAdmin || (isStudent && isStudentAdmin);

  /// Campus admin, or club manager for this specific community (not global faculty).
  bool canManageClubContent(int communityId) {
    if (communityId <= 0) return false;
    return isAdmin || moderatingCommunityIds.contains(communityId);
  }

  bool get moderatesAnyClub => moderatingCommunityIds.isNotEmpty;

  bool _itemIsAcademicBoard(Map<String, dynamic> item) {
    final s = item["dashboard_segment"]?.toString();
    if (s == "academic") return true;
    if (s == "non_academic") return false;
    final cat = item["category"]?.toString().toLowerCase() ?? "";
    return cat == "academic" || cat == "exam";
  }

  /// Campus admin: any activity. Faculty / student campus leads: only activities they created,
  /// and only on the board their role may manage (academic vs non-academic).
  bool canEditDashboardActivity(Map<String, dynamic> item) {
    if (isAdmin) return true;
    final createdBy = _createdByFromItem(item);
    final me = intFromJsonField(profile ?? {}, "id");
    if (createdBy == null || me == null || createdBy != me) {
      return false;
    }
    final acad = _itemIsAcademicBoard(item);
    if (isFaculty && academicPostingAllowed) return acad;
    if (isStudent && isStudentAdmin) return !acad;
    return false;
  }

  /// Dashboard FAB: admins always; granted faculty on Academic board; student leads on non-academic board.
  bool get canQuickAddDashboardActivity =>
      isAdmin ||
      (isFaculty && academicPostingAllowed && dashboardAcademicMode) ||
      (isStudent && isStudentAdmin && !dashboardAcademicMode);

  /// Staff tools for a given event (registrants, polls, etc.) — same scope as editing that row.
  bool canStaffManageThisEvent(Map<String, dynamic> item) {
    return canManageEvents && canEditDashboardActivity(item);
  }

  /// Creator of this dashboard row (from API).
  int? _createdByFromItem(Map<String, dynamic> item) => intFromJsonField(item, "created_by");

  /// Same rules as [canEditDashboardActivity]: campus admin or the creator with a staff role.
  bool canDeleteDashboardActivity(Map<String, dynamic> item) {
    return canManageEvents && canEditDashboardActivity(item);
  }

  /// Dashboard only: non-academic (highlights, clubs) vs academic (timetable, notices, etc.).
  bool dashboardAcademicMode = false;

  void setDashboardAcademicMode(bool value) {
    if (dashboardAcademicMode == value) return;
    dashboardAcademicMode = value;
    notifyListeners();
  }

  Future<void> bootstrap() async {
    await api.loadStoredBaseUrl();
    accessToken ??= await api.token();
    if (accessToken != null) {
      await loadAll();
      await _setupFcm();
      _startNotificationPolling();
    }
    notifyListeners();
  }

  Future<void> login(String email, String password) async {
    final data = await api.login(email, password);
    accessToken = data["access_token"] as String;
    await api.saveToken(accessToken!);
    await loadAll();
    await _setupFcm();
    _startNotificationPolling();
    notifyListeners();
  }

  Future<void> register(String name, String email, String password, {String role = "student"}) async {
    await api.register(name, email, password, role: role);
  }

  /// Admin: update another campus member (role, active flag, display name).
  Future<String?> adminUpdateCampusMember({
    required int userId,
    String? fullName,
    String? role,
    bool? isActive,
    bool? academicPostingAllowed,
    bool? studentAdmin,
  }) async {
    if (accessToken == null) return "Not signed in.";
    if (!isAdmin) return "Only administrators can update member accounts.";
    try {
      await api.adminUpdateUser(
        accessToken!,
        userId,
        fullName: fullName,
        role: role,
        isActive: isActive,
        academicPostingAllowed: academicPostingAllowed,
        studentAdmin: studentAdmin,
      );
      await loadAll();
      return null;
    } on DioException catch (e) {
      return _dioUserMessage(e);
    } catch (e) {
      return _anyUserMessage(e);
    }
  }

  /// Campus admin: grant or revoke per-club manager (student/faculty can post for that club only).
  Future<String?> adminSetUserClubModerator({
    required int userId,
    required int communityId,
    required bool isModerator,
  }) async {
    if (accessToken == null) return "Not signed in.";
    if (!isAdmin) return "Only administrators can assign club managers.";
    try {
      await api.adminSetClubModerator(accessToken!, userId, communityId: communityId, isModerator: isModerator);
      await loadAll();
      return null;
    } on DioException catch (e) {
      return _dioUserMessage(e);
    } catch (e) {
      return _anyUserMessage(e);
    }
  }

  Future<void> logout() async {
    accessToken = null;
    profile = null;
    events = [];
    dashboard = {};
    communities = [];
    myCommunities = [];
    moderatingCommunityIds.clear();
    myFollowedCommunities = [];
    polls = [];
    lostFound = [];
    notifications = [];
    myRegistrations = [];
    lostFoundComments = {};
    campusShortcuts = {};
    academicNotices = [];
    dashboardAcademicMode = false;
    _notificationPollTimer?.cancel();
    _notificationPollTimer = null;
    _seenNotificationIds.clear();
    await api.clearToken();
    notifyListeners();
  }

  /// Reloads profile, events, dashboard, clubs, polls, notifications, etc. Always calls [notifyListeners]
  /// so every screen using [context.watch] updates without a manual pull-to-refresh.
  ///
  /// [toastNewNotifications]: when true (e.g. background poll), show in-app toasts for newly arrived notifications.
  Future<void> loadAll({bool toastNewNotifications = false}) async {
    if (accessToken == null) return;
    _loadInProgress = true;
    notifyListeners();
    try {
      final token = accessToken!;
      profile = await api.me(token);

      final core = await Future.wait<List<dynamic>>([
        api.getEvents(token),
        api.getCommunities(token),
        api.getMyCommunities(token),
      ]);
      events = core[0];
      communities = core[1];
      myCommunities = core[2];

      final dashPollsLostReg = await Future.wait<dynamic>([
        api.getDashboard(token),
        api.getPolls(token),
        api.getLostFound(token),
        api.getMyRegistrations(token),
      ]);
      dashboard = Map<String, dynamic>.from(dashPollsLostReg[0] as Map);
      polls = dashPollsLostReg[1] as List<dynamic>;
      lostFound = dashPollsLostReg[2] as List<dynamic>;
      myRegistrations = dashPollsLostReg[3] as List<dynamic>;

      try {
        final modRaw = await api.getMyModeratingCommunities(token);
        moderatingCommunityIds.clear();
        for (final row in modRaw) {
          if (row is! Map) continue;
          final id = intFromJsonField(Map<String, dynamic>.from(row.map((k, v) => MapEntry(k.toString(), v))), "id");
          if (id != null) moderatingCommunityIds.add(id);
        }
      } catch (_) {
        moderatingCommunityIds.clear();
      }
      try {
        myFollowedCommunities = isStudent ? await api.getFollowingCommunities(token) : <dynamic>[];
      } catch (_) {
        myFollowedCommunities = [];
      }
      try {
        campusShortcuts = await api.getCampusShortcuts(token);
      } catch (_) {
        campusShortcuts = {};
      }
      try {
        academicNotices = await api.getAcademicNotices(token);
      } catch (_) {
        academicNotices = [];
      }
      _ingestNotificationsFromServer(
        await api.getNotifications(token, limit: 50),
        emitPop: toastNewNotifications,
      );
    } catch (e, st) {
      assert(() {
        debugPrint("Campus Board loadAll: $e\n$st");
        return true;
      }());
    } finally {
      _loadInProgress = false;
      notifyListeners();
    }
  }

  int? _notificationId(Map<dynamic, dynamic> n) {
    final v = n["id"];
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? "");
  }

  Future<void> refreshNotifications({bool emitPop = true}) async {
    if (accessToken == null) return;
    final fresh = await api.getNotifications(accessToken!, limit: 50);
    _ingestNotificationsFromServer(fresh, emitPop: emitPop);
    notifyListeners();
  }

  void _startNotificationPolling() {
    _notificationPollTimer?.cancel();
    // Full campus refresh so admin/faculty edits and new content show up for all signed-in users without manual refresh.
    _notificationPollTimer = Timer.periodic(const Duration(seconds: 35), (_) async {
      if (accessToken == null) return;
      await loadAll(toastNewNotifications: true);
    });
  }

  void _ingestNotificationsFromServer(List<dynamic> fresh, {required bool emitPop}) {
    final idsNow = <int>{};
    final newcomers = <Map<dynamic, dynamic>>[];
    for (final row in fresh) {
      if (row is! Map) continue;
      final id = _notificationId(row);
      if (id == null) continue;
      idsNow.add(id);
      if (emitPop && !_seenNotificationIds.contains(id)) {
        newcomers.add(row);
      }
    }
    notifications = fresh;
    _seenNotificationIds
      ..clear()
      ..addAll(idsNow);
    if (emitPop && newcomers.isNotEmpty) {
      _emitNewNotificationToasts(newcomers);
    }
  }

  void _emitNewNotificationToasts(List<Map<dynamic, dynamic>> rows) {
    void openFeed() => appNavigateTo("/notifications");
    if (rows.length == 1) {
      final r = rows.first;
      final t = r["title"]?.toString() ?? "Campus Board";
      final b = (r["message"] ?? r["body"])?.toString() ?? "";
      final rawType = r["notification_type"]?.toString().trim();
      showCampusNotificationToast(
        t,
        b,
        category: (rawType != null && rawType.isNotEmpty) ? rawType : null,
        onOpen: openFeed,
      );
      return;
    }
    showCampusNotificationToast(
      "Campus Board",
      "${rows.length} new notifications — dashboard, events, clubs, or lost & found.",
      category: "Multiple updates",
      onOpen: openFeed,
    );
  }

  Future<void> markNotificationRead(int notificationId) async {
    if (accessToken == null) return;
    await api.markNotificationRead(accessToken!, notificationId);
    for (var i = 0; i < notifications.length; i++) {
      final row = notifications[i];
      if (row is Map && _notificationId(row) == notificationId) {
        final copy = Map<String, dynamic>.from(row.map((k, v) => MapEntry(k.toString(), v)));
        copy["is_read"] = true;
        notifications[i] = copy;
        break;
      }
    }
    notifyListeners();
  }

  Future<void> markAllNotificationsRead() async {
    if (accessToken == null) return;
    await api.markAllNotificationsRead(accessToken!);
    for (var i = 0; i < notifications.length; i++) {
      final row = notifications[i];
      if (row is Map) {
        final copy = Map<String, dynamic>.from(row.map((k, v) => MapEntry(k.toString(), v)));
        copy["is_read"] = true;
        notifications[i] = copy;
      }
    }
    notifyListeners();
  }

  Future<void> deleteNotification(int notificationId) async {
    if (accessToken == null) return;
    await api.deleteNotification(accessToken!, notificationId);
    notifications = notifications.where((row) {
      if (row is! Map) return true;
      return _notificationId(row) != notificationId;
    }).toList();
    notifyListeners();
  }

  Future<void> createLostItem(String title, String description, String location, XFile? image) async {
    if (accessToken == null) return;
    await api.createLostFound(accessToken!, title, description, location, image);
    lostFound = await api.getLostFound(accessToken!);
    notifyListeners();
  }

  Future<String?> saveAdminEvent({
    int? eventId,
    required String title,
    required String description,
    required String category,
    required String priority,
    required String location,
    required DateTime startTime,
    required DateTime endTime,
    required int autoRemoveAfterHours,
    required bool allowRegistration,
    required String dashboardSegment,
    required bool showDescription,
    required bool showLocation,
    required bool showRegistrationSection,
    required bool showPollsSection,
    required bool showAnnouncementsSection,
    String? customLinkLabel,
    String? customLinkUrl,
    String? festName,
    String? teamFormat,
    String? entryFee,
    String? prizeSummary,
    bool showCategoryBadge = true,
    String? editorSectionOrderJson,
    bool showInDashboard = true,
    bool trendingHighlight = false,
    String? dashboardTitle,
    String? dashboardDescription,
    String? eventPageJson,
    bool useSeparateCarouselImage = false,
    String eventPageBackgroundKind = "none",
    String? eventPageBackgroundColor,
    XFile? poster,
    XFile? carouselPoster,
    XFile? eventPageBackground,
    PlatformFile? examTimetable,
  }) async {
    if (accessToken == null) {
      return "Not signed in";
    }
    if (!canManageEvents) {
      return "You do not have permission to create or edit campus activities. Ask a campus administrator.";
    }
    try {
      if (eventId == null) {
        await api.createAdminEvent(
          accessToken!,
          title: title,
          description: description,
          category: category,
          priority: priority,
          location: location,
          startTime: startTime,
          endTime: endTime,
          autoRemoveAfterHours: autoRemoveAfterHours,
          allowRegistration: allowRegistration,
          dashboardSegment: dashboardSegment,
          showDescription: showDescription,
          showLocation: showLocation,
          showRegistrationSection: showRegistrationSection,
          showPollsSection: showPollsSection,
          showAnnouncementsSection: showAnnouncementsSection,
          customLinkLabel: customLinkLabel,
          customLinkUrl: customLinkUrl,
          festName: festName,
          teamFormat: teamFormat,
          entryFee: entryFee,
          prizeSummary: prizeSummary,
          showCategoryBadge: showCategoryBadge,
          editorSectionOrderJson: editorSectionOrderJson,
          showInDashboard: showInDashboard,
          trendingHighlight: trendingHighlight,
          dashboardTitle: dashboardTitle,
          dashboardDescription: dashboardDescription,
          eventPageJson: eventPageJson,
          useSeparateCarouselImage: useSeparateCarouselImage,
          eventPageBackgroundKind: eventPageBackgroundKind,
          eventPageBackgroundColor: eventPageBackgroundColor,
          poster: poster,
          carouselPoster: carouselPoster,
          eventPageBackground: eventPageBackground,
          examTimetable: examTimetable,
        );
      } else {
        await api.updateAdminEvent(
          accessToken!,
          eventId,
          title: title,
          description: description,
          category: category,
          priority: priority,
          location: location,
          startTime: startTime,
          endTime: endTime,
          autoRemoveAfterHours: autoRemoveAfterHours,
          allowRegistration: allowRegistration,
          dashboardSegment: dashboardSegment,
          showDescription: showDescription,
          showLocation: showLocation,
          showRegistrationSection: showRegistrationSection,
          showPollsSection: showPollsSection,
          showAnnouncementsSection: showAnnouncementsSection,
          customLinkLabel: customLinkLabel,
          customLinkUrl: customLinkUrl,
          festName: festName,
          teamFormat: teamFormat,
          entryFee: entryFee,
          prizeSummary: prizeSummary,
          showCategoryBadge: showCategoryBadge,
          editorSectionOrderJson: editorSectionOrderJson,
          showInDashboard: showInDashboard,
          trendingHighlight: trendingHighlight,
          dashboardTitle: dashboardTitle,
          dashboardDescription: dashboardDescription,
          eventPageJson: eventPageJson,
          useSeparateCarouselImage: useSeparateCarouselImage,
          eventPageBackgroundKind: eventPageBackgroundKind,
          eventPageBackgroundColor: eventPageBackgroundColor,
          poster: poster,
          carouselPoster: carouselPoster,
          eventPageBackground: eventPageBackground,
          examTimetable: examTimetable,
        );
      }
      await loadAll();
      return null;
    } on DioException catch (e) {
      return _dioUserMessage(e);
    } catch (e) {
      return _anyUserMessage(e);
    }
  }

  Future<String?> deleteAdminEvent(int eventId) async {
    if (accessToken == null) {
      return "Not signed in";
    }
    if (!canManageEvents) {
      return "You do not have permission to delete campus activities.";
    }
    Map<String, dynamic>? row;
    for (final raw in events) {
      if (raw is! Map) continue;
      final m = Map<String, dynamic>.from(raw.map((k, v) => MapEntry(k.toString(), v)));
      if (intFromJsonField(m, "id") == eventId) {
        row = m;
        break;
      }
    }
    if (row != null && !canDeleteDashboardActivity(row)) {
      return "You can only delete activities you created (or ask a campus administrator).";
    }
    try {
      await api.deleteAdminEvent(accessToken!, eventId);
      await loadAll();
      return null;
    } on DioException catch (e) {
      return _dioUserMessage(e);
    } catch (e) {
      return _anyUserMessage(e);
    }
  }

  Future<String?> setAdminEventTrendingHighlight(int eventId, {required bool trendingHighlight}) async {
    if (accessToken == null) {
      return "Not signed in";
    }
    if (!canManageEvents) {
      return "You do not have permission to update campus activities.";
    }
    Map<String, dynamic>? row;
    for (final raw in events) {
      if (raw is! Map) continue;
      final m = Map<String, dynamic>.from(raw.map((k, v) => MapEntry(k.toString(), v)));
      if (intFromJsonField(m, "id") == eventId) {
        row = m;
        break;
      }
    }
    if (row != null && !canEditDashboardActivity(row)) {
      return "You can only update activities you created (or ask a campus administrator).";
    }
    try {
      await api.setEventTrendingHighlightAdmin(accessToken!, eventId, trendingHighlight: trendingHighlight);
      await loadAll();
      return null;
    } on DioException catch (e) {
      return _dioUserMessage(e);
    } catch (e) {
      return _anyUserMessage(e);
    }
  }

  Future<String?> uploadCampusShortcut(String slot, PlatformFile file) async {
    if (accessToken == null) {
      return "Not signed in";
    }
    if (!canManageCampusShortcuts) {
      return "Only campus administrators or faculty with academic posting enabled may change these files.";
    }
    try {
      campusShortcuts = await api.uploadCampusShortcut(accessToken!, slot, file);
      notifyListeners();
      return null;
    } on DioException catch (e) {
      return _dioUserMessage(e);
    } catch (e) {
      return _anyUserMessage(e);
    }
  }

  Future<String?> deleteCampusShortcut(String slot) async {
    if (accessToken == null) {
      return "Not signed in";
    }
    if (!canManageCampusShortcuts) {
      return "Only campus administrators or faculty with academic posting enabled may change these files.";
    }
    try {
      campusShortcuts = await api.deleteCampusShortcut(accessToken!, slot);
      notifyListeners();
      return null;
    } on DioException catch (e) {
      return _dioUserMessage(e);
    } catch (e) {
      return _anyUserMessage(e);
    }
  }

  Future<String?> createAcademicNotice({
    required String title,
    String? body,
    String? linkUrl,
    DateTime? expiresAt,
    PlatformFile? file,
  }) async {
    if (accessToken == null) {
      return "Not signed in";
    }
    if (!canManageCampusShortcuts) {
      return "Only campus administrators or faculty with academic posting enabled may post notices.";
    }
    try {
      await api.createAcademicNotice(
        accessToken!,
        title: title,
        body: body,
        linkUrl: linkUrl,
        expiresAtIso: expiresAt?.toUtc().toIso8601String(),
        file: file,
      );
      academicNotices = await api.getAcademicNotices(accessToken!);
      notifyListeners();
      return null;
    } on DioException catch (e) {
      return _dioUserMessage(e);
    } catch (e) {
      return _anyUserMessage(e);
    }
  }

  Future<String?> deleteAcademicNotice(int noticeId) async {
    if (accessToken == null) {
      return "Not signed in";
    }
    if (!canManageCampusShortcuts) {
      return "Only campus administrators or faculty with academic posting enabled may delete notices.";
    }
    try {
      await api.deleteAcademicNotice(accessToken!, noticeId);
      academicNotices = await api.getAcademicNotices(accessToken!);
      notifyListeners();
      return null;
    } on DioException catch (e) {
      return _dioUserMessage(e);
    } catch (e) {
      return _anyUserMessage(e);
    }
  }

  Future<String?> cancelLostFoundRequest(int itemId) async {
    if (accessToken == null) {
      return "Not signed in";
    }
    try {
      await api.cancelLostFound(accessToken!, itemId);
      lostFound = await api.getLostFound(accessToken!);
      lostFoundComments.remove(itemId);
      notifyListeners();
      return null;
    } on DioException catch (e) {
      return _dioUserMessage(e);
    } catch (e) {
      return _anyUserMessage(e);
    }
  }

  Future<String?> setLostFoundItemFound(int itemId, bool isFound) async {
    if (accessToken == null) {
      return "Not signed in";
    }
    try {
      await api.patchLostFoundStatus(accessToken!, itemId, isFound);
      lostFound = await api.getLostFound(accessToken!);
      notifyListeners();
      return null;
    } on DioException catch (e) {
      return _dioUserMessage(e);
    } catch (e) {
      return _anyUserMessage(e);
    }
  }

  Future<String?> loadLostFoundComments(int itemId) async {
    if (accessToken == null) {
      return "Not signed in";
    }
    try {
      final comments = await api.getLostFoundComments(accessToken!, itemId);
      lostFoundComments[itemId] = comments;
      notifyListeners();
      return null;
    } on DioException catch (e) {
      return _dioUserMessage(e);
    } catch (e) {
      return _anyUserMessage(e);
    }
  }

  Future<String?> addFoundComment({
    required int itemId,
    required String finderName,
    required String message,
    String? contact,
  }) async {
    if (accessToken == null) {
      return "Not signed in";
    }
    try {
      await api.addLostFoundComment(
        accessToken!,
        itemId,
        finderName: finderName,
        message: message,
        contact: contact,
      );
      final comments = await api.getLostFoundComments(accessToken!, itemId);
      lostFoundComments[itemId] = comments;
      notifyListeners();
      return null;
    } on DioException catch (e) {
      return _dioUserMessage(e);
    } catch (e) {
      return _anyUserMessage(e);
    }
  }

  Map<String, dynamic>? myRegistrationForEvent(int eventId) {
    for (final r in myRegistrations) {
      final m = r as Map<String, dynamic>;
      if (intFromJsonField(m, "event_id") == eventId) {
        return m;
      }
    }
    return null;
  }

  bool isRegisteredForEvent(int? eventId) {
    if (eventId == null) {
      return false;
    }
    return myRegistrationForEvent(eventId) != null;
  }

  Future<String?> submitEventRegistration({
    required int eventId,
    required String participantName,
    required String rollNo,
    required String branch,
    required String collegeName,
    required String phone,
    required String email,
  }) async {
    if (accessToken == null) {
      return "Not signed in";
    }
    try {
      await api.registerEvent(accessToken!, eventId, {
        "participant_name": participantName,
        "roll_no": rollNo,
        "branch": branch,
        "college_name": collegeName,
        "phone": phone,
        "email": email,
      });
      await loadAll();
      return null;
    } on DioException catch (e) {
      return _dioUserMessage(e);
    } catch (e) {
      return _anyUserMessage(e);
    }
  }

  bool isFollowingCommunity(int communityId) {
    for (final raw in myFollowedCommunities) {
      if (raw is! Map) continue;
      final m = Map<String, dynamic>.from(raw.map((k, v) => MapEntry(k.toString(), v)));
      if (intFromJsonField(m, "id") == communityId) {
        return true;
      }
    }
    return false;
  }

  Future<String?> followCommunity(int communityId) async {
    if (accessToken == null) {
      return "Not signed in";
    }
    if (!isStudent) {
      return "Only students can follow clubs";
    }
    try {
      await api.followCommunity(accessToken!, communityId);
      myFollowedCommunities = await api.getFollowingCommunities(accessToken!);
      notifyListeners();
      return null;
    } on DioException catch (e) {
      return _dioUserMessage(e);
    } catch (e) {
      return _anyUserMessage(e);
    }
  }

  Future<String?> unfollowCommunity(int communityId) async {
    if (accessToken == null) {
      return "Not signed in";
    }
    if (!isStudent) {
      return "Only students can unfollow clubs";
    }
    try {
      await api.unfollowCommunity(accessToken!, communityId);
      myFollowedCommunities = await api.getFollowingCommunities(accessToken!);
      notifyListeners();
      return null;
    } on DioException catch (e) {
      return _dioUserMessage(e);
    } catch (e) {
      return _anyUserMessage(e);
    }
  }

  /// Adds membership (e.g. admin-added member flows). Students use [followCommunity] from the UI.
  Future<String?> joinCommunity(int communityId) async {
    if (accessToken == null) {
      return "Not signed in";
    }
    try {
      await api.joinCommunity(accessToken!, communityId);
      await loadAll();
      return null;
    } on DioException catch (e) {
      return _dioUserMessage(e);
    } catch (e) {
      return _anyUserMessage(e);
    }
  }

  Future<String?> createClubAnnouncement({
    required int clubId,
    required String title,
    required String description,
    required String priority,
    XFile? image,
  }) async {
    if (accessToken == null) {
      return "Not signed in";
    }
    if (!canManageClubContent(clubId)) {
      return "Only a club manager or campus admin can post announcements for this club";
    }
    try {
      await api.createClubAnnouncement(
        accessToken!,
        clubId,
        title: title,
        description: description,
        priority: priority,
        image: image,
      );
      await loadAll();
      return null;
    } on DioException catch (e) {
      return _dioUserMessage(e);
    } catch (e) {
      return _anyUserMessage(e);
    }
  }

  Future<String?> updateClubAnnouncement({
    required int announcementId,
    required int clubId,
    String? title,
    String? description,
    String? priority,
    XFile? image,
  }) async {
    if (accessToken == null) {
      return "Not signed in";
    }
    if (!canManageClubContent(clubId)) {
      return "Only a club manager or campus admin can edit announcements for this club";
    }
    try {
      await api.updateClubAnnouncement(
        accessToken!,
        announcementId,
        title: title,
        description: description,
        priority: priority,
        image: image,
      );
      await loadAll();
      return null;
    } on DioException catch (e) {
      return _dioUserMessage(e);
    } catch (e) {
      return _anyUserMessage(e);
    }
  }

  Future<String?> deleteClubAnnouncement(int announcementId, {required int clubId}) async {
    if (accessToken == null) {
      return "Not signed in";
    }
    if (!canManageClubContent(clubId)) {
      return "Only a club manager or campus admin can delete announcements for this club";
    }
    try {
      await api.deleteClubAnnouncement(accessToken!, announcementId);
      await loadAll();
      return null;
    } on DioException catch (e) {
      return _dioUserMessage(e);
    } catch (e) {
      return _anyUserMessage(e);
    }
  }

  Future<String?> updateCommunitySettings({
    required int communityId,
    String? name,
    String? description,
    XFile? poster,
  }) async {
    if (accessToken == null) {
      return "Not signed in";
    }
    if (!canManageClubContent(communityId)) {
      return "Only a club manager or campus admin can update this community";
    }
    try {
      await api.updateCommunityAdmin(accessToken!, communityId, name: name, description: description, poster: poster);
      await loadAll();
      return null;
    } on DioException catch (e) {
      return _dioUserMessage(e);
    } catch (e) {
      return _anyUserMessage(e);
    }
  }

  Future<String?> deleteCommunity(int communityId) async {
    if (accessToken == null) {
      return "Not signed in";
    }
    if (!canManageClubContent(communityId)) {
      return "Only a club manager or campus admin can delete this community";
    }
    try {
      await api.deleteCommunityAdmin(accessToken!, communityId);
      await loadAll();
      return null;
    } on DioException catch (e) {
      return _dioUserMessage(e);
    } catch (e) {
      return _anyUserMessage(e);
    }
  }

  Future<String?> addCommunityMemberByUserId({required int communityId, required int userId}) async {
    if (accessToken == null) {
      return "Not signed in";
    }
    if (!canManageClubContent(communityId)) {
      return "Only a club manager or campus admin can add members to this club";
    }
    try {
      await api.addCommunityMember(accessToken!, communityId, userId);
      await loadAll();
      return null;
    } on DioException catch (e) {
      return _dioUserMessage(e);
    } catch (e) {
      return _anyUserMessage(e);
    }
  }

  Future<String?> createCommunity({
    required String name,
    String? description,
  }) async {
    if (accessToken == null) {
      return "Not signed in";
    }
    if (!canCreateClubs) {
      return "Only campus administrators or appointed student campus leads may create clubs.";
    }
    try {
      await api.createCommunityAdmin(
        accessToken!,
        name: name,
        description: description,
      );
      await loadAll();
      return null;
    } on DioException catch (e) {
      return _dioUserMessage(e);
    } catch (e) {
      return _anyUserMessage(e);
    }
  }

  Future<String?> saveMyProfile({
    String? fullName,
    String? bio,
    String? birthDateIso,
    String? phone,
    String? collegeName,
    XFile? profileImage,
  }) async {
    if (accessToken == null) {
      return "Not signed in";
    }
    try {
      await api.updateMyProfile(
        accessToken!,
        fullName: fullName,
        bio: bio,
        birthDateIso: birthDateIso,
        phone: phone,
        collegeName: collegeName,
        profileImage: profileImage,
      );
      profile = await api.me(accessToken!);
      notifyListeners();
      return null;
    } on DioException catch (e) {
      return _dioUserMessage(e);
    } catch (e) {
      return _anyUserMessage(e);
    }
  }

  Future<String?> broadcastNoticeToStudents({
    required String title,
    required String body,
    String priority = "normal",
    String audience = "students",
  }) async {
    if (accessToken == null) {
      return "Not signed in";
    }
    if (!canManageEvents) {
      return "You do not have permission to send this notice.";
    }
    try {
      await api.broadcastNoticeToStudents(
        accessToken!,
        title: title,
        body: body,
        priority: priority,
        audience: audience,
      );
    } on DioException catch (e) {
      return _dioUserMessage(e);
    } catch (e) {
      return _anyUserMessage(e);
    }
    await loadAll();
    return null;
  }

  Future<String?> savePoll({
    int? pollId,
    required String question,
    String? description,
    required bool isActive,
    required List<String> options,
  }) async {
    if (accessToken == null) {
      return "Not signed in";
    }
    if (!canManageEvents) {
      return "You do not have permission to manage polls.";
    }
    final cleanOptions = options.map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    if (question.trim().isEmpty || cleanOptions.length < 2) {
      return "Question and at least 2 options are required";
    }
    try {
      if (pollId == null) {
        await api.createPoll(
          accessToken!,
          question: question.trim(),
          description: description,
          isActive: isActive,
          options: cleanOptions,
        );
      } else {
        await api.updatePoll(
          accessToken!,
          pollId,
          question: question.trim(),
          description: description,
          isActive: isActive,
          options: cleanOptions,
        );
      }
      await loadAll();
      return null;
    } on DioException catch (e) {
      return _dioUserMessage(e);
    } catch (e) {
      return _anyUserMessage(e);
    }
  }

  Future<String?> removePoll(int pollId) async {
    if (accessToken == null) {
      return "Not signed in";
    }
    if (!canManageEvents) {
      return "You do not have permission to delete polls.";
    }
    try {
      await api.deletePoll(accessToken!, pollId);
      await loadAll();
      return null;
    } on DioException catch (e) {
      return _dioUserMessage(e);
    } catch (e) {
      return _anyUserMessage(e);
    }
  }

  Future<String?> submitPollVote({required int pollId, required int optionId}) async {
    if (accessToken == null) {
      return "Not signed in";
    }
    try {
      await api.votePoll(accessToken!, pollId, optionId);
      polls = await api.getPolls(accessToken!);
      notifyListeners();
      return null;
    } on DioException catch (e) {
      return _dioUserMessage(e);
    } catch (e) {
      return _anyUserMessage(e);
    }
  }

  Future<String?> cancelEventRegistration(int eventId) async {
    if (accessToken == null) {
      return "Not signed in";
    }
    try {
      await api.unregisterEvent(accessToken!, eventId);
      await loadAll();
      return null;
    } on DioException catch (e) {
      return _dioUserMessage(e);
    } catch (e) {
      return _anyUserMessage(e);
    }
  }

  /// Call after changing API base URL so widgets showing `api.currentBaseUrl` rebuild.
  void refreshAfterApiUrlChange() => notifyListeners();

  /// Call after assigning to [events], [notifications], [polls], or other exposed fields
  /// from outside this class so [Provider] consumers rebuild (protected [notifyListeners] cannot be called externally).
  void applyDataChange() => notifyListeners();

  Future<void> _setupFcm() async {
    if (accessToken == null) return;
    try {
      await FirebaseMessaging.instance.requestPermission();
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
        await api.registerFcmToken(accessToken!, token);
      }
    } catch (_) {}
  }
}
