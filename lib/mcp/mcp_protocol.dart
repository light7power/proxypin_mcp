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

/// MCP (Machine Conversation Protocol) 协议定义
library mcp_protocol;

import 'dart:convert';

/// MCP 消息基类
class McpMessage {
  final String jsonrpc;
  final String? id;

  McpMessage({this.jsonrpc = '2.0', this.id});

  Map<String, dynamic> toJson() => {
        'jsonrpc': jsonrpc,
        if (id != null) 'id': id,
      };

  static T? fromJson<T extends McpMessage>(Map<String, dynamic> json) {
    final method = json['method'] as String?;
    if (method != null) {
      return McpRequest.fromJson(json) as T?;
    } else if (json.containsKey('result') || json.containsKey('error')) {
      return McpResponse.fromJson(json) as T?;
    }
    return null;
  }
}

/// MCP 请求
class McpRequest extends McpMessage {
  final String method;
  final Map<String, dynamic>? params;

  McpRequest({
    required this.method,
    this.params,
    super.id,
    super.jsonrpc,
  });

  @override
  Map<String, dynamic> toJson() => {
        ...super.toJson(),
        'method': method,
        if (params != null) 'params': params,
      };

  static McpRequest fromJson(Map<String, dynamic> json) => McpRequest(
        method: json['method'] as String,
        params: json['params'] as Map<String, dynamic>?,
        id: json['id'] as String?,
        jsonrpc: json['jsonrpc'] as String? ?? '2.0',
      );
}

/// MCP 响应
class McpResponse extends McpMessage {
  final dynamic result;
  final McpError? error;

  McpResponse({
    this.result,
    this.error,
    super.id,
    super.jsonrpc,
  });

  @override
  Map<String, dynamic> toJson() => {
        ...super.toJson(),
        if (error != null) 'error': error!.toJson(),
        if (result != null && error == null) 'result': result,
      };

  static McpResponse fromJson(Map<String, dynamic> json) => McpResponse(
        result: json['result'],
        error: json['error'] != null
            ? McpError.fromJson(json['error'] as Map<String, dynamic>)
            : null,
        id: json['id'] as String?,
        jsonrpc: json['jsonrpc'] as String? ?? '2.0',
      );

  static McpResponse success(dynamic data, {String? id}) =>
      McpResponse(result: data, id: id);

  static McpResponse failure(int code, String message,
          {dynamic data, String? id}) =>
      McpResponse(error: McpError(code: code, message: message, data: data), id: id);
}

/// MCP 错误
class McpError {
  final int code;
  final String message;
  final dynamic data;

  McpError({required this.code, required this.message, this.data});

  Map<String, dynamic> toJson() => {
        'code': code,
        'message': message,
        if (data != null) 'data': data,
      };

  static McpError fromJson(Map<String, dynamic> json) => McpError(
        code: json['code'] as int,
        message: json['message'] as String,
        data: json['data'],
      );
}

/// MCP 工具定义
class McpTool {
  final String name;
  final String description;
  final Map<String, dynamic>? inputSchema;

  const McpTool({
    required this.name,
    this.description = '',
    this.inputSchema,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'description': description,
        if (inputSchema != null) 'inputSchema': inputSchema,
      };
}

/// MCP 资源定义
class McpResource {
  final String uri;
  final String name;
  final String? description;
  final String? mimeType;

  const McpResource({
    required this.uri,
    required this.name,
    this.description,
    this.mimeType = 'application/json',
  });

  Map<String, dynamic> toJson() => {
        'uri': uri,
        'name': name,
        if (description != null) 'description': description,
        if (mimeType != null) 'mimeType': mimeType,
      };
}

/// MCP 资源内容
class McpResourceContent {
  final String uri;
  final String mimeType;
  final String text;

  McpResourceContent({
    required this.uri,
    this.mimeType = 'application/json',
    required this.text,
  });

  Map<String, dynamic> toJson() => {
        'uri': uri,
        'mimeType': mimeType,
        'text': text,
      };
}

/// MCP 通知消息（无 ID）
class McpNotification extends McpMessage {
  final String method;
  final Map<String, dynamic>? params;

  McpNotification({required this.method, this.params}) : super(id: null);

  @override
  Map<String, dynamic> toJson() => {
        'jsonrpc': jsonrpc,
        'method': method,
        if (params != null) 'params': params,
      };

  static McpNotification fromJson(Map<String, dynamic> json) =>
      McpNotification(
        method: json['method'] as String,
        params: json['params'] as Map<String, dynamic>?,
      );
}

/// MCP 消息解析器
class McpMessageParser {
  static McpMessage? parse(String data) {
    try {
      final json = jsonDecode(data) as Map<String, dynamic>;
      if (json['id'] == null && json['method'] != null) {
        return McpNotification.fromJson(json);
      }
      return McpMessage.fromJson(json);
    } catch (e) {
      return null;
    }
  }
}

/// MCP 标准方法名
class McpMethods {
  static const String initialize = 'initialize';
  static const String ping = 'ping';
  static const String resourcesList = 'resources/list';
  static const String resourcesRead = 'resources/read';
  static const String toolsList = 'tools/list';
  static const String toolsCall = 'tools/call';
  static const String notificationsInitialized = 'notifications/initialized';
}
