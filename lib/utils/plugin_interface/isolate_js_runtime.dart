import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/services.dart';
import 'package:flutter_js/flutter_js.dart';
import 'package:path/path.dart' as p;

late JavascriptRuntime _runtime;
bool _initialized = false;

void initPluginIsolate(SendPort mainSendPort) async {
  final receivePort = ReceivePort();
  mainSendPort.send(receivePort.sendPort);

  await for (final message in receivePort) {
    if (!_initialized) {
      _setup(message);
      continue;
    }

    if (message["type"] == "dispose") {
      _runtime.dispose();
      Isolate.current.kill();
      return;
    }

    _callFunction(message);
  }
}

void _setup(Map<String, dynamic> initMessage) {
  final rootToken = initMessage["rootToken"] as RootIsolateToken;
  final SendPort logPort = initMessage["logPort"] as SendPort;
  final SendPort fetchPort = initMessage["fetchPort"] as SendPort;
  final SendPort readyPort = initMessage["readyPort"] as SendPort;
  final String cachePath = initMessage["cachePath"] as String;
  BackgroundIsolateBinaryMessenger.ensureInitialized(rootToken);

  _runtime = getJavascriptRuntime(xhr: false);
  final jsCode = File("${initMessage["pluginPath"] as String}/bundle.js")
      .readAsStringSync();
  _runtime.evaluate(jsCode);

  _runtime.onMessage(
      "consoleLog",
      (dynamic args) => logPort.send({
            "level": args["level"],
            "message": args["message"],
          }));

  _runtime.onMessage("httpRequest", (dynamic args) {
    final responsePort = ReceivePort();
    fetchPort.send({
      "responsePort": responsePort.sendPort,
      "url": args["url"],
      "headers": args["headers"]
    });
    return responsePort.first.then((response) {
      responsePort.close();
      return jsonEncode(response as Map);
    });
  });

  _runtime.onMessage("writeCacheFile", (dynamic message) {
    final resolved = p.normalize(p.join(cachePath, message["filePath"]));
    if (!resolved.startsWith(cachePath + p.separator)) {
      logPort.send({
        "level": "error",
        "message": "Failed to write cache file due to invalid path: $resolved",
      });
      return jsonEncode("Error: Invalid path");
    }
    try {
      final file = File(resolved);
      file.createSync(recursive: true);
      file.writeAsBytesSync(base64Decode(message["base64EncodedContents"]));
    } catch (e, st) {
      // Send error message back to main isolate
      logPort.send({
        "level": "error",
        "message": "Failed to write cache file: $e\n$st",
      });
      return jsonEncode("Error: $e");
    }
    return jsonEncode(true);
  });

  _runtime.onMessage("readCacheFile", (dynamic message) {
    final resolved = p.normalize(p.join(cachePath, message["filePath"]));
    if (!resolved.startsWith(cachePath + p.separator)) {
      return jsonEncode("Error: Invalid path");
    }
    try {
      final file = File(resolved);
      return jsonEncode(base64Encode(file.readAsBytesSync()));
    } catch (e, st) {
      // Send warning message back to main isolate
      logPort.send({
        "level": "warning",
        "message": "Failed to read cache file: $e\n$st",
      });
      return jsonEncode("Error: $e");
    }
  });

  _initialized = true;
  readyPort.send(true);
}

void _callFunction(Map<String, dynamic> message) async {
  final SendPort replyPort = message["replyPort"] as SendPort;
  try {
    final String functionName = message["function"] as String;
    final encodedArgs =
        (message["args"] as List).map((a) => jsonEncode(a)).join(", ");

    JsEvalResult jsResult =
        await _runtime.evaluateAsync("$functionName($encodedArgs)");
    _runtime.executePendingJob();

    JsEvalResult finalResult = await _runtime.handlePromise(jsResult);
    // Make sure to await dart futures before sending back to main isolate
    var raw = finalResult.rawResult;
    if (raw is Future) {
      raw = await raw;
    }

    if (finalResult.isError) {
      throw Exception("JS error: ${finalResult.rawResult}");
    }
    replyPort.send({"result": jsonEncode(raw)});
  } catch (e, st) {
    replyPort.send({"error": e.toString(), "stackTrace": st.toString()});
  }
}
