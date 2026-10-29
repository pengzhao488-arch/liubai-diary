import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:liubai_diary/controller.dart';
import 'package:liubai_diary/cloud.dart';
import 'package:liubai_diary/store.dart';
import 'package:liubai_diary/entry.dart';

class FakeCloud extends Cloud {
  final Map<String,Entry> rows={};
  bool fail=false;
  FakeCloud():super('https://example.supabase.co','public-key');
  @override String get userId=>'user-one';
  @override Future<Map<String,dynamic>> push(Entry e) async {
    if(fail)throw Exception('offline');
    final remote=rows[e.id];
    if(remote!=null&&remote.version!=e.version){
      return {'conflict':true,'entry':remote.toJson()};
    }
    final saved=e.edit(version:e.version+1,dirty:false);
    rows[e.id]=saved;return {'conflict':false,'entry':saved.toJson()};
  }
  @override Future<List<Entry>> pull()async=>rows.values.toList();
}
void main(){
  late Directory dir;late DiaryController c;late FakeCloud cloud;
  setUp(()async{
    SharedPreferences.setMockInitialValues({});
    dir=await Directory.systemTemp.createTemp('liubai-sync');
    c=DiaryController(DiaryStore(dir),await SharedPreferences.getInstance());
    cloud=FakeCloud();c.cloud=cloud;
  });
  tearDown(()async{c.dispose();await dir.delete(recursive:true);});
  test('offline failures preserve pending text on disk',()async{
    final e=Entry.fresh().edit(body:'offline draft');await c.save(e);
    cloud.fail=true;await expectLater(c.sync(),throwsException);
    final saved=(await c.store.read(c.namespace)).single;
    expect(saved.body,'offline draft');expect(saved.dirty,true);
  });
  test('conflicts preserve both versions and upload copy next sync',()async{
    const local=Entry(id:'one',date:'2026-10-29',title:'日记',body:'local text',version:1);
    cloud.rows['one']=local.edit(body:'remote text',version:2,dirty:false);
    await c.save(local);await c.sync();
    expect(c.visible.length,2);
    expect(c.entries.singleWhere((e)=>e.id=='one').body,'remote text');
    final copy=c.entries.singleWhere((e)=>e.id!='one');
    expect(copy.body,'local text');expect(copy.dirty,true);
    await c.sync();expect(cloud.rows.length,2);expect(c.entries.every((e)=>!e.dirty),true);
  });
  test('tombstone synchronizes and can be restored',()async{
    final e=Entry.fresh().edit(body:'recoverable');await c.save(e);await c.sync();
    await c.save(c.entries.single.edit(deleted:true));await c.sync();
    expect(c.visible,isEmpty);expect(cloud.rows[e.id]!.deleted,true);
    await c.save(c.entries.single.edit(deleted:false));await c.sync();
    expect(c.visible.single.body,'recoverable');expect(cloud.rows[e.id]!.deleted,false);
  });
}
