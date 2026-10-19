import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../../services/auth_service.dart';

// Keep the dialog and its input alive until persistence succeeds.
Future<bool?> editProfileFields(BuildContext context,
        {required String title,
        required Map<String, String> values,
        required Future<String?> Function(Map<String, String>) save}) =>
    showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) =>
            _ProfileDialog(title: title, values: values, save: save));

class _ProfileDialog extends StatefulWidget {
  const _ProfileDialog(
      {required this.title, required this.values, required this.save});
  final String title;
  final Map<String, String> values;
  final Future<String?> Function(Map<String, String>) save;
  @override
  State<_ProfileDialog> createState() => _ProfileDialogState();
}

class _ProfileDialogState extends State<_ProfileDialog> {
  late final fields =
      widget.values.map((k, v) => MapEntry(k, TextEditingController(text: v)));
  late final int epoch;
  @override
  void initState() {
    super.initState();
    epoch = AuthService.instance.epoch;
    AuthService.instance.addListener(_sessionChanged);
  }

  bool _closing = false;
  void _sessionChanged() {
    if (mounted &&
        !_closing &&
        (epoch != AuthService.instance.epoch ||
            AuthService.instance.isClearing)) {
      _closing = true;
      Navigator.of(context).pop(false);
    }
  }

  bool pending = false;
  String? error;
  @override
  void dispose() {
    AuthService.instance.removeListener(_sessionChanged);
    for (final c in fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> submit() async {
    if (pending) return;
    setState(() {
      pending = true;
      error = null;
    });
    final message =
        await widget.save(fields.map((k, v) => MapEntry(k, v.text.trim())));
    if (!mounted) return;
    if (message == null) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      pending = false;
      error = message;
    });
  }

  @override
  Widget build(BuildContext context) => PopScope(
      canPop: !pending,
      child: AlertDialog(
        backgroundColor: AppColors.darkSurface,
        title: Text(widget.title),
        content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final entry in fields.entries)
            TextField(
                enabled: !pending,
                controller: entry.value,
                decoration: InputDecoration(labelText: entry.key)),
          if (error != null)
            Text(error!, style: const TextStyle(color: AppColors.darkError)),
        ])),
        actions: [
          TextButton(
              onPressed: pending ? null : () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: pending ? null : submit,
              child: Text(pending ? 'Saving...' : 'Save'))
        ],
      ));
}
