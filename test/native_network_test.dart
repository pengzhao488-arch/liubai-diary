import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:liubai_diary/native_network.dart';
void main() {
  test('native adapter preserves POST body and UTF-8 response',() async {
    final client=NativeNetworkClient((payload)async{
      expect(payload['method'],'POST');
      expect(payload['url'],'https://example.com/auth/v1/token');
      expect((payload['headers'] as Map)['accept-encoding'],'identity');
      expect(payload['body'],Uint8List.fromList([123,125]));
      return {'status':200,'body':Uint8List.fromList([123,125])};
    });
    final response=await client.post(Uri.parse('https://example.com/auth/v1/token'),body:'{}');
    expect(response.statusCode,200);expect(response.body,'{}');
  });
  test('native adapter rejects unencrypted URLs before sending',() async {
    bool sent=false;
    final client=NativeNetworkClient((_) async {sent=true;return {};});
    await expectLater(client.get(Uri.parse('http://example.com')),throwsA(isA<http.ClientException>()));
    expect(sent,false);
  });
}
