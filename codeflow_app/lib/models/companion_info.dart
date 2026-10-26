import 'package:flutter/foundation.dart';

/// Monitor information reported by Companion.
@immutable
class MonitorInfo {
  final int id;
  final bool isAll;
  final int left;
  final int top;
  final int width;
  final int height;

  const MonitorInfo({
    required this.id,
    this.isAll = false,
    this.left = 0,
    this.top = 0,
    required this.width,
    required this.height,
  });

  factory MonitorInfo.fromJson(Map<String, dynamic> json) => MonitorInfo(
    id: json['id'] as int? ?? 1,
    isAll: json['is_all'] as bool? ?? false,
    left: json['left'] as int? ?? 0,
    top: json['top'] as int? ?? 0,
    width: json['width'] as int? ?? 1920,
    height: json['height'] as int? ?? 1080,
  );
}

/// Information returned by the companion's /info endpoint.
@immutable
class CompanionInfo {
  final String hostname;
  final String os;
  final String osRelease;
  final String osVersion;
  final String companionVersion;
  final List<MonitorInfo> monitors;
  final int selectedMonitor;
  final String? activeWindow;
  final int targetFps;
  final int jpegQuality;
  final double currentCaptureFps;
  final double latestCaptureDurationMs;
  final bool authRequired;
  final String workspaceDir;

  const CompanionInfo({
    required this.hostname,
    required this.os,
    required this.osRelease,
    required this.osVersion,
    required this.companionVersion,
    required this.monitors,
    required this.selectedMonitor,
    this.activeWindow,
    this.targetFps = 30,
    this.jpegQuality = 75,
    this.currentCaptureFps = 0.0,
    this.latestCaptureDurationMs = 0.0,
    this.authRequired = false,
    this.workspaceDir = '',
  });

  factory CompanionInfo.fromJson(Map<String, dynamic> json) {
    final streamSettings =
        json['stream_settings'] as Map<String, dynamic>? ?? {};
    final monitorsList =
        (json['monitors'] as List<dynamic>?)
            ?.map((m) => MonitorInfo.fromJson(m as Map<String, dynamic>))
            .toList() ??
        const [];

    return CompanionInfo(
      hostname: json['hostname'] as String? ?? 'Unknown Host',
      os: json['os'] as String? ?? 'Unknown OS',
      osRelease: json['os_release'] as String? ?? '',
      osVersion: json['os_version'] as String? ?? '',
      companionVersion: json['companion_version'] as String? ?? '1.0.0',
      monitors: monitorsList,
      selectedMonitor: json['selected_monitor'] as int? ?? 1,
      activeWindow: json['active_window'] as String?,
      targetFps: streamSettings['target_fps'] as int? ?? 30,
      jpegQuality: streamSettings['jpeg_quality'] as int? ?? 75,
      currentCaptureFps:
          (json['current_capture_fps'] as num?)?.toDouble() ?? 0.0,
      latestCaptureDurationMs:
          (json['latest_capture_duration_ms'] as num?)?.toDouble() ?? 0.0,
      authRequired: json['auth_required'] as bool? ?? false,
      workspaceDir: json['workspace_dir'] as String? ?? '',
    );
  }
}
