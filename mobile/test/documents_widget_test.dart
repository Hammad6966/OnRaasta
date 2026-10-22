import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onraasta/features/mechanic/document_upload_screen.dart';
import 'package:onraasta/services/media_service.dart';

class FakeMedia extends MediaService {
  bool fail = false;
  int submissions = 0;
  Map<String, dynamic> value = {
    'expectedVersion': 3,
    'status': 'draft',
    'revision': 3,
    'files': [
      {
        'kind': 'cnic_front',
        'fileId': 'front',
        'name': 'cnic.jpg',
        'mime': 'image/jpeg'
      }
    ]
  };
  @override
  Future<Map<String, dynamic>> documents() async {
    if (fail) throw Exception('offline');
    return value;
  }

  @override
  Future<Map<String, dynamic>> submit(Map<String, dynamic> body) async {
    submissions++;
    expect(body['expectedVersion'], 3);
    return {...value, 'status': 'submitted', 'expectedVersion': 4};
  }
}

void main() {
  test('upload validation checks supported signatures and size', () {
    expect(uploadMime(Uint8List.fromList(List.filled(15, 0))), isNull);
    final pdf = Uint8List.fromList('%PDF-1.7\n%%EOF'.codeUnits);
    expect(uploadMime(pdf), isNull);
    expect(uploadMime(pdf, pdf: true), 'application/pdf');
    expect(uploadMime(Uint8List(8 * 1024 * 1024 + 1)), isNull);
  });
  for (final scale in [1.0, 1.6]) {
    testWidgets('documents remain scrollable at 320px and text scale $scale',
        (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final service = FakeMedia();
      await tester.pumpWidget(MaterialApp(
          builder: (_, child) => MediaQuery(
              data: MediaQueryData(
                  size: const Size(320, 640),
                  textScaler: TextScaler.linear(scale)),
              child: child!),
          home: DocumentUploadScreen(service: service)));
      await tester.pumpAndSettle();
      expect(find.text('Document status: DRAFT'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Mechanic Certificate'), 220);
      await tester.scrollUntilVisible(find.text('Submit for review'), 220);
      await tester.tap(find.text('Submit for review'));
      await tester.pumpAndSettle();
      expect(service.submissions, 1);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('document error offers retry and recovers real state',
      (tester) async {
    final service = FakeMedia()..fail = true;
    await tester
        .pumpWidget(MaterialApp(home: DocumentUploadScreen(service: service)));
    await tester.pumpAndSettle();
    expect(find.text('Reload documents'), findsOneWidget);
    service.fail = false;
    await tester.tap(find.text('Reload documents'));
    await tester.pumpAndSettle();
    expect(find.text('Document status: DRAFT'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
