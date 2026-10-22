import 'dart:io';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import '../../core/widgets/file_upload_dialog.dart';
import '../../core/widgets/onraasta_card.dart';
import '../../models/bid_model.dart';
import '../../services/media_service.dart';
import '../../services/profile_service.dart';
import '../../services/auth_service.dart';

class DocumentUploadScreen extends StatefulWidget {
  const DocumentUploadScreen({super.key, this.service});
  final MediaService? service;
  @override
  State<DocumentUploadScreen> createState() => _DocumentUploadScreenState();
}

class _DocumentUploadScreenState extends State<DocumentUploadScreen> {
  late final service = widget.service ?? MediaService.instance;
  final permit = TextEditingController();
  Map<String, dynamic>? data;
  String? error;
  bool loading = true, saving = false, license = false, workshop = false;
  final epoch = AuthService.instance.epoch;
  bool get current => mounted && epoch == AuthService.instance.epoch;
  static const labels = {
    'cnic_front': 'CNIC Front',
    'cnic_back': 'CNIC Back',
    'license': 'Driving License',
    'certificate': 'Mechanic Certificate',
    'workshop': 'Workshop Permit'
  };
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    permit.dispose();
    super.dispose();
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final result = await service.documents();
      if (!current) return;
      setState(() {
        data = result;
        license = result['licenseApplicable'] == true;
        workshop = result['workshopApplicable'] == true;
        permit.text = result['permitNumber'] as String? ?? '';
      });
    } catch (e) {
      if (current) setState(() => error = profileError(e));
    } finally {
      if (current) setState(() => loading = false);
    }
  }

  Future<void> upload(String kind) async {
    await showFileUpload(context,
        title: labels[kind]!, pdf: !kind.startsWith('cnic'),
        upload: (bytes, name, mime, progress) async {
      final result = await service.upload(
          '/mechanics/documents/$kind', bytes, name, mime, progress,
          expectedVersion: data!['expectedVersion'] as int);
      if (current) setState(() => data = result);
    });
  }

  Future<void> preview(Map<String, dynamic> file) async {
    try {
      final bytes =
          await service.bytes('/mechanics/documents/files/${file['fileId']}');
      if (!current) return;
      if (file['mime'] == 'application/pdf') {
        final dir = await getTemporaryDirectory();
        if (!current) return;
        final local =
            File('${dir.path}/onraasta-document-${file['fileId']}.pdf');
        await local.writeAsBytes(bytes, flush: true);
        final result = await OpenFilex.open(local.path);
        if (result.type != ResultType.done) throw StateError(result.message);
      } else {
        await showDialog<void>(
            context: context,
            builder: (c) => Dialog(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Flexible(
                      child: InteractiveViewer(
                          child: Image.memory(bytes, fit: BoxFit.contain))),
                  TextButton(
                      onPressed: () => Navigator.pop(c),
                      child: const Text('Close preview')),
                ])));
      }
    } catch (_) {
      if (current)
        setState(() => error =
            'Unable to open document. Retry; PDFs need an installed PDF viewer.');
    }
  }

  Future<void> submit() async {
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final result = await service.submit({
        'expectedVersion': data!['expectedVersion'],
        'licenseApplicable': license,
        'workshopApplicable': workshop,
        'permitNumber': permit.text.trim()
      });
      if (current) setState(() => data = result);
      if (current)
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Documents submitted for review.')));
    } catch (e) {
      if (current) setState(() => error = profileError(e));
    } finally {
      if (current) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = data?['status'] as String? ?? 'draft';
    final files = (data?['files'] as List? ?? []).map(objectMap).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Verify Your Account')),
      body: SafeArea(
          child: RefreshIndicator(
              onRefresh: load,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Text('Upload Documents',
                      style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 8),
                  const Text(
                      'Upload clear documents for identity and qualification review. Account approval is a separate decision.'),
                  const SizedBox(height: 20),
                  if (loading) const LinearProgressIndicator(),
                  if (error != null) ...[
                    Text(error!,
                        style: const TextStyle(color: Color(0xFFEF4444))),
                    TextButton(
                        onPressed: load, child: const Text('Reload documents'))
                  ],
                  if (data != null) ...[
                    OnRaastaCard(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Text('Document status: ${status.toUpperCase()}',
                              style: TextStyle(
                                  color: status == 'verified'
                                      ? const Color(0xFF22C55E)
                                      : const Color(0xFFF59E0B),
                                  fontWeight: FontWeight.w600)),
                          if ((data!['reason'] as String? ?? '').isNotEmpty)
                            Text(data!['reason'] as String),
                          if (status == 'submitted')
                            const Text(
                                'Your submission is awaiting an administrator review.'),
                        ])),
                    const SizedBox(height: 12),
                    SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Driving license applies'),
                        subtitle: const Text(
                            'Required if driving as part of your service.'),
                        value: license,
                        onChanged:
                            saving ? null : (v) => setState(() => license = v)),
                    SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('I operate a registered workshop'),
                        subtitle: const Text(
                            'Upload its permit and registration number.'),
                        value: workshop,
                        onChanged: saving
                            ? null
                            : (v) => setState(() => workshop = v)),
                    for (final entry in labels.entries) ...[
                      Builder(builder: (context) {
                        final matches =
                            files.where((f) => f['kind'] == entry.key);
                        final file = matches.isEmpty ? null : matches.first;
                        final required = entry.key.startsWith('cnic') ||
                            entry.key == 'certificate' ||
                            entry.key == 'license' && license ||
                            entry.key == 'workshop' && workshop;
                        return OnRaastaCard(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                              Row(children: [
                                Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                        color: const Color(0x1A2563EB),
                                        borderRadius:
                                            BorderRadius.circular(12)),
                                    child: Icon(
                                        entry.key == 'workshop'
                                            ? Icons.storefront_outlined
                                            : entry.key == 'certificate'
                                                ? Icons
                                                    .workspace_premium_outlined
                                                : Icons.badge_outlined,
                                        color: const Color(0xFF60A5FA))),
                                const SizedBox(width: 12),
                                Expanded(
                                    child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                      Text(entry.value,
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleSmall),
                                      Text(
                                          required
                                              ? 'Required'
                                              : 'Where applicable',
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall)
                                    ]))
                              ]),
                              const SizedBox(height: 12),
                              if (file != null)
                                Text(
                                    file['name'] as String? ??
                                        'Uploaded document',
                                    overflow: TextOverflow.ellipsis),
                              Wrap(spacing: 8, children: [
                                OutlinedButton.icon(
                                    onPressed: saving || loading
                                        ? null
                                        : () => upload(entry.key),
                                    icon:
                                        const Icon(Icons.cloud_upload_outlined),
                                    label: Text(file == null
                                        ? 'Upload document'
                                        : 'Replace document')),
                                if (file != null)
                                  TextButton(
                                      onPressed: () => preview(file),
                                      child: const Text('Preview'))
                              ]),
                            ]));
                      }),
                      const SizedBox(height: 12),
                    ],
                    if (workshop)
                      TextField(
                          controller: permit,
                          maxLength: 80,
                          decoration: const InputDecoration(
                              labelText: 'Workshop permit number')),
                    const SizedBox(height: 16),
                    const OnRaastaCard(
                        child: Text(
                            'Verification Info\nJPG, PNG, WebP up to 8 MB. Qualification, license and permit also accept PDF. Replacing a document creates a draft which must be submitted again.')),
                    const SizedBox(height: 20),
                    FilledButton(
                        onPressed: saving ||
                                loading ||
                                !['draft', 'rejected'].contains(status)
                            ? null
                            : submit,
                        child: Text(saving
                            ? 'Submitting…'
                            : status == 'rejected'
                                ? 'Resubmit documents'
                                : 'Submit for review')),
                    if (data!['history'] is List &&
                        (data!['history'] as List).isNotEmpty) ...[
                      const SizedBox(height: 20),
                      Text('Review history',
                          style: Theme.of(context).textTheme.titleMedium),
                      for (final raw in data!['history'] as List)
                        ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                                '${objectMap(raw)['action']} · Revision ${objectMap(raw)['revision']}'),
                            subtitle: Text(
                                '${objectMap(raw)['reason'] ?? ''}\n${objectMap(raw)['createdAt'] ?? ''}')),
                    ],
                  ],
                ],
              ))),
    );
  }
}
