import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_colors.dart';
import '../../models/bid_model.dart';
import '../../models/booking_arguments.dart';
import '../../services/assignment_service.dart';
import '../../services/auth_service.dart';
import '../../services/job_chat_service.dart';
import '../../services/job_contact_service.dart';
import '../../services/socket_service.dart';

class JobChatScreen extends StatefulWidget {
  final AcceptedBooking booking;
  final bool mechanic;
  const JobChatScreen(
      {super.key, required this.booking, required this.mechanic});

  @override
  State<JobChatScreen> createState() => _JobChatScreenState();
}

class _JobChatScreenState extends State<JobChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _service = JobChatService();
  final _socket = SocketService();
  final Map<String, JobMessage> _messages = {};
  String? _before, _senderId, _error, _contactName, _contactPhone;
  bool _loading = true, _olderLoading = false, _sending = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _socket.on('chat:new', _received);
    _socket.on('connect', _connected);
    _open();
  }

  void _received(dynamic data) {
    try {
      final message = JobMessage.fromJson(data);
      if (message.jobId == widget.booking.jobId && mounted) {
        setState(() => _messages[message.id] = message);
        _scrollBottom();
      }
    } catch (_) {/* Ignore malformed transport events. */}
  }

  void _connected(dynamic _) {
    _refresh();
  }

  Future<void> _open() async {
    try {
      final booking =
          await AssignmentService.instance.load(widget.booking.jobId);
      final token = await AuthService.instance.accessToken();
      if (token == null) throw const FormatException('Please sign in again.');
      await _socket.ensureConnected(token);
      if (!mounted) return;
      _senderId = widget.mechanic
          ? booking.bid.mechanicUserId
          : objectId(booking.driver['_id']);
      _contactName = widget.mechanic
          ? textValue(booking.driver['name'])
          : booking.bid.mechanicName;
      _contactPhone = widget.mechanic
          ? textValue(booking.driver['phone'])
          : booking.bid.mechanicPhone;
      if (_senderId == null)
        throw const FormatException('Conversation identity unavailable.');
      await _refresh();
    } catch (error) {
      if (mounted)
        setState(() {
          _loading = false;
          _error = _message(error);
        });
    }
  }

  Future<void> _refresh() async {
    if (_senderId == null) return;
    final generation = ++_generation;
    try {
      final page = await _service.load(widget.booking.jobId);
      if (!mounted || generation != _generation) return;
      setState(() {
        for (final item in page.messages) {
          _messages[item.id] = item;
        }
        _before = page.nextBefore;
        _loading = false;
        _error = null;
      });
      _scrollBottom();
    } catch (error) {
      if (mounted && generation == _generation)
        setState(() {
          _loading = false;
          _error = _message(error);
        });
    }
  }

  Future<void> _loadOlder() async {
    final before = _before;
    if (before == null || _olderLoading) return;
    setState(() => _olderLoading = true);
    try {
      final page = await _service.load(widget.booking.jobId, before: before);
      if (!mounted) return;
      setState(() {
        for (final item in page.messages) {
          _messages[item.id] = item;
        }
        _before = page.nextBefore;
        _error = null;
      });
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _olderLoading = false);
    }
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || text.length > 2000 || _sending || _senderId == null)
      return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final saved = await _service.send(widget.booking.jobId, text);
      if (!mounted) return;
      setState(() {
        _messages[saved.id] = saved;
        _input.clear();
      });
      _scrollBottom();
    } catch (error) {
      if (mounted) {
        setState(() => _error = _message(error));
        await _refresh(); // An ambiguous timeout may have saved the message.
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  String _message(Object error) => error is AssignmentFailure
      ? error.message
      : 'Could not reach the conversation. Check your connection and retry.';

  void _scrollBottom() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients)
          _scroll.animateTo(_scroll.position.maxScrollExtent,
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut);
      });

  @override
  void dispose() {
    _socket.off('chat:new', _received);
    _socket.off('connect', _connected);
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final messages = _messages.values.toList()
      ..sort((a, b) {
        final time = a.createdAt.compareTo(b.createdAt);
        return time != 0 ? time : a.id.compareTo(b.id);
      });
    final fallbackName = widget.mechanic
        ? textValue(widget.booking.driver['name'])
        : widget.booking.bid.mechanicName;
    return Scaffold(
      backgroundColor: AppColors.darkBg,
      appBar: AppBar(
          title:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_contactName ?? fallbackName ?? 'Job chat'),
            if (_contactPhone != null)
              Text(_contactPhone!,
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.darkTextSecondary)),
          ]),
          actions: [
            IconButton(
                tooltip: 'Call contact',
                onPressed: _senderId == null
                    ? null
                    : () => callAssignedPerson(context, widget.booking,
                        mechanic: widget.mechanic),
                icon: const Icon(Icons.phone_rounded))
          ],
          backgroundColor: AppColors.darkSurface,
          foregroundColor: Colors.white),
      body: SafeArea(
          child: Column(children: [
        if (_error != null)
          MaterialBanner(content: Text(_error!), actions: [
            TextButton(onPressed: _open, child: const Text('Retry'))
          ]),
        Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : messages.isEmpty
                    ? const Center(
                        child: Text('No messages yet',
                            style:
                                TextStyle(color: AppColors.darkTextSecondary)))
                    : ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.all(16),
                        itemCount: messages.length + (_before != null ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (_before != null && index == 0)
                            return TextButton(
                                onPressed: _olderLoading ? null : _loadOlder,
                                child: Text(_olderLoading
                                    ? 'Loading…'
                                    : 'Load earlier messages'));
                          final message =
                              messages[index - (_before != null ? 1 : 0)];
                          final mine = message.senderId == _senderId;
                          return Align(
                            alignment: mine
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                            child: Container(
                              constraints: BoxConstraints(
                                  maxWidth:
                                      MediaQuery.sizeOf(context).width * .78),
                              margin: const EdgeInsets.only(bottom: 10),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                  color: mine
                                      ? AppColors.darkPrimary
                                      : AppColors.darkSurface,
                                  borderRadius: BorderRadius.circular(16),
                                  border: mine
                                      ? null
                                      : Border.all(
                                          color: AppColors.darkBorder)),
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(message.text,
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontFamily: 'DM Sans')),
                                    const SizedBox(height: 4),
                                    Text(
                                        DateFormat('d MMM, h:mm a').format(
                                            message.createdAt.toLocal()),
                                        style: const TextStyle(
                                            color: AppColors.darkTextSecondary,
                                            fontSize: 11)),
                                  ]),
                            ),
                          );
                        })),
        Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              Expanded(
                  child: TextField(
                      controller: _input,
                      maxLength: 2000,
                      maxLines: 4,
                      minLines: 1,
                      enabled: !_loading && _senderId != null,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                          hintText: 'Message',
                          counterText: '',
                          filled: true,
                          fillColor: AppColors.darkSurface,
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(20))))),
              IconButton(
                  tooltip: 'Send message',
                  onPressed: _sending || _loading || _senderId == null ? null : _send,
                  icon: const Icon(Icons.send_rounded,
                      color: AppColors.darkPrimary)),
            ])),
      ])),
    );
  }
}
