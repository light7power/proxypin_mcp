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

/// MCP Server - 主类，管理传输层、工具处理器和资源提供者
library mcp_server;

import 'dart:async';
import 'dart:convert';

import 'package:proxypin/mcp/mcp_config.dart';
import 'package:proxypin/mcp/mcp_protocol.dart';
import 'package:proxypin/mcp/mcp_transport.dart';
import 'package:proxypin/mcp/mcp_tool_handler.dart';
import 'package:proxypin/mcp/mcp_resource_provider.dart';
import 'package:proxypin/network/bin/listener.dart';
import 'package:proxypin/network/bin/server.dart';
import 'package:proxypin/network/channel/channel.dart';
import 'package:proxypin/network/channel/channel_context.dart';
import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/network/http/websocket.dart';
import 'package:proxypin/network/util/logger.dart';

/// MCP Server 单例主类
///
/// 负责：
/// - 管理 HTTP/SSE 传输层
/// - 调度工具调用和资源读取
/// - 作为 EventListener 监听代理事件
/// - 通过 SSE 推送实时请求通知
class McpServer extends EventListener {
  static McpServer? _instance;

  final McpServerConfig config;
  final McpResourceProvider _resourceProvider;
  late final HttpSseTransport _transport;
  StreamSubscription<McpMessage>? _messageSubscription;
  bool _initialized = false;
  bool _running = false;

  McpServer._(this.config)
      : _resourceProvider = McpResourceProvider();

  /// 工厂方法：创建或返回已有实例
  static McpServer create(McpServerConfig config) {
    if (_instance != null) return _instance!;
    _instance = McpServer._(config);
    return _instance!;
  }

  /// 获取单例实例
  static McpServer? get instance => _instance;

  /// 是否正在运行
  bool get isRunning => _running;

  /// 是否已初始化
  bool get initialized => _initialized;

  /// 启动 MCP Server
  Future<void> start() async {
    if (_running) return;

    try {
      final host = config.allowRemote ? '0.0.0.0' : '127.0.0.1';
      _transport = HttpSseTransport(
        port: config.port,
        host: host,
        authToken: config.authToken?.isNotEmpty == true ? config.authToken : null,
      );

      await _transport.start();

      // 订阅传输层消息
      _messageSubscription = _transport.messages.listen(_handleMessage);

      _running = true;
      logger.i('MCP Server started on $host:${config.port}');
    } catch (e) {
      logger.e('MCP Server start error: $e');
      _running = false;
      rethrow;
    }
  }

  /// 停止 MCP Server
  Future<void> stop() async {
    if (!_running) return;

    await _messageSubscription?.cancel();
    _messageSubscription = null;
    await _transport.stop();
    _running = false;
    _initialized = false;
    logger.i('MCP Server stopped');
  }

  /// 处理收到的 MCP 消息
  void _handleMessage(McpMessage message) {
    if (message is McpNotification) {
      _handleNotification(message);
      return;
    }

    if (message is McpRequest) {
      _handleRequest(message);
      return;
    }
  }

  /// 处理通知消息
  void _handleNotification(McpNotification notification) {
    switch (notification.method) {
      case McpMethods.notificationsInitialized:
        _initialized = true;
        logger.d('MCP client initialized');
        break;
      default:
        logger.d('Unhandled notification: ${notification.method}');
    }
  }

  /// 处理请求消息
  void _handleRequest(McpRequest request) {
    try {
      switch (request.method) {
        case McpMethods.initialize:
          _handleInitialize(request);
          break;
        case McpMethods.ping:
          _handlePing(request);
          break;
        case McpMethods.toolsList:
          _handleToolsList(request);
          break;
        case McpMethods.toolsCall:
          _handleToolsCall(request);
          break;
        case McpMethods.resourcesList:
          _handleResourcesList(request);
          break;
        case McpMethods.resourcesRead:
          _handleResourcesRead(request);
          break;
        default:
          _sendError(request.id,
              -32601, 'Method not found: ${request.method}');
      }
    } catch (e) {
      logger.e('Error handling request ${request.method}: $e');
      _sendError(request.id, -32603, 'Internal error: $e');
    }
  }

  /// 处理 initialize 请求
  void _handleInitialize(McpRequest request) {
    final protocolVersion = request.params?['protocolVersion'] as String? ?? '2024-11-05';
    final clientInfo = request.params?['clientInfo'] as Map<String, dynamic>? ?? {};

    logger.i('MCP client connected: ${clientInfo['name'] ?? 'unknown'} v${clientInfo['version'] ?? '?'}');

    final response = McpResponse.success({
      'protocolVersion': protocolVersion,
      'serverInfo': {
        'name': 'ProxyPin MCP',
        'version': '1.0.0',
      },
      'capabilities': {
        'tools': {},
        'resources': {},
      },
    }, id: request.id);

    _sendResponse(response);
    _initialized = true;
  }

  /// 处理 ping 请求
  void _handlePing(McpRequest request) {
    _sendResponse(McpResponse.success(null, id: request.id));
  }

  /// 处理 tools/list 请求
  void _handleToolsList(McpRequest request) {
    final tools = McpToolHandler.getTools();
    _sendResponse(McpResponse.success({
      'tools': tools.map((t) => t.toJson()).toList(),
    }, id: request.id));
  }

  /// 处理 tools/call 请求
  void _handleToolsCall(McpRequest request) async {
    final params = request.params ?? {};
    final name = params['name'] as String?;
    final arguments = params['arguments'] as Map<String, dynamic>? ?? {};

    if (name == null || name.isEmpty) {
      _sendError(request.id, -32602, 'Tool name is required');
      return;
    }

    try {
      final server = ProxyServer.current;
      if (server == null) {
        _sendError(request.id, -32001, 'ProxyServer not available');
        return;
      }

      final context = McpToolContext(server: server, args: {
        'name': name,
        'arguments': arguments,
      });

      final result = await McpToolHandler.execute(context);
      _sendResponse(McpResponse.success(result, id: request.id));
    } catch (e) {
      logger.e('Tool execution error: $e');
      _sendError(request.id, -32603, 'Tool execution failed: $e');
    }
  }

  /// 处理 resources/list 请求
  void _handleResourcesList(McpRequest request) async {
    try {
      final resources = await _resourceProvider.getResources();
      _sendResponse(McpResponse.success({
        'resources': resources.map((r) => r.toJson()).toList(),
      }, id: request.id));
    } catch (e) {
      logger.e('Resources list error: $e');
      _sendError(request.id, -32603, 'Failed to list resources: $e');
    }
  }

  /// 处理 resources/read 请求
  void _handleResourcesRead(McpRequest request) async {
    final params = request.params ?? {};
    final uri = params['uri'] as String?;

    if (uri == null || uri.isEmpty) {
      _sendError(request.id, -32602, 'Resource URI is required');
      return;
    }

    try {
      final content = await _resourceProvider.readResource(uri);
      _sendResponse(McpResponse.success({
        'contents': [content.toJson()],
      }, id: request.id));
    } catch (e) {
      logger.e('Resource read error: $e');
      _sendError(request.id, -32603, 'Failed to read resource: $e');
    }
  }

  /// 发送响应
  void _sendResponse(McpResponse response) {
    _transport.sendMessage(response.toJson());
  }

  /// 发送错误响应
  void _sendError(String? id, int code, String message) {
    _transport.sendMessage(
      McpResponse.failure(code, message, id: id).toJson(),
    );
  }

  // ============= EventListener 接口实现 =============

  @override
  void onRequest(Channel channel, HttpRequest request) {
    if (!_running || !_initialized) return;
    try {
      final notification = McpNotification(
        method: 'notifications/request',
        params: {
          'id': request.id,
          'url': request.requestLine?.uri,
          'method': request.method,
          'host': request.host,
        },
      );
      _transport.sendMessage(notification.toJson());
    } catch (e) {
      // 忽略推送错误
    }
  }

  @override
  void onResponse(ChannelContext channelContext, HttpResponse response) {
    if (!_running || !_initialized) return;
    try {
      final request = channelContext.request;
      final notification = McpNotification(
        method: 'notifications/response',
        params: {
          'id': request?.id,
          'statusCode': response.statusCode,
          'contentType': response.headers?.value('content-type'),
          'bodySize': response.body?.length,
        },
      );
      _transport.sendMessage(notification.toJson());
    } catch (e) {
      // 忽略推送错误
    }
  }

  @override
  void onMessage(Channel channel, HttpMessage message, WebSocketFrame frame) {
    if (!_running || !_initialized) return;
    try {
      final notification = McpNotification(
        method: 'notifications/message',
        params: {
          'channelId': channel.id,
          'frameType': frame.opcode,
          'dataLength': frame.payloadData?.length,
        },
      );
      _transport.sendMessage(notification.toJson());
    } catch (e) {
      // 忽略推送错误
    }
  }
}
