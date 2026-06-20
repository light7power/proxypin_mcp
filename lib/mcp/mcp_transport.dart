/*
 * Copyright 2023 Hongen Wang All rights reserved.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      https://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

/// MCP 传输层 - HTTP/SSE 实现
library mcp_transport;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:proxypin/mcp/mcp_protocol.dart';

/// MCP 传输抽象接口
abstract class McpTransport {
  Stream<McpMessage> get messages;
  Future<void> sendMessage(Map<String, dynamic> message);
  Future<void> start();
  Future<void> stop();
  bool get isRunning;
}

/// HTTP + SSE 传输实现
class HttpSseTransport implements McpTransport {
  HttpServer? _server;
  final List<StreamController<McpMessage>> _controllers = [];
  bool _running = false;
  final int port;
  final String host;
  final String? authToken;

  HttpSseTransport({
    this.port = 8080,
    this.host = '127.0.0.1',
    this.authToken,
  });

  @override
  bool get isRunning => _running;

  @override
  Stream<McpMessage> get messages => _createController().stream;

  StreamController<McpMessage> _createController() {
    final controller = StreamController<McpMessage>.broadcast();
    _controllers.add(controller);
    return controller;
  }

  @override
  Future<void> start() async {
    if (_running) return;
    _server = await HttpServer.bind(host, port);
    _running = true;
    _server!.listen(_handleRequest);
  }

  @override
  Future<void> stop() async {
    _running = false;
    await _server?.close(force: true);
    _server = null;
    for (final c in _controllers) {
      await c.close();
    }
    _controllers.clear();
  }

  void _handleRequest(HttpRequest request) {
    // CORS 预检请求
    if (request.method == 'OPTIONS') {
      _sendCorsResponse(request.response);
      return;
    }

    // 验证 Token
    if (authToken != null && authToken!.isNotEmpty) {
      final auth = request.headers.value('authorization');
      if (auth == null || auth != 'Bearer $authToken') {
        request.response.statusCode = 401;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({'error': 'Unauthorized'}));
        request.response.close();
        return;
      }
    }

    final uri = request.uri.toString();
    if (uri == '/mcp' && request.method == 'POST') {
      _handleMcpPost(request);
    } else if (uri == '/mcp/sse' && request.method == 'GET') {
      _handleSseConnection(request);
    } else if (uri == '/health' && request.method == 'GET') {
      _handleHealth(request);
    } else {
      request.response.statusCode = 404;
      request.response.close();
    }
  }

  void _handleMcpPost(HttpRequest request) {
    request.transform(utf8.decoder).join().then((body) {
      final message = McpMessageParser.parse(body);
      if (message != null) {
        for (final c in _controllers) {
          c.add(message);
        }
      }
      request.response.statusCode = 202;
      request.response.close();
    });
  }

  void _handleSseConnection(HttpRequest request) {
    request.response.headers.contentType = ContentType('text', 'event-stream');
    request.response.headers.set('Cache-Control', 'no-cache');
    request.response.headers.set('Connection', 'keep-alive');
    request.response.statusCode = 200;

    // 发送初始端点信息
    request.response.writeln('event: endpoint');
    request.response.writeln('data: /mcp');
    request.response.writeln();

    final controller = StreamController<McpMessage>();
    final sub = messages.listen((msg) {
      try {
        request.response.writeln('event: message');
        request.response.writeln('data: ${jsonEncode(msg.toJson())}');
        request.response.writeln();
      } catch (_) {}
    });

    request.response.done.then((_) {
      sub.cancel();
      controller.close();
    });
  }

  void _handleHealth(HttpRequest request) {
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({
      'status': 'ok',
      'service': 'proxypin-mcp',
      'version': '1.0.0',
    }));
    request.response.close();
  }

  void _sendCorsResponse(HttpResponse response) {
    response.headers.set('Access-Control-Allow-Origin', '*');
    response.headers.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
    response.headers.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');
    response.statusCode = 204;
    response.close();
  }

  @override
  Future<void> sendMessage(Map<String, dynamic> message) async {
    // 通过 SSE 发送，由外部调用者写入
  }
}
