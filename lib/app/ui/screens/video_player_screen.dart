import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:screen_brightness/screen_brightness.dart';

/// Professional Video Player using media_kit (libmpv/VLC engine)
/// Supports: MP4, MKV, HEVC (H.265), 4K, AC3/DTS audio, embedded subtitles
///
/// Supported Formats (via libmpv/FFmpeg):
///   Streaming: DASH, HLS, SmoothStreaming, RTMP, RTSP
///   Containers: MP4, MOV, FLV, MKV, WebM, Ogg, MPEG, AVI, TS, M2TS
///   Video: H.263, H.264 AVC, H.265 HEVC, MPEG-4, VP8, VP9, AV1
///   Audio: Vorbis, Opus, FLAC, ALAC, MP1, MP2, MP3, AAC, AC-3, E-AC-3, DTS, DTS-HD
///
/// Performance Strategy — Smart 3-tier auto-tuning:
///   1. NORMAL (high-end / ECO off): Full quality for ALL resolutions (480p-4K)
///   2. ECO (low-end auto / manual toggle): Smooth playback, preserves 1080p quality
///   3. ECO+4K (low-end + 2K/4K video): Slight quality trade-off for smooth 4K
///
/// Key principle: NEVER downscale output resolution. Use mpv-level optimizations
/// (frame dropping, skip filters, buffer tuning) instead. This ensures:
///   - 480p video looks like 480p (not worse)
///   - 1080p video looks like 1080p (not downscaled to 480p)
///   - 4K video plays smoothly on low-end (with ECO optimizations)
///
/// Features:
/// - ECO Mode toggle (🌿 icon): smart optimization for low-end devices
/// - Double Tap to Seek 10s (YouTube-style animation)
/// - Brightness Control (left 50% vertical drag)
/// - Audio Boost up to 300% (right 30% vertical drag)
/// - Smooth Seekbar (drag to preview, release to seek)
/// - Zoom/Fit toggle (Contain ↔ Cover)
/// - Resume Playback (save position, auto-resume dialog)
/// - HW/SW decoding auto-fallback for 4K HEVC
/// - App lifecycle handling (pause/resume on background/foreground)
class VideoPlayerScreen extends StatefulWidget {
  final String videoUrl;
  final String title;
  final String? videoId; // For resume playback (movie/episode ID)

  const VideoPlayerScreen({
    super.key,
    required this.videoUrl,
    required this.title,
    this.videoId,
  });

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen>
    with WidgetsBindingObserver {
  late Player _player;
  late VideoController _controller;
  bool _isInitialized = false;
  String? _errorMessage;
  bool _isBuffering = false;
  bool _showControls = true;
  bool _hasVideoOutput = false;

  // CRITICAL: Flag to prevent post-disposal crashes
  bool _isDisposed = false;

  // Hardware/Software decoding fallback
  bool _useSoftwareDecoding = false;
  int _retryCount = 0;
  static const int _maxRetries = 2;

  // Device info for adaptive configuration
  // Performance tier: 0=ultra-low (≤2GB), 1=low (≤3GB), 2=normal (>3GB)
  int _perfTier = 2;
  bool _isLowEndDevice = false;

  // Performance Mode: ECO = aggressive optimization, Normal = standard
  // Default based on device tier; user can toggle manually
  bool _ecoMode = false;
  int _screenWidth = 1080;
  int _screenHeight = 1920;
  int _androidVersion = 30;
  int _totalMemoryMB = 4096; // Total RAM in MB

  // Audio Boost: media_kit (libmpv) supports volume 0-300+
  double _currentVolume = 100.0;
  static const double _maxVolume = 300.0;
  static const double _normalVolume = 100.0;
  bool _isVolumeBoosted = false;
  bool _showVolumeIndicator = false;
  Timer? _volumeIndicatorTimer;

  // Brightness Control
  double _currentBrightness = 0.5;
  bool _showBrightnessIndicator = false;
  Timer? _brightnessIndicatorTimer;

  // Gesture tracking
  bool _isDraggingVolume = false;
  bool _isDraggingBrightness = false;

  // Feature 1: Zoom/Fit toggle
  BoxFit _videoFit = BoxFit.contain;
  double _zoomScale = 1.0; // Used for Transform.scale approach

  // Feature 2: Double Tap to Seek animation
  bool _showSeekForward = false;
  bool _showSeekBackward = false;
  Timer? _seekAnimationTimer;

  // Seekbar: track dragging state to prevent seek-every-frame
  bool _isSeeking = false;
  double _seekValue = 0.0;

  // Feature 4: Resume Playback
  Timer? _positionSaveTimer;
  Duration _lastKnownPosition = Duration.zero; // Track from stream for reliable save
  Duration _lastKnownDuration = Duration.zero;
  bool _hasResumed = false;
  bool _videoCompleted = false;

  // App lifecycle
  bool _wasPlayingBeforePause = false;

  // Stream subscriptions — MUST be stored and cancelled in dispose()
  List<StreamSubscription> _streamSubscriptions = [];

  // Guard against double-exit (prevents double-pop causing app close)
  bool _isExiting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
      DeviceOrientation.portraitUp,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _initBrightness();
    _detectDeviceAndInitialize();
  }

  Future<void> _initBrightness() async {
    try {
      _currentBrightness = await ScreenBrightness().current;
    } catch (e) {
      _currentBrightness = 0.5;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // CRITICAL: Guard against crashes when player is disposed or widget unmounted
    if (_isDisposed || !mounted) return;

    try {
      switch (state) {
        case AppLifecycleState.paused:
          _wasPlayingBeforePause = _player.state.playing;
          if (_player.state.playing) {
            _player.pause();
          }
          _saveWatchProgress(); // Save on background
          break;
        case AppLifecycleState.resumed:
          // Delay slightly to allow surface to recreate after background
          Future.delayed(const Duration(milliseconds: 300), () {
            if (_isDisposed || !mounted) return;
            try {
              if (_wasPlayingBeforePause) {
                _player.play();
              }
              SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
            } catch (e) {
              debugPrint('Resume playback error: $e');
            }
          });
          _wasPlayingBeforePause = false;
          break;
        case AppLifecycleState.inactive:
        case AppLifecycleState.detached:
        case AppLifecycleState.hidden:
          break;
      }
    } catch (e) {
      debugPrint('Lifecycle state change error: $e');
      // Don't crash the app — just log and continue
    }
  }

  // Safe exit: pause player first, reset orientation/UI, then pop
  // Guard against double-exit which could pop the detail screen too,
  // returning to HomePage, and then another pop closing the app entirely.
  void _exitPlayer() {
    if (_isDisposed || _isExiting || !mounted) return;
    _isExiting = true; // Prevent double-exit

    try {
      // 1. Pause player immediately to stop native engine processing
      //    This reduces the chance of native crash after dispose
      if (!_isDisposed) {
        try { _player.pause(); } catch (_) {}
      }

      // 2. Save progress synchronously before pop
      try { _saveWatchProgressSync(); } catch (_) {}

      // 3. Cancel timers immediately to prevent any callbacks after pop
      _positionSaveTimer?.cancel();
      _volumeIndicatorTimer?.cancel();
      _brightnessIndicatorTimer?.cancel();
      _seekAnimationTimer?.cancel();

      // 4. Reset orientation and system UI BEFORE popping
      //    Doing this before pop prevents the orientation change from
      //    triggering an Android activity recreation that could cause
      //    a synthetic back press event on the previous route
      try {
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.portraitUp,
        ]);
        SystemChrome.setEnabledSystemUIMode(
          SystemUiMode.manual,
          overlays: SystemUiOverlay.values,
        );
      } catch (_) {}

      // 5. Pop the route — this triggers dispose() which cleans up the rest
      //    Using maybePop is NOT used here because PopScope has canPop: false
      //    We intentionally want to pop regardless.
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      debugPrint('Exit player error: $e');
      // Fallback: try to pop anyway
      if (mounted && !_isDisposed) {
        try { Navigator.of(context).pop(); } catch (_) {}
      }
    }
  }

  @override
  void dispose() {
    // CRITICAL: Mark as disposed FIRST to prevent any async callbacks from crashing
    _isDisposed = true;
    WidgetsBinding.instance.removeObserver(this);

    // Cancel all timers
    _volumeIndicatorTimer?.cancel();
    _brightnessIndicatorTimer?.cancel();
    _seekAnimationTimer?.cancel();
    _positionSaveTimer?.cancel();

    // FIX: Cancel ALL stream subscriptions explicitly to prevent
    // stream events from firing after the widget is disposed.
    // This is critical — without this, stream callbacks can call setState()
    // on a disposed widget, causing unhandled exceptions that crash the app.
    for (final sub in _streamSubscriptions) {
      try { sub.cancel(); } catch (_) {}
    }
    _streamSubscriptions.clear();

    // FIX: Pause player BEFORE disposing to reduce native crash risk.
    // media_kit's libmpv engine can crash if disposed while actively decoding.
    try { _player.pause(); } catch (_) {}

    // Save position using last known values (doesn't read from player)
    try { _saveWatchProgressSync(); } catch (e) { debugPrint('Save progress error on dispose: $e'); }

    // Dispose player — wrap in try-catch because native crash may throw
    try { _player.dispose(); } catch (e) { debugPrint('Player dispose error: $e'); }

    // Reset brightness to system default
    try { ScreenBrightness().resetScreenBrightness(); } catch (_) {}

    // Reset system UI and orientation
    try {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
      ]);
      SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.manual,
        overlays: SystemUiOverlay.values,
      );
      SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemNavigationBarColor: Colors.white,
        systemNavigationBarIconBrightness: Brightness.dark,
      ));
    } catch (e) { debugPrint('SystemChrome reset error: $e'); }
    super.dispose();
  }

  // ==============================================================
  // Feature 4: Resume Playback — Save/Load watch progress
  // ==============================================================

  String get _progressKey => 'watch_pos_${widget.videoId ?? widget.videoUrl.hashCode}';
  String get _durationKey => 'watch_dur_${widget.videoId ?? widget.videoUrl.hashCode}';

  // Sync save — uses _lastKnownPosition (captured from stream)
  // Safe to call from dispose() because it doesn't read from player
  void _saveWatchProgressSync() {
    final posMs = _lastKnownPosition.inMilliseconds;
    final durMs = _lastKnownDuration.inMilliseconds;
    if (_videoCompleted) {
      // Video finished — clear saved position
      SharedPreferences.getInstance().then((prefs) {
        prefs.remove(_progressKey);
        prefs.remove(_durationKey);
      });
      return;
    }
    if (posMs > 5000 && durMs > 0) {
      SharedPreferences.getInstance().then((prefs) {
        prefs.setInt(_progressKey, posMs);
        prefs.setInt(_durationKey, durMs);
      });
    }
  }

  // Async save — reads from player directly (for timer & background)
  Future<void> _saveWatchProgress() async {
    if (_isDisposed || _isExiting) return;
    try {
      if (_videoCompleted) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_progressKey);
        await prefs.remove(_durationKey);
        return;
      }
      final position = _player.state.position;
      final duration = _player.state.duration;
      if (position.inSeconds > 0 && duration.inSeconds > 0) {
        _lastKnownPosition = position;
        _lastKnownDuration = duration;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt(_progressKey, position.inMilliseconds);
        await prefs.setInt(_durationKey, duration.inMilliseconds);
        debugPrint('Saved progress: ${position.inSeconds}s / ${duration.inSeconds}s key=$_progressKey');
      }
    } catch (e) {
      debugPrint('Save watch progress error: $e');
    }
  }

  Future<Duration?> _loadSavedPosition() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final posMs = prefs.getInt(_progressKey);
      final durMs = prefs.getInt(_durationKey);
      debugPrint('Resume check: posMs=$posMs, durMs=$durMs, key=$_progressKey');
      if (posMs != null && durMs != null && posMs > 5000) {
        // Only resume if watched more than 5s and less than 95%
        final progress = posMs / durMs;
        if (progress < 0.95) {
          return Duration(milliseconds: posMs);
        }
      }
    } catch (e) {
      debugPrint('Resume load error: $e');
    }
    return null;
  }

  void _startPositionSaveTimer() {
    _positionSaveTimer?.cancel();
    _positionSaveTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _saveWatchProgress();
    });
  }

  void _showResumeDialog(Duration savedPosition) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Row(
          children: [
            Icon(Icons.history, color: Color(0xFFE50914), size: 24),
            SizedBox(width: 8),
            Text('Continue Watching?',
                style: TextStyle(color: Colors.white, fontSize: 18)),
          ],
        ),
        content: Text(
          'You watched up to ${_formatDuration(savedPosition)}. Continue?',
          style: const TextStyle(color: Colors.white70, fontSize: 15),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _hasResumed = true;
            },
            child: const Text('From Start',
                style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _player.seek(savedPosition);
              _hasResumed = true;
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE50914),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
  }

  // ==============================================================
  // Device Detection & Player Initialization
  // ==============================================================

  Future<void> _detectDeviceAndInitialize() async {
    try {
      final views = ui.PlatformDispatcher.instance.views;
      if (views.isNotEmpty) {
        final view = views.first;
        _screenWidth = view.physicalSize.width.toInt();
        _screenHeight = view.physicalSize.height.toInt();
      }
      if (Platform.isAndroid) {
        final deviceInfo = DeviceInfoPlugin();
        final androidInfo = await deviceInfo.androidInfo;
        _androidVersion = androidInfo.version.sdkInt;

        // Detect total RAM — try Android ActivityManager via platform channel
        // On most Android devices, we can read /proc/meminfo
        try {
          // Method 1: Read /proc/meminfo (works on most Android devices)
          final meminfo = File('/proc/meminfo');
          if (await meminfo.exists()) {
            final content = await meminfo.readAsString();
            final match = RegExp(r'MemTotal:\s+(\d+) kB').firstMatch(content);
            if (match != null) {
              _totalMemoryMB = (int.parse(match.group(1)!) / 1024).round();
              debugPrint('Device RAM: ${_totalMemoryMB}MB');
            }
          }
        } catch (_) {
          // Fallback: estimate RAM from device characteristics
          // Low Android version + low screen = likely ≤2GB
          // Medium version = likely ≤3GB
          // Recent device = likely >3GB
          if (_androidVersion <= 27 || _screenWidth < 720) {
            _totalMemoryMB = 2048;
          } else if (_androidVersion <= 29) {
            _totalMemoryMB = 3072;
          } else {
            _totalMemoryMB = 4096;
          }
        }

        // Performance tier based on RAM + screen resolution + Android version
        // Tier 0: Ultra-low (≤2GB RAM or very old device)
        // Tier 1: Low (≤3GB RAM or low resolution)
        // Tier 2: Normal (>3GB RAM)
        if (_totalMemoryMB <= 2048 || _androidVersion <= 27) {
          _perfTier = 0;
        } else if (_totalMemoryMB <= 3072 || _androidVersion <= 29 || _screenWidth < 1080) {
          _perfTier = 1;
        } else {
          _perfTier = 2;
        }

        _isLowEndDevice = _perfTier <= 1;
        // Auto-enable ECO mode on low-end devices
        _ecoMode = _perfTier <= 1;
        debugPrint('Performance tier: $_perfTier (RAM=${_totalMemoryMB}MB, SDK=$_androidVersion, screen=${_screenWidth}x$_screenHeight, eco=$_ecoMode)');
      }
    } catch (e) {
      debugPrint('Device detection error: $e');
    }
    _initializePlayer();
  }

  Future<void> _initializePlayer() async {
    try {
      if (widget.videoUrl.isEmpty) {
        if (mounted) {
          setState(() {
            _isInitialized = true;
            _errorMessage = 'Video URL is empty';
          });
        }
        return;
      }

      // ==============================================================
      // IMPORTANT: Do NOT set output width/height in VideoControllerConfiguration!
      // Setting width/height FORCES mpv to downscale the video to that resolution,
      // which makes 1080p/4K video look blurry on low-end devices.
      // Instead, we let mpv render at the video's native resolution and use
      // mpv-level optimizations (frame dropping, skip filters) for performance.
      // This preserves full visual quality for ALL resolutions (480p-4K).
      // ==============================================================

      // Adaptive buffer size based on RAM
      // IMPORTANT: Buffer must be large enough to prevent constant rebuffering!
      // 4K HEVC at 20Mbps = 2.5MB/sec. Too small buffer = stop-and-go stuttering.
      // The buffer holds compressed data which is small compared to decoded frames.
      final int bufferSizeBytes;
      switch (_perfTier) {
        case 0: // Ultra-low: 32MB buffer (~12 seconds of 4K content)
          bufferSizeBytes = 32 * 1024 * 1024;
          break;
        case 1: // Low: 48MB buffer (~18 seconds of 4K content)
          bufferSizeBytes = 48 * 1024 * 1024;
          break;
        default: // Normal: 64MB buffer
          bufferSizeBytes = 64 * 1024 * 1024;
          break;
      }

      final bool useHWAccel = !_useSoftwareDecoding;
      // Use 'auto-safe' on low-end for more reliable HW decoding fallback
      final String hwdecValue = _useSoftwareDecoding
          ? 'no'
          : (_perfTier <= 1 ? 'auto-safe' : 'auto');

      _player = Player(
        configuration: PlayerConfiguration(
          bufferSize: bufferSizeBytes,
          title: 'CM Movies Player',
          // Do NOT set vo here — VideoController handles it
          logLevel: MPVLogLevel.error,
        ),
      );

      _controller = VideoController(
        _player,
        configuration: VideoControllerConfiguration(
          vo: 'gpu',
          hwdec: hwdecValue,
          enableHardwareAcceleration: useHWAccel,
          androidAttachSurfaceAfterVideoParameters: true,
          // Do NOT set width/height — let video render at native resolution
          // This preserves full quality for 480p, 720p, 1080p, 2K, 4K videos.
          // Performance is managed via mpv-level tuning (frame drop, skip filters)
          // instead of downscaling the output.
        ),
      );

      // FIX: Store stream subscriptions so they can be cancelled in dispose().
      // Without explicit cancellation, stream events can fire after the widget
      // is disposed, causing setState() on a disposed widget → unhandled exception → app crash.
      _streamSubscriptions.add(
        _player.stream.buffering.listen((buffering) {
          if (mounted && !_isDisposed) setState(() => _isBuffering = buffering);
        }),
      );

      _streamSubscriptions.add(
        _player.stream.error.listen((error) {
          if (mounted && !_isDisposed && error.isNotEmpty) _handlePlayerError(error);
        }),
      );

      _streamSubscriptions.add(
        _player.stream.completed.listen((completed) {
          if (completed && mounted && !_isDisposed) {
            _videoCompleted = true;
            _saveWatchProgress(); // Clear saved position since video ended
          }
        }),
      );

      _streamSubscriptions.add(
        _player.stream.playing.listen((playing) {
          if (playing && !_hasVideoOutput && mounted && !_isDisposed) {
            setState(() => _hasVideoOutput = true);
          }
        }),
      );

      _streamSubscriptions.add(
        _player.stream.width.listen((width) {
          if (width != null && width > 0 && !_hasVideoOutput && mounted && !_isDisposed) {
            setState(() => _hasVideoOutput = true);
          }
        }),
      );

      _streamSubscriptions.add(
        _player.stream.volume.listen((volume) {
          if (mounted && !_isDisposed) {
            setState(() {
              _currentVolume = volume;
              _isVolumeBoosted = volume > _normalVolume;
            });
          }
        }),
      );

      // Track position from stream for reliable resume playback saving
      _streamSubscriptions.add(
        _player.stream.position.listen((position) {
          _lastKnownPosition = position;
        }),
      );
      _streamSubscriptions.add(
        _player.stream.duration.listen((duration) {
          _lastKnownDuration = duration;
        }),
      );

      await _player.open(Media(widget.videoUrl));
      await _player.play();

      // CRITICAL: Apply performance tuning AFTER open/play.
      // NativePlayer.setProperty() awaits waitForVideoControllerInitializationIfAttached,
      // which only completes after video parameters are available (i.e., after open()).
      // Calling it BEFORE open() causes it to HANG indefinitely, freezing the app.
      // We run it non-blocking (fire-and-forget) with a timeout so it never blocks UI.
      _applyPerformanceTuningNonBlocking();

      if (mounted) {
        setState(() {
          _isInitialized = true;
          _showControls = true;
        });
        // Start periodic position saving
        _startPositionSaveTimer();
        // Feature 4: Check for saved position AFTER a short delay
        // (give the video surface time to render before showing dialog)
        Future.delayed(const Duration(milliseconds: 800), () {
          if (mounted) _checkResumePosition();
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isInitialized = true;
          _errorMessage = e.toString();
        });
      }
    }
  }

  Future<void> _checkResumePosition() async {
    if (_isDisposed || !mounted) return;
    try {
      // Always check — use URL hash as fallback if videoId is null
      final savedPos = await _loadSavedPosition();
      if (savedPos != null && mounted && !_isDisposed) {
        // Pause while showing dialog so user can decide
        _player.pause();
        _showResumeDialog(savedPos);
      }
    } catch (e) {
      debugPrint('Resume position check error: $e');
      // Don't crash — just continue from start
    }
  }

  // ==============================================================
  // Performance Tuning via mpv setProperty
  // ==============================================================

  /// Detect if current video is high resolution (needs ECO optimizations)
  bool get _isHighResVideo {
    final w = _player.state.width ?? 0;
    return w > 1920; // >1080p = 2K/4K
  }

  /// Helper: set mpv property via NativePlayer.setProperty() with timeout.
  /// Player.setProperty() is NOT exposed in media_kit 1.1.11's public API,
  /// but NativePlayer (accessed via Player.platform) has it.
  /// We use dynamic cast to avoid importing internal source files.
  /// Each call has a 3-second timeout to prevent hanging.
  Future<void> _setMpvProperty(String property, String value) async {
    try {
      final platform = _player.platform;
      if (platform == null) return;
      await (platform as dynamic)
          .setProperty(property, value)
          .timeout(const Duration(seconds: 3));
      debugPrint('mpv: $property=$value ✓');
    } on TimeoutException {
      debugPrint('mpv: $property=$value TIMEOUT');
    } catch (e) {
      debugPrint('mpv: $property=$value ERROR: $e');
    }
  }

  /// Non-blocking performance tuning — fire-and-forget.
  /// MUST be called AFTER _player.open() because NativePlayer.setProperty()
  /// awaits waitForVideoControllerInitializationIfAttached, which only
  /// completes after video parameters are available from an opened video.
  void _applyPerformanceTuningNonBlocking() {
    Future.microtask(() => _applyPerformanceTuning());
  }

  /// Applies mpv performance tuning based on device tier, ECO mode,
  /// and video resolution. Uses a smart 3-tier approach:
  ///
  /// 1. NORMAL mode (ECO OFF, high-end devices):
  ///    - Minimal optimizations: frame drop on display lag, VSync off
  ///    - Full quality for ALL resolutions (480p-4K)
  ///
  /// 2. ECO mode (auto for low-end, manual toggle):
  ///    - Smooth optimizations: frame drop, skip HEVC loop filter
  ///    - Preserves visual quality for 480p-1080p
  ///    - Makes 4K playable on low-end with slight quality trade-off
  ///
  /// 3. ECO + 4K mode (auto when low-end + high-res video):
  ///    - All ECO optimizations plus aggressive decoder shortcuts
  ///    - This is the ONLY mode that degrades quality (slightly)
  ///    - Necessary trade-off: without it, 4K stutters on 2GB devices
  Future<void> _applyPerformanceTuning() async {
    try {
      if (_isDisposed) return;

      // Wait for video parameters to be available
      await Future.delayed(const Duration(milliseconds: 500));
      if (_isDisposed) return;

      // Smart mode detection:
      // - High-end device + ECO off → Normal (full quality)
      // - Low-end device OR ECO on → ECO (good quality + smooth)
      // - Low-end + 4K/2K video → ECO+4K (slight quality trade-off for smooth)
      final bool isEco = _ecoMode || _perfTier <= 1;
      final bool is4K = _isHighResVideo;
      final bool isEco4K = isEco && is4K;

      debugPrint('Tuning: tier=$_perfTier, eco=$_ecoMode, isEco=$isEco, is4K=$is4K, eco4K=$isEco4K, videoWidth=${_player.state.width}');

      // =============================================================
      // ALL DEVICES: Baseline optimizations (no quality loss)
      // =============================================================

      // Frame dropping when display can't keep up — essential for smoothness
      // 'vo' = only drop at display level (least aggressive, best quality)
      // 'decoder+vo' = also skip at decoder (more aggressive, for ECO)
      await _setMpvProperty('framedrop', isEco ? 'decoder+vo' : 'vo');

      // Allow decoder to drop frames too in ECO mode
      await _setMpvProperty('vd-lavc-framedrop', isEco ? 'all' : 'nonref');

      // Disable VSync — reduces micro-stutter, possible tearing (invisible on mobile)
      await _setMpvProperty('opengl-swapinterval', '0');

      // Pixel Buffer Objects — faster GPU texture uploads (no quality impact)
      await _setMpvProperty('opengl-pbo', 'yes');

      // Relaxed video sync — slight A/V desync is better than stutter
      await _setMpvProperty('video-sync', 'audio-desync');

      // Disable frame interpolation — saves CPU, no quality loss
      await _setMpvProperty('interpolation', 'no');

      // =============================================================
      // ECO MODE: Smooth optimizations (minimal quality impact)
      // Applied when: low-end device OR user toggled ECO
      // These preserve quality for 480p-1080p, help with 4K
      // =============================================================
      if (isEco) {
        // Skip HEVC/H.264 deblocking loop filter
        // This is the most effective CPU-saving optimization for HEVC.
        // Quality impact: slight blocking artifacts on edges (barely visible)
        // CPU saving: ~30-40% for HEVC decode
        await _setMpvProperty('vd-lavc-skiploopfilter', is4K ? 'all' : 'nonref');

        // Faster seeking — don't require exact keyframe alignment
        await _setMpvProperty('hr-seek', 'no');

        // Disable ICC profile auto-detection — saves CPU
        await _setMpvProperty('icc-profile-auto', 'no');

        // Simplified tone mapping — saves GPU on HDR content
        await _setMpvProperty('tone-mapping', 'clip');

        // Bilinear scaling — faster than bicubic, quality OK on small screens
        await _setMpvProperty('scale', 'bilinear');
        await _setMpvProperty('dscale', 'bilinear');
        await _setMpvProperty('cscale', 'bilinear');

        // Disable debanding — saves GPU, quality loss minimal
        await _setMpvProperty('deband', 'no');

        // Demuxer back-buffer for reverse seeking
        final backBytes = _perfTier == 0
            ? (8 * 1024 * 1024).toString()    // 8MB for ultra-low
            : (16 * 1024 * 1024).toString();   // 16MB for low
        await _setMpvProperty('demuxer-max-back-bytes', backBytes);

        // Demuxer forward buffer — must be large enough to prevent rebuffering
        final maxBytes = _perfTier == 0
            ? (32 * 1024 * 1024).toString()    // 32MB for ultra-low
            : (48 * 1024 * 1024).toString();    // 48MB for low
        await _setMpvProperty('demuxer-max-bytes', maxBytes);
      }

      // =============================================================
      // ECO + 4K/2K MODE: Aggressive optimizations
      // Applied ONLY when: low-end device + high-res video (2K/4K)
      // These trade some quality for smoothness — ONLY for 4K on low-end
      // 1080p and below will NOT have these applied
      // =============================================================
      if (isEco4K) {
        // Skip non-reference frames at decoder level
        // Only for 4K — 1080p doesn't need this level of optimization
        await _setMpvProperty('vd-lavc-skipframe', 'nonref');

        // Limit decoder threads on very low-end devices
        await _setMpvProperty('vd-lavc-threads', _perfTier == 0 ? '2' : '4');

        // Reduce audio buffer to save memory for video decode
        await _setMpvProperty('audio-buffer', '0.1');

        // Don't cache on disk — save I/O for video decode
        await _setMpvProperty('cache-on-disk', 'no');
      }

      debugPrint('Performance tuning applied: tier=$_perfTier, eco=$isEco, 4k=$is4K, eco4k=$isEco4K');
    } catch (e) {
      debugPrint('Performance tuning error (non-critical): $e');
    }
  }

  /// Toggle ECO mode and re-apply performance tuning
  void _toggleEcoMode() {
    setState(() {
      _ecoMode = !_ecoMode;
    });
    // Re-apply tuning with new eco mode setting
    _applyPerformanceTuningNonBlocking();
  }

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

  // ==============================================================
  // Gesture Handlers
  // ==============================================================

  // ONLY toggle controls visibility — NEVER pause the video
  void _toggleControls() {
    setState(() => _showControls = !_showControls);
  }

  // Feature 2: Double Tap to Seek
  void _handleDoubleTapSeek(Offset position) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isRight = position.dx > screenWidth / 2;

    if (isRight) {
      _player.seek(_player.state.position + const Duration(seconds: 10));
      setState(() {
        _showSeekForward = true;
        _showSeekBackward = false;
      });
    } else {
      _player.seek(_player.state.position - const Duration(seconds: 10));
      setState(() {
        _showSeekBackward = true;
        _showSeekForward = false;
      });
    }

    _seekAnimationTimer?.cancel();
    _seekAnimationTimer = Timer(const Duration(milliseconds: 800), () {
      if (mounted) {
        setState(() {
          _showSeekForward = false;
          _showSeekBackward = false;
        });
      }
    });
  }

  // Volume drag — right 30% of screen
  void _handleVolumeDrag(DragUpdateDetails details) {
    if (!_isDraggingVolume) return;
    final screenHeight = MediaQuery.of(context).size.height;
    final volumeChange = (-details.delta.dy / screenHeight) * _maxVolume;
    double newVolume = (_currentVolume + volumeChange).clamp(0.0, _maxVolume);
    newVolume = newVolume.roundToDouble();
    _player.setVolume(newVolume);
    setState(() {
      _currentVolume = newVolume;
      _isVolumeBoosted = newVolume > _normalVolume;
      _showVolumeIndicator = true;
      _showBrightnessIndicator = false;
    });
    _volumeIndicatorTimer?.cancel();
    _volumeIndicatorTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _showVolumeIndicator = false);
    });
  }

  // Feature 3: Brightness drag — left 50% of screen
  void _handleBrightnessDrag(DragUpdateDetails details) {
    if (!_isDraggingBrightness) return;
    final screenHeight = MediaQuery.of(context).size.height;
    final brightnessChange = -details.delta.dy / screenHeight;
    double newBrightness =
        (_currentBrightness + brightnessChange).clamp(0.0, 1.0);
    newBrightness = (newBrightness * 100).roundToDouble() / 100;
    ScreenBrightness().setScreenBrightness(newBrightness);
    setState(() {
      _currentBrightness = newBrightness;
      _showBrightnessIndicator = true;
      _showVolumeIndicator = false;
    });
    _brightnessIndicatorTimer?.cancel();
    _brightnessIndicatorTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _showBrightnessIndicator = false);
    });
  }

  void _handleVerticalDragStart(DragStartDetails details) {
    final screenWidth = MediaQuery.of(context).size.width;
    final x = details.globalPosition.dx;
    if (x > screenWidth * 0.7) {
      _isDraggingVolume = true;
      _isDraggingBrightness = false;
    } else if (x < screenWidth * 0.5) {
      _isDraggingBrightness = true;
      _isDraggingVolume = false;
    } else {
      _isDraggingVolume = false;
      _isDraggingBrightness = false;
    }
  }

  void _handleVerticalDragUpdate(DragUpdateDetails details) {
    if (_isDraggingVolume) {
      _handleVolumeDrag(details);
    } else if (_isDraggingBrightness) {
      _handleBrightnessDrag(details);
    }
  }

  void _handleVerticalDragEnd(DragEndDetails details) {
    _isDraggingVolume = false;
    _isDraggingBrightness = false;
  }

  void _handleVolumeSliderChange(double value) {
    _player.setVolume(value);
    setState(() {
      _currentVolume = value;
      _isVolumeBoosted = value > _normalVolume;
    });
  }

  // Feature 1: Zoom/Fit toggle — uses Transform.scale for reliable zoom
  void _toggleVideoFit() {
    setState(() {
      if (_videoFit == BoxFit.contain) {
        _videoFit = BoxFit.cover;
        _zoomScale = 1.3; // Scale up 30% to fill screen edges
      } else {
        _videoFit = BoxFit.contain;
        _zoomScale = 1.0; // Normal size
      }
    });
  }

  // ==============================================================
  // Utility Methods
  // ==============================================================

  IconData _getVolumeIcon(double volume) {
    if (volume == 0) return Icons.volume_off;
    if (volume <= 50) return Icons.volume_mute;
    if (volume <= 100) return Icons.volume_down;
    return Icons.volume_up;
  }

  Color _getVolumeColor(double volume) {
    if (volume == 0) return Colors.white38;
    if (volume <= _normalVolume) return Colors.white;
    return const Color(0xFFFF4444);
  }

  IconData _getBrightnessIcon(double brightness) {
    if (brightness <= 0.2) return Icons.brightness_low;
    if (brightness <= 0.6) return Icons.brightness_medium;
    return Icons.brightness_high;
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    if (hours > 0) return '$hours:${twoDigits(minutes)}:${twoDigits(seconds)}';
    return '${twoDigits(minutes)}:${twoDigits(seconds)}';
  }

  // ==============================================================
  // BUILD
  //
  // Layer 1: Video (IgnorePointer) — BOTTOM
  // Layer 2: GestureDetector — tap toggle + double-tap seek + drag
  // Layer 3: Seek animations (IgnorePointer)
  // Layer 4: Controls (when visible)
  // Layer 5: Volume/Brightness side indicators (IgnorePointer)
  // Layer 6: Buffering indicator (IgnorePointer)
  // Layer 7: SW badge (IgnorePointer)
  // ==============================================================

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Prevent accidental double-back exit: always intercept back button
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        // User pressed back → exit player properly (save progress, clean up)
        _exitPlayer();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
        children: [
          // ====== LAYER 1: Video (IgnorePointer) ======
          Positioned.fill(
            child: IgnorePointer(
              child: _buildVideoLayer(),
            ),
          ),

          // ====== LAYER 2: GestureDetector ======
          // Single tap: toggle controls (with delay for double-tap detection)
          // Double tap: seek 10s (left=backward, right=forward)
          // Vertical drag left 50%: brightness, right 30%: volume
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              // Single tap → toggle controls (Flutter adds ~250ms delay
              // when onDoubleTap is also registered — this is expected)
              onTap: _toggleControls,
              // Double tap → seek 10s based on position
              onDoubleTap: () {}, // Required to activate double-tap recognizer
              onDoubleTapDown: (details) {
                _handleDoubleTapSeek(details.globalPosition);
              },
              // Vertical drag: brightness (left 50%) or volume (right 30%)
              onVerticalDragStart: _handleVerticalDragStart,
              onVerticalDragUpdate: _handleVerticalDragUpdate,
              onVerticalDragEnd: _handleVerticalDragEnd,
              child: Container(color: Colors.transparent),
            ),
          ),

          // ====== LAYER 3: Double-tap Seek Animation ======
          if (_showSeekForward)
            Positioned(
              right: MediaQuery.of(context).size.width * 0.15,
              top: 0,
              bottom: 0,
              child: IgnorePointer(child: _buildSeekAnimation(isForward: true)),
            ),
          if (_showSeekBackward)
            Positioned(
              left: MediaQuery.of(context).size.width * 0.15,
              top: 0,
              bottom: 0,
              child: IgnorePointer(child: _buildSeekAnimation(isForward: false)),
            ),

          // ====== LAYER 4: Controls (when visible) ======
          if (_showControls) ...[
            // Top gradient decoration (IgnorePointer → taps pass through)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 100,
              child: IgnorePointer(
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.black87, Colors.transparent],
                    ),
                  ),
                ),
              ),
            ),

            // Top bar buttons (interactive — NOT IgnorePointer)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: _buildTopBar(),
            ),

            // Center: Play/Pause big button (interactive)
            Center(
              child: StreamBuilder<bool>(
                stream: _player.stream.playing,
                builder: (context, snapshot) {
                  final isPlaying = _player.state.playing;
                  return GestureDetector(
                    onTap: () {
                      if (isPlaying) {
                        _player.pause();
                      } else {
                        _player.play();
                      }
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black45,
                        borderRadius: BorderRadius.circular(40),
                      ),
                      padding: const EdgeInsets.all(16),
                      child: Icon(
                        isPlaying ? Icons.pause : Icons.play_arrow,
                        color: Colors.white,
                        size: 48,
                      ),
                    ),
                  );
                },
              ),
            ),

            // Bottom gradient decoration (IgnorePointer → taps pass through)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              height: 130,
              child: IgnorePointer(
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Colors.black87],
                    ),
                  ),
                ),
              ),
            ),

            // Bottom bar (interactive — seek bar + buttons)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _buildBottomBar(),
            ),
          ],

          // ====== LAYER 5: Volume/Brightness side indicators ======
          if (_showVolumeIndicator)
            Positioned(
              right: 16,
              top: 0,
              bottom: 0,
              width: 56,
              child: IgnorePointer(child: _buildVolumeSideIndicator()),
            ),
          if (_showBrightnessIndicator)
            Positioned(
              left: 16,
              top: 0,
              bottom: 0,
              width: 56,
              child: IgnorePointer(child: _buildBrightnessSideIndicator()),
            ),

          // ====== LAYER 6: Buffering indicator ======
          if (_isBuffering)
            const Positioned.fill(
              child: IgnorePointer(
                child: Center(
                  child: CircularProgressIndicator(color: Color(0xFFE50914)),
                ),
              ),
            ),

          // ====== LAYER 7: SW badge + Performance mode indicator ======
          if (_useSoftwareDecoding && _hasVideoOutput)
            Positioned(
              top: 48,
              right: 8,
              child: IgnorePointer(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    _ecoMode
                        ? (_isHighResVideo ? 'SW · ECO 4K' : 'SW · ECO')
                        : 'SW',
                    style: const TextStyle(
                        color: Colors.orange,
                        fontSize: 10,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),
          // Show ECO mode badge when ECO is active (auto on low-end or manually toggled)
          if (!_useSoftwareDecoding && _hasVideoOutput && _ecoMode)
            Positioned(
              top: 48,
              right: 8,
              child: IgnorePointer(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    _isHighResVideo ? 'ECO 4K' : 'ECO',
                    style: TextStyle(
                        color: _isHighResVideo ? Colors.amber : Colors.green,
                        fontSize: 10,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
    );
  }

  // ==============================================================
  // Video Layer
  // ==============================================================

  Widget _buildVideoLayer() {
    if (!_isInitialized) return _buildLoadingScreen();
    if (_errorMessage != null) return _buildErrorScreen();

    // Get video aspect ratio
    final videoWidth = _player.state.width;
    final videoHeight = _player.state.height;
    final videoAspectRatio = (videoWidth != null && videoHeight != null && videoHeight > 0)
        ? videoWidth / videoHeight
        : 16.0 / 9.0;

    // Build the base Video widget
    final videoWidget = Center(
      child: AspectRatio(
        aspectRatio: videoAspectRatio,
        child: Video(
          controller: _controller,
          controls: NoVideoControls,
          fit: BoxFit.contain,
        ),
      ),
    );

    // FIX: Zoom/Fit toggle using ClipRect + Transform.scale
    // This approach is reliable because it works regardless of how
    // media_kit's Video widget handles the `fit` parameter internally.
    // Transform.scale physically scales the rendered texture,
    // and ClipRect crops the overflow to fill the screen.
    if (_videoFit == BoxFit.cover && _zoomScale > 1.0) {
      return ClipRect(
        child: Transform.scale(
          scale: _zoomScale,
          child: videoWidget,
        ),
      );
    }

    // Normal mode: maintain aspect ratio with letterboxing
    return videoWidget;
  }

  // ==============================================================
  // Feature 2: YouTube-style Seek Animation
  // ==============================================================

  Widget _buildSeekAnimation({required bool isForward}) {
    return Center(
      child: Container(
        width: 100,
        height: 100,
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(50),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isForward ? Icons.fast_forward : Icons.fast_rewind,
              color: Colors.white,
              size: 36,
            ),
            const SizedBox(height: 4),
            Text(
              '10s',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==============================================================
  // Loading / Error Screens
  // ==============================================================

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
              style: const TextStyle(
                  color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _useSoftwareDecoding
                ? 'Switching to software decoder...'
                : 'Loading video...',
            style: TextStyle(
              color: _useSoftwareDecoding ? Colors.orange : Colors.white70,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorScreen() {
    final isCodecError = _errorMessage != null &&
        (_errorMessage!.contains('codec') ||
            _errorMessage!.contains('Could not open') ||
            _errorMessage!.contains('decoder') ||
            _errorMessage!.contains('HEVC') ||
            _errorMessage!.contains('H.265'));

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isCodecError
                  ? Icons.high_quality_outlined
                  : Icons.error_outline,
              color: isCodecError ? Colors.orange : Colors.redAccent,
              size: 56,
            ),
            const SizedBox(height: 16),
            Text(
              isCodecError
                  ? 'Video codec not supported'
                  : 'Failed to load video',
              style: const TextStyle(
                  color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
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
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: _exitPlayer,
                  icon: const Icon(Icons.close),
                  label: const Text('Close'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white70,
                    side: const BorderSide(color: Colors.white38),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ==============================================================
  // Top Bar
  // ==============================================================

  Widget _buildTopBar() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            // Back button — use _exitPlayer for safe cleanup
            IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white, size: 24),
              onPressed: _exitPlayer,
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
                    fontWeight: FontWeight.w600),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // Feature 1: Zoom/Fit toggle button
            IconButton(
              icon: Icon(
                _videoFit == BoxFit.contain
                    ? Icons.fit_screen
                    : Icons.fullscreen,
                color: Colors.white,
                size: 22,
              ),
              onPressed: _toggleVideoFit,
              style: IconButton.styleFrom(
                  backgroundColor: Colors.black45,
                  padding: const EdgeInsets.all(8)),
              tooltip: _videoFit == BoxFit.contain ? 'Zoom In' : 'Zoom Out',
            ),
            const SizedBox(width: 4),
            // ECO Mode toggle — reduces quality for smoother 4K on low-end
            IconButton(
              icon: Icon(
                _ecoMode ? Icons.eco : Icons.eco_outlined,
                color: _ecoMode ? const Color(0xFF4CAF50) : Colors.white54,
                size: 22,
              ),
              onPressed: _toggleEcoMode,
              style: IconButton.styleFrom(
                  backgroundColor: _ecoMode
                      ? const Color(0xFF1B5E20).withOpacity(0.7)
                      : Colors.black45,
                  padding: const EdgeInsets.all(8)),
              tooltip: _ecoMode ? 'ECO Mode ON' : 'ECO Mode OFF',
            ),
            const SizedBox(width: 4),
            // Audio track
            IconButton(
              icon: const Icon(Icons.audiotrack, color: Colors.white, size: 22),
              onPressed: _showAudioTrackSheet,
              style: IconButton.styleFrom(
                  backgroundColor: Colors.black45,
                  padding: const EdgeInsets.all(8)),
            ),
            const SizedBox(width: 4),
            // Subtitle
            IconButton(
              icon:
                  const Icon(Icons.subtitles, color: Colors.white, size: 22),
              onPressed: _showSubtitleTrackSheet,
              style: IconButton.styleFrom(
                  backgroundColor: Colors.black45,
                  padding: const EdgeInsets.all(8)),
            ),
            const SizedBox(width: 4),
            // Speed
            IconButton(
              icon: const Icon(Icons.speed, color: Colors.white, size: 22),
              onPressed: _showSpeedSheet,
              style: IconButton.styleFrom(
                  backgroundColor: Colors.black45,
                  padding: const EdgeInsets.all(8)),
            ),
            const SizedBox(width: 4),
            // Fullscreen toggle
            IconButton(
              icon: const Icon(Icons.fullscreen,
                  color: Colors.white, size: 22),
              onPressed: () {
                final isPortrait =
                    MediaQuery.of(context).orientation == Orientation.portrait;
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
              style: IconButton.styleFrom(
                  backgroundColor: Colors.black45,
                  padding: const EdgeInsets.all(8)),
            ),
          ],
        ),
      ),
    );
  }

  // ==============================================================
  // Bottom Bar
  // ==============================================================

  Widget _buildBottomBar() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildSeekBar(),
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
          final streamProgress = duration.inMilliseconds > 0
              ? position.inMilliseconds / duration.inMilliseconds
              : 0.0;
          // Use seek value while dragging, stream value otherwise
          final progress = _isSeeking ? _seekValue : streamProgress;

          return Column(
            children: [
              SliderTheme(
                data: SliderThemeData(
                  trackHeight: 3,
                  thumbShape:
                      const RoundSliderThumbShape(enabledThumbRadius: 6),
                  overlayShape:
                      const RoundSliderOverlayShape(overlayRadius: 12),
                  activeTrackColor: const Color(0xFFE50914),
                  inactiveTrackColor: Colors.white24,
                  thumbColor: const Color(0xFFE50914),
                  overlayColor: const Color(0xFFE50914).withOpacity(0.2),
                ),
                child: Slider(
                  value: progress.clamp(0.0, 1.0),
                  // User started dragging slider
                  onChangeStart: (value) {
                    _isSeeking = true;
                    _seekValue = value;
                  },
                  // Update visual position while dragging (don't seek yet)
                  onChanged: (value) {
                    setState(() {
                      _seekValue = value;
                    });
                  },
                  // User released — actually seek to position
                  onChangeEnd: (value) {
                    _isSeeking = false;
                    final seekPosition = Duration(
                      milliseconds:
                          (duration.inMilliseconds * value).round(),
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
                      _formatDuration(_isSeeking
                          ? Duration(milliseconds: (duration.inMilliseconds * _seekValue).round())
                          : position),
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 12)),
                    Text(_formatDuration(duration),
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 12)),
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
            onPressed: () => _player
                .seek(_player.state.position - const Duration(seconds: 10)),
          ),
          const SizedBox(width: 16),
          // Play/Pause (center)
          StreamBuilder<bool>(
            stream: _player.stream.playing,
            builder: (context, snapshot) {
              final isPlaying = _player.state.playing;
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
            onPressed: () => _player
                .seek(_player.state.position + const Duration(seconds: 10)),
          ),
          const Spacer(),
          // Volume slider with boost
          _buildVolumeSlider(),
        ],
      ),
    );
  }

  // ==============================================================
  // Volume Slider (in bottom bar)
  // ==============================================================

  Widget _buildVolumeSlider() {
    final isBoosted = _currentVolume > _normalVolume;
    final sliderValue = (_currentVolume / _maxVolume).clamp(0.0, 1.0);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
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
          child: Icon(_getVolumeIcon(_currentVolume),
              color: _getVolumeColor(_currentVolume), size: 22),
        ),
        const SizedBox(width: 4),
        SizedBox(
          width: 100,
          child: SliderTheme(
            data: SliderThemeData(
              trackHeight: 3,
              thumbShape:
                  const RoundSliderThumbShape(enabledThumbRadius: 5),
              overlayShape:
                  const RoundSliderOverlayShape(overlayRadius: 10),
              activeTrackColor:
                  isBoosted ? const Color(0xFFFF4444) : Colors.white,
              inactiveTrackColor: Colors.white24,
              thumbColor:
                  isBoosted ? const Color(0xFFFF4444) : Colors.white,
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
        Text(
          '${_currentVolume.round()}%',
          style: TextStyle(
            color: _getVolumeColor(_currentVolume),
            fontSize: 11,
            fontWeight: _isVolumeBoosted ? FontWeight.w700 : FontWeight.normal,
          ),
        ),
      ],
    );
  }

  // ==============================================================
  // Volume Side Indicator (right edge)
  // ==============================================================

  Widget _buildVolumeSideIndicator() {
    final isBoosted = _currentVolume > _normalVolume;
    final fillPercent = (_currentVolume / _maxVolume).clamp(0.0, 1.0);
    final normalLinePercent = _normalVolume / _maxVolume;

    return Center(
      child: Container(
        width: 48,
        height: 200,
        decoration: BoxDecoration(
          color: Colors.black87,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(_getVolumeIcon(_currentVolume),
                color: _getVolumeColor(_currentVolume), size: 24),
            const SizedBox(height: 8),
            Container(
              width: 6,
              height: 100,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(3),
              ),
              child: Stack(
                alignment: Alignment.bottomCenter,
                children: [
                  FractionallySizedBox(
                    heightFactor: fillPercent,
                    child: Container(
                      decoration: BoxDecoration(
                        color: isBoosted
                            ? const Color(0xFFFF4444)
                            : Colors.white,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: normalLinePercent * 100 - 1,
                    left: -2,
                    right: -2,
                    child: Container(height: 2, color: Colors.white70),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${_currentVolume.round()}%',
              style: TextStyle(
                color: _getVolumeColor(_currentVolume),
                fontSize: 10,
                fontWeight: _isVolumeBoosted ? FontWeight.w700 : FontWeight.normal,
              ),
            ),
            if (isBoosted)
              const Text(
                'BOOST',
                style: TextStyle(
                  color: Color(0xFFFF4444),
                  fontSize: 8,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ==============================================================
  // Feature 3: Brightness Side Indicator (left edge)
  // ==============================================================

  Widget _buildBrightnessSideIndicator() {
    final fillPercent = _currentBrightness.clamp(0.0, 1.0);

    return Center(
      child: Container(
        width: 48,
        height: 200,
        decoration: BoxDecoration(
          color: Colors.black87,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(_getBrightnessIcon(_currentBrightness),
                color: Colors.white, size: 24),
            const SizedBox(height: 8),
            Container(
              width: 6,
              height: 100,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(3),
              ),
              child: Stack(
                alignment: Alignment.bottomCenter,
                children: [
                  FractionallySizedBox(
                    heightFactor: fillPercent,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.amber,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${(_currentBrightness * 100).round()}%',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==============================================================
  // Bottom Sheets: Audio Track, Subtitles, Speed
  // ==============================================================

  void _showAudioTrackSheet() {
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
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    final screenWidth = MediaQuery.of(context).size.width;

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        Widget content = SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: const Text('Audio Track',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w600)),
              ),
              const Divider(color: Colors.white12, height: 1),
              ...audioTracks.map((track) {
                final isSelected = _player.state.track.audio == track;
                return ListTile(
                  dense: true,
                  leading: Icon(
                      isSelected
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      color: isSelected
                          ? const Color(0xFFE50914)
                          : Colors.white54),
                  title: Text(
                      track.title?.isNotEmpty == true
                          ? track.title!
                          : 'Audio ${track.id}',
                      style: TextStyle(
                          color: isSelected ? Colors.white : Colors.white70,
                          fontWeight: isSelected
                              ? FontWeight.w600
                              : FontWeight.normal)),
                  subtitle: track.language != null
                      ? Text(track.language!,
                          style: const TextStyle(
                              color: Colors.white38, fontSize: 12))
                      : null,
                  onTap: () {
                    _player.setAudioTrack(track);
                    Navigator.pop(context);
                  },
                );
              }),
            ],
          ),
        );
        if (isLandscape) {
          return Center(
            child: SizedBox(width: screenWidth * 0.5, child: content),
          );
        }
        return content;
      },
    );
  }

  void _showSubtitleTrackSheet() {
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
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    final screenWidth = MediaQuery.of(context).size.width;

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        Widget content = SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: const Text('Subtitles',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w600)),
              ),
              const Divider(color: Colors.white12, height: 1),
              ListTile(
                dense: true,
                leading: Icon(
                    _player.state.track.subtitle == AudioTrack.no()
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    color: const Color(0xFFE50914)),
                title: const Text('Off',
                    style: TextStyle(color: Colors.white)),
                onTap: () {
                  _player.setSubtitleTrack(SubtitleTrack.no());
                  Navigator.pop(context);
                },
              ),
              const Divider(color: Colors.white12),
              ...subtitleTracks.map((track) {
                final isSelected = _player.state.track.subtitle == track;
                return ListTile(
                  dense: true,
                  leading: Icon(
                      isSelected
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      color: isSelected
                          ? const Color(0xFFE50914)
                          : Colors.white54),
                  title: Text(
                      track.title?.isNotEmpty == true
                          ? track.title!
                          : 'Subtitle ${track.id}',
                      style: TextStyle(
                          color: isSelected ? Colors.white : Colors.white70,
                          fontWeight: isSelected
                              ? FontWeight.w600
                              : FontWeight.normal)),
                  subtitle: track.language != null
                      ? Text(track.language!,
                          style: const TextStyle(
                              color: Colors.white38, fontSize: 12))
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
        if (isLandscape) {
          return Center(
            child: SizedBox(width: screenWidth * 0.5, child: content),
          );
        }
        return content;
      },
    );
  }

  void _showSpeedSheet() {
    const speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];
    final currentSpeed = _player.state.rate;
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    final screenWidth = MediaQuery.of(context).size.width;

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        Widget content = SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: const Text('Playback Speed',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w600)),
              ),
              const Divider(color: Colors.white12, height: 1),
              ...speeds.map((speed) {
                final isSelected = (currentSpeed - speed).abs() < 0.01;
                return ListTile(
                  dense: true,
                  leading: Icon(
                      isSelected
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      color: isSelected
                          ? const Color(0xFFE50914)
                          : Colors.white54),
                  title: Text(
                      speed == 1.0 ? 'Normal' : '${speed}x',
                      style: TextStyle(
                          color: isSelected ? Colors.white : Colors.white70,
                          fontWeight: isSelected
                              ? FontWeight.w600
                              : FontWeight.normal)),
                  onTap: () {
                    _player.setRate(speed);
                    Navigator.pop(context);
                  },
                );
              }),
            ],
          ),
        );
        if (isLandscape) {
          return Center(
            child: SizedBox(width: screenWidth * 0.5, child: content),
          );
        }
        return content;
      },
    );
  }
}
