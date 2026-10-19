import 'package:flutter_test/flutter_test.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:onraasta/services/socket_service.dart';

class _Transport extends io.Socket {
  bool disposed = false;
  int connects = 0;
  Function? acknowledge;
  String? event;
  dynamic payload;
  _Transport(Map<String, dynamic> options)
      : super(
            io.io('http://fixture.invalid', <String, dynamic>{
              ...options,
              'autoConnect': false,
              'forceNew': true
            }).io,
            '/',
            options);
  @override
  io.Socket connect() {
    connects++;
    return this;
  }

  void serverConnect() => onconnect('controlled-socket', null);
  @override
  void emitWithAck(String event, dynamic data,
      {Function? ack, bool binary = false}) {
    if (['connect', 'disconnect', 'disconnecting', 'error', 'connect_error']
        .contains(event)) {
      super.emitWithAck(event, data, ack: ack, binary: binary);
      return;
    }
    this.event = event;
    payload = data;
    acknowledge = ack;
  }

  @override
  void dispose() {
    disposed = true;
    connected = false;
    super.dispose();
  }
}

void main() {
  late SocketService service;
  late List<_Transport> transports;
  setUp(() {
    transports = [];
    service = SocketService.withFactory((url, options) {
      final socket = _Transport(options);
      transports.add(socket);
      return socket;
    });
  });
  tearDown(() => service.disconnect());
  test(
      'handshake contains current token and account switching disposes previous transport',
      () {
    service.connect('first-access-token');
    expect(transports.single.auth, {'token': 'first-access-token'});
    transports.single.serverConnect();
    service.connect('second-access-token');
    expect(transports.first.disposed, true);
    expect(transports.last.auth, {'token': 'second-access-token'});
    expect(transports.last.io.reconnectionAttempts, 5);
    service.disconnect();
    expect(transports.last.disposed, true);
    expect(service.isConnected, false);
  });
  test('connection is event-driven and pre-connection listeners survive',
      () async {
    int bids = 0;
    void listener(dynamic _) {
      bids++;
    }

    service.on('bid:new', listener);
    final connected = service.ensureConnected('access-token');
    expect(service.isConnected, false);
    transports.single.serverConnect();
    await connected;
    transports.single.onevent({
      'data': [
        'bid:new',
        {'jobId': 'saved-job'}
      ]
    });
    expect(bids, 1);
    service.off('bid:new', listener);
    transports.single.onevent({
      'data': ['bid:new', {}]
    });
    expect(bids, 1);
  });
  test('removing one subscription preserves another screen listener', () {
    int first = 0, second = 0;
    void a(dynamic _) {
      first++;
    }

    void b(dynamic _) {
      second++;
    }

    service.on('job:new_request', a);
    service.on('job:new_request', a);
    service.on('job:new_request', b);
    service.connect('token');
    transports.single.serverConnect();
    service.off('job:new_request', a);
    transports.single.onevent({
      'data': ['job:new_request', {}]
    });
    expect(first, 0);
    expect(second, 1);
  });
  test('availability request waits for server ack and parses confirmed data',
      () async {
    service.connect('token');
    transports.single.serverConnect();
    final response =
        service.request('mechanic:go_online', {'lat': 31, 'lng': 74});
    expect(transports.single.event, 'mechanic:go_online');
    transports.single.acknowledge!({
      'success': true,
      'data': {'isOnline': true, 'mechanicId': 'm'}
    });
    expect(await response, {'isOnline': true, 'mechanicId': 'm'});
  });
  test('disconnect cancels pending availability operations', () async {
    service.connect('token');
    transports.single.serverConnect();
    final response =
        service.request('mechanic:go_online', {'lat': 31, 'lng': 74});
    final failed = expectLater(response, throwsA(isA<SocketFailure>()));
    service.disconnect();
    await failed;
  });
  test(
      'namespace authentication rejection stops retries and fails pending connection',
      () async {
    final response = service.ensureConnected('expired-token');
    final failed = expectLater(response,
        throwsA(isA<SocketFailure>().having((e) => e.status, 'status', 401)));
    // Exercise the installed client's actual CONNECT_ERROR packet decoding.
    transports.single.onpacket({
      'nsp': '/',
      'type': 4,
      'data': {
        'message': 'Socket authentication failed',
        'data': {'status': 401}
      }
    });
    await failed;
    expect(transports.single.io.reconnection, false);
    expect(transports.single.disposed, true);
  });
  test('rejected availability acknowledgment returns controlled failure',
      () async {
    service.connect('token');
    transports.single.serverConnect();
    final response =
        service.request('mechanic:go_online', {'lat': 31, 'lng': 74});
    final failed = expectLater(response,
        throwsA(isA<SocketFailure>().having((e) => e.status, 'status', 403)));
    transports.single.acknowledge!(
        {'success': false, 'status': 403, 'message': 'Not approved'});
    await failed;
  });
  testWidgets('missing ack has a bounded timeout', (tester) async {
    service.connect('token');
    transports.single.serverConnect();
    final response =
        service.request('mechanic:go_online', {'lat': 31, 'lng': 74});
    final failed = expectLater(response, throwsA(isA<SocketFailure>()));
    await tester.pump(const Duration(seconds: 9));
    await failed;
  });
}
