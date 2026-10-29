import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_selector/file_selector.dart';
import 'controller.dart';
import 'store.dart';
import 'entry.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final c = DiaryController(await DiaryStore.open(), await SharedPreferences.getInstance());
    await c.init(); runApp(LiubaiApp(controller: c));
  } catch (e) {
    runApp(MaterialApp(home: Scaffold(body: Center(child: Padding(
      padding: const EdgeInsets.all(32), child: SelectableText('启动失败，请保留应用数据，不要卸载。\n$e'))))));
  }
}
class LiubaiApp extends StatelessWidget {
  final DiaryController controller;
  const LiubaiApp({super.key, required this.controller});
  @override Widget build(BuildContext context) => MaterialApp(
    title: '留白日记', debugShowCheckedModeBanner: false,
    locale: const Locale('zh', 'CN'), supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    theme: ThemeData(useMaterial3: true, colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xff526950), surface: const Color(0xfffaf9f4)),
      scaffoldBackgroundColor: const Color(0xfff5f4ee),
      inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
      appBarTheme: const AppBarTheme(backgroundColor: Color(0xfff5f4ee))),
    home: Home(c: controller));
}
class Home extends StatefulWidget {
  final DiaryController c;
  const Home({super.key, required this.c});
  @override State<Home> createState() => _HomeState();
}
class _HomeState extends State<Home> {
  String query = '';
  DiaryController get c => widget.c;
  @override void initState() { super.initState(); c.addListener(changed); }
  void changed() { if (mounted) setState(() {}); }
  @override void dispose() { c.removeListener(changed); super.dispose(); }
  Future<void> action(Future<void> Function() f) async {
    try { await c.guard(f); } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), duration: const Duration(seconds: 8)));
    }
  }
  Future<void> editor([Entry? entry]) async {
    if (c.busy) return;
    final result = await Navigator.of(context).push<Entry>(MaterialPageRoute(builder: (_) => Editor(entry: entry ?? Entry.fresh())));
    if (result != null) {
      try { await c.guard(() => c.save(result)); } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('保存失败：$e。已重新打开文字，请勿关闭。')));
          await editor(result);
        }
      }
    }
  }
  Future<void> export() async {
    if (Platform.isAndroid) {
      final directory = await getTemporaryDirectory();
      final path = '${directory.path}/liubai-backup.json';
      await File(path).writeAsString(c.exportJson(), flush: true);
      await Share.shareXFiles([XFile(path)], text: '留白日记备份（包含日记正文）');
      return;
    }
    final location = await getSaveLocation(suggestedName: 'liubai-${DateTime.now().toIso8601String().substring(0,10)}.json');
    if (location == null) return;
    await XFile.fromData(utf8.encode(c.exportJson()), mimeType: 'application/json', name: 'liubai.json').saveTo(location.path);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('备份已导出，请妥善保管，文件包含日记正文。')));
  }
  Future<void> importBackup() async {
    final file = await openFile(acceptedTypeGroups: [const XTypeGroup(label: '日记备份', extensions: ['json'])]);
    if (file != null) await c.importJson(await file.readAsString());
  }
  Future<void> delete(Entry e) async {
    final yes = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('移到回收站？'), content: const Text('同步后，其他设备也会隐藏这篇日记。可以在回收站恢复。'),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx,false), child: const Text('取消')),
      FilledButton(onPressed: () => Navigator.pop(ctx,true), child: const Text('移到回收站'))]));
    if (yes == true) await action(() => c.save(e.edit(deleted: true)));
  }
  Future<void> trash() async {
    final deleted = c.entries.where((e) => e.deleted).toList();
    final selected = await showDialog<Entry>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('回收站'), content: SizedBox(width: 420, child: deleted.isEmpty ? const Text('回收站是空的')
        : ListView(shrinkWrap: true, children: deleted.map((e) => ListTile(
          title: Text(e.title.isEmpty ? '无题' : e.title), subtitle: Text(e.date),
          trailing: TextButton(onPressed: () => Navigator.pop(ctx,e), child: const Text('恢复')))).toList())),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('关闭'))]));
    if (selected != null) await action(() => c.save(selected.edit(deleted:false)));
  }
  @override Widget build(BuildContext context) {
    final items = c.visible.where((e) => '${e.title}\n${e.body}\n${e.date}'.contains(query)).toList();
    return Scaffold(appBar: AppBar(title: const Text('留白 · 日记'), actions: [
      IconButton(tooltip: '同步日记', onPressed: c.busy ? null : () => action(c.sync), icon: const Icon(Icons.sync)),
      IconButton(tooltip: '账号与云端设置', onPressed: c.busy ? null : () => Navigator.push(context,
        MaterialPageRoute(builder: (_) => Settings(c:c))), icon: const Icon(Icons.cloud_outlined)),
      PopupMenuButton<String>(enabled: !c.busy, onSelected: (v) {
        if(v=='export') action(export); if(v=='import') action(importBackup); if(v=='trash') trash();
      }, itemBuilder: (_) => const [PopupMenuItem(value:'export',child:Text('导出备份')),
        PopupMenuItem(value:'import',child:Text('导入备份')),PopupMenuItem(value:'trash',child:Text('回收站'))])]),
      body: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 1080), child: Column(children: [
        if (c.busy) const LinearProgressIndicator(minHeight:2),
        Padding(padding: const EdgeInsets.fromLTRB(24,24,24,8),child: Column(crossAxisAlignment: CrossAxisAlignment.start,children:[
          Text('给今天，留一点空白。',style:Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height:8), const Text('不必写得漂亮，真实就很好。',style:TextStyle(color:Colors.grey)),
          const SizedBox(height:20),TextField(onChanged:(v)=>setState(()=>query=v),decoration: const InputDecoration(
            hintText:'搜索标题、正文或日期',prefixIcon:Icon(Icons.search))),
          const SizedBox(height:12),Row(children:[const Icon(Icons.circle,size:8,color:Color(0xff718369)),
            const SizedBox(width:8),Expanded(child:Text(c.status,style: const TextStyle(fontSize:12))),
            Text('${c.visible.length} 篇',style: const TextStyle(fontSize:12))]),
          const SizedBox(height:4),Text(c.signedIn ? '账号：${c.cloud!.email}' : '本机模式 · 尚未连接云端',
            style:const TextStyle(fontSize:11,color:Colors.grey))])),
        Expanded(child: items.isEmpty ? const Center(child:Text('把今天的小事，写成明天的回忆。\n\n点击右下角开始写日记。',textAlign:TextAlign.center))
          : ListView.builder(padding:const EdgeInsets.fromLTRB(20,8,20,100),itemCount:items.length,itemBuilder:(ctx,i){
            final e=items[i];return Card(elevation:0,margin: const EdgeInsets.only(bottom:10),
              child: ListTile(contentPadding: const EdgeInsets.symmetric(horizontal:20,vertical:12),
                onTap: c.busy ? null : ()=>editor(e),
                title:Text(e.title.isEmpty?'无题':e.title,maxLines:1,overflow:TextOverflow.ellipsis),
                subtitle:Padding(padding:const EdgeInsets.only(top:8),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                  Text('${e.date}  ·  ${e.mood}${e.dirty && c.signedIn ? '  ·  待同步' : ''}',style: const TextStyle(fontSize:11)),
                  const SizedBox(height:7),Text(e.body,maxLines:2,overflow:TextOverflow.ellipsis)])),
                trailing:IconButton(tooltip:'移到回收站',onPressed:c.busy?null:()=>delete(e),icon:const Icon(Icons.delete_outline,size:20))));}))]))),
      floatingActionButton:FloatingActionButton.extended(onPressed:c.busy?null:()=>editor(),icon:const Icon(Icons.edit_outlined),label:const Text('写日记')));
  }
}
class Editor extends StatefulWidget {
  final Entry entry;
  const Editor({super.key,required this.entry});
  @override State<Editor> createState()=>_EditorState();
}
class _EditorState extends State<Editor> {
  late TextEditingController title,body;
  late String mood,date;
  bool dirty=false,leaving=false;
  @override void initState(){super.initState();title=TextEditingController(text:widget.entry.title);body=TextEditingController(text:widget.entry.body);
    mood=widget.entry.mood;date=widget.entry.date;title.addListener(touched);body.addListener(touched);}
  void touched(){setState(()=>dirty=true);}
  @override void dispose(){title.dispose();body.dispose();super.dispose();}
  Future<void> leave()async{if(!dirty){Navigator.pop(context);return;}final yes=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(
    title:const Text('放弃未保存的修改？'),content:const Text('选择继续写作，再点击保存即可保留内容。'),actions:[
      TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('继续写作')),
      TextButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('放弃修改'))]));
    if(yes==true&&mounted){setState(()=>leaving=true);WidgetsBinding.instance.addPostFrameCallback((_){if(mounted)Navigator.pop(context);});}}
  void save(){if(title.text.trim().isEmpty&&body.text.trim().isEmpty)return;
    final result=widget.entry.edit(title:title.text.trim(),body:body.text,mood:mood,date:date);
    setState(()=>leaving=true);WidgetsBinding.instance.addPostFrameCallback((_){if(mounted)Navigator.pop(context,result);});}
  @override Widget build(BuildContext context)=>PopScope(canPop:!dirty||leaving,onPopInvokedWithResult:(didPop,result){if(!didPop)leave();},
    child:Scaffold(appBar:AppBar(leading:IconButton(icon:const Icon(Icons.arrow_back),onPressed:leave),title:const Text('写下今天'),actions:[
      TextButton.icon(onPressed:save,icon:const Icon(Icons.check),label:const Text('保存'))]),
      body:Center(child:ConstrainedBox(constraints:const BoxConstraints(maxWidth:850),child:Padding(padding:const EdgeInsets.all(24),child:Column(children:[
        Row(children:[TextButton.icon(icon:const Icon(Icons.calendar_today_outlined,size:16),label:Text(date),onPressed:()async{
          final d=await showDatePicker(context:context,initialDate:DateTime.tryParse(date)??DateTime.now(),firstDate:DateTime(1900),lastDate:DateTime(2200));
          if(d!=null)setState((){date=d.toIso8601String().substring(0,10);dirty=true;});}),const Spacer(),Text('${body.text.length} 字')]),
        TextField(controller:title,maxLength:200,style:Theme.of(context).textTheme.headlineSmall,
          decoration:const InputDecoration(hintText:'今天，想记下什么？',border:InputBorder.none,counterText:'')),
        const SizedBox(height:12),Wrap(spacing:8,children:['开心','平静','疲惫','低落','期待'].map((m)=>ChoiceChip(label:Text(m),selected:mood==m,
          onSelected:(_)=>setState((){mood=m;dirty=true;}))).toList()),const Divider(height:32),
        Expanded(child:TextField(controller:body,maxLength:100000,maxLines:null,expands:true,textAlignVertical:TextAlignVertical.top,
          style:const TextStyle(fontSize:16,height:1.9),decoration:const InputDecoration(hintText:'一件小事，一段心情，\n或某个不想忘记的瞬间……',border:InputBorder.none))),
        const Text('保存后回到列表，点击同步即可更新其他设备。',style:TextStyle(fontSize:11,color:Colors.grey))]))))));
}
class Settings extends StatefulWidget {
  final DiaryController c;
  const Settings({super.key,required this.c});
  @override State<Settings> createState()=>_SettingsState();
}
class _SettingsState extends State<Settings> {
  late TextEditingController url,key;
  final email=TextEditingController(),password=TextEditingController();
  bool busy=false;String message='';
  DiaryController get c=>widget.c;
  @override void initState(){super.initState();url=TextEditingController(text:c.cloud?.url??'');key=TextEditingController(text:c.cloud?.key??'');}
  @override void dispose(){url.dispose();key.dispose();email.dispose();password.dispose();super.dispose();}
  Future<void> run(Future<void> Function() f,String success)async{
    setState((){busy=true;message='处理中…';});try{await c.guard(f);if(mounted)setState(()=>message=success);}
    catch(e){if(mounted)setState(()=>message='$e');}finally{if(mounted)setState(()=>busy=false);}}
  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('账号与云端')),
    body:Center(child:ConstrainedBox(constraints:const BoxConstraints(maxWidth:680),child:ListView(padding:const EdgeInsets.all(24),children:[
      const Text('两端互通',style:TextStyle(fontSize:26)),const SizedBox(height:12),
      const Text('安卓与 Windows 配置同一个云端项目，并登录同一邮箱账号，即可同步。未配置时仍可在本机写日记。'),
      const SizedBox(height:20),TextField(controller:url,enabled:!busy,decoration:const InputDecoration(labelText:'Supabase 项目 URL',hintText:'https://项目编号.supabase.co')),
      const SizedBox(height:12),TextField(controller:key,enabled:!busy,decoration:const InputDecoration(labelText:'Publishable / anon 公钥（不是服务端密钥）')),
      const SizedBox(height:12),OutlinedButton(onPressed:busy?null:()=>run(()=>c.configure(url.text,key.text),'云端配置已保存'),child:const Text('保存云端配置')),
      const Divider(height:40),
      if(c.signedIn)...[Text('已登录：${c.cloud!.email}'),const SizedBox(height:12),
        FilledButton(onPressed:busy?null:()=>run(c.sync,'同步操作结束，返回列表查看具体状态'),child:const Text('立即同步')),
        OutlinedButton(onPressed:busy?null:()async{
          final yes=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(title:const Text('复制本机日记到当前账号？'),
            content:const Text('复制后点击同步，会上传这些日记到你配置的云端。本机原日记仍保留。'),actions:[
              TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('取消')),
              FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('复制'))]));
          if(yes==true)run(c.importGuest,'已复制，点击立即同步上传');},child:const Text('复制本机日记到当前账号')),
        TextButton(onPressed:busy?null:()=>run(c.logout,'已退出，切换到本机日记'),child:const Text('退出账号'))]
      else ...[TextField(controller:email,keyboardType:TextInputType.emailAddress,enabled:!busy,decoration:const InputDecoration(labelText:'邮箱')),
        const SizedBox(height:12),TextField(controller:password,obscureText:true,enabled:!busy,decoration:const InputDecoration(labelText:'密码（至少 8 位）')),
        const SizedBox(height:16),FilledButton(onPressed:busy?null:()=>run(()async{
          await c.login(email.text,password.text);password.clear();},'已登录，返回列表点击同步'),child:const Text('登录')),
        TextButton(onPressed:busy?null:()=>run(()async{
          if(c.cloud==null)throw Exception('请先保存云端配置');if(password.text.length<8)throw Exception('密码至少 8 位');
          await c.cloud!.register(email.text.trim(),password.text);password.clear();},'注册请求已提交，请检查确认邮件；确认后再登录。'),child:const Text('注册新账号'))],
      if(busy)const LinearProgressIndicator(),const SizedBox(height:12),SelectableText(message),
      const Divider(height:32),const Text('数据说明',style:TextStyle(fontSize:18)),const SizedBox(height:8),
      const Text('日记保存在应用本地目录；同步时通过 HTTPS 上传到你配置的 Supabase 项目，按账号隔离。当前版本不提供端到端加密。\n\n本机日记与各云端账号分别保存，退出账号不会删除本机副本。卸载应用前请导出备份。\n\n云端配置步骤见代码仓库 README。原网页版的日记不会自动迁移。',style:TextStyle(height:1.8,fontSize:12))]))));
}
