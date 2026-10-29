import 'dart:convert';
import 'package:uuid/uuid.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'entry.dart';
import 'cloud.dart';
import 'store.dart';

class DiaryController extends ChangeNotifier {
  final DiaryStore store;
  final SharedPreferences prefs;
  Cloud? cloud;
  List<Entry> entries = [];
  bool busy = false;
  String status = '仅本机保存';
  DiaryController(this.store, this.prefs);
  String get namespace => cloud?.userId == null ? 'guest' : '${cloud!.url}/${cloud!.userId}';
  bool get signedIn => cloud?.userId != null;
  List<Entry> get visible => entries.where((e) => !e.deleted).toList()..sort((a,b) => b.date.compareTo(a.date));
  Future<void> init() async {
    final url = prefs.getString('cloud_url') ?? const String.fromEnvironment('SUPABASE_URL');
    final key = prefs.getString('cloud_key') ?? const String.fromEnvironment('SUPABASE_ANON_KEY');
    if (url.isNotEmpty && key.isNotEmpty) {
      cloud = Cloud(url, key);
      await cloud!.restore();
    }
    entries = await store.read(namespace);
    status = signedIn ? '本地数据已打开 · 点击同步更新云端' : '仅本机保存 · 登录后可同步';
  }
  Future<void> guard(Future<void> Function() task) async {
    if (busy) return;
    busy = true; notifyListeners();
    try { await task(); } finally { busy = false; notifyListeners(); }
  }
  Future<void> configure(String url, String key) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty || uri.path.isNotEmpty && uri.path != '/' || uri.hasQuery || uri.hasFragment) {
      throw Exception('请输入 HTTPS 云端项目地址，例如 https://项目编号.supabase.co');
    }
    if (key.trim().isEmpty || key.startsWith('sb_secret_')) throw Exception('请使用 publishable / anon 公钥，不能使用服务端密钥。');
    final normalized = '${uri.scheme}://${uri.authority}';
    final newCloud = Cloud(normalized, key.trim());
    await newCloud.restore();
    final newNamespace = newCloud.userId == null ? 'guest' : '$normalized/${newCloud.userId}';
    final next = await store.read(newNamespace);
    await prefs.setString('cloud_url', normalized); await prefs.setString('cloud_key', key.trim());
    cloud = newCloud; entries = next; status = '配置已保存 · 直连尚未检测'; notifyListeners();
  }
  Future<void> checkConnection() async {
    if (cloud == null) throw Exception('请先保存云端配置。');
    try {
      await cloud!.checkConnection();
      status = signedIn ? '直连检测成功 · 已登录，点击同步' : '直连检测成功 · 尚未登录';
    } catch (_) {
      status = '直连检测失败 · 本机保存仍可用';
      rethrow;
    } finally { notifyListeners(); }
  }
  Future<void> login(String email, String password) async {
    if (cloud == null) throw Exception('请先配置云端服务。');
    await cloud!.login(email.trim(), password);
    entries = []; notifyListeners();
    entries = await store.read(namespace); status = '已登录 · 点击同步'; notifyListeners();
  }
  Future<void> logout() async {
    await cloud?.logout(); entries = []; notifyListeners(); entries = await store.read('guest'); status = '已切换到本机日记'; notifyListeners();
  }
  Future<void> save(Entry entry) async {
    final next = [...entries.where((e) => e.id != entry.id), entry];
    await store.write(namespace, next); entries = next;
    status = signedIn ? '已保存本机 · 等待同步' : '已保存到本机'; notifyListeners();
  }
  Future<void> importGuest() async {
    if (!signedIn) throw Exception('请先登录。');
    final guest = await store.read('guest');
    final copies = guest.where((g) => !g.deleted).map((g) => Entry(
      id: const Uuid().v5(Uuid.NAMESPACE_URL, '$namespace/guest/${g.id}'),
      date: g.date, title: g.title, body: g.body, mood: g.mood)).toList();
    final next = [...entries, ...copies.where((g) => !entries.any((e) => e.id == g.id))];
    await store.write(namespace, next); entries = next;
    status = '已复制本机日记到当前账号 · 等待同步'; notifyListeners();
  }
  Future<void> sync() async {
    if (!signedIn) throw Exception('请先登录云端账号。');
    int conflicts = 0;
    for (final local in [...entries.where((e) => e.dirty)]) {
      final result = await cloud!.push(local);
      if (result['conflict'] == true) {
        conflicts++;
        // Preserve local text as a separate record; retain the remote original.
        if (!local.deleted) {
          final copy = local.conflictCopy();
          await save(copy);
        }
        final remote = Entry.fromJson(Map<String, dynamic>.from(result['entry']));
        final next = [...entries.where((e) => e.id != local.id), remote];
        await store.write(namespace, next); entries = next;
      } else {
        final remote = Entry.fromJson(Map<String, dynamic>.from(result['entry']));
        final next = [...entries.where((e) => e.id != local.id), remote];
        await store.write(namespace, next); entries = next;
      }
    }
    // A conflict copy remains queued locally until the next sync, never discarded.
    final remote = await cloud!.pull();
    final pending = entries.where((e) => e.dirty).toList();
    final next = [...remote.where((r) => !pending.any((p) => p.id == r.id)), ...pending];
    await store.write(namespace, next); entries = next;
    status = conflicts > 0 ? '发现 $conflicts 处冲突，已保留双方内容；再次同步上传保留副本'
      : '同步完成 · ${DateTime.now().toLocal().toString().substring(11,16)}';
    notifyListeners();
  }
  String exportJson() => const JsonEncoder.withIndent('  ').convert({
    'format': 'liubai-diary', 'version': 1,
    'entries': entries.map((e) => e.toJson()).toList()});
  Future<void> importJson(String text) async {
    final data = jsonDecode(text);
    if (data is! Map || data['format'] != 'liubai-diary' || data['version'] != 1 || data['entries'] is! List) {
      throw Exception('这不是支持的留白日记备份。');
    }
    final imported = (data['entries'] as List).map((j) => Entry.fromJson(Map<String,dynamic>.from(j)))
      .where((e) => !e.deleted).map((e) => Entry(id: Entry.fresh().id,
        date: e.date, title: e.title, body: e.body, mood: e.mood)).toList();
    final next = [...entries, ...imported];
    await store.write(namespace, next); entries = next;
    status = '已导入 ${imported.length} 篇（作为新日记，未覆盖原内容）'; notifyListeners();
  }
}
