import 'dart:io';

import 'package:hedon_haven/utils/global_vars.dart';
import 'package:http/http.dart';
import 'package:http/io_client.dart';

String findFastestProxy() {
  throw UnimplementedError();
}

String findRandomProxy() {
  throw UnimplementedError();
}

Client getHttpClient(String? proxy) {
  final httpClient = HttpClient();
  if (proxy != null && proxy.isNotEmpty) {
    httpClient.findProxy = (uri) => "PROXY $proxy";
    // Allow bad certificates
    httpClient.badCertificateCallback = (cert, host, port) => true;
  }
  httpClient.connectionTimeout = Duration(seconds: 30);
  httpClient.userAgent = httpUserAgent;

  return IOClient(httpClient);
}
