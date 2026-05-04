import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:studentboard/providers/app_state.dart';
import 'package:studentboard/widgets/campus_board_logo.dart';
import 'package:studentboard/utils/api_user_message.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _apiUrlCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  bool _registerMode = false;
  bool _busy = false;
  bool _showServerSettings = false;
  bool _obscurePassword = true;
  List<Map<String, String>> _savedLogins = [];
  String? _error;
  /// Self-service signup role: `student` or `faculty` (admins are provisioned separately).
  String _registerRole = "student";

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final app = context.read<AppState>();
      await app.bootstrap();
      if (mounted) {
        final saved = await app.api.loadSavedLoginAccounts();
        setState(() {
          _apiUrlCtrl.text = app.api.currentBaseUrl;
          _savedLogins = saved;
        });
      }
      if (mounted && context.read<AppState>().accessToken != null) {
        context.go("/dashboard");
      }
    });
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _apiUrlCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              cs.surfaceContainerLow,
              cs.primaryContainer.withValues(alpha: 0.4),
              cs.surfaceContainer,
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 430),
                child: Card(
                  margin: EdgeInsets.zero,
                  elevation: 2,
                  shadowColor: cs.shadow.withValues(alpha: 0.12),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const CampusBoardLogoHero(markSize: 52),
                        const SizedBox(height: 12),
                      Text(
                        "API: ${context.watch<AppState>().api.currentBaseUrl}",
                        style: Theme.of(context).textTheme.bodySmall,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 6),
                      InkWell(
                        onTap: () => setState(() => _showServerSettings = !_showServerSettings),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(_showServerSettings ? Icons.expand_less : Icons.expand_more, size: 20),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  _showServerSettings ? "Hide server URL" : "Change server URL (if login fails)",
                                  textAlign: TextAlign.center,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (_showServerSettings) ...[
                        const SizedBox(height: 8),
                        TextField(
                          controller: _apiUrlCtrl,
                          decoration: const InputDecoration(
                            labelText: "API base URL",
                            hintText: "http://192.168.x.x:8010/api/v1",
                            helperText: "Phone: PC LAN IP + backend port. Emulator: http://10.0.2.2:8010/api/v1",
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: _busy
                                    ? null
                                    : () async {
                                        final app = context.read<AppState>();
                                        await app.api.saveBaseUrl(_apiUrlCtrl.text);
                                        app.refreshAfterApiUrlChange();
                                        if (mounted) setState(() => _apiUrlCtrl.text = app.api.currentBaseUrl);
                                      },
                                child: const Text("Save URL"),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: OutlinedButton(
                                onPressed: _busy
                                    ? null
                                    : () async {
                                        final app = context.read<AppState>();
                                        await app.api.clearBaseUrlOverride();
                                        app.refreshAfterApiUrlChange();
                                        if (mounted) setState(() => _apiUrlCtrl.text = app.api.currentBaseUrl);
                                      },
                                child: const Text("Reset default"),
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 14),
                      if (_registerMode) ...[
                        TextField(
                          controller: _nameCtrl,
                          decoration: const InputDecoration(labelText: "Full name"),
                        ),
                        const SizedBox(height: 12),
                        Text("Register as", style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 6),
                        SegmentedButton<String>(
                          segments: const [
                            ButtonSegment<String>(
                              value: "student",
                              label: Text("Student"),
                              icon: Icon(Icons.school_outlined, size: 18),
                            ),
                            ButtonSegment<String>(
                              value: "faculty",
                              label: Text("Faculty / staff"),
                              icon: Icon(Icons.badge_outlined, size: 18),
                            ),
                          ],
                          selected: {_registerRole},
                          onSelectionChanged: _busy
                              ? null
                              : (selection) {
                                  if (selection.isEmpty) return;
                                  setState(() => _registerRole = selection.first);
                                },
                        ),
                        const SizedBox(height: 8),
                        Text(
                          "Choose Student or Faculty for your campus role. Campus IT creates administrator accounts.",
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.black87),
                        ),
                        const SizedBox(height: 10),
                      ],
                      if (!_registerMode && _savedLogins.isNotEmpty) ...[
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            onPressed: () => _openSavedLoginsBottomSheet(context),
                            icon: const Icon(Icons.key_outlined, size: 20),
                            label: Text("Use saved login (${_savedLogins.length})"),
                          ),
                        ),
                        const SizedBox(height: 6),
                      ],
                      TextField(
                        controller: _emailCtrl,
                        decoration: InputDecoration(
                          labelText: "Email",
                          suffixIcon: !_registerMode && _savedLogins.isNotEmpty
                              ? IconButton(
                                  tooltip: "Choose a saved login",
                                  onPressed: () => _openSavedLoginsBottomSheet(context),
                                  icon: const Icon(Icons.vpn_key_rounded),
                                )
                              : null,
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _passwordCtrl,
                        obscureText: _obscurePassword,
                        decoration: InputDecoration(
                          labelText: "Password",
                          suffixIcon: IconButton(
                            tooltip: _obscurePassword ? "Show password" : "Hide password",
                            onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                            icon: Icon(
                              _obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                            ),
                          ),
                        ),
                      ),
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(
                            _error!,
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Theme.of(context).colorScheme.error, height: 1.35),
                          ),
                        ),
                      const SizedBox(height: 14),
                      FilledButton(
                        onPressed: _busy ? null : _submit,
                        child: Text(_registerMode ? "Create account" : "Login"),
                      ),
                      const SizedBox(height: 6),
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => setState(() {
                                  _registerMode = !_registerMode;
                                  if (!_registerMode) {
                                    _registerRole = "student";
                                  }
                                }),
                        child: Text(_registerMode ? "Have an account? Login" : "No account? Register"),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
    );
  }

  Future<void> _submit() async {
    final validation = _validateForm();
    if (validation != null) {
      setState(() => _error = validation);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final app = context.read<AppState>();
    try {
      if (_registerMode) {
        await app.register(
          _nameCtrl.text.trim(),
          _emailCtrl.text.trim(),
          _passwordCtrl.text.trim(),
          role: _registerRole,
        );
      }
      final email = _emailCtrl.text.trim();
      final password = _passwordCtrl.text;
      await app.login(email, password);
      await app.api.saveLoginAccount(email, password);
      if (mounted) {
        final updated = await app.api.loadSavedLoginAccounts();
        setState(() => _savedLogins = updated);
      }
      if (mounted) context.go("/dashboard");
    } catch (err) {
      if (mounted) setState(() => _error = _mapSubmitError(err));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String? _validateForm() {
    if (_registerMode && _nameCtrl.text.trim().isEmpty) {
      return "Please enter your full name.";
    }
    final email = _emailCtrl.text.trim();
    if (email.isEmpty) {
      return "Please enter your email.";
    }
    if (!_looksLikeEmail(email)) {
      return "Please enter a valid email address.";
    }
    if (_passwordCtrl.text.isEmpty) {
      return "Please enter your password.";
    }
    return null;
  }

  static bool _looksLikeEmail(String s) {
    return RegExp(r"^[^\s@]+@[^\s@]+\.[^\s@]+$").hasMatch(s);
  }

  static String _mapSubmitError(Object err) {
    if (err is! DioException) {
      return userMessageFromUnknown(err);
    }
    final e = err;
    if (e.type == DioExceptionType.badResponse && e.response?.statusCode == 404) {
      final fromBody = detailFromResponseData(e.response?.data);
      return fromBody ?? "API not found. The base URL should end with /api/v1.";
    }
    if (e.type == DioExceptionType.connectionError) {
      return "Cannot reach the server. Check that the API is running, the URL is correct "
          "(emulator: http://10.0.2.2:8010/api/v1), and on a phone use your PC's Wi-Fi IP, not 127.0.0.1.";
    }
    if (e.type == DioExceptionType.badResponse && e.response?.statusCode == 401) {
      final fromBody = detailFromResponseData(e.response?.data);
      return fromBody ?? "Invalid email or password.";
    }
    return mapDioToUserMessage(e);
  }

  Future<void> _openSavedLoginsBottomSheet(BuildContext context) async {
    if (_savedLogins.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No saved logins yet. Sign in once to save this device.")),
      );
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black54,
      builder: (sheetContext) {
        return _SavedLoginsBottomSheet(
          accounts: _savedLogins,
          onPick: (email, password) {
            setState(() {
              _emailCtrl.text = email;
              _passwordCtrl.text = password;
              _obscurePassword = true;
            });
            Navigator.of(sheetContext).pop();
          },
        );
      },
    );
  }
}

/// Google Password Manager–style picker: dark sheet, rounded top, list of saved accounts.
class _SavedLoginsBottomSheet extends StatelessWidget {
  const _SavedLoginsBottomSheet({
    required this.accounts,
    required this.onPick,
  });

  final List<Map<String, String>> accounts;
  final void Function(String email, String password) onPick;

  static const _sheetBg = Color(0xFF2B2B2D);
  static const _listBg = Color(0xFF3A3A3C);
  static const _divider = Color(0xFF505050);

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(top: MediaQuery.sizeOf(context).height * 0.12),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          color: _sheetBg,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 4, 0),
                child: Row(
                  children: [
                    const Spacer(),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close, color: Colors.white70),
                      tooltip: "Close",
                    ),
                  ],
                ),
              ),
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.school_rounded, size: 28, color: Theme.of(context).colorScheme.primary),
              ),
              const SizedBox(height: 10),
              Text(
                "Campus Board",
                style: TextStyle(
                  color: Colors.grey.shade400,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  "Choose a saved password for\nIntelligent Campus Highlight Board",
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    height: 1.25,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: _listBg,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var index = 0; index < accounts.length; index++) ...[
                        if (index > 0) const Divider(height: 1, color: _divider, indent: 56),
                        Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () {
                              final row = accounts[index];
                              onPick(row["email"] ?? "", row["password"] ?? "");
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                              child: Row(
                                children: [
                                  Icon(Icons.lock_outline, color: Colors.grey.shade300, size: 26),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          "Campus Board account",
                                          style: TextStyle(
                                            color: Colors.grey.shade400,
                                            fontSize: 13,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          accounts[index]["email"] ?? "",
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Icon(Icons.chevron_right, color: Colors.grey.shade500),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: EdgeInsets.fromLTRB(20, 0, 20, 16 + bottomInset),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(
                      "Cancel",
                      style: TextStyle(color: Colors.blue.shade200, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
