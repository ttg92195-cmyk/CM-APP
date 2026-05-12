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
/// Key features:
/// - Manual toggle controls (tap to show/hide, NO auto-hide)
/// - Audio Boost up to 300% (vertical drag on right side of screen)
/// - Hardware decoding first, software fallback if HW fails
/// - Auto-retry with software decoding when "Could not open codec"
/// - Video output downscaling for low-end devices
/// - App lifecycle handling (pause/resume on background/foreground)
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

class _VideoPlayerScreenState extends State<VideoPlayerScreen>
    with WidgetsBindingObserver {
  late final Player _player;
  late final VideoController _controller;
  bool _isInitialized = false;
  String? _errorMessage;
  bool _isBuffering = false;

  // Controls: Manual toggle (tap to show/hide) - NO auto-hide
  bool _showControls = true; // Start visible - user taps to toggle

  bool _hasVideoOutput = false;

  // Hardware/Software decoding fallback
  bool _useSoftwareDecoding = false;
  int _retryCount = 0;
  static const int _maxRetries = 2;

  // Device info for adaptive configuration
  bool _isLowEndDevice = false;
  int _screenWidth = 1080;
  int _screenHeight = 1920;
  int _androidVersion = 30;

  // Audio Boost: media_kit (libmpv) supports volume 0-300+
  // Normal = 100, Boost = 100-300 (may cause distortion above 100)
  double _currentVolume = 100.0;
  static const double _maxVolume = 300.0;
  static const double _normalVolume = 100.0;
  bool _isVolumeBoosted = false;
  bool _showVolumeIndicator = false;
  Timer? _volumeIndicatorTimer;

  // App lifecycle: track if video was playing before going to background
  bool _wasPlayingBeforePause = false;

  @override
  void initState() {
    super.initState();
    // Register for app lifecycle changes (background/foreground)
    WidgetsBinding.instance.addObserver(this);
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

  /// Handle app lifecycle state changes
  /// When app goes to background: pause video
  /// When app comes to foreground: resume video (if it was playing before)
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    debugPrint('App lifecycle: $state');
    switch (state) {
      case AppLifecycleState.paused:
        // App went to background - remember if video was playing, then pause
        _wasPlayingBeforePause = _player.state.playing;
        if (_player.state.playing) {
          _player.pause();
          debugPrint('Video paused (app backgrounded)');
        }
        break;
      case AppLifecycleState.resumed:
        // App came to foreground - resume if it was playing before
        if (_wasPlayingBeforePause && mounted) {
          _player.play();
          debugPrint('Video resumed (app foregrounded)');
        }
        _wasPlayingBeforePause = false;
        // Re-apply immersive mode (Android may reset it)
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
        break;
      case AppLifecycleState.inactive:
        // App is inactive (e.g., phone call, notification overlay)
        // Don't pause here - only pause on 'paused' state
        break;
      case AppLifecycleState.detached:
        // App is detached - no action needed
        break;
      case AppLifecycleState.hidden:
        // App is hidden - no action needed
        break;
    }
  }

  @override
  void dispose() {
    // Remove lifecycle observer
    WidgetsBinding.instance.removeObserver(this);
    _volumeIndicatorTimer?.cancel();
    _player.dispose();
    // Reset orientation to portrait when leaving
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);
    // IMPORTANT: Restore System UI properly to fix black status bar issue
    // Step 1: Exit immersive mode and show system UI
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values, // Show both status bar and nav bar
    );
    // Step 2: Restore status bar color to match app theme (not black)
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark, // Dark icons for light background
      statusBarBrightness: Brightness.light, // For iOS
      systemNavigationBarColor: Colors.white,
      systemNavigationBarIconBrightness: Brightness.dark,
    ));
    super.dispose();
  }

  /// Detect device capabilities and initialize player with optimal settings
  Future<void> _detectDeviceAndInitialize() async {
    try {
      // Get screen resolution for adaptive video output sizing
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
      int? outputWidth;
      int? outputHeight;

      if (_isLowEndDevice) {
        outputWidth = 1280;
        outputHeight = 720;
      } else if (_screenWidth <= 1080) {
        outputWidth = 1920;
        outputHeight = 1080;
      }

      // Choose decoding strategy
      final bool useHWAccel = !_useSoftwareDecoding;
      final String hwdecValue = _useSoftwareDecoding ? 'no' : 'auto';
      final String voValue = 'gpu';

      debugPrint('HW acceleration: $useHWAccel, hwdec: $hwdecValue, vo: $voValue');
      debugPrint('Output size: ${outputWidth ?? 'auto'}x${outputHeight ?? 'auto'}');

      // Create player with optimized buffer settings for 4K streaming
      _player = Player(
        configuration: PlayerConfiguration(
          bufferSize: 64 * 1024 * 1024,
          title: 'CM Movies Player',
          vo: voValue,
          logLevel: MPVLogLevel.error,
        ),
      );

      // Create video controller with hardware-accelerated rendering
      _controller = VideoController(
        _player,
        configuration: VideoControllerConfiguration(
          vo: voValue,
          hwdec: hwdecValue,
          enableHardwareAcceleration: useHWAccel,
          androidAttachSurfaceAfterVideoParameters: true,
          width: outputWidth,
          height: outputHeight,
        ),
      );

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

      // Listen for volume changes from external sources
      _player.stream.volume.listen((volume) {
        if (mounted) {
          setState(() {
            _currentVolume = volume;
            _isVolumeBoosted = volume > _normalVolume;
          });
        }
      });

      // Open the video URL - do NOT use Uri.encodeFull()
      final url = widget.videoUrl;
      debugPrint('Opening media: $url');

      await _player.open(Media(url));

      // Explicitly call play() to ensure playback starts
      await _player.play();

      debugPrint('Player open+play completed successfully');

      if (mounted) {
        setState(() {
          _isInitialized = true;
          _showControls = true; // Show controls when video starts
        });
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
      _retryCount++;
      debugPrint('=== Retrying with SOFTWARE decoding (attempt $_retryCount) ===');
      _player.dispose();
      _useSoftwareDecoding = true;
      _hasVideoOutput = false;
      _initializePlayer();
    } else if (mounted) {
      setState(() {
        _isInitialized = true;
        _errorMessage = error;
      });
    }
  }

  // ============================================================
  // Controls: Manual Toggle (NO auto-hide)
  // Tap screen → show/hide controls
  // ============================================================

  /// Toggle controls visibility - manual only, NO auto-hide
  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
    });
  }

  // ============================================================
  // Audio Boost 300% - Vertical Drag on Right Side of Screen
  // ============================================================

  /// Handle vertical drag on right side of screen for volume control
  /// Drag up = increase volume, Drag down = decrease volume
  /// Supports volume 0-300 (100 = normal, 100-300 = boost)
  void _handleVolumeDrag(DragUpdateDetails details) {
    final screenHeight = MediaQuery.of(context).size.height;
    // Negative delta = drag up = increase volume
    // Calculate volume change based on drag distance
    final volumeChange = (-details.delta.dy / screenHeight) * _maxVolume;
    double newVolume = (_currentVolume + volumeChange).clamp(0.0, _maxVolume);

    // Round to whole numbers for cleaner display
    newVolume = newVolume.roundToDouble();

    _player.setVolume(newVolume);
    setState(() {
      _currentVolume = newVolume;
      _isVolumeBoosted = newVolume > _normalVolume;
      _showVolumeIndicator = true;
    });

    // Auto-hide volume indicator after 1.5 seconds
    _volumeIndicatorTimer?.cancel();
    _volumeIndicatorTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) {
        setState(() {
          _showVolumeIndicator = false;
        });
      }
    });
  }

  /// Handle volume slider change (from controls overlay)
  void _handleVolumeSliderChange(double value) {
    _player.setVolume(value);
    setState(() {
      _currentVolume = value;
      _isVolumeBoosted = value > _normalVolume;
    });
  }

  /// Get volume icon based on current volume level
  IconData _getVolumeIcon(double volume) {
    if (volume == 0) return Icons.volume_off;
    if (volume <= 50) return Icons.volume_mute;
    if (volume <= 100) return Icons.volume_down;
    return Icons.volume_up; // Boost mode
  }

  /// Get volume color (white for normal, red for boost)
  Color _getVolumeColor(double volume) {
    if (volume == 0) return Colors.white38;
    if (volume <= _normalVolume) return Colors.white;
    return const Color(0xFFFF4444); // Red for boost mode
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
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // ====== LAYER 1: Video (bottom) ======
          // media_kit Video widget fills entire screen
          Positioned.fill(
            child: _buildVideoLayer(),
          ),

          // ====== LAYER 2: Controls overlay (middle) ======
          // Shows/hides based on _showControls
          // Uses IgnorePointer so taps pass through to Layer 3 gesture detector
          if (_showControls)
            Positioned.fill(
              child: IgnorePointer(
                // When controls are visible, taps on EMPTY areas pass through
                // But interactive elements (buttons, sliders) still respond
                ignoring: false,
                child: _buildControlsOverlay(),
              ),
            ),

          // ====== LAYER 3: Buffering indicator ======
          if (_isBuffering)
            const Positioned.fill(
              child: Center(
                child: CircularProgressIndicator(color: Color(0xFFE50914)),
              ),
            ),

          // ====== LAYER 4: Volume indicator (auto-hides) ======
          if (_showVolumeIndicator) _buildVolumeIndicator(),

          // ====== LAYER 5: SW badge ======
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

          // ====== LAYER 6: GESTURE DETECTOR (TOPMOST - above everything!) ======
          // This is the CRITICAL layer that makes toggle work.
          // It must be ABOVE the Video widget and ABOVE the Controls overlay
          // so that it receives ALL tap events first.
          //
          // How it works with Controls:
          // - When controls are VISIBLE: This gesture detector sits on TOP.
          //   Taps on buttons/sliders go to controls (they're hit first).
          //   Taps on EMPTY areas go to this gesture detector → toggle OFF.
          // - When controls are HIDDEN: This gesture detector catches ALL taps → toggle ON.
          //
          // Volume drag: RIGHT 30% of screen
          // Tap toggle + Double-tap seek: LEFT 70% of screen
          Positioned.fill(
            child: Row(
              children: [
                // LEFT 70%: Tap to toggle controls, Double-tap to seek
                Expanded(
                  flex: 7,
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    // Single tap: toggle controls
                    onTap: _toggleControls,
                    // Double tap: seek ±10 seconds
                    onDoubleTapDown: (details) {
                      final halfWidth = screenWidth * 0.35; // Half of 70%
                      if (details.globalPosition.dx < halfWidth) {
                        _player.seek(_player.state.position - const Duration(seconds: 10));
                      } else {
                        _player.seek(_player.state.position + const Duration(seconds: 10));
                      }
                    },
                    child: Container(color: Colors.transparent),
                  ),
                ),
                // RIGHT 30%: Vertical drag for volume control
                Expanded(
                  flex: 3,
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onVerticalDragUpdate: _handleVolumeDrag,
                    // Also allow tap on right side to toggle controls
                    onTap: _toggleControls,
                    child: Container(color: Colors.transparent),
                  ),
                ),
              ],
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
                    _useSoftwareDecoding = true;
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

  /// Volume indicator - shows current volume level with boost indicator
  /// Appears during vertical drag, auto-hides after 1.5 seconds
  Widget _buildVolumeIndicator() {
    final volumePercent = (_currentVolume / _maxVolume * 100).round();
    final isBoosted = _currentVolume > _normalVolume;
    final normalPercent = (_normalVolume / _maxVolume * 100); // 33% of slider

    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.black87,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Volume icon
            Icon(
              _getVolumeIcon(_currentVolume),
              color: _getVolumeColor(_currentVolume),
              size: 32,
            ),
            const SizedBox(height: 8),
            // Volume percentage
            Text(
              '$volumePercent%',
              style: TextStyle(
                color: _getVolumeColor(_currentVolume),
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            // Volume bar
            Container(
              width: 160,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
              child: Stack(
                children: [
                  // Normal range (0-100): white/red fill
                  FractionallySizedBox(
                    widthFactor: (_currentVolume / _maxVolume).clamp(0.0, 1.0),
                    child: Container(
                      decoration: BoxDecoration(
                        color: isBoosted ? const Color(0xFFFF4444) : Colors.white,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  // Normal/Boost divider line at 100 (33% position)
                  Positioned(
                    left: normalPercent / 100 * 160 - 1,
                    top: -2,
                    child: Container(
                      width: 2,
                      height: 8,
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            // Boost label
            if (isBoosted)
              const Text(
                'BOOST',
                style: TextStyle(
                  color: Color(0xFFFF4444),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5,
                ),
              )
            else if (_currentVolume == 0)
              const Text(
                'MUTED',
                style: TextStyle(
                  color: Colors.white38,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.5,
                ),
              ),
          ],
        ),
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

          // Bottom bar: Seek + Controls (with Volume Boost Slider)
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
            // Audio track button
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
            // Subtitle track button
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
            },
          ),
          const Spacer(),
          // Volume slider with Boost support (0-300)
          _buildVolumeSlider(),
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
            },
          ),
        ],
      ),
    );
  }

  /// Volume slider with Boost mode support (0-300)
  /// White color for 0-100 (normal), Red color for 100-300 (boost)
  Widget _buildVolumeSlider() {
    final isBoosted = _currentVolume > _normalVolume;
    // Map 0-300 to 0.0-1.0 for slider
    final sliderValue = (_currentVolume / _maxVolume).clamp(0.0, 1.0);
    // Position of normal volume (100/300 = 0.333)
    const normalMarker = _normalVolume / _maxVolume;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Volume icon button (tap to mute/unmute)
        GestureDetector(
          onTap: () {
            if (_currentVolume == 0) {
              _player.setVolume(_normalVolume);
              setState(() {
                _currentVolume = _normalVolume;
                _isVolumeBoosted = false;
              });
            } else {
              _player.setVolume(0);
              setState(() {
                _currentVolume = 0;
                _isVolumeBoosted = false;
              });
            }
          },
          child: Icon(
            _getVolumeIcon(_currentVolume),
            color: _getVolumeColor(_currentVolume),
            size: 22,
          ),
        ),
        const SizedBox(width: 4),
        // Volume slider (0-300)
        SizedBox(
          width: 100,
          child: SliderTheme(
            data: SliderThemeData(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
              // Normal range: white, Boost range: red
              activeTrackColor: isBoosted ? const Color(0xFFFF4444) : Colors.white,
              inactiveTrackColor: Colors.white24,
              thumbColor: isBoosted ? const Color(0xFFFF4444) : Colors.white,
              overlayColor: isBoosted
                  ? const Color(0xFFFF4444).withOpacity(0.2)
                  : Colors.white.withOpacity(0.2),
            ),
            child: Slider(
              value: sliderValue,
              onChanged: (value) {
                final newVolume = (value * _maxVolume).roundToDouble();
                _handleVolumeSliderChange(newVolume);
              },
            ),
          ),
        ),
        // Volume percentage label
        Text(
          '${(_currentVolume).round()}%',
          style: TextStyle(
            color: _getVolumeColor(_currentVolume),
            fontSize: 11,
            fontWeight: _isVolumeBoosted ? FontWeight.w700 : FontWeight.normal,
          ),
        ),
      ],
    );
  }

  /// Show audio track selection dialog for MKV files with multiple audio tracks
  void _showAudioTrackDialog() {
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
}
