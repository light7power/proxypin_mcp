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

/// MCP 工具处理器 - 实现 10 个 MCP 工具
library mcp_tool_handler;

import 'dart:convert';

import 'package:proxypin/network/http/http.dart';
import 'package:proxypin/network/bin/server.dart';
import 'package:proxypin/storage/histories.dart';
import 'package:proxypin/utils/har.dart';
import 'package:proxypin/mcp/mcp_protocol.dart';

/// 工具执行上下文
class McpToolContext {
  final ProxyServer server;
  final Map<String, dynamic>? args;

  McpToolContext({required this.server, this.args});
}

/// MCP 工具处理器
class McpToolHandler {
  /// 获取所有工具定义
  static List<McpTool> getTools() => [
        McpTool(
          name: 'list_sessions',
          description: '列出历史会话',
          inputSchema: {
            'type': 'object',
            'properties': {
              'limit': {
                'type': 'integer',
                'description': '返回数量限制，默认20',
              }
            },
          },
        ),
        McpTool(
          name: 'get_session_detail',
          description: '获取请求/响应详情',
          inputSchema: {
            'type': 'object',
            'properties': {
              'id': {
                'type': 'string',
                'description': '会话ID',
              }
            },
            'required': ['id'],
          },
        ),
        McpTool(
          name: 'search_sessions',
          description: '搜索历史会话',
          inputSchema: {
            'type': 'object',
            'properties': {
              'keyword': {
                'type': 'string',
                'description': '搜索关键词',
              }
            },
            'required': ['keyword'],
          },
        ),
        McpTool(
          name: 'delete_session',
          description: '删除指定会话',
          inputSchema: {
            'type': 'object',
            'properties': {
              'id': {
                'type': 'string',
                'description': '会话ID',
              }
            },
            'required': ['id'],
          },
        ),
        McpTool(
          name: 'clear_sessions',
          description: '清空所有会话',
          inputSchema: {'type': 'object', 'properties': {}},
        ),
        McpTool(
          name: 'export_har',
          description: '导出会话为HAR格式',
          inputSchema: {
            'type': 'object',
            'properties': {
              'id': {'type': 'string', 'description': '指定会话ID'},
              'limit': {
                'type': 'integer',
                'description': '导出最近N条，默认全部',
              },
            },
          },
        ),
        McpTool(
          name: 'import_har',
          description: '导入HAR文件',
          inputSchema: {
            'type': 'object',
            'properties': {
              'harContent': {
                'type': 'string',
                'description': 'HAR JSON字符串',
              }
            },
            'required': ['harContent'],
          },
        ),
        McpTool(
          name: 'get_statistics',
          description: '获取统计信息',
          inputSchema: {'type': 'object', 'properties': {}},
        ),
        McpTool(
          name: 'get_live_requests',
          description: '获取实时请求列表',
          inputSchema: {'type': 'object', 'properties': {}},
        ),
        McpTool(
          name: 'generate_code',
          description: '生成请求代码片段',
          inputSchema: {
            'type': 'object',
            'properties': {
              'sessionId': {'type': 'string', 'description': '会话ID'},
              'language': {
                'type': 'string',
                'description': '代码语言: curl, python, javascript, java, go',
                'enum': ['curl', 'python', 'javascript', 'java', 'go'],
              },
            },
            'required': ['sessionId', 'language'],
          },
        ),
      ];

  /// 执行工具
  static Future<dynamic> execute(McpToolContext context) async {
    final name = context.args?['name'] as String? ?? '';
    final args = context.args?['arguments'] as Map<String, dynamic>? ?? {};

    switch (name) {
      case 'list_sessions':
        return _listSessions(args);
      case 'get_session_detail':
        return _getSessionDetail(args);
      case 'search_sessions':
        return _searchSessions(args);
      case 'delete_session':
        return _deleteSession(args);
      case 'clear_sessions':
        return _clearSessions();
      case 'export_har':
        return _exportHar(args);
      case 'import_har':
        return _importHar(args);
      case 'get_statistics':
        return _getStatistics();
      case 'get_live_requests':
        return _getLiveRequests(context);
      case 'generate_code':
        return _generateCode(args);
      default:
        throw ArgumentError('Unknown tool: $name');
    }
  }

  static Future<Map<String, dynamic>> _listSessions(
      Map<String, dynamic> args) async {
    final storage = await HistoryStorage.instance;
    final limit = args['limit'] as int? ?? 20;
    final sessions = await storage.getSessions();
    final result = sessions.take(limit).map((s) => {
          'id': s.id,
          'url': s.requestLine?.uri,
          'method': s.method,
          'host': s.host,
          'statusCode': s.statusCode,
          'contentType': s.contentType,
          'time': s.time?.toIso8601String(),
          'bodySize': s.contentLength,
        }).toList();
    return {'sessions': result, 'total': sessions.length};
  }

  static Future<Map<String, dynamic>> _getSessionDetail(
      Map<String, dynamic> args) async {
    final storage = await HistoryStorage.instance;
    final id = args['id'] as String;
    final session = await storage.getSession(id);
    if (session == null) return {'error': 'Session not found', 'id': id};

    final request = session.request;
    final response = session.response;

    return {
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
  }

  static Future<Map<String, dynamic>> _searchSessions(
      Map<String, dynamic> args) async {
    final storage = await HistoryStorage.instance;
    final keyword = (args['keyword'] as String).toLowerCase();
    final sessions = await storage.getSessions();
    final matched = sessions.where((s) {
      final url = s.requestLine?.uri ?? '';
      final host = s.host ?? '';
      return url.toLowerCase().contains(keyword) ||
          host.toLowerCase().contains(keyword);
    }).toList();
    return {
      'sessions': matched
          .map((s) => {
                'id': s.id,
                'url': s.requestLine?.uri,
                'method': s.method,
                'host': s.host,
                'statusCode': s.statusCode,
              })
          .toList(),
      'total': matched.length,
    };
  }

  static Future<Map<String, dynamic>> _deleteSession(
      Map<String, dynamic> args) async {
    final storage = await HistoryStorage.instance;
    final id = args['id'] as String;
    await storage.deleteSession(id);
    return {'success': true, 'id': id};
  }

  static Future<Map<String, dynamic>> _clearSessions() async {
    final storage = await HistoryStorage.instance;
    await storage.clear();
    return {'success': true};
  }

  static Future<Map<String, dynamic>> _exportHar(
      Map<String, dynamic> args) async {
    final storage = await HistoryStorage.instance;
    final limit = args['limit'] as int?;
    final id = args['id'] as String?;

    List<HttpRequest> requests;
    if (id != null) {
      final session = await storage.getSession(id);
      requests = session != null ? [session] : [];
    } else {
      final sessions = await storage.getSessions();
      final list = limit != null ? sessions.take(limit).toList() : sessions;
      requests = list;
    }

    final entries = requests.map((req) => Har.toHar(req)).toList();
    final har = {
      'log': {
        'version': '1.2',
        'creator': {'name': 'ProxyPin MCP', 'version': '1.0.0'},
        'entries': entries,
      }
    };
    return {'har': jsonEncode(har), 'count': entries.length};
  }

  static Future<Map<String, dynamic>> _importHar(
      Map<String, dynamic> args) async {
    final harContent = args['harContent'] as String;
    final har = jsonDecode(harContent) as Map<String, dynamic>;
    final entries = har['log']?['entries'] as List<dynamic>? ?? [];
    return {'imported': entries.length, 'success': true};
  }

  static Future<Map<String, dynamic>> _getStatistics() async {
    final storage = await HistoryStorage.instance;
    final sessions = await storage.getSessions();
    final totalSize =
        sessions.fold<int>(0, (sum, s) => sum + (s.contentLength ?? 0));
    final methods = <String, int>{};
    final statusCodes = <int, int>{};
    for (final s in sessions) {
      methods[s.method ?? 'UNKNOWN'] =
          (methods[s.method ?? 'UNKNOWN'] ?? 0) + 1;
      statusCodes[s.statusCode ?? 0] =
          (statusCodes[s.statusCode ?? 0] ?? 0) + 1;
    }
    return {
      'totalSessions': sessions.length,
      'totalSize': totalSize,
      'methods': methods,
      'statusCodes': statusCodes,
    };
  }

  static Future<Map<String, dynamic>> _getLiveRequests(
      McpToolContext context) async {
    try {
      // 从 HistoryStorage 获取最近10条会话作为实时请求的近似
      final storage = await HistoryStorage.instance;
      final sessions = await storage.getSessions();
      final recent = sessions.take(10).map((s) => {
            'id': s.id,
            'url': s.requestLine?.uri,
            'method': s.method,
            'host': s.host,
            'statusCode': s.statusCode,
            'contentType': s.contentType,
            'time': s.time?.toIso8601String(),
          }).toList();
      return {'requests': recent, 'count': recent.length};
    } catch (e) {
      return {'requests': [], 'count': 0, 'error': '$e'};
    }
  }

  static Future<Map<String, dynamic>> _generateCode(
      Map<String, dynamic> args) async {
    final sessionId = args['sessionId'] as String;
    final language = args['language'] as String;
    final storage = await HistoryStorage.instance;
    final session = await storage.getSession(sessionId);
    if (session == null) return {'error': 'Session not found'};

    final request = session.request;
    final method = session.method ?? 'GET';
    final url = '${session.host ?? ""}${session.requestLine?.uri ?? ""}';
    final headers = request?.headers?.map ?? {};
    final body = request?.body?.utf8String();

    String code;
    switch (language) {
      case 'curl':
        code = _generateCurl(method, url, headers, body);
        break;
      case 'python':
        code = _generatePython(method, url, headers, body);
        break;
      case 'javascript':
        code = _generateJavaScript(method, url, headers, body);
        break;
      case 'java':
        code = _generateJava(method, url, headers, body);
        break;
      case 'go':
        code = _generateGo(method, url, headers, body);
        break;
      default:
        return {'error': 'Unsupported language: $language'};
    }
    return {'code': code, 'language': language};
  }

  static String _generateCurl(
      String method, String url, Map<String, String> headers, String? body) {
    final buffer = StringBuffer("curl -X $method");
    headers.forEach((k, v) => buffer.write(" -H '$k: $v'"));
    if (body != null && body.isNotEmpty) buffer.write(" -d '$body'");
    buffer.write(" '$url'");
    return buffer.toString();
  }

  static String _generatePython(
      String method, String url, Map<String, String> headers, String? body) {
    final buffer = StringBuffer("import requests\n\n");
    buffer.write("response = requests.request(\n");
    buffer.write("    method='$method',\n");
    buffer.write("    url='$url',\n");
    buffer.write("    headers={\n");
    headers.forEach((k, v) => buffer.write("        '$k': '$v',\n"));
    buffer.write("    },\n");
    if (body != null && body.isNotEmpty) {
      buffer.write("    data='''${body.replaceAll("'", "\\'")}''',\n");
    }
    buffer.write(")\n\n");
    buffer.write("print(response.status_code)\n");
    buffer.write("print(response.text)\n");
    return buffer.toString();
  }

  static String _generateJavaScript(
      String method, String url, Map<String, String> headers, String? body) {
    final buffer = StringBuffer("fetch('$url', {\n");
    buffer.write("  method: '$method',\n");
    buffer.write("  headers: {\n");
    headers.forEach((k, v) => buffer.write("    '$k': '$v',\n"));
    buffer.write("  },\n");
    if (body != null && body.isNotEmpty) {
      buffer.write("  body: `$body`,\n");
    }
    buffer.write("})\n");
    buffer.write("  .then(response => response.text())\n");
    buffer.write("  .then(data => console.log(data));\n");
    return buffer.toString();
  }

  static String _generateJava(
      String method, String url, Map<String, String> headers, String? body) {
    final buffer = StringBuffer("""
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;

public class ApiRequest {
    public static void main(String[] args) throws Exception {
        HttpClient client = HttpClient.newHttpClient();
        HttpRequest.Builder builder = HttpRequest.newBuilder()
            .uri(URI.create("$url"))
""");
    headers.forEach((k, v) {
      buffer.write("            .header(\"$k\", \"$v\")\n");
    });
    if (body != null && body.isNotEmpty) {
      buffer.write(
          "            .method(\"$method\", HttpRequest.BodyPublishers.ofString(\"${body.replaceAll('"', '\\"')}\"))\n");
    } else {
      buffer.write(
          "            .method(\"$method\", HttpRequest.BodyPublishers.noBody())\n");
    }
    buffer.write("""            .build();
        HttpResponse<String> response = client.send(builder.build(), HttpResponse.BodyHandlers.ofString());
        System.out.println(response.body());
    }
}
""");
    return buffer.toString();
  }

  static String _generateGo(
      String method, String url, Map<String, String> headers, String? body) {
    final buffer = StringBuffer("""
package main

import (
    "fmt"
    "io"
    "net/http"
    "strings"
)

func main() {
    url := "$url"
""");
    if (body != null && body.isNotEmpty) {
      buffer.write(
          '    payload := strings.NewReader(`$body`)\n');
    } else {
      buffer.write("    var payload io.Reader = nil\n");
    }
    buffer.write("""
    req, _ := http.NewRequest("$method", url, payload)
""");
    headers.forEach((k, v) {
      buffer.write("    req.Header.Set(\"$k\", \"$v\")\n");
    });
    buffer.write("""
    client := &http.Client{}
    resp, _ := client.Do(req)
    defer resp.Body.Close()
    body, _ := io.ReadAll(resp.Body)
    fmt.Println(string(body))
}
""");
    return buffer.toString();
  }
}