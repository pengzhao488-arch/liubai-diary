import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'entry.dart';

class Cloud {
  final String url, key;
  final _vault = const FlutterSecureStorage();
  Map<String, dynamic>? session;
  Cloud(this.url, this.key);
  String get sessionKey => 'liubai-session-$url';
  String? get userId => session?['user']?['id'] as String?;
  String? get email => session?['user']?['email'] as String?;
  Future<void> restore() async {
    final data = await _vault.read(key: sessionKey);
    if (data != null) session = jsonDecode(data) as Map<String, dynamic>;
  }
  Future<dynamic> request(String method, String path, {dynamic body, bool authenticated = true}) async {
    if (authenticated) await refresh();
    final headers = {'apikey': key, 'Content-Type': 'application/json',
      if (authenticated && session != null) 'Authorization': 'Bearer ${session!['access_token']}'};
    final req = http.Request(method, Uri.parse('$url$path'))..headers.addAll(headers);
    if (body != null) req.body = jsonEncode(body);
    final res = await http.Response.fromStream(await req.send().timeout(const Duration(seconds: 25)))
      .timeout(const Duration(seconds: 25));
    dynamic data;
    try { data = jsonDecode(res.body); } catch (_) { data = null; }
    if (res.statusCode >= 400) {
      final message = data is Map ? data['msg'] ?? data['message'] ?? data['error_description'] ?? data['error'] : null;
      throw Exception(message ?? '云端请求失败（${res.statusCode}），请检查网络和云端设置。');
    }
    return data;
  }
  Future<void> saveSession(Map<String, dynamic> value) async {
    value['expires_at'] ??= DateTime.now().millisecondsSinceEpoch ~/ 1000 + (value['expires_in'] as int? ?? 3600);
    await _vault.write(key: sessionKey, value: jsonEncode(value));
    session = value;
  }
  Future<void> refresh() async {
    if (session == null) throw Exception('请先登录云端账号。');
    if ((session!['expires_at'] as int? ?? 0) > DateTime.now().millisecondsSinceEpoch ~/ 1000 + 90) return;
    final data = await request('POST', '/auth/v1/token?grant_type=refresh_token',
      body: {'refresh_token': session!['refresh_token']}, authenticated: false);
    await saveSession(Map<String, dynamic>.from(data));
  }
  Future<void> login(String email, String password) async {
    final data = await request('POST', '/auth/v1/token?grant_type=password',
      body: {'email': email, 'password': password}, authenticated: false);
    await saveSession(Map<String, dynamic>.from(data));
  }
  Future<void> register(String email, String password) async {
    await request('POST', '/auth/v1/signup', body: {'email': email, 'password': password}, authenticated: false);
  }
  Future<void> logout() async {
    // Local sign-out always works offline; credentials remain revocable on the server.
    await _vault.delete(key: sessionKey);
    session = null;
  }
  Future<Map<String, dynamic>> push(Entry e) async => Map<String, dynamic>.from(
    await request('POST', '/rest/v1/rpc/save_diary', body: {
      'p_id': e.id, 'p_date': e.date, 'p_title': e.title, 'p_body': e.body,
      'p_mood': e.mood, 'p_version': e.version, 'p_deleted': e.deleted}));
  Future<List<Entry>> pull() async {
    final all = <Entry>[];
    var offset = 0;
    while (true) {
      final rows = await request('GET', '/rest/v1/diary_entries?select=*&order=id.asc&limit=500&offset=$offset');
      final page = rows as List;
      all.addAll(page.map((j) => Entry.fromJson(Map<String, dynamic>.from(j))));
      if (page.length < 500) break;
      offset += page.length;
    }
    return all;
  }
}
