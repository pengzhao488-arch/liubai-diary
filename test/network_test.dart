import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:liubai_diary/network.dart';
import 'package:liubai_diary/cloud.dart';

class RecordingClient implements HttpClient {
  String Function(Uri)? resolver;
  Duration? timeout;
  @override set findProxy(String Function(Uri)? callback) { resolver = callback; }
  @override set connectionTimeout(Duration? value) { timeout = value; }
  @override Duration? get connectionTimeout => timeout;
  @override void close({bool force = false}) {}
  @override dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('direct mode does not consult proxy environment settings', () {
    final recording = RecordingClient();
    HttpOverrides.runZoned(() {
      final client = directHttpClient();
      expect(recording.resolver!(Uri.parse('https://example.com')), 'DIRECT');
      expect(client.connectionTimeout, const Duration(seconds:15));
      client.close();
    }, createHttpClient: (_) => recording);
  });
  test('connection check uses client public key, without login credentials', () async {
    final fake = MockClient((request) async {
      expect(request.url.path, '/auth/v1/health');
      expect(request.headers['apikey'], 'public-key');
      expect(request.headers.containsKey('Authorization'), false);
      expect(request.body, isEmpty);
      expect(request.followRedirects, false);
      return http.Response(jsonEncode({'version':'test','name':'GoTrue'}),200);
    });
    await Cloud('https://example.com','public-key',transport:fake).checkConnection();
  });
  test('bad public key cannot be reported as connection success', () async {
    final fake = MockClient((_) async => http.Response('{"message":"Invalid API key"}',401));
    await expectLater(Cloud('https://example.com','bad-key',transport:fake).checkConnection(),throwsException);
  });
  test('TLS failure stays a connection error, never a password error', () async {
    final fake = MockClient((_) async => throw const HandshakeException('terminated'));
    await expectLater(Cloud('https://example.com','public-key',transport:fake).checkConnection(),
      throwsA(predicate((e)=>e.toString().contains('HTTPS 安全连接未建立'))));
  });
  test('redirects do not forward keys or masquerade as successful health', () async {
    final fake = MockClient((_) async => http.Response('',302,headers:{'location':'https://elsewhere.invalid'}));
    await expectLater(Cloud('https://example.com','public-key',transport:fake).checkConnection(),throwsException);
  });
}
