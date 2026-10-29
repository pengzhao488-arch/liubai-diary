import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

/// Explicit application-level direct routing. System VPN/TUN routing, if any,
/// remains controlled by the operating system. TLS validation stays enabled.
HttpClient directHttpClient() {
  final client = HttpClient();
  client.findProxy = (_) => 'DIRECT';
  client.connectionTimeout = const Duration(seconds: 15);
  return client;
}

http.Client directClient() => IOClient(directHttpClient());

String networkFailure(Object error) {
  if (error is HandshakeException) {
    return 'HTTPS 安全连接未建立。当前使用直连（不读取代理设置）。'
      '这与账号密码无关，本机日记仍可保存；当前网络到云端的连接需要进一步排查。';
  }
  if (error is SocketException || error is http.ClientException) {
    return '直连云端失败或连接被中断。本机日记仍可保存，但尚未上传。'
      '请点击“检测直连”查看结果；反复修改密码不能解决这个连接问题。';
  }
  return '网络请求失败，本机日记仍保留。';
}
