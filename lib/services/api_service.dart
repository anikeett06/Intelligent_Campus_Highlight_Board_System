import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:image_picker/image_picker.dart';

import 'package:studentboard/app/app_config.dart';

class ApiService {
  ApiService() {
    _dio = Dio(
      BaseOptions(
        baseUrl: resolvedDefaultBaseUrl(),
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 30),
      ),
    );
  }

  late Dio _dio;
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  static const String _apiBaseUrlKey = "api_base_url";
  static const String _savedLoginsKey = "saved_login_accounts_v1";
  static const int _maxSavedLoginSlots = 5;

  String get currentBaseUrl => _dio.options.baseUrl;

  String get serverOrigin {
    final uri = Uri.tryParse(_dio.options.baseUrl);
    return uri?.origin ?? "";
  }

  Future<void> loadStoredBaseUrl() async {
    final stored = await _storage.read(key: _apiBaseUrlKey);
    if (stored != null && stored.isNotEmpty) {
      final normalized = normalizeApiBaseUrl(stored);
      if (normalized != stored.trim()) {
        await _storage.write(key: _apiBaseUrlKey, value: normalized);
      }
      _dio.options.baseUrl = normalized;
    } else {
      _dio.options.baseUrl = resolvedDefaultBaseUrl();
    }
  }

  Future<void> saveBaseUrl(String raw) async {
    final normalized = normalizeApiBaseUrl(raw);
    await _storage.write(key: _apiBaseUrlKey, value: normalized);
    _dio.options.baseUrl = normalized;
  }

  Future<void> clearBaseUrlOverride() async {
    await _storage.delete(key: _apiBaseUrlKey);
    _dio.options.baseUrl = resolvedDefaultBaseUrl();
  }

  Future<String?> token() => _storage.read(key: "access_token");

  Future<void> saveToken(String token) => _storage.write(key: "access_token", value: token);

  Future<void> clearToken() => _storage.delete(key: "access_token");

  /// Last successful logins on this device (encrypted at rest via secure storage). Newest first, max [_maxSavedLoginSlots].
  Future<List<Map<String, String>>> loadSavedLoginAccounts() async {
    final raw = await _storage.read(key: _savedLoginsKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List<dynamic>) return [];
      final out = <Map<String, String>>[];
      for (final item in decoded) {
        if (item is! Map) continue;
        final m = Map<String, dynamic>.from(item);
        final email = m["email"]?.toString().trim() ?? "";
        if (email.isEmpty) continue;
        out.add({"email": email, "password": m["password"]?.toString() ?? ""});
      }
      return out;
    } catch (_) {
      return [];
    }
  }

  Future<void> saveLoginAccount(String email, String password) async {
    final e = email.trim();
    if (e.isEmpty) return;
    var list = await loadSavedLoginAccounts();
    list = list.where((m) => (m["email"] ?? "").toLowerCase() != e.toLowerCase()).toList();
    list.insert(0, {"email": e, "password": password});
    if (list.length > _maxSavedLoginSlots) {
      list = list.sublist(0, _maxSavedLoginSlots);
    }
    await _storage.write(key: _savedLoginsKey, value: jsonEncode(list));
  }

  Future<Map<String, dynamic>> login(String email, String password) async {
    final response = await _dio.post("/auth/login", data: {"email": email, "password": password});
    return Map<String, dynamic>.from(response.data);
  }

  Future<void> register(String fullName, String email, String password, {String role = "student"}) async {
    final r = role.trim().toLowerCase();
    final roleOut = r == "faculty" ? "faculty" : "student";
    await _dio.post(
      "/auth/signup",
      data: {"full_name": fullName, "email": email, "password": password, "role": roleOut},
    );
  }

  Future<List<dynamic>> getUsersList(String token) async {
    final response = await _dio.get("/users/", options: Options(headers: {"Authorization": "Bearer $token"}));
    return response.data as List<dynamic>;
  }

  Future<Map<String, dynamic>> adminUpdateUser(
    String token,
    int userId, {
    String? fullName,
    String? role,
    bool? isActive,
    bool? academicPostingAllowed,
    bool? studentAdmin,
  }) async {
    final body = <String, dynamic>{};
    if (fullName != null) body["full_name"] = fullName;
    if (role != null) body["role"] = role.trim().toLowerCase() == "faculty" ? "faculty" : "student";
    if (isActive != null) body["is_active"] = isActive;
    if (academicPostingAllowed != null) body["academic_posting_allowed"] = academicPostingAllowed;
    if (studentAdmin != null) body["student_admin"] = studentAdmin;
    final response = await _dio.patch(
      "/users/$userId",
      data: body,
      options: Options(headers: {"Authorization": "Bearer $token"}),
    );
    return Map<String, dynamic>.from(response.data);
  }

  Future<void> adminSetClubModerator(
    String token,
    int userId, {
    required int communityId,
    required bool isModerator,
  }) async {
    await _dio.patch(
      "/users/$userId/community-moderator",
      data: {"community_id": communityId, "is_moderator": isModerator},
      options: Options(headers: {"Authorization": "Bearer $token"}),
    );
  }

  Future<List<dynamic>> getEvents(String token) async {
    final response = await _dio.get("/events/", options: Options(headers: {"Authorization": "Bearer $token"}));
    return response.data as List<dynamic>;
  }

  Future<Map<String, dynamic>> getEventById(String token, int eventId) async {
    final response = await _dio.get("/events/$eventId", options: Options(headers: {"Authorization": "Bearer $token"}));
    return Map<String, dynamic>.from(response.data);
  }

  Future<Map<String, dynamic>> getDashboard(String token) async {
    final response = await _dio.get("/events/dashboard/grouped", options: Options(headers: {"Authorization": "Bearer $token"}));
    return Map<String, dynamic>.from(response.data);
  }

  Future<Map<String, dynamic>> getCampusShortcuts(String token) async {
    final response = await _dio.get("/campus-shortcuts/", options: Options(headers: {"Authorization": "Bearer $token"}));
    return Map<String, dynamic>.from(response.data);
  }

  Future<Map<String, dynamic>> uploadCampusShortcut(String token, String slot, PlatformFile file) async {
    final form = FormData();
    if (file.bytes != null) {
      form.files.add(MapEntry("file", MultipartFile.fromBytes(file.bytes!, filename: file.name)));
    } else if (file.path != null && file.path!.isNotEmpty) {
      form.files.add(MapEntry("file", await MultipartFile.fromFile(file.path!, filename: file.name)));
    } else {
      throw StateError("No file bytes or path for upload");
    }
    final response = await _dio.put(
      "/campus-shortcuts/$slot",
      data: form,
      options: Options(headers: {"Authorization": "Bearer $token"}),
    );
    return Map<String, dynamic>.from(response.data);
  }

  Future<Map<String, dynamic>> deleteCampusShortcut(String token, String slot) async {
    final response = await _dio.delete(
      "/campus-shortcuts/$slot",
      options: Options(headers: {"Authorization": "Bearer $token"}),
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<List<dynamic>> getAcademicNotices(String token) async {
    final response = await _dio.get(
      "/academic-notices/",
      options: Options(headers: {"Authorization": "Bearer $token"}),
    );
    return List<dynamic>.from(response.data as List);
  }

  Future<Map<String, dynamic>> createAcademicNotice(
    String token, {
    required String title,
    String? body,
    String? linkUrl,
    String? expiresAtIso,
    PlatformFile? file,
  }) async {
    final form = FormData.fromMap({
      "title": title,
      "body": body ?? "",
      "link_url": linkUrl ?? "",
      "expires_at": expiresAtIso ?? "",
    });
    if (file != null) {
      if (file.bytes != null) {
        form.files.add(MapEntry("file", MultipartFile.fromBytes(file.bytes!, filename: file.name)));
      } else if (file.path != null && file.path!.isNotEmpty) {
        form.files.add(MapEntry("file", await MultipartFile.fromFile(file.path!, filename: file.name)));
      }
    }
    final response = await _dio.post(
      "/academic-notices/",
      data: form,
      options: Options(headers: {"Authorization": "Bearer $token"}),
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<void> deleteAcademicNotice(String token, int noticeId) async {
    await _dio.delete(
      "/academic-notices/$noticeId",
      options: Options(headers: {"Authorization": "Bearer $token"}),
    );
  }

  Future<void> registerEvent(String token, int eventId, Map<String, dynamic> body) async {
    await _dio.post(
      "/events/$eventId/register",
      data: body,
      options: Options(headers: {"Authorization": "Bearer $token"}),
    );
  }

  Future<Map<String, dynamic>> createAdminEvent(
    String token, {
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
    final form = FormData.fromMap({
      "title": title,
      "description": description,
      "category": category,
      "priority": priority,
      "location": location,
      "start_time": startTime.toUtc().toIso8601String(),
      "end_time": endTime.toUtc().toIso8601String(),
      "auto_remove_after_hours": autoRemoveAfterHours.toString(),
      "allow_registration": allowRegistration.toString(),
      "dashboard_segment": dashboardSegment,
      "show_description": showDescription.toString(),
      "show_location": showLocation.toString(),
      "show_registration_section": showRegistrationSection.toString(),
      "show_polls_section": showPollsSection.toString(),
      "show_announcements_section": showAnnouncementsSection.toString(),
      "custom_link_label": customLinkLabel ?? "",
      "custom_link_url": customLinkUrl ?? "",
      "fest_name": festName ?? "",
      "team_format": teamFormat ?? "",
      "entry_fee": entryFee ?? "",
      "prize_summary": prizeSummary ?? "",
      "show_category_badge": showCategoryBadge.toString(),
      "editor_section_order": editorSectionOrderJson ?? "",
      "show_in_dashboard": showInDashboard.toString(),
      "trending_highlight": trendingHighlight.toString(),
      "dashboard_title": dashboardTitle ?? "",
      "dashboard_description": dashboardDescription ?? "",
      "event_page_json": eventPageJson ?? "",
      "use_separate_carousel_image": useSeparateCarouselImage.toString(),
      "event_page_background_kind": eventPageBackgroundKind,
      "event_page_background_color": eventPageBackgroundColor ?? "",
    });
    if (poster != null) {
      if (kIsWeb) {
        final bytes = await poster.readAsBytes();
        form.files.add(MapEntry("poster", MultipartFile.fromBytes(bytes, filename: poster.name)));
      } else {
        form.files.add(MapEntry("poster", await MultipartFile.fromFile(poster.path, filename: poster.name)));
      }
    }
    if (carouselPoster != null) {
      if (kIsWeb) {
        final bytes = await carouselPoster.readAsBytes();
        form.files.add(MapEntry("carousel_poster", MultipartFile.fromBytes(bytes, filename: carouselPoster.name)));
      } else {
        form.files.add(
          MapEntry("carousel_poster", await MultipartFile.fromFile(carouselPoster.path, filename: carouselPoster.name)),
        );
      }
    }
    if (eventPageBackground != null) {
      if (kIsWeb) {
        final bytes = await eventPageBackground.readAsBytes();
        form.files.add(
          MapEntry("event_page_background", MultipartFile.fromBytes(bytes, filename: eventPageBackground.name)),
        );
      } else {
        form.files.add(
          MapEntry(
            "event_page_background",
            await MultipartFile.fromFile(eventPageBackground.path, filename: eventPageBackground.name),
          ),
        );
      }
    }
    if (examTimetable != null) {
      if (examTimetable.bytes != null) {
        form.files.add(
          MapEntry("exam_timetable", MultipartFile.fromBytes(examTimetable.bytes!, filename: examTimetable.name)),
        );
      } else if (examTimetable.path != null && examTimetable.path!.isNotEmpty) {
        form.files.add(
          MapEntry("exam_timetable", await MultipartFile.fromFile(examTimetable.path!, filename: examTimetable.name)),
        );
      }
    }
    final response = await _dio.post(
      "/events/admin",
      data: form,
      options: Options(headers: {"Authorization": "Bearer $token"}),
    );
    return Map<String, dynamic>.from(response.data);
  }

  Future<Map<String, dynamic>> updateAdminEvent(
    String token,
    int eventId, {
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
    final form = FormData.fromMap({
      "title": title,
      "description": description,
      "category": category,
      "priority": priority,
      "location": location,
      "start_time": startTime.toUtc().toIso8601String(),
      "end_time": endTime.toUtc().toIso8601String(),
      "auto_remove_after_hours": autoRemoveAfterHours.toString(),
      "allow_registration": allowRegistration.toString(),
      "dashboard_segment": dashboardSegment,
      "show_description": showDescription.toString(),
      "show_location": showLocation.toString(),
      "show_registration_section": showRegistrationSection.toString(),
      "show_polls_section": showPollsSection.toString(),
      "show_announcements_section": showAnnouncementsSection.toString(),
      "custom_link_label": customLinkLabel ?? "",
      "custom_link_url": customLinkUrl ?? "",
      "fest_name": festName ?? "",
      "team_format": teamFormat ?? "",
      "entry_fee": entryFee ?? "",
      "prize_summary": prizeSummary ?? "",
      "show_category_badge": showCategoryBadge.toString(),
      "editor_section_order": editorSectionOrderJson ?? "",
      "show_in_dashboard": showInDashboard.toString(),
      "trending_highlight": trendingHighlight.toString(),
      "dashboard_title": dashboardTitle ?? "",
      "dashboard_description": dashboardDescription ?? "",
      "event_page_json": eventPageJson ?? "",
      "use_separate_carousel_image": useSeparateCarouselImage.toString(),
      "event_page_background_kind": eventPageBackgroundKind,
      "event_page_background_color": eventPageBackgroundColor ?? "",
    });
    if (poster != null) {
      if (kIsWeb) {
        final bytes = await poster.readAsBytes();
        form.files.add(MapEntry("poster", MultipartFile.fromBytes(bytes, filename: poster.name)));
      } else {
        form.files.add(MapEntry("poster", await MultipartFile.fromFile(poster.path, filename: poster.name)));
      }
    }
    if (carouselPoster != null) {
      if (kIsWeb) {
        final bytes = await carouselPoster.readAsBytes();
        form.files.add(MapEntry("carousel_poster", MultipartFile.fromBytes(bytes, filename: carouselPoster.name)));
      } else {
        form.files.add(
          MapEntry("carousel_poster", await MultipartFile.fromFile(carouselPoster.path, filename: carouselPoster.name)),
        );
      }
    }
    if (eventPageBackground != null) {
      if (kIsWeb) {
        final bytes = await eventPageBackground.readAsBytes();
        form.files.add(
          MapEntry("event_page_background", MultipartFile.fromBytes(bytes, filename: eventPageBackground.name)),
        );
      } else {
        form.files.add(
          MapEntry(
            "event_page_background",
            await MultipartFile.fromFile(eventPageBackground.path, filename: eventPageBackground.name),
          ),
        );
      }
    }
    if (examTimetable != null) {
      if (examTimetable.bytes != null) {
        form.files.add(
          MapEntry("exam_timetable", MultipartFile.fromBytes(examTimetable.bytes!, filename: examTimetable.name)),
        );
      } else if (examTimetable.path != null && examTimetable.path!.isNotEmpty) {
        form.files.add(
          MapEntry("exam_timetable", await MultipartFile.fromFile(examTimetable.path!, filename: examTimetable.name)),
        );
      }
    }
    final response = await _dio.put(
      "/events/$eventId/admin",
      data: form,
      options: Options(headers: {"Authorization": "Bearer $token"}),
    );
    return Map<String, dynamic>.from(response.data);
  }

  Future<void> deleteAdminEvent(String token, int eventId) async {
    await _dio.delete(
      "/events/$eventId/admin",
      options: Options(headers: {"Authorization": "Bearer $token"}),
    );
  }

  Future<Map<String, dynamic>> setEventTrendingHighlightAdmin(
    String token,
    int eventId, {
    required bool trendingHighlight,
  }) async {
    final response = await _dio.patch(
      "/events/$eventId/admin/trending",
      queryParameters: {"trending_highlight": trendingHighlight},
      options: Options(headers: {"Authorization": "Bearer $token"}),
    );
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<void> unregisterEvent(String token, int eventId) async {
    await _dio.delete(
      "/events/$eventId/register",
      options: Options(headers: {"Authorization": "Bearer $token"}),
    );
  }

  Future<List<dynamic>> getMyRegistrations(String token) async {
    final response = await _dio.get("/registrations/me", options: Options(headers: {"Authorization": "Bearer $token"}));
    return response.data as List<dynamic>;
  }

  Future<List<dynamic>> getCommunities(String token) async {
    final response = await _dio.get("/communities/", options: Options(headers: {"Authorization": "Bearer $token"}));
    return response.data as List<dynamic>;
  }

  Future<List<dynamic>> getMyCommunities(String token) async {
    final response = await _dio.get("/communities/mine", options: Options(headers: {"Authorization": "Bearer $token"}));
    return response.data as List<dynamic>;
  }

  Future<List<dynamic>> getMyModeratingCommunities(String token) async {
    final response = await _dio.get(
      "/communities/moderating/mine",
      options: Options(headers: {"Authorization": "Bearer $token"}),
    );
    return response.data as List<dynamic>;
  }

  Future<List<dynamic>> getFollowingCommunities(String token) async {
    final response = await _dio.get(
      "/communities/following/mine",
      options: Options(headers: {"Authorization": "Bearer $token"}),
    );
    return response.data as List<dynamic>;
  }

  Future<void> followCommunity(String token, int communityId) async {
    await _dio.post(
      "/communities/$communityId/follow",
      options: Options(headers: {"Authorization": "Bearer $token"}),
    );
  }

  Future<void> unfollowCommunity(String token, int communityId) async {
    await _dio.delete(
      "/communities/$communityId/follow",
      options: Options(headers: {"Authorization": "Bearer $token"}),
    );
  }

  Future<void> joinCommunity(String token, int communityId) async {
    await _dio.post(
      "/communities/$communityId/join",
      options: Options(headers: {"Authorization": "Bearer $token"}),
    );
  }

  Future<List<dynamic>> getClubAnnouncements(String token, int clubId) async {
    final response = await _dio.get(
      "/clubs/$clubId/announcements",
      options: Options(headers: {"Authorization": "Bearer $token"}),
    );
    return response.data as List<dynamic>;
  }

  Future<Map<String, dynamic>> createClubAnnouncement(
    String token,
    int clubId, {
    required String title,
    required String description,
    required String priority,
    XFile? image,
  }) async {
    final form = FormData.fromMap({"title": title, "description": description, "priority": priority});
    if (image != null) {
      if (kIsWeb) {
        final bytes = await image.readAsBytes();
        form.files.add(MapEntry("image", MultipartFile.fromBytes(bytes, filename: image.name)));
      } else {
        form.files.add(MapEntry("image", await MultipartFile.fromFile(image.path, filename: image.name)));
      }
    }
    final response = await _dio.post(
      "/clubs/$clubId/announcements",
      data: form,
      options: Options(headers: {"Authorization": "Bearer $token"}),
    );
    return Map<String, dynamic>.from(response.data);
  }

  Future<Map<String, dynamic>> updateClubAnnouncement(
    String token,
    int announcementId, {
    String? title,
    String? description,
    String? priority,
    XFile? image,
  }) async {
    final map = <String, dynamic>{};
    if (title != null) {
      map["title"] = title;
    }
    if (description != null) {
      map["description"] = description;
    }
    if (priority != null) {
      map["priority"] = priority;
    }
    final form = FormData.fromMap(map);
    if (image != null) {
      if (kIsWeb) {
        final bytes = await image.readAsBytes();
        form.files.add(MapEntry("image", MultipartFile.fromBytes(bytes, filename: image.name)));
      } else {
        form.files.add(MapEntry("image", await MultipartFile.fromFile(image.path, filename: image.name)));
      }
    }
    final response = await _dio.put(
      "/announcements/$announcementId",
      data: form,
      options: Options(headers: {"Authorization": "Bearer $token"}),
    );
    return Map<String, dynamic>.from(response.data);
  }

  Future<void> deleteClubAnnouncement(String token, int announcementId) async {
    await _dio.delete(
      "/announcements/$announcementId",
      options: Options(headers: {"Authorization": "Bearer $token"}),
    );
  }

  Future<void> updateCommunityAdmin(
    String token,
    int communityId, {
    String? name,
    String? description,
    XFile? poster,
  }) async {
    final map = <String, dynamic>{};
    if (name != null) {
      map["name"] = name;
    }
    if (description != null) {
      map["description"] = description;
    }
    final form = FormData.fromMap(map);
    if (poster != null) {
      if (kIsWeb) {
        final bytes = await poster.readAsBytes();
        form.files.add(MapEntry("poster", MultipartFile.fromBytes(bytes, filename: poster.name)));
      } else {
        form.files.add(MapEntry("poster", await MultipartFile.fromFile(poster.path, filename: poster.name)));
      }
    }
    await _dio.put(
      "/communities/$communityId/admin",
      data: form,
      options: Options(headers: {"Authorization": "Bearer $token"}),
    );
  }

  Future<void> deleteCommunityAdmin(String token, int communityId) async {
    await _dio.delete(
      "/communities/$communityId/admin",
      options: Options(headers: {"Authorization": "Bearer $token"}),
    );
  }

  Future<void> addCommunityMember(String token, int communityId, int userId) async {
    await _dio.post(
      "/communities/$communityId/members",
      data: {"user_id": userId},
      options: Options(headers: {"Authorization": "Bearer $token"}),
    );
  }

  Future<Map<String, dynamic>> createCommunityAdmin(
    String token, {
    required String name,
    String? description,
  }) async {
    final response = await _dio.post(
      "/communities/",
      data: {"name": name, "description": description},
      options: Options(headers: {"Authorization": "Bearer $token"}),
    );
    return Map<String, dynamic>.from(response.data);
  }

  Future<List<dynamic>> getEventRegistrationsAdmin(String token, int eventId) async {
    final response = await _dio.get(
      "/registrations/event/$eventId",
      options: Options(headers: {"Authorization": "Bearer $token"}),
    );
    return response.data as List<dynamic>;
  }

  Future<Map<String, dynamic>> getUserAdminProfile(String token, int userId) async {
    final response = await _dio.get(
      "/users/$userId/admin-profile",
      options: Options(headers: {"Authorization": "Bearer $token"}),
    );
    return Map<String, dynamic>.from(response.data);
  }

  Future<Map<String, dynamic>> updateMyProfile(
    String token, {
    String? fullName,
    String? bio,
    String? birthDateIso,
    String? phone,
    String? collegeName,
    XFile? profileImage,
  }) async {
    final map = <String, dynamic>{};
    if (fullName != null && fullName.trim().isNotEmpty) {
      map["full_name"] = fullName.trim();
    }
    if (bio != null) {
      map["bio"] = bio;
    }
    if (birthDateIso != null) {
      map["birth_date"] = birthDateIso;
    }
    if (phone != null) {
      map["phone"] = phone;
    }
    if (collegeName != null) {
      map["college_name"] = collegeName;
    }
    final form = FormData.fromMap(map);
    if (profileImage != null) {
      if (kIsWeb) {
        final bytes = await profileImage.readAsBytes();
        form.files.add(MapEntry("profile_image", MultipartFile.fromBytes(bytes, filename: profileImage.name)));
      } else {
        form.files.add(MapEntry("profile_image", await MultipartFile.fromFile(profileImage.path, filename: profileImage.name)));
      }
    }
    final response = await _dio.patch(
      "/users/me/profile",
      data: form,
      options: Options(headers: {"Authorization": "Bearer $token"}),
    );
    return Map<String, dynamic>.from(response.data);
  }

  Future<List<dynamic>> getLostFound(String token) async {
    final response = await _dio.get("/lost-found/", options: Options(headers: {"Authorization": "Bearer $token"}));
    return response.data as List<dynamic>;
  }

  Future<void> cancelLostFound(String token, int itemId) async {
    await _dio.delete("/lost-found/$itemId", options: Options(headers: {"Authorization": "Bearer $token"}));
  }

  Future<void> patchLostFoundStatus(String token, int itemId, bool isFound) async {
    await _dio.patch(
      "/lost-found/$itemId/status",
      queryParameters: {"is_found": isFound},
      options: Options(headers: {"Authorization": "Bearer $token"}),
    );
  }

  Future<List<dynamic>> getLostFoundComments(String token, int itemId) async {
    final response = await _dio.get("/lost-found/$itemId/comments", options: Options(headers: {"Authorization": "Bearer $token"}));
    return response.data as List<dynamic>;
  }

  Future<void> addLostFoundComment(
    String token,
    int itemId, {
    required String finderName,
    required String message,
    String? contact,
  }) async {
    await _dio.post(
      "/lost-found/$itemId/comments",
      data: {"finder_name": finderName, "message": message, "contact": contact},
      options: Options(headers: {"Authorization": "Bearer $token"}),
    );
  }

  Future<void> createLostFound(
    String token,
    String title,
    String description,
    String location,
    XFile? image,
  ) async {
    final form = FormData.fromMap({
      "title": title,
      "description": description,
      "location": location,
    });
    if (image != null) {
      if (kIsWeb) {
        final bytes = await image.readAsBytes();
        form.files.add(
          MapEntry(
            "image",
            MultipartFile.fromBytes(bytes, filename: image.name),
          ),
        );
      } else {
        form.files.add(
          MapEntry(
            "image",
            await MultipartFile.fromFile(image.path, filename: image.name),
          ),
        );
      }
    }
    await _dio.post(
      "/lost-found/",
      data: form,
      options: Options(headers: {"Authorization": "Bearer $token"}),
    );
  }

  Future<List<dynamic>> getNotifications(String token, {int limit = 50}) async {
    final response = await _dio.get(
      "/notifications/",
      queryParameters: {"limit": limit},
      options: Options(headers: {"Authorization": "Bearer $token"}),
    );
    return response.data as List<dynamic>;
  }

  Future<void> markNotificationRead(String token, int notificationId) async {
    await _dio.patch(
      "/notifications/$notificationId/read",
      options: Options(headers: {"Authorization": "Bearer $token"}),
    );
  }

  Future<void> markAllNotificationsRead(String token) async {
    await _dio.put(
      "/notifications/read-all",
      options: Options(headers: {"Authorization": "Bearer $token"}),
    );
  }

  Future<void> deleteNotification(String token, int notificationId) async {
    await _dio.delete(
      "/notifications/$notificationId",
      options: Options(headers: {"Authorization": "Bearer $token"}),
    );
  }

  Future<List<dynamic>> getPolls(String token) async {
    final response = await _dio.get("/polls/", options: Options(headers: {"Authorization": "Bearer $token"}));
    return response.data as List<dynamic>;
  }

  Future<void> createPoll(
    String token, {
    required String question,
    String? description,
    required bool isActive,
    required List<String> options,
  }) async {
    await _dio.post(
      "/polls/",
      data: {
        "question": question,
        "description": description,
        "is_active": isActive,
        "options": options.map((e) => {"label": e}).toList(),
      },
      options: Options(headers: {"Authorization": "Bearer $token"}),
    );
  }

  Future<void> updatePoll(
    String token,
    int pollId, {
    required String question,
    String? description,
    required bool isActive,
    required List<String> options,
  }) async {
    await _dio.put(
      "/polls/$pollId",
      data: {
        "question": question,
        "description": description,
        "is_active": isActive,
        "options": options.map((e) => {"label": e}).toList(),
      },
      options: Options(headers: {"Authorization": "Bearer $token"}),
    );
  }

  Future<void> deletePoll(String token, int pollId) async {
    await _dio.delete("/polls/$pollId", options: Options(headers: {"Authorization": "Bearer $token"}));
  }

  Future<void> votePoll(String token, int pollId, int optionId) async {
    await _dio.post(
      "/polls/$pollId/vote",
      data: {"option_id": optionId},
      options: Options(headers: {"Authorization": "Bearer $token"}),
    );
  }

  Future<int> broadcastNoticeToStudents(
    String token, {
    required String title,
    required String body,
    String priority = "normal",
    String audience = "students",
    String route = "/dashboard",
  }) async {
    final response = await _dio.post(
      "/notifications/broadcast/students",
      data: {
        "title": title,
        "body": body,
        "priority": priority,
        "audience": audience,
        "route": route,
      },
      options: Options(headers: {"Authorization": "Bearer $token"}),
    );
    final data = Map<String, dynamic>.from(response.data as Map);
    final count = data["recipients_notified"] ?? data["students_notified"];
    if (count is int) {
      return count;
    }
    if (count is num) {
      return count.toInt();
    }
    return 0;
  }

  Future<Map<String, dynamic>> me(String token) async {
    final response = await _dio.get("/auth/me", options: Options(headers: {"Authorization": "Bearer $token"}));
    return Map<String, dynamic>.from(response.data);
  }

  Future<void> registerFcmToken(String token, String deviceToken) async {
    await _dio.post(
      "/device-tokens/",
      data: {"token": deviceToken, "platform": "android"},
      options: Options(headers: {"Authorization": "Bearer $token"}),
    );
  }
}
