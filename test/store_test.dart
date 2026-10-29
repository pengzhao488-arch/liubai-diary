import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:liubai_diary/store.dart';
import 'package:liubai_diary/entry.dart';
void main(){
  test('stores are isolated and corrupt primary falls back to backup',()async{
    final dir=await Directory.systemTemp.createTemp('liubai-test');
    addTearDown(()=>dir.delete(recursive:true));final s=DiaryStore(dir);
    const one=Entry(id:'one',date:'2026-10-29',body:'first');
    await s.write('account-a',[one]);await s.write('account-a',[one.edit(body:'second')]);
    expect((await s.read('account-a')).single.body,'second');
    expect(await s.read('account-b'),isEmpty);
    await File(s.path('account-a')).writeAsString('{broken');
    expect((await s.read('account-a')).single.body,'first');
  });
}
