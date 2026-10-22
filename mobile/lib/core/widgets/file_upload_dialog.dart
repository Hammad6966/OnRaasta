import 'dart:typed_data';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../services/media_service.dart';
import '../../services/profile_service.dart';
import '../../services/auth_service.dart';

typedef UploadFile = Future<void> Function(
    Uint8List, String, String, void Function(int, int));

Future<bool?> showFileUpload(BuildContext context,
        {required String title,
        required UploadFile upload,
        bool pdf = false}) =>
    showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _UploadDialog(title: title, upload: upload, pdf: pdf));

class _UploadDialog extends StatefulWidget {
  const _UploadDialog(
      {required this.title, required this.upload, required this.pdf});
  final String title;
  final UploadFile upload;
  final bool pdf;
  @override
  State<_UploadDialog> createState() => _UploadDialogState();
}

class _UploadDialogState extends State<_UploadDialog> {
  Uint8List? bytes;
  String name = '', mime = '';
  String? error;
  bool busy = false;
  double progress = 0;
  final epoch = AuthService.instance.epoch;
  Future<void> pick(String source) async {
    try {
      Uint8List? data;
      String? filename;
      if (source == 'pdf') {
        final chosen = await FilePicker.pickFiles(
            type: FileType.custom, allowedExtensions: ['pdf']);
        final selected = chosen?.files.single;
        if (selected != null && selected.size > 8 * 1024 * 1024) {
          if (mounted) setState(() => error = 'Choose a file up to 8 MB.');
          return;
        }
        if (selected?.path != null)
          data = await File(selected!.path!).readAsBytes();
        filename = selected?.name;
      } else {
        final chosen = await ImagePicker().pickImage(
            source:
                source == 'camera' ? ImageSource.camera : ImageSource.gallery,
            maxWidth: 2400,
            maxHeight: 2400,
            imageQuality: 90);
        data = await chosen?.readAsBytes();
        filename = chosen?.name;
      }
      if (!mounted || data == null) return;
      final type = uploadMime(data, pdf: widget.pdf);
      if (type == null) {
        setState(() => error =
            'Choose a JPG, PNG or WebP${widget.pdf ? ' or PDF' : ''} up to 8 MB.');
        return;
      }
      setState(() {
        bytes = data;
        name = filename!;
        mime = type;
        error = null;
      });
    } catch (_) {
      if (mounted)
        setState(() => error =
            'Unable to open the picker. Check camera/photos permission and retry.');
    }
  }

  Future<void> save() async {
    if (busy || bytes == null) return;
    if (epoch != AuthService.instance.epoch) {
      Navigator.pop(context, false);
      return;
    }
    setState(() {
      busy = true;
      error = null;
      progress = 0;
    });
    try {
      await widget.upload(bytes!, name, mime, (sent, total) {
        if (mounted) setState(() => progress = total > 0 ? sent / total : 0);
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted)
        setState(() {
          busy = false;
          error = profileError(e);
        });
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
      canPop: !busy,
      child: AlertDialog(
        title: Text(widget.title),
        content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (bytes != null) ...[
            if (mime.startsWith('image/'))
              Image.memory(bytes!,
                  height: 180,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Text(
                      'Image cannot be decoded. Choose another file.'))
            else
              const Icon(Icons.picture_as_pdf_outlined, size: 64),
            const SizedBox(height: 8),
            Text(name),
            Text('${(bytes!.length / 1024).ceil()} KB'),
          ],
          Wrap(spacing: 8, children: [
            TextButton.icon(
                onPressed: busy ? null : () => pick('camera'),
                icon: const Icon(Icons.camera_alt_outlined),
                label: const Text('Camera')),
            TextButton.icon(
                onPressed: busy ? null : () => pick('gallery'),
                icon: const Icon(Icons.photo_outlined),
                label: const Text('Gallery')),
            if (widget.pdf)
              TextButton.icon(
                  onPressed: busy ? null : () => pick('pdf'),
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  label: const Text('PDF')),
          ]),
          if (busy) ...[
            LinearProgressIndicator(value: progress),
            Text(progress < 1
                ? 'Uploading ${(progress * 100).round()}%'
                : 'Saving securely…')
          ],
          if (error != null)
            Text(error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ])),
        actions: [
          TextButton(
              onPressed: busy ? null : () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: busy || bytes == null ? null : save,
              child: Text(error == null ? 'Upload' : 'Retry upload'))
        ],
      ));
}
