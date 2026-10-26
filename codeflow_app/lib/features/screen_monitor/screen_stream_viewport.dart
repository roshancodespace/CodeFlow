import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../services/companion_api_service.dart';

enum StreamStatus { idle, connecting, streaming, reconnecting, error }

/// Viewport widget rendering the live MJPEG screen stream from CodeFlow Companion.
class ScreenStreamViewport extends StatefulWidget {
  final String host;
  final int port;
  final String? token;
  final CompanionApiService apiService;

  const ScreenStreamViewport({
    super.key,
    required this.host,
    required this.port,
    this.token,
    required this.apiService,
  });

  @override
  State<ScreenStreamViewport> createState() => _ScreenStreamViewportState();
}

class _ScreenStreamViewportState extends State<ScreenStreamViewport> {
  StreamStatus _status = StreamStatus.idle;
  Uint8List? _currentFrame;
  HttpClient? _httpClient;
  HttpClientRequest? _activeRequest;
  StreamSubscription<List<int>>? _streamSub;

  int _frameCount = 0;
  double _measuredFps = 0.0;
  Timer? _fpsTimer;
  Timer? _pingTimer;
  int? _roundTripLatencyMs;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _startStream();
    _startMetrics();
  }

  void _startMetrics() {
    _fpsTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _measuredFps = _frameCount.toDouble();
          _frameCount = 0;
        });
      }
    });

    _pingTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      final lat = await widget.apiService.measurePingLatency(
        host: widget.host,
        port: widget.port,
      );
      if (mounted) {
        setState(() {
          _roundTripLatencyMs = lat;
        });
      }
    });
  }

  Future<void> _startStream() async {
    _stopStream();
    setState(() {
      _status = StreamStatus.connecting;
      _errorMessage = null;
    });

    try {
      _httpClient = HttpClient()
        ..connectionTimeout = const Duration(seconds: 5);

      final uri = Uri.parse('http://${widget.host}:${widget.port}/stream');
      final request = await _httpClient!.getUrl(uri);
      _activeRequest = request;

      if (widget.token != null && widget.token!.isNotEmpty) {
        request.headers.set('Authorization', 'Bearer ${widget.token}');
        request.headers.set('X-CodeFlow-Token', widget.token!);
      }

      final response = await request.close();
      if (response.statusCode != 200) {
        throw Exception('Stream endpoint returned HTTP ${response.statusCode}');
      }

      setState(() {
        _status = StreamStatus.streaming;
      });

      // MJPEG parser buffer
      final buffer = BytesBuilder(copy: false);
      const jpegStart = [0xFF, 0xD8];
      const jpegEnd = [0xFF, 0xD9];

      _streamSub = response.listen(
        (chunk) {
          buffer.add(chunk);
          final bytes = buffer.toBytes();

          // Find JPEG start marker 0xFF 0xD8
          int startIdx = -1;
          for (int i = 0; i < bytes.length - 1; i++) {
            if (bytes[i] == jpegStart[0] && bytes[i + 1] == jpegStart[1]) {
              startIdx = i;
              break;
            }
          }

          if (startIdx >= 0) {
            // Find JPEG end marker 0xFF 0xD9 after startIdx
            int endIdx = -1;
            for (int i = startIdx + 2; i < bytes.length - 1; i++) {
              if (bytes[i] == jpegEnd[0] && bytes[i + 1] == jpegEnd[1]) {
                endIdx = i + 2;
                break;
              }
            }

            if (endIdx > startIdx) {
              final frameBytes = bytes.sublist(startIdx, endIdx);
              if (mounted) {
                setState(() {
                  _currentFrame = frameBytes;
                  _frameCount++;
                });
              }

              // Retain remaining data after the extracted frame
              buffer.clear();
              if (endIdx < bytes.length) {
                buffer.add(bytes.sublist(endIdx));
              }
            }
          }

          // Guard against unbounded buffer buildup if network drops packets
          if (buffer.length > 2 * 1024 * 1024) {
            buffer.clear();
          }
        },
        onError: (Object error) {
          if (mounted) {
            setState(() {
              _status = StreamStatus.error;
              _errorMessage = 'Stream disconnected: $error';
            });
          }
        },
        onDone: () {
          if (mounted && _status == StreamStatus.streaming) {
            setState(() {
              _status = StreamStatus.reconnecting;
            });
            Future.delayed(const Duration(seconds: 1), _startStream);
          }
        },
        cancelOnError: true,
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _status = StreamStatus.error;
          _errorMessage = e.toString();
        });
      }
    }
  }

  void _stopStream() {
    _streamSub?.cancel();
    _streamSub = null;
    _activeRequest?.abort();
    _activeRequest = null;
    _httpClient?.close(force: true);
    _httpClient = null;
  }

  Future<void> _fetchSingleScreenshot() async {
    final frame = await widget.apiService.getScreenshot(
      host: widget.host,
      port: widget.port,
      token: widget.token,
    );
    if (frame != null && mounted) {
      setState(() {
        _currentFrame = frame;
        _errorMessage = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Screenshot refreshed.'),
          duration: Duration(seconds: 1),
        ),
      );
    }
  }

  @override
  void dispose() {
    _fpsTimer?.cancel();
    _pingTimer?.cancel();
    _stopStream();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor = isDark
        ? AppColors.darkSurface
        : AppColors.lightSurface;
    final borderColor = isDark ? AppColors.darkBorder : AppColors.lightBorder;

    return Container(
      decoration: BoxDecoration(
        color: surfaceColor,
        border: Border.all(color: borderColor),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Stream Header Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: borderColor)),
            ),
            child: Row(
              children: [
                _buildStatusDot(),
                const SizedBox(width: 8),
                Text(
                  _statusText,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                if (_status == StreamStatus.streaming) ...[
                  Text(
                    '${_measuredFps.toStringAsFixed(1)} FPS',
                    style: const TextStyle(
                      fontSize: 11,
                      fontFamily: 'monospace',
                    ),
                  ),
                  const SizedBox(width: 12),
                  if (_roundTripLatencyMs != null)
                    Text(
                      '${_roundTripLatencyMs}ms ping',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.lightTextMuted,
                        fontFamily: 'monospace',
                      ),
                    ),
                  const SizedBox(width: 12),
                ],
                IconButton(
                  icon: const Icon(Icons.camera_alt_outlined, size: 18),
                  tooltip: 'Capture Screenshot',
                  onPressed: _fetchSingleScreenshot,
                  visualDensity: VisualDensity.compact,
                ),
                IconButton(
                  icon: Icon(
                    _status == StreamStatus.streaming
                        ? Icons.pause
                        : Icons.play_arrow,
                    size: 18,
                  ),
                  tooltip: _status == StreamStatus.streaming
                      ? 'Pause Stream'
                      : 'Start Stream',
                  onPressed: () {
                    if (_status == StreamStatus.streaming) {
                      _stopStream();
                      setState(() => _status = StreamStatus.idle);
                    } else {
                      _startStream();
                    }
                  },
                  visualDensity: VisualDensity.compact,
                ),
                IconButton(
                  icon: const Icon(Icons.refresh, size: 18),
                  tooltip: 'Reconnect Stream',
                  onPressed: _startStream,
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),

          // Stream Viewport Body
          Expanded(
            child: Container(
              color: Colors.black,
              alignment: Alignment.center,
              child: _buildViewportContent(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildViewportContent() {
    if (_currentFrame != null) {
      return InteractiveViewer(
        maxScale: 4.0,
        minScale: 0.5,
        child: Image.memory(
          _currentFrame!,
          fit: BoxFit.contain,
          gaplessPlayback: true,
        ),
      );
    }

    if (_status == StreamStatus.connecting) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white70,
              ),
            ),
            SizedBox(height: 12),
            Text(
              'Connecting to PC Stream...',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ],
        ),
      );
    }

    if (_status == StreamStatus.error) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline,
                color: AppColors.statusError,
                size: 32,
              ),
              const SizedBox(height: 8),
              Text(
                _errorMessage ?? 'Stream disconnected',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
              const SizedBox(height: 12),
              FilledButton.tonal(
                onPressed: _startStream,
                child: const Text('Retry Connection'),
              ),
            ],
          ),
        ),
      );
    }

    return Center(
      child: TextButton.icon(
        icon: const Icon(Icons.play_circle_outline, color: Colors.white70),
        label: const Text(
          'Start Screen Stream',
          style: TextStyle(color: Colors.white70),
        ),
        onPressed: _startStream,
      ),
    );
  }

  Widget _buildStatusDot() {
    Color color;
    switch (_status) {
      case StreamStatus.streaming:
        color = AppColors.statusSuccess;
        break;
      case StreamStatus.connecting:
      case StreamStatus.reconnecting:
        color = AppColors.statusWarning;
        break;
      case StreamStatus.error:
        color = AppColors.statusError;
        break;
      case StreamStatus.idle:
        color = AppColors.lightTextMuted;
        break;
    }
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );
  }

  String get _statusText {
    switch (_status) {
      case StreamStatus.streaming:
        return 'LIVE';
      case StreamStatus.connecting:
        return 'Connecting...';
      case StreamStatus.reconnecting:
        return 'Reconnecting...';
      case StreamStatus.error:
        return 'Error';
      case StreamStatus.idle:
        return 'Offline';
    }
  }
}
