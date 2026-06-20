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

library mcp_config;

/// MCP Server 配置
class McpServerConfig {
  /// 是否启用 MCP Server
  bool enabled;

  /// 监听端口
  int port;

  /// 是否允许远程连接
  bool allowRemote;

  /// 是否自动启动
  bool autoStart;

  /// 认证令牌（可选）
  String? authToken;

  /// 传输方式: http, stdio
  String transport;

  McpServerConfig({
    this.enabled = true,
    this.port = 8080,
    this.allowRemote = false,
    this.autoStart = true,
    this.authToken,
    this.transport = 'http',
  });

  /// 从 JSON 创建
  factory McpServerConfig.fromJson(Map<String, dynamic> json) {
    return McpServerConfig(
      enabled: json['mcpEnabled'] as bool? ?? true,
      port: json['mcpPort'] as int? ?? 8080,
      allowRemote: json['mcpAllowRemote'] as bool? ?? false,
      autoStart: json['mcpAutoStart'] as bool? ?? true,
      authToken: json['mcpToken'] as String?,
      transport: json['mcpTransport'] as String? ?? 'http',
    );
  }

  /// 转为 JSON（带 mcp 前缀，与 ui_config 兼容）
  Map<String, dynamic> toJson() => {
        'mcpEnabled': enabled,
        'mcpPort': port,
        'mcpAllowRemote': allowRemote,
        'mcpAutoStart': autoStart,
        'mcpToken': authToken,
        'mcpTransport': transport,
      };

  /// 创建副本（可选覆盖部分字段）
  McpServerConfig copyWith({
    bool? enabled,
    int? port,
    bool? allowRemote,
    bool? autoStart,
    String? authToken,
    String? transport,
  }) {
    return McpServerConfig(
      enabled: enabled ?? this.enabled,
      port: port ?? this.port,
      allowRemote: allowRemote ?? this.allowRemote,
      autoStart: autoStart ?? this.autoStart,
      authToken: authToken ?? this.authToken,
      transport: transport ?? this.transport,
    );
  }
}
