import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onraasta/models/history_models.dart';
import 'package:onraasta/providers/history_controller.dart';
import 'package:onraasta/services/history_service.dart';
import 'package:onraasta/services/auth_service.dart';
import 'package:onraasta/features/user/job_history_screen.dart';
import 'package:onraasta/features/mechanic/mechanic_earnings_screen.dart';
import 'presence_fixtures.dart';
import 'bidding_fixtures.dart';

Map<String, dynamic> saved(
        {String id = 'job-1',
        String status = 'completed',
        bool priced = true}) =>
    {
      '_id': id,
      'status': status,
      'description': 'Actual saved repair',
      'createdAt': '2026-01-01T10:00:00Z',
      'completedAt': '2026-01-02T10:00:00Z',
      'mechanic': {'_id': 'mechanic-1', 'name': 'Persisted Mechanic'},
      'pricingStatus': priced ? 'booked' : 'unavailable',
      if (priced)
        'pricing': {
          'totalMinor': 100000,
          'labourMinor': 80000,
          'partsMinor': 20000,
          'commissionMinor': 15000,
          'netMinor': 85000
        },
    };
Map<String, dynamic> totals({bool empty = false, bool unknown = false}) => {
      'completedJobs': empty ? 0 : 1,
      'pricedJobs': empty || unknown ? 0 : 1,
      'unpricedJobs': unknown ? 1 : 0,
      'grossMinor': empty || unknown ? '0' : '100000',
      'commissionMinor': empty || unknown ? '0' : '15000',
      'netMinor': empty || unknown ? '0' : '85000',
      'months': empty
          ? []
          : [
              {
                'month': '2026-01',
                'completedJobs': 1,
                'pricedJobs': unknown ? 0 : 1,
                'unpricedJobs': unknown ? 1 : 0,
                'netMinor': unknown ? '0' : '85000'
              }
            ],
    };
HistoryPage page(
        {List<Map<String, dynamic>>? rows,
        int number = 1,
        bool more = false,
        bool empty = false,
        bool unknown = false}) =>
    HistoryPage(
        jobs: (rows ?? (empty ? [] : [saved(priced: !unknown)]))
            .map(HistoryJob.new)
            .toList(),
        page: number,
        hasMore: more,
        summary: totals(empty: empty, unknown: unknown));

class Histories extends HistoryService {
  HistoryPage result = page();
  final calls = <Map<String, dynamic>>[];
  final detailIds = <String>[];
  Future<HistoryPage> Function(int)? read;
  @override
  Future<HistoryPage> fetch(
      {bool mechanic = false,
      bool earnings = false,
      int page = 1,
      String? status,
      String? from,
      String? to}) async {
    calls.add({
      'page': page,
      'mechanic': mechanic,
      'earnings': earnings,
      'status': status,
      'from': from,
      'to': to
    });
    return read == null ? result : await read!(page);
  }

  @override
  Future<Map<String, dynamic>> detail(String id) async {
    detailIds.add(id);
    return saved(id: id)..['accounting'] = {'totalMinor': 100000};
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Histories service;
  late AuthService auth;
  late FakePresenceSocket socket;
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    service = Histories();
    auth = AuthService.forTesting(Dio());
    socket = FakePresenceSocket();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', (message) async {
      final name = utf8.decode(message!.buffer.asUint8List());
      if (name == 'AssetManifest.bin') {
        return const StandardMessageCodec().encodeMessage({
          for (final font in [
            'DMSans-Regular.ttf',
            'DMSans-Medium.ttf',
            'DMSans-SemiBold.ttf',
            'Syne-Bold.ttf',
            'Syne-SemiBold.ttf'
          ])
            font: [
              {'asset': font}
            ]
        });
      }
      return ByteData(0);
    });
  });
  tearDown(() {
    auth.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', null);
  });
  HistoryController controller(
          {bool mechanic = false, bool earnings = false}) =>
      HistoryController(
          service: service,
          auth: auth,
          socket: socket,
          mechanic: mechanic,
          earnings: earnings);
  test(
      'currency formatting uses integer paisa and never silently substitutes zero',
      () {
    expect(pkr(110075), 'PKR 1,100.75');
    expect(pkr('85000'), 'PKR 850.00');
    expect(pkr('100000000000000000000'), 'PKR 1,000,000,000,000,000,000.00');
    expect(pkr(0), 'PKR 0.00');
    for (final value in [null, -1, 'bad', 1.5]) {
      expect(pkr(value), 'Amount unavailable');
    }
  });
  test('bid preview uses the backend commission rounding convention', () {
    expect(commissionPaisa(50010), 7502);
    expect(50010 - commissionPaisa(50010), 42508);
    expect(commissionPaisa(110075), 16511);
  });
  test(
      'real history parser preserves job identity, price and missing optional details',
      () {
    final j = HistoryJob(saved());
    expect(j.id, 'job-1');
    expect(j.total, 'PKR 1,000.00');
    expect(j.mechanicName, 'Persisted Mechanic');
    final old = HistoryJob({'_id': 'old', 'status': 'completed'});
    expect(old.total, 'Amount unavailable');
    expect(old.date, 'Date unavailable');
  });
  test('malformed IDs and statuses are rejected rather than replaced', () {
    expect(() => HistoryJob({'status': 'completed'}), throwsFormatException);
    expect(() => HistoryJob({'_id': 'job-1', 'status': 'paid'}),
        throwsFormatException);
  });
  test(
      'history service requests scoped routes with pagination, dates and authenticated client',
      () async {
    final dio = Dio(BaseOptions(
        baseUrl: 'https://fixture.test',
        headers: {'Authorization': 'Bearer fixture-only'}));
    final adapter = BiddingAdapter();
    dio.httpClientAdapter = adapter;
    adapter.respond = (_) async => ResponseBody.fromString(
            jsonEncode({
              'success': true,
              'data': [saved()],
              'pagination': {'page': 2, 'hasMore': false}
            }),
            200,
            headers: {
              Headers.contentTypeHeader: [Headers.jsonContentType]
            });
    final result = await HistoryService(client: dio).fetch(
        mechanic: true,
        page: 2,
        status: 'completed',
        from: '2026-01-01',
        to: '2026-01-31');
    expect(result.jobs.single.id, 'job-1');
    final request = adapter.requests.single;
    expect(request.path, '/mechanics/history');
    expect(request.queryParameters['from'], '2026-01-01');
    expect(request.headers['Authorization'], 'Bearer fixture-only');
  });
  test('earnings parser requires booked basis and a stable response envelope',
      () {
    expect(
        () => HistoryPage.parse({
              'success': true,
              'data': {
                'basis': 'paid',
                'jobs': [],
                'pagination': {'page': 1, 'hasMore': false},
                'summary': totals()
              }
            }, earnings: true),
        throwsFormatException);
    expect(() => HistoryPage.parse({'success': true, 'data': []}),
        throwsFormatException);
  });
  test('load and pagination merge real IDs without duplicate rows', () async {
    service.result = page(more: true);
    final c = controller();
    addTearDown(c.dispose);
    await c.load();
    service.result = page(rows: [saved(), saved(id: 'job-2')], number: 2);
    await c.load(more: true);
    expect(c.jobs.map((j) => j.id), ['job-1', 'job-2']);
    expect(c.page, 2);
    expect(service.calls.last['page'], 2);
  });
  test('failed refresh retains existing history and supports retry', () async {
    final c = controller();
    addTearDown(c.dispose);
    await c.load();
    service.read = (_) async => throw Exception('offline');
    await c.load();
    expect(c.jobs.single.id, 'job-1');
    expect(c.error, contains('retry'));
    expect(c.loading, false);
    service.read = null;
    await c.load();
    expect(c.error, isNull);
  });
  test('old filter request cannot replace a newer response', () async {
    final old = Completer<HistoryPage>(), latest = Completer<HistoryPage>();
    var n = 0;
    service.read = (_) => n++ == 0 ? old.future : latest.future;
    final c = controller();
    addTearDown(c.dispose);
    final first = c.load();
    final second = c.filter(status: 'cancelled');
    latest
        .complete(page(rows: [saved(id: 'cancelled-1', status: 'cancelled')]));
    await second;
    old.complete(page());
    await first;
    expect(c.jobs.single.id, 'cancelled-1');
    expect(c.status, 'cancelled');
  });
  test('logout clears history and ignores late financial response', () async {
    final c = controller(mechanic: true, earnings: true);
    addTearDown(c.dispose);
    await c.load();
    final gate = Completer<HistoryPage>();
    service.read = (_) => gate.future;
    final pending = c.load();
    await auth.clearTokens();
    expect(c.jobs, isEmpty);
    expect(c.summary, isNull);
    gate.complete(page());
    await pending;
    expect(c.summary, isNull);
    expect(c.jobs, isEmpty);
  });
  test('socket session end clears sensitive financial state', () async {
    final c = controller();
    addTearDown(c.dispose);
    await c.load();
    socket.fire('session:ended');
    expect(c.jobs, isEmpty);
    expect(c.summary, isNull);
  });
  test('reconnect and completion notifications reload authoritative history',
      () async {
    final c = controller();
    addTearDown(c.dispose);
    await c.load();
    service.result = page(rows: [saved(id: 'new')]);
    socket.fire('job:status_changed', {'jobId': 'new', 'status': 'completed'});
    await Future<void>.delayed(Duration.zero);
    expect(c.jobs.single.id, 'new');
    socket.reconnect();
    await Future<void>.delayed(Duration.zero);
    expect(service.calls.length, 3);
  });
  test('disposal removes only its own subscriptions', () async {
    void other(dynamic _) {}
    socket.on('job:status_changed', other);
    final c = controller();
    await c.load();
    c.dispose();
    expect(socket.listeners['job:status_changed'], {other});
    expect(socket.listeners['connect'], isEmpty);
  });
  test('restart uses persisted retrieval rather than a local financial cache',
      () async {
    final first = controller();
    await first.load();
    first.dispose();
    service.result = page(rows: [saved(id: 'persisted-later')]);
    final second = controller();
    addTearDown(second.dispose);
    await second.load();
    expect(second.jobs.single.id, 'persisted-later');
  });
  testWidgets('empty driver history is honest and contains no sample jobs',
      (tester) async {
    service.result = page(empty: true);
    await tester
        .pumpWidget(MaterialApp(home: JobHistoryScreen(service: service)));
    await tester.pumpAndSettle();
    expect(find.text('No jobs found'), findsOneWidget);
    expect(find.text('Ahmed Khan'), findsNothing);
    expect(find.text('JOB-001'), findsNothing);
  });
  testWidgets('history loading, failure and retry use backend data',
      (tester) async {
    final gate = Completer<HistoryPage>();
    service.read = (_) => gate.future;
    await tester
        .pumpWidget(MaterialApp(home: JobHistoryScreen(service: service)));
    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    gate.completeError(Exception('offline'));
    await tester.pumpAndSettle();
    expect(find.text('Retry'), findsOneWidget);
    service.read = null;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Actual saved repair'), findsOneWidget);
  });
  testWidgets('driver filter is server backed and job details retain real ID',
      (tester) async {
    await tester
        .pumpWidget(MaterialApp(home: JobHistoryScreen(service: service)));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Completed'));
    await tester.pumpAndSettle();
    expect(service.calls.last['status'], 'completed');
    await tester.tap(find.text('View Details'));
    await tester.pumpAndSettle();
    expect(service.detailIds, ['job-1']);
    expect(find.text('Job Details'), findsOneWidget);
  });
  testWidgets(
      'earnings renders genuine amounts, months and external-payment wording',
      (tester) async {
    await tester.pumpWidget(
        MaterialApp(home: MechanicEarningsScreen(service: service)));
    await tester.pumpAndSettle();
    expect(find.text('PKR 850.00'), findsWidgets);
    expect(find.text('PKR 1,000.00'), findsWidgets);
    expect(find.text('PKR 150.00'), findsOneWidget);
    expect(find.textContaining('not confirmed cash'), findsOneWidget);
    expect(find.textContaining('+12%'), findsNothing);
    expect(service.calls.single['earnings'], true);
  });
  testWidgets('unknown legacy amounts do not appear as zero earnings',
      (tester) async {
    service.result = page(unknown: true);
    await tester.pumpWidget(
        MaterialApp(home: MechanicEarningsScreen(service: service)));
    await tester.pumpAndSettle();
    expect(find.text('Amount unavailable'), findsWidgets);
    expect(find.textContaining('unavailable pricing'), findsOneWidget);
  });
  testWidgets('zero completed jobs show real zero and empty state',
      (tester) async {
    service.result = page(empty: true);
    await tester.pumpWidget(
        MaterialApp(home: MechanicEarningsScreen(service: service)));
    await tester.pumpAndSettle();
    expect(find.text('PKR 0.00'), findsWidgets);
    await tester.scrollUntilVisible(
        find.text('No completed jobs in this period.'), 250,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('No completed jobs in this period.'), findsOneWidget);
  });
  testWidgets('period selection sends UTC dates rather than fake growth values',
      (tester) async {
    await tester.pumpWidget(
        MaterialApp(home: MechanicEarningsScreen(service: service)));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('This Month').last);
    await tester.pumpAndSettle();
    final date = DateTime.now().toUtc();
    expect(service.calls.last['from'],
        '${date.year}-${date.month.toString().padLeft(2, '0')}-01');
    expect(service.calls.last['to'], isNotNull);
  });
  test(
      'aggregate currency strings preserve precision beyond machine integer range',
      () {
    expect(pkr('100000000000000000000'), 'PKR 1,000,000,000,000,000,000.00');
  });
  test(
      'canonical earnings response parses exact booked values and monthly data',
      () {
    final result = HistoryPage.parse({
      'success': true,
      'data': {
        'currency': 'PKR',
        'basis': 'booked_not_paid',
        'summary': totals(),
        'jobs': [saved()],
        'pagination': {'page': 1, 'hasMore': false}
      }
    }, earnings: true);
    expect(result.summary!['netMinor'], '85000');
    expect(result.jobs.single.id, 'job-1');
  });
  test(
      'notifications received during initial load trigger one reconciled refresh',
      () async {
    final gate = Completer<HistoryPage>();
    var calls = 0;
    service.read = (_) => calls++ == 0
        ? gate.future
        : Future.value(page(rows: [saved(id: 'fresh')]));
    final c = controller();
    addTearDown(c.dispose);
    final initial = c.load();
    socket
        .fire('job:status_changed', {'jobId': 'fresh', 'status': 'completed'});
    socket
        .fire('job:status_changed', {'jobId': 'fresh', 'status': 'completed'});
    gate.complete(page());
    await initial;
    await Future<void>.delayed(Duration.zero);
    expect(service.calls.length, 2);
    expect(c.jobs.single.id, 'fresh');
  });
}
