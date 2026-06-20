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

/// MCP 资源提供者
library mcp_resource_provider;

import 'dart:convert';

import 'package:proxypin/mcp/mcp_protocol.dart';
import 'package:proxypin/storage/histories.dart';
import 'package:proxypin/network/http/http.dart';

/// MCP 资源提供者 - 提供历史会话和统计信息资源的读取能力
class McpResourceProvider {
  /// 获取资源列表
  Future<List<McpResource>> getResources() async {
    final storage = await HistoryStorage.instance;
    final sessions = await storage.getSessions();
    return [
      const McpResource(
        uri: 'proxypin://sessions/list',
        name: '会话列表',
        description: '所有历史会话的列表',
      ),
      ...sessions.map((s) => McpResource(
            uri: 'proxypin://sessions/${s.id}',
            name: '会话: ${s.id}',
            description: '请求: ${s.requestLine?.uri ?? "N/A"}',
          )),
      const McpResource(
        uri: 'proxypin://statistics',
        name: '统计信息',
        description: '抓包统计概览',
      ),
    ];
  }

  /// 读取指定资源的内容
  Future<McpResourceContent> readResource(String uri) async {
    if (uri == 'proxypin://sessions/list') {
      return _listSessions();
    }
    if (uri == 'proxypin://statistics') {
      return _getStatistics();
    }
    final sessionMatch = RegExp(r'^proxypin://sessions/(.+)$').firstMatch(uri);
    if (sessionMatch != null) {
      final id = sessionMatch.group(1)!;
      return _getSessionDetail(id);
    }
    throw ArgumentError('Unknown resource: $uri');
  }

  Future<McpResourceContent> _listSessions() async {
    final storage = await HistoryStorage.instance;
    final sessions = await storage.getSessions();
    final data = sessions.map((s) => {
          'id': s.id,
          'url': s.requestLine?.uri,
          'method': s.method,
          'host': s.host,
          'statusCode': s.statusCode,
          'contentType': s.contentType,
          'time': s.time?.toIso8601String(),
          'bodySize': s.contentLength,
        }).toList();
    return McpResourceContent(
      uri: 'proxypin://sessions/list',
      text: jsonEncode(data),
    );
  }

  Future<McpResourceContent> _getSessionDetail(String id) async {
    final storage = await HistoryStorage.instance;
    final session = await storage.getSession(id);
    if (session == null) {
      return McpResourceContent(
        uri: 'proxypin://sessions/$id',
        text: jsonEncode({'error': 'Session not found', 'id': id}),
      );
    }

    final request = session.request;
    final response = session.response;

    final data = <String, dynamic>{
      'id': session.id,
      'url': '${session.host ?? ""}${session.requestLine?.uri ?? ""}',
      'method': session.method,
      'host': session.host,
      'statusCode': session.statusCode,
      'contentType': session.contentType,
      'time': session.time?.toIso8601String(),
      'request': {
        'headers': request?.headers?.map ?? {},
        'body': request?.body?.utf8String(),
        'bodySize': request?.body?.length,
      },
      'response': {
        'headers': response?.headers?.map ?? {},
        'body': response?.body?.utf8String(),
        'bodySize': response?.body?.length,
      },
    };
    return McpResourceContent(
      uri: 'proxypin://sessions/$id',
      text: jsonEncode(data),
    );
  }

  Future<McpResourceContent> _getStatistics() async {
    final storage = await HistoryStorage.instance;
    final sessions = await storage.getSessions();
    final totalSize = sessions.fold<int>(0, (sum, s) => sum + (s.contentLength ?? 0));
    final methods = <String, int>{};
    final statusCodes = <int, int>{};
    for (final s in sessions) {
      final m = s.method ?? 'UNKNOWN';
      methods[m] = (methods[m] ?? 0) + 1;
      final code = s.statusCode ?? 0;
      statusCodes[code] = (statusCodes[code] ?? 0) + 1;
    }

    return McpResourceContent(
      uri: 'proxypin://statistics',
      text: jsonEncode({
        'totalSessions': sessions.length,
        'totalSize': totalSize,
        'methods': methods,
        'statusCodes': statusCodes,
      }),
    );
  }
}
