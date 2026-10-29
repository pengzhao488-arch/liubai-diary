import 'package:flutter_test/flutter_test.dart';
import 'package:liubai_diary/entry.dart';
void main(){
  test('editing preserves server version for compare-and-swap',(){
    const e=Entry(id:'one',date:'2026-10-29',version:7,dirty:false);
    final changed=e.edit(body:'修改');
    expect(changed.version,7);expect(changed.dirty,true);expect(e.body,'');
  });
  test('conflict preserves local text under a fresh id',(){
    const e=Entry(id:'original',date:'2026-10-29',title:'日记',body:'离线文字',version:3);
    final copy=e.conflictCopy();expect(copy.id,isNot(e.id));expect(copy.body,e.body);
    expect(copy.version,0);expect(copy.dirty,true);expect(copy.title,contains('冲突保留'));
  });
  test('remote rows are clean and tombstones survive roundtrip',(){
    final e=Entry.fromJson({'id':'one','date':'2026-10-29','version':4,'deleted':true});
    expect(e.dirty,false);expect(Entry.fromJson(e.toJson()).deleted,true);
  });
}
