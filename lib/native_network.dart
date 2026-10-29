import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

typedef NativeSender = Future<Map<String,dynamic>> Function(Map<String,dynamic>);

class NativeNetworkClient extends http.BaseClient {
  final NativeSender sender;
  NativeNetworkClient(this.sender);
  @override Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if(request.url.scheme!='https') throw http.ClientException('仅支持 HTTPS',request.url);
    final body=await request.finalize().toBytes();
    final payload=<String,dynamic>{'url':request.url.toString(),'method':request.method,
      'headers':Map<String,String>.from(request.headers)..putIfAbsent('accept-encoding',()=>'identity'),
      'body':body};
    try {
      final response=await sender(payload);
      final bytes=response['body'] as Uint8List;
      return http.StreamedResponse(Stream.value(bytes),response['status'] as int,request:request,
        headers:{'content-type':'application/json; charset=utf-8'});
    } on PlatformException catch(e) {
      throw http.ClientException('安卓系统直连失败：${e.message}',request.url);
    }
  }
}

Future<Map<String,dynamic>> androidRequest(Map<String,dynamic> payload) async {
  const channel=MethodChannel('liubai/native_network');
  final response=await channel.invokeMapMethod<String,dynamic>('request',payload);
  if(response==null)throw http.ClientException('系统未返回网络结果');
  return response;
}
Future<Map<String,dynamic>> windowsRequest(Map<String,dynamic> payload) => compute(_windowsRequest,payload);

final class _Response extends Struct {
  @Int32() external int status;
  @Uint32() external int length;
  @Uint32() external int error;
  external Pointer<Uint8> body;
}
typedef _RequestNative=Pointer<_Response> Function(Pointer<Utf16>,Pointer<Utf16>,Pointer<Utf16>,Pointer<Uint8>,Uint32);
typedef _RequestDart=Pointer<_Response> Function(Pointer<Utf16>,Pointer<Utf16>,Pointer<Utf16>,Pointer<Uint8>,int);
typedef _FreeNative=Void Function(Pointer<_Response>);
typedef _FreeDart=void Function(Pointer<_Response>);

Map<String,dynamic> _windowsRequest(Map<String,dynamic> payload) {
  final directory=File(Platform.resolvedExecutable).parent.path;
  final lib=DynamicLibrary.open('$directory/liubai_network.dll');
  final call=lib.lookupFunction<_RequestNative,_RequestDart>('liubai_request');
  final release=lib.lookupFunction<_FreeNative,_FreeDart>('liubai_free');
  final url=(payload['url'] as String).toNativeUtf16();
  final method=(payload['method'] as String).toNativeUtf16();
  final map=Map<String,String>.from(payload['headers']);
  final headers=map.entries.map((e)=>'${e.key}: ${e.value}\r\n').join().toNativeUtf16();
  final bytes=payload['body'] as Uint8List;
  final data=calloc<Uint8>(bytes.isEmpty?1:bytes.length);
  if(bytes.isNotEmpty)data.asTypedList(bytes.length).setAll(0,bytes);
  Pointer<_Response> result=nullptr;
  try {
    result=call(url,method,headers,data,bytes.length);
    if(result==nullptr)throw Exception('系统网络组件内存分配失败');
    if(result.ref.error!=0) {
      throw Exception('Windows 原生直连失败，错误码 ${result.ref.error}。本机日记仍可保存。');
    }
    return {'status':result.ref.status,'body':Uint8List.fromList(
      result.ref.length==0?<int>[]:result.ref.body.asTypedList(result.ref.length))};
  } finally {
    if(result!=nullptr)release(result);
    calloc.free(url);calloc.free(method);calloc.free(headers);calloc.free(data);
  }
}
