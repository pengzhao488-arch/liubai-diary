import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import 'entry.dart';

class DiaryStore {
  final Directory root;
  DiaryStore(this.root);
  static Future<DiaryStore> open() async => DiaryStore(
    Directory('${(await getApplicationSupportDirectory()).path}/diaries'));
  String path(String namespace) => '${root.path}/${sha256.convert(utf8.encode(namespace))}.json';
  Future<List<Entry>> read(String namespace) async {
    final main = File(path(namespace));
    final backup = File('${main.path}.bak');
    for (final file in [main, backup]) {
      if (await file.exists()) {
        try {
          final rows = jsonDecode(await file.readAsString()) as List;
          return rows.map((j) => Entry.fromJson(Map<String,dynamic>.from(j))).toList();
        } catch (_) { /* Try the last known complete backup. */ }
      }
    }
    if (await main.exists() || await backup.exists()) {
      throw Exception('本地数据无法读取，请保留应用数据并联系开发者，不要卸载。');
    }
    return [];
  }
  Future<void> write(String namespace, List<Entry> entries) async {
    await root.create(recursive: true);
    final main = File(path(namespace));
    final backup = File('${main.path}.bak');
    final temp = File('${main.path}.tmp');
    await temp.writeAsString(jsonEncode(entries.map((e) => e.toJson()).toList()), flush: true);
    if (await main.exists()) {
      var valid = false;
      try { valid = jsonDecode(await main.readAsString()) is List; } catch (_) {}
      if (valid) {
        if (await backup.exists()) await backup.delete();
        await main.rename(backup.path);
      } else {
        // Never replace the known-good backup with a corrupt primary.
        await main.delete();
      }
    }
    await temp.rename(main.path);
  }
}
