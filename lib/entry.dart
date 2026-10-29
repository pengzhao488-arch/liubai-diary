import 'package:uuid/uuid.dart';

class Entry {
  final String id, date, title, body, mood;
  final int version;
  final bool dirty, deleted;
  const Entry({required this.id, required this.date, this.title = '',
    this.body = '', this.mood = '平静', this.version = 0,
    this.dirty = true, this.deleted = false});
  factory Entry.fresh() => Entry(id: const Uuid().v4(),
    date: DateTime.now().toIso8601String().substring(0, 10));
  factory Entry.fromJson(Map<String, dynamic> j) => Entry(
    id: j['id'] as String, date: j['date'] as String,
    title: j['title'] as String? ?? '', body: j['body'] as String? ?? '',
    mood: j['mood'] as String? ?? '平静', version: j['version'] as int? ?? 0,
    dirty: j['dirty'] as bool? ?? false, deleted: j['deleted'] as bool? ?? false);
  Map<String, dynamic> toJson() => {'id': id, 'date': date, 'title': title,
    'body': body, 'mood': mood, 'version': version, 'dirty': dirty, 'deleted': deleted};
  Entry edit({String? title, String? body, String? mood, String? date,
    int? version, bool? dirty, bool? deleted}) => Entry(id: id,
    date: date ?? this.date, title: title ?? this.title, body: body ?? this.body,
    mood: mood ?? this.mood, version: version ?? this.version,
    dirty: dirty ?? true, deleted: deleted ?? this.deleted);
  Entry conflictCopy() => Entry(id: const Uuid().v4(), date: date,
    title: '${title.length > 190 ? title.substring(0,190) : title}（冲突保留）', body: body, mood: mood);
}
