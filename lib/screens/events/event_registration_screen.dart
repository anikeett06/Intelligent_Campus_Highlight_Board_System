import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:studentboard/providers/app_state.dart';
import 'package:studentboard/utils/json_helpers.dart';
import 'package:studentboard/widgets/campus_refresh.dart';

class EventRegistrationScreen extends StatefulWidget {
  const EventRegistrationScreen({super.key, required this.eventId});

  final int eventId;

  @override
  State<EventRegistrationScreen> createState() => _EventRegistrationScreenState();
}

class _EventRegistrationScreenState extends State<EventRegistrationScreen> {
  final _participantName = TextEditingController();
  final _rollNo = TextEditingController();
  final _branch = TextEditingController();
  final _collegeName = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  bool _busy = false;
  String? _eventTitle;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final app = context.read<AppState>();
      if (widget.eventId <= 0) {
        return;
      }
      for (final ev in app.events) {
        final m = ev as Map<String, dynamic>;
        if (eventIdFromJson(m) == widget.eventId) {
          _eventTitle = m["title"]?.toString();
          break;
        }
      }
      final existing = app.myRegistrationForEvent(widget.eventId);
      if (existing != null) {
        _participantName.text = existing["participant_name"]?.toString() ?? "";
        _rollNo.text = existing["roll_no"]?.toString() ?? "";
        _branch.text = existing["branch"]?.toString() ?? "";
        _collegeName.text = existing["college_name"]?.toString() ?? "";
        _phone.text = existing["phone"]?.toString() ?? "";
        _email.text = existing["email"]?.toString() ?? "";
      } else {
        final p = app.profile;
        _participantName.text = p?["full_name"]?.toString() ?? "";
        _email.text = p?["email"]?.toString() ?? "";
      }
      setState(() {});
    });
  }

  Future<void> _onPullRefresh() async {
    await context.read<AppState>().loadAll();
    if (!mounted || widget.eventId <= 0) {
      return;
    }
    final app = context.read<AppState>();
    for (final ev in app.events) {
      final m = ev as Map<String, dynamic>;
      if (eventIdFromJson(m) == widget.eventId) {
        _eventTitle = m["title"]?.toString();
        break;
      }
    }
    final existing = app.myRegistrationForEvent(widget.eventId);
    if (existing != null) {
      _participantName.text = existing["participant_name"]?.toString() ?? "";
      _rollNo.text = existing["roll_no"]?.toString() ?? "";
      _branch.text = existing["branch"]?.toString() ?? "";
      _collegeName.text = existing["college_name"]?.toString() ?? "";
      _phone.text = existing["phone"]?.toString() ?? "";
      _email.text = existing["email"]?.toString() ?? "";
    } else {
      final p = app.profile;
      _participantName.text = p?["full_name"]?.toString() ?? "";
      _email.text = p?["email"]?.toString() ?? "";
    }
    setState(() {});
  }

  @override
  void dispose() {
    _participantName.dispose();
    _rollNo.dispose();
    _branch.dispose();
    _collegeName.dispose();
    _phone.dispose();
    _email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.eventId <= 0) {
      return Scaffold(
        appBar: AppBar(title: const Text("Invalid event")),
        body: const Center(child: Text("Missing or invalid event id.")),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_eventTitle ?? "Event registration"),
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()),
      ),
      body: CampusRefreshIndicator(
        onRefresh: _onPullRefresh,
        child: ListView(
          physics: kCampusPullToRefreshPhysics,
          padding: const EdgeInsets.all(16),
          children: [
          if (_eventTitle != null) Text(_eventTitle!, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),
          TextField(controller: _participantName, decoration: const InputDecoration(labelText: "Full name")),
          TextField(controller: _rollNo, decoration: const InputDecoration(labelText: "Roll number")),
          TextField(controller: _branch, decoration: const InputDecoration(labelText: "Branch")),
          TextField(controller: _collegeName, decoration: const InputDecoration(labelText: "College name")),
          TextField(controller: _phone, decoration: const InputDecoration(labelText: "Phone number"), keyboardType: TextInputType.phone),
          TextField(controller: _email, decoration: const InputDecoration(labelText: "Email"), keyboardType: TextInputType.emailAddress),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: Text(context.watch<AppState>().isRegisteredForEvent(widget.eventId) ? "Save registration" : "Submit registration"),
          ),
          const SizedBox(height: 10),
          if (context.watch<AppState>().isRegisteredForEvent(widget.eventId))
            OutlinedButton(
              onPressed: _busy
                  ? null
                  : () async {
                      setState(() => _busy = true);
                      final messenger = ScaffoldMessenger.of(context);
                      final router = GoRouter.of(context);
                      final app = context.read<AppState>();
                      final err = await app.cancelEventRegistration(widget.eventId);
                      if (!mounted) {
                        return;
                      }
                      setState(() => _busy = false);
                      messenger.showSnackBar(SnackBar(content: Text(err ?? "Registration cancelled.")));
                      if (err == null) {
                        router.pop();
                      }
                    },
              child: const Text("Cancel registration"),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit() async {
    final name = _participantName.text.trim();
    final roll = _rollNo.text.trim();
    final branch = _branch.text.trim();
    final college = _collegeName.text.trim();
    final phone = _phone.text.trim();
    final email = _email.text.trim();
    if (name.isEmpty || roll.isEmpty || branch.isEmpty || college.isEmpty || phone.isEmpty || email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please fill all fields.")));
      return;
    }
    setState(() => _busy = true);
    final app = context.read<AppState>();
    final err = await app.submitEventRegistration(
      eventId: widget.eventId,
      participantName: name,
      rollNo: roll,
      branch: branch,
      collegeName: college,
      phone: phone,
      email: email,
    );
    if (!mounted) {
      return;
    }
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err ?? "Registration saved.")));
    if (err == null) {
      context.pop();
    }
  }
}
