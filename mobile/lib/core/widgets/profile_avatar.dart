import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../services/media_service.dart';
import '../../services/auth_service.dart';
import 'file_upload_dialog.dart';

class ProfileAvatar extends StatefulWidget {
  const ProfileAvatar(
      {super.key,
      required this.userId,
      this.revision,
      this.name = '',
      this.radius = 40,
      this.onChanged});
  final String? userId;
  final Object? revision;
  final String name;
  final double radius;
  final Future<void> Function()? onChanged;
  @override
  State<ProfileAvatar> createState() => _ProfileAvatarState();
}

class _ProfileAvatarState extends State<ProfileAvatar> {
  Future<Uint8List>? image;
  int epoch = AuthService.instance.epoch;
  @override
  void initState() {
    super.initState();
    load();
    AuthService.instance.addListener(sessionChanged);
  }

  void sessionChanged() {
    if (mounted && epoch != AuthService.instance.epoch) {
      epoch = AuthService.instance.epoch;
      setState(() => image = null);
    }
  }

  @override
  void dispose() {
    AuthService.instance.removeListener(sessionChanged);
    super.dispose();
  }

  @override
  void didUpdateWidget(ProfileAvatar old) {
    super.didUpdateWidget(old);
    if (old.userId != widget.userId || old.revision != widget.revision) load();
  }

  void load() {
    image = widget.userId != null && widget.revision != null
        ? MediaService.instance.bytes('/users/${widget.userId}/photo')
        : null;
  }

  Future<void> edit() async {
    final saved = await showFileUpload(context, title: 'Profile photo',
        upload: (bytes, name, mime, progress) async {
      await MediaService.instance
          .upload('/users/photo', bytes, name, mime, progress);
    });
    if (saved == true && mounted) await widget.onChanged?.call();
  }

  @override
  Widget build(BuildContext context) =>
      Stack(clipBehavior: Clip.none, children: [
        FutureBuilder<Uint8List>(
            future: image,
            builder: (_, result) => CircleAvatar(
                  radius: widget.radius,
                  backgroundColor: const Color(0xFF0F2040),
                  backgroundImage:
                      result.hasData ? MemoryImage(result.data!) : null,
                  child: result.hasData
                      ? null
                      : Text(
                          widget.name.trim().isEmpty
                              ? '?'
                              : widget.name.trim()[0].toUpperCase(),
                          style: TextStyle(
                              fontSize: widget.radius * .65,
                              color: Colors.white)),
                )),
        if (widget.onChanged != null)
          Positioned(
              bottom: -4,
              right: -4,
              child: IconButton.filled(
                  tooltip: 'Change profile photo',
                  style: IconButton.styleFrom(
                      backgroundColor: const Color(0xFFF97316)),
                  onPressed: widget.userId == null ? null : edit,
                  icon: const Icon(Icons.camera_alt_outlined, size: 20))),
      ]);
}
