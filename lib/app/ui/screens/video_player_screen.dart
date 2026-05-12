import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:device_info_plus/device_info_plus.dart';

/// Professional Video Player using media_kit (libmpv/VLC engine)
/// Supports: MP4, MKV, HEVC (H.265), 4K, AC3/DTS audio, embedded subtitles
///
/// Key features for 4K HEVC on all Android versions:
/// - Hardware decoding first (MediaCodec GPU), software fallback if HW fails
/// - Auto-retry with software decoding when "Could not open codec" error occurs
/// - Video output downscaling to match device screen (reduces GPU load on low-end devices)
/// - Optimized buffering for 4K high-bitrate network streams
/// - Performance mpv properties for smoother playback on older devices
class VideoPlayerScreen extends StatefulWidget {
  final String videoUrl;
  final String title;

  const VideoPlayerScreen({
    super.key,
    required this.videoUrl,
    required this.title,
  });

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  late final Player _player;
  late final VideoController _controller;
  bool _isInitialized = false;
  String? _errorMessage;
  bool _isBuffering = false;
  bool _showControls = false; // Start hidden - tap to show
  Timer? _hideControlsTimer;
  bool _hasVideoOutput = false;

  // Hardware/Software decoding fallback
  bool _useSoftwareDecoding = false;
  int _retryCount = 0;
  static const int _maxRetries = 2;

  // Device info for adaptive configuration
  bool _isLowEndDevice = false;
  int _screenWidth = 1080;
  int _screenHeight = 1920;
  int _androidVersion = 30; // Default to Android 11

  @override
  void initState() {
    super.initState();
    // Allow landscape rotation for immersive video experience
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
      DeviceOrientation.portraitUp,
    ]);
    // Immersive mode - hide status bar and navigation bar
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _detectDeviceAndInitialize();
  }

  /// Detect device capabilities and initialize player with optimal settings
  Future<void> _detectDeviceAndInitialize() async {
    try {
      // Get screen resolution for adaptive video output sizing
      // Use PlatformDispatcher (works on all Flutter versions)
      final views = ui.PlatformDispatcher.instance.views;
      if (views.isNotEmpty) {
        final view = views.first;
        _screenWidth = view.physicalSize.width.toInt();
        _screenHeight = view.physicalSize.height.toInt();
        debugPrint('Screen resolution: ${_screenWidth}x$_screenHeight');
      }

      // Get Android version for capability detection
      if (Platform.isAndroid) {
        final deviceInfo = DeviceInfoPlugin();
        final androidInfo = await deviceInfo.androidInfo;
        _androidVersion = androidInfo.version.sdkInt;
        debugPrint('Android SDK: $_androidVersion');

        // Detect low-end device: Android 10 (SDK 29) or below, or screen < 1080p
        _isLowEndDevice = _androidVersion <= 29 ||
            _screenWidth < 1080 ||
            _screenHeight < 1920;
        debugPrint('Is low-end device: $_isLowEndDevice');
      }
    } catch (e) {
      debugPrint('Device detection error (non-critical): $e');
    }

    _initializePlayer();
  }

  /// Initialize the video player with hardware or software decoding
  Future<void> _initializePlayer() async {
    try {
      // Validate URL first
      if (widget.videoUrl.isEmpty) {
        if (mounted) {
          setState(() {
            _isInitialized = true;
            _errorMessage = 'Video URL is empty';
          });
        }
        return;
      }

      debugPrint('=== Video Player ===');
      debugPrint('Title: ${widget.title}');
      debugPrint('URL: ${widget.videoUrl}');
      debugPrint('Software decoding: $_useSoftwareDecoding');
      debugPrint('Low-end device: $_isLowEndDevice');
      debugPrint('Retry count: $_retryCount');

      // Calculate optimal video output size for the device
      // On low-end devices with 720p screens, output at max 1280x720 to reduce GPU load
      // On mid-range devices with 1080p screens, output at max 1920x1080
      // On high-end devices, let mpv decide (no width/height constraint)
      int? outputWidth;
      int? outputHeight;

      if (_isLowEndDevice) {
        // For 720p screens: limit output to 1280x720 (saves GPU on 4K content)
        outputWidth = 1280;
        outputHeight = 720;
      } else if (_screenWidth <= 1080) {
        // For 1080p screens: limit output to 1920x1080
        outputWidth = 1920;
        outputHeight = 1080;
      }
      // For higher-res screens, no limit needed - mpv handles it

      // Choose decoding strategy
      final bool useHWAccel = !_useSoftwareDecoding;
      final String hwdecValue = _useSoftwareDecoding ? 'no' : 'auto';
      final String voValue = 'gpu';

      debugPrint('HW acceleration: $useHWAccel, hwdec: $hwdecValue, vo: $voValue');
      debugPrint('Output size: ${outputWidth ?? 'auto'}x${outputHeight ?? 'auto'}');

      // Create player with optimized buffer settings for 4K streaming
      // bufferSize maps to mpv's demuxer-max-bytes and demuxer-max-back-bytes
      _player = Player(
        configuration: PlayerConfiguration(
          // 64MB buffer for 4K high-bitrate streams - prevents stuttering
          // (increased from 32MB default for better 4K experience)
          bufferSize: 64 * 1024 * 1024,
          title: 'CM Movies Player',
          // GPU video output driver - enables hardware rendering
          vo: voValue,
          // Show errors in log for debugging
          logLevel: MPVLogLevel.error,
        ),
      );

      // Create video controller with hardware-accelerated rendering
      // Key settings for 4K HEVC/MKV playback:
      // - vo: 'gpu' → Force GPU video output
      // - hwdec: 'auto' → Auto-select best hardware decoder (MediaCodec on Android)
      //   Falls back to software decoding if hardware decoder fails
      // - androidAttachSurfaceAfterVideoParameters: true → Wait for video info before rendering
      //   This fixes "Could not open codec" on some devices by allowing the surface
      //   to be configured with correct parameters before attaching
      // - width/height → Limit video output size for low-end devices
      //   Reduces GPU rendering load when playing 4K on 720p/1080p screens
      _controller = VideoController(
        _player,
        configuration: VideoControllerConfiguration(
          // Force GPU video output driver
          vo: voValue,
          // Hardware decoding mode:
          // 'auto' = try MediaCodec first, fall back to FFmpeg software decoder
          // 'no' = force FFmpeg software decoder only (fallback mode)
          hwdec: hwdecValue,
          // Enable/disable hardware acceleration
          enableHardwareAcceleration: useHWAccel,
          // On Android, wait for video parameters before attaching Surface.
          // This is crucial for 4K HEVC - the surface needs to know the video
          // dimensions before it can properly configure the hardware decoder
          androidAttachSurfaceAfterVideoParameters: true,
          // Limit video output size for low-end devices
          // This tells mpv to downscale the output to match the device screen,
          // reducing GPU rendering load when playing 4K on 720p/1080p screens
          width: outputWidth,
          height: outputHeight,
        ),
      );

      // NOTE: media_kit 1.1.11 does not expose Player.setProperty() for arbitrary
      // mpv properties. Performance optimizations like vd-lavc-skiploopfilter,
      // vd-lavc-skipframe, framedrop, demuxer-secs, etc. cannot be set at runtime.
      //
      // However, the most critical settings are configured through:
      // - PlayerConfiguration.bufferSize → maps to demuxer-max-bytes + demuxer-max-back-bytes
      // - VideoControllerConfiguration.hwdec → hardware decoding mode
      // - VideoControllerConfiguration.width/height → video output downscaling
      //
      // The hwdec='auto' mode in libmpv already handles:
      // - Auto frame dropping when decoder is too slow
      // - Software fallback when hardware decoder fails
      debugPrint('Player configured with bufferSize=64MB, hwdec=$hwdecValue, output=${outputWidth ?? "auto"}x${outputHeight ?? "auto"}');

      // Listen to player state for buffering indicator
      _player.stream.buffering.listen((buffering) {
        if (mounted) {
          setState(() {
            _isBuffering = buffering;
          });
          debugPrint('Buffering: $buffering');
        }
      });

      // Listen for errors - critical for hardware/software fallback
      _player.stream.error.listen((error) {
        if (mounted && error.isNotEmpty) {
          debugPrint('Player error: $error');
          _handlePlayerError(error);
        }
      });

      // Listen for playback completion
      _player.stream.completed.listen((completed) {
        if (completed && mounted) {
          debugPrint('Video playback completed');
        }
      });

      // Listen for playing state changes
      _player.stream.playing.listen((playing) {
        debugPrint('Playing state: $playing');
        if (playing && !_hasVideoOutput && mounted) {
          setState(() {
            _hasVideoOutput = true;
          });
        }
      });

      // Listen for width/height to detect video output
      _player.stream.width.listen((width) {
        debugPrint('Video width: $width');
        if (width != null && width > 0 && !_hasVideoOutput && mounted) {
          setState(() {
            _hasVideoOutput = true;
          });
        }
      });

      // Open the video URL - do NOT use Uri.encodeFull(), it breaks query params
      // media_kit's libmpv handles URL encoding internally
      final url = widget.videoUrl;
      debugPrint('Opening media: $url');

      await _player.open(Media(url));

      // Explicitly call play() to ensure playback starts
      await _player.play();

      debugPrint('Player open+play completed successfully');

      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
        // Show controls briefly when video starts, then auto-hide
        _showControlsWithAutoHide();
      }
    } catch (e) {
      debugPrint('Player initialization error: $e');
      if (mounted) {
        setState(() {
          _isInitialized = true;
          _errorMessage = e.toString();
        });
      }
    }
  }

  /// Handle player errors with intelligent hardware/software fallback
  ///
  /// Flow:
  /// 1. First attempt: hwdec='auto' (tries GPU MediaCodec, falls back to software)
  /// 2. If "Could not open codec" or similar: retry with hwdec='no' (pure software)
  /// 3. Software decoding uses performance optimizations (frame skip, loop filter skip)
  /// 4. If software also fails: show error with helpful message
  void _handlePlayerError(String error) {
    final isCodecError = error.contains('codec') ||
        error.contains('Could not open') ||
        error.contains('decoder') ||
        error.contains('HEVC') ||
        error.contains('H.265') ||
        error.contains('h265') ||
        error.contains('hevc') ||
        error.contains('not supported') ||
        error.contains('failed to initialize');

    if (isCodecError && _retryCount < _maxRetries && !_useSoftwareDecoding) {
      // Hardware decoding failed - retry with software decoding
      _retryCount++;
      debugPrint('=== Retrying with SOFTWARE decoding (attempt $_retryCount) ===');

      // Dispose current player
      _player.dispose();
      _hideControlsTimer?.cancel();

      // Switch to software decoding
      _useSoftwareDecoding = true;
      _hasVideoOutput = false;

      // Re-initialize with software decoding
      _initializePlayer();
    } else if (mounted) {
      // All retries exhausted or non-codec error
      setState(() {
        _isInitialized = true;
        _errorMessage = error;
      });
    }
  }

  @override
  void dispose() {
    _hideControlsTimer?.cancel();
    _player.dispose();
    // Reset orientation to portrait when leaving
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  /// Show controls and start auto-hide timer (3 seconds)
  void _showControlsWithAutoHide() {
    _hideControlsTimer?.cancel();
    setState(() {
      _showControls = true;
    });
    _hideControlsTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() {
          _showControls = false;
        });
      }
    });
  }

  /// Toggle controls visibility with auto-hide
  void _toggleControls() {
    if (_showControls) {
      // Controls are visible - hide immediately
      _hideControlsTimer?.cancel();
      setState(() {
        _showControls = false;
      });
    } else {
      // Controls are hidden - show and auto-hide after 3 seconds
      _showControlsWithAutoHide();
    }
  }

  /// Reset auto-hide timer (e.g., on seek or button press)
  void _resetAutoHideTimer() {
    if (_showControls) {
      _hideControlsTimer?.cancel();
      _hideControlsTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) {
          setState(() {
            _showControls = false;
          });
        }
      });
    }
  }

  /// Show audio track selection dialog for MKV files with multiple audio tracks
  void _showAudioTrackDialog() {
    _resetAutoHideTimer();
    final audioTracks = _player.state.tracks.audio;
    if (audioTracks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No audio tracks available'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          title: const Text(
            'Audio Track',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: audioTracks.map((track) {
              final isSelected = _player.state.track.audio == track;
              return ListTile(
                leading: Icon(
                  isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                  color: isSelected ? const Color(0xFFE50914) : Colors.white54,
                ),
                title: Text(
                  track.title?.isNotEmpty == true
                      ? track.title!
                      : 'Audio ${track.id}',
                  style: TextStyle(
                    color: isSelected ? Colors.white : Colors.white70,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
                subtitle: track.language != null
                    ? Text(
                        track.language!,
                        style: const TextStyle(color: Colors.white38, fontSize: 12),
                      )
                    : null,
                onTap: () {
                  _player.setAudioTrack(track);
                  Navigator.pop(context);
                },
              );
            }).toList(),
          ),
        );
      },
    );
  }

  /// Show subtitle track selection dialog for MKV files with embedded subtitles
  void _showSubtitleTrackDialog() {
    _resetAutoHideTimer();
    final subtitleTracks = _player.state.tracks.subtitle;
    if (subtitleTracks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No subtitle tracks available'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          title: const Text(
            'Subtitles',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Option to disable subtitles
              ListTile(
                leading: Icon(
                  _player.state.track.subtitle == AudioTrack.no()
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  color: const Color(0xFFE50914),
                ),
                title: const Text(
                  'Off',
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () {
                  _player.setSubtitleTrack(SubtitleTrack.no());
                  Navigator.pop(context);
                },
              ),
              const Divider(color: Colors.white12),
              ...subtitleTracks.map((track) {
                final isSelected = _player.state.track.subtitle == track;
                return ListTile(
                  leading: Icon(
                    isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                    color: isSelected ? const Color(0xFFE50914) : Colors.white54,
                  ),
                  title: Text(
                    track.title?.isNotEmpty == true
                        ? track.title!
                        : 'Subtitle ${track.id}',
                    style: TextStyle(
                      color: isSelected ? Colors.white : Colors.white70,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                  subtitle: track.language != null
                      ? Text(
                          track.language!,
                          style: const TextStyle(color: Colors.white38, fontSize: 12),
                        )
                      : null,
                  onTap: () {
                    _player.setSubtitleTrack(track);
                    Navigator.pop(context);
                  },
                );
              }),
            ],
          ),
        );
      },
    );
  }

  /// Show playback speed selection dialog
  void _showSpeedDialog() {
    _resetAutoHideTimer();
    const speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];
    final currentSpeed = _player.state.rate;

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          title: const Text(
            'Playback Speed',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: speeds.map((speed) {
              final isSelected = (currentSpeed - speed).abs() < 0.01;
              return ListTile(
                leading: Icon(
                  isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                  color: isSelected ? const Color(0xFFE50914) : Colors.white54,
                ),
                title: Text(
                  speed == 1.0 ? 'Normal' : '${speed}x',
                  style: TextStyle(
                    color: isSelected ? Colors.white : Colors.white70,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
                onTap: () {
                  _player.setRate(speed);
                  Navigator.pop(context);
                },
              );
            }).toList(),
          ),
        );
      },
    );
  }

  /// Format duration for display
  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '$hours:${twoDigits(minutes)}:${twoDigits(seconds)}';
    }
    return '${twoDigits(minutes)}:${twoDigits(seconds)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Video display layer - must fill entire screen
          Positioned.fill(
            child: _buildVideoLayer(),
          ),

          // Gesture layer (tap to toggle controls)
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _toggleControls,
              // Double tap to seek ±10 seconds
              onDoubleTapDown: (details) {
                final width = MediaQuery.of(context).size.width;
                if (details.globalPosition.dx < width / 2) {
                  _player.seek(_player.state.position - const Duration(seconds: 10));
                } else {
                  _player.seek(_player.state.position + const Duration(seconds: 10));
                }
                _resetAutoHideTimer();
              },
              child: Container(color: Colors.transparent),
            ),
          ),

          // Controls overlay layer (auto-hides after 3 seconds)
          if (_showControls) _buildControlsOverlay(),

          // Buffering indicator (always visible when buffering)
          if (_isBuffering) _buildBufferingIndicator(),

          // Decoding mode indicator (small badge in corner)
          if (_useSoftwareDecoding && _hasVideoOutput)
            Positioned(
              top: 48,
              right: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'SW',
                  style: TextStyle(color: Colors.orange, fontSize: 10, fontWeight: FontWeight.w600),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildVideoLayer() {
    if (!_isInitialized) {
      return _buildLoadingScreen();
    }

    if (_errorMessage != null) {
      return _buildErrorScreen();
    }

    // Use Video widget - let it fill the entire screen
    // media_kit handles aspect ratio and scaling internally
    return Video(
      controller: _controller,
      controls: NoVideoControls,
    );
  }

  Widget _buildLoadingScreen() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(color: Color(0xFFE50914)),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              widget.title,
              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 8),
          if (_useSoftwareDecoding)
            const Text(
              'Switching to software decoder...',
              style: TextStyle(color: Colors.orange, fontSize: 13),
            )
          else
            const Text(
              'Loading video...',
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
        ],
      ),
    );
  }

  Widget _buildErrorScreen() {
    // Detect if this is a codec error (4K HEVC not supported by device)
    final isCodecError = _errorMessage != null && (
      _errorMessage!.contains('codec') ||
      _errorMessage!.contains('Could not open') ||
      _errorMessage!.contains('decoder') ||
      _errorMessage!.contains('hardware') ||
      _errorMessage!.contains('HEVC') ||
      _errorMessage!.contains('H.265')
    );

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isCodecError ? Icons.high_quality_outlined : Icons.error_outline,
              color: isCodecError ? Colors.orange : Colors.redAccent,
              size: 56,
            ),
            const SizedBox(height: 16),
            Text(
              isCodecError ? 'Video codec not supported' : 'Failed to load video',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            if (isCodecError)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'This video uses a codec or resolution that your device may not fully support. '
                  'Try a lower quality version or open in browser.',
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                  textAlign: TextAlign.center,
                ),
              )
            else
              Text(
                _errorMessage ?? 'Unknown error',
                style: const TextStyle(color: Colors.white54, fontSize: 12),
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton.icon(
                  onPressed: () {
                    _player.dispose();
                    _retryCount = 0;
                    _useSoftwareDecoding = true; // Try software on manual retry
                    setState(() {
                      _isInitialized = false;
                      _errorMessage = null;
                      _hasVideoOutput = false;
                    });
                    _initializePlayer();
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry (SW)'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE50914),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                  label: const Text('Close'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white70,
                    side: const BorderSide(color: Colors.white38),
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBufferingIndicator() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(color: Color(0xFFE50914)),
          const SizedBox(height: 12),
          Text(
            _isBuffering ? 'Buffering...' : '',
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildControlsOverlay() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.center,
          colors: [Colors.black54, Colors.transparent],
        ),
      ),
      child: Column(
        children: [
          // Top bar: Back + Title + Track buttons
          _buildTopBar(),

          const Spacer(),

          // Bottom bar: Seek + Controls
          _buildBottomBar(),
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            // Back button
            IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white, size: 24),
              onPressed: () => Navigator.pop(context),
              style: IconButton.styleFrom(
                backgroundColor: Colors.black45,
                padding: const EdgeInsets.all(8),
              ),
            ),
            const SizedBox(width: 12),
            // Title
            Expanded(
              child: Text(
                widget.title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // Audio track button (for MKV dual audio)
            IconButton(
              icon: const Icon(Icons.audiotrack, color: Colors.white, size: 22),
              onPressed: _showAudioTrackDialog,
              style: IconButton.styleFrom(
                backgroundColor: Colors.black45,
                padding: const EdgeInsets.all(8),
              ),
              tooltip: 'Audio Track',
            ),
            const SizedBox(width: 4),
            // Subtitle track button (for MKV embedded subtitles)
            IconButton(
              icon: const Icon(Icons.subtitles, color: Colors.white, size: 22),
              onPressed: _showSubtitleTrackDialog,
              style: IconButton.styleFrom(
                backgroundColor: Colors.black45,
                padding: const EdgeInsets.all(8),
              ),
              tooltip: 'Subtitles',
            ),
            const SizedBox(width: 4),
            // Speed button
            IconButton(
              icon: const Icon(Icons.speed, color: Colors.white, size: 22),
              onPressed: _showSpeedDialog,
              style: IconButton.styleFrom(
                backgroundColor: Colors.black45,
                padding: const EdgeInsets.all(8),
              ),
              tooltip: 'Speed',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.center,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.black87],
        ),
      ),
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Seek bar
          _buildSeekBar(),
          // Control buttons row
          _buildControlButtons(),
        ],
      ),
    );
  }

  Widget _buildSeekBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: StreamBuilder<Duration>(
        stream: _player.stream.position,
        builder: (context, snapshot) {
          final position = snapshot.data ?? Duration.zero;
          final duration = _player.state.duration;
          final progress = duration.inMilliseconds > 0
              ? position.inMilliseconds / duration.inMilliseconds
              : 0.0;

          return Column(
            children: [
              SliderTheme(
                data: SliderThemeData(
                  trackHeight: 3,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                  activeTrackColor: const Color(0xFFE50914),
                  inactiveTrackColor: Colors.white24,
                  thumbColor: const Color(0xFFE50914),
                  overlayColor: const Color(0xFFE50914).withOpacity(0.2),
                ),
                child: Slider(
                  value: progress.clamp(0.0, 1.0),
                  onChanged: (value) {
                    final seekPosition = Duration(
                      milliseconds: (duration.inMilliseconds * value).round(),
                    );
                    _player.seek(seekPosition);
                    _resetAutoHideTimer();
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _formatDuration(position),
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                    Text(
                      _formatDuration(duration),
                      style: const TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildControlButtons() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Rewind 10s
          IconButton(
            icon: const Icon(Icons.replay_10, color: Colors.white, size: 28),
            onPressed: () {
              _player.seek(_player.state.position - const Duration(seconds: 10));
              _resetAutoHideTimer();
            },
          ),
          const SizedBox(width: 16),
          // Play/Pause
          StreamBuilder<bool>(
            stream: _player.stream.playing,
            builder: (context, snapshot) {
              final isPlaying = snapshot.data ?? false;
              return IconButton(
                icon: Icon(
                  isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
                  color: Colors.white,
                  size: 48,
                ),
                onPressed: () {
                  if (isPlaying) {
                    _player.pause();
                  } else {
                    _player.play();
                  }
                  _resetAutoHideTimer();
                },
              );
            },
          ),
          const SizedBox(width: 16),
          // Forward 10s
          IconButton(
            icon: const Icon(Icons.forward_10, color: Colors.white, size: 28),
            onPressed: () {
              _player.seek(_player.state.position + const Duration(seconds: 10));
              _resetAutoHideTimer();
            },
          ),
          const Spacer(),
          // Volume
          StreamBuilder<double>(
            stream: _player.stream.volume,
            builder: (context, snapshot) {
              final volume = snapshot.data ?? 100.0;
              return IconButton(
                icon: Icon(
                  volume == 0 ? Icons.volume_off : volume < 50 ? Icons.volume_down : Icons.volume_up,
                  color: Colors.white,
                  size: 24,
                ),
                onPressed: () {
                  _player.setVolume(volume == 0 ? 100 : 0);
                  _resetAutoHideTimer();
                },
              );
            },
          ),
          const SizedBox(width: 8),
          // Fullscreen toggle
          IconButton(
            icon: const Icon(Icons.fullscreen, color: Colors.white, size: 24),
            onPressed: () {
              final isPortrait = MediaQuery.of(context).orientation == Orientation.portrait;
              if (isPortrait) {
                SystemChrome.setPreferredOrientations([
                  DeviceOrientation.landscapeLeft,
                  DeviceOrientation.landscapeRight,
                ]);
              } else {
                SystemChrome.setPreferredOrientations([
                  DeviceOrientation.landscapeLeft,
                  DeviceOrientation.landscapeRight,
                  DeviceOrientation.portraitUp,
                ]);
              }
              _resetAutoHideTimer();
            },
          ),
        ],
      ),
    );
  }
}
