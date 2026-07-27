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
import 'package:provider/provider.dart';
import 'package:cm_movies/more_libs/setting/app_config.dart';
import 'package:cm_movies/app/core/services/external_player_service.dart';

/// Professional Video Player using media_kit (libmpv/VLC engine)
/// Supports: MP4, MKV, HEVC (H.265), 4K, AC3/DTS audio, embedded subtitles
///
/// Supported Formats (via libmpv/FFmpeg):
///   Streaming: DASH, HLS, SmoothStreaming, RTMP, RTSP
///   Containers: MP4, MOV, FLV, MKV, WebM, Ogg, MPEG, AVI, TS, M2TS
///   Video: H.263, H.264 AVC, H.265 HEVC, MPEG-4, VP8, VP9, AV1
///   Audio: Vorbis, Opus, FLAC, ALAC, MP1, MP2, MP3, AAC, AC-3, E-AC-3, DTS, DTS-HD
///
/// Performance Strategy — Quality-First Approach (like MX Player / VLC):
///
/// Core principle: Play every video at its NATIVE quality.
///   - 480p looks like 480p, 720p like 720p, 1080p like 1080p
///   - 4K plays at full resolution — NO downscaling, NO bilinear forcing
///
/// How we achieve smooth playback WITHOUT degrading quality:
///   1. Hardware decoding first (MediaCodec on Android) — always preferred
///   2. Auto SW fallback if HW fails for specific codecs
///   3. Smart frame dropping only when display actually falls behind
///   4. Reasonable buffer sizes (not too small = stutter, not too big = OOM)
///   5. Fast GPU texture upload (PBO)
///   6. Minimal mpv overrides — let mpv's excellent defaults do their job
///
/// ECO Mode (⚡ icon) — optional manual toggle:
///   - Only activates frame-drop optimizations and skip-loop-filter
///   - NEVER forces bilinear scaling or reduces output resolution
///   - Useful for very old devices (≤2GB RAM) with 4K content
///   - Default: OFF on 4GB+ devices, can be toggled manually
///
/// Supported Formats (via libmpv/FFmpeg):
///   Streaming: DASH, HLS, SmoothStreaming, RTMP, RTSP
///   Containers: MP4, MOV, FLV, MKV, WebM, Ogg, MPEG, AVI, TS, M2TS
///   Video: H.263, H.264 AVC, H.265 HEVC, MPEG-4, VP8, VP9, AV1
///   Audio: Vorbis, Opus, FLAC, ALAC, MP1, MP2, MP3, AAC, AC-3, E-AC-3, DTS, DTS-HD
///
/// Features:
/// - ECO Mode toggle (⚡ icon): optional optimization for very low-end devices
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

  // Global lock: prevent creating a new Player while one is still being disposed
  // This is the main cause of the re-entry crash — native libmpv needs time
  // to fully release resources before a new Player can be created safely.
  static bool _isPlayerDisposing = false;

  // Hardware/Software decoding fallback
  bool _useSoftwareDecoding = false;
  int _retryCount = 0;
  static const int _maxRetries = 2;

  // MX Player-style: Video output mode fallback
  // Mode 0: GPU rendering (best quality, may fail on 4K/low-end devices)
  // Mode 1: GPU with downscaling (4K → 1080p, works on most devices)
  // Mode 2: Software rendering (fallback, works everywhere but slower)
  int _videoOutputMode = 0;

  // Black screen detection: if no video output after timeout, try fallback
  Timer? _blackScreenDetectionTimer;
  bool _blackScreenFallbackAttempted = false;

  // Device info for adaptive configuration
  // Performance tier: 0=ultra-low (≤2GB), 1=low (2-3GB), 2=mid (3-4GB), 3=high (>4GB)
  int _perfTier = 3;
  bool _isLowEndDevice = false;

  // ECO Mode: manual toggle only, NOT auto-enabled.
  // Quality-first: we don't force ECO on any device.
  // User can enable it manually if they experience stuttering.
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

  // Whether to use external player instead of built-in
  bool _useExternalPlayer = false;
  bool _externalLaunched = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Check video player mode setting
    _checkVideoPlayerMode();
  }

  Future<void> _checkVideoPlayerMode() async {
    if (!mounted) return;
    final appConfig = Provider.of<AppConfig>(context, listen: false);
    if (appConfig.videoPlayerMode == 'external') {
      _useExternalPlayer = true;
      // Launch external player and pop back
      final success = await ExternalPlayerService.playWithExternalPlayer(widget.videoUrl);
      if (mounted) {
        if (success) {
          _externalLaunched = true;
          Navigator.of(context).pop();
        } else {
          // Fallback to built-in player if external launch fails
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(appConfig.languageCode == 'my'
                  ? 'External ပလေယာ ဖွင့်မရပါ။ Built-in ပလေယာဖြင့် ဖွင့်ပါသည်။'
                  : 'Could not open external player. Using built-in player.'),
              duration: const Duration(seconds: 3),
            ),
          );
          _useExternalPlayer = false;
          _initBuiltInPlayer();
        }
      }
    } else {
      _initBuiltInPlayer();
    }
  }

  void _initBuiltInPlayer() {
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
      // 1. Stop and pause player immediately to release native resources
      //    stop() releases the media stream and frees decoder hardware (MediaCodec),
      //    which is critical for preventing native crashes on re-entry.
      if (!_isDisposed) {
        try { _player.stop(); } catch (_) {}
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
    _blackScreenDetectionTimer?.cancel();

    // FIX: Cancel ALL stream subscriptions explicitly to prevent
    // stream events from firing after the widget is disposed.
    // This is critical — without this, stream callbacks can call setState()
    // on a disposed widget, causing unhandled exceptions that crash the app.
    for (final sub in _streamSubscriptions) {
      try { sub.cancel(); } catch (_) {}
    }
    _streamSubscriptions.clear();

    // FIX: Stop player BEFORE disposing to reduce native crash risk.
    // media_kit's libmpv engine can crash if disposed while actively decoding.
    // We use stop() instead of pause() because stop() releases the media stream
    // and frees native decoder resources, while pause() keeps them allocated.
    // This is critical for re-entry — if decoder resources aren't freed,
    // creating a new Player will conflict with the old one and crash the app.
    _isPlayerDisposing = true; // Lock to prevent new Player creation while disposing
    try { _player.stop(); } catch (_) {}
    try { _player.pause(); } catch (_) {}

    // Save position using last known values (doesn't read from player)
    try { _saveWatchProgressSync(); } catch (e) { debugPrint('Save progress error on dispose: $e'); }

    // Dispose player — wrap in try-catch because native crash may throw
    try { _player.dispose(); } catch (e) { debugPrint('Player dispose error: $e'); }

    // Release the global lock after a short delay to allow native cleanup.
    // libmpv's native cleanup is async — it needs time to release decoder
    // hardware (MediaCodec), GPU surfaces, and demuxer resources.
    // Without this delay, re-entering the player and creating a new Player
    // immediately can cause a native crash (SIGSEGV) that kills the app.
    Future.delayed(const Duration(milliseconds: 500), () {
      _isPlayerDisposing = false;
    });

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

        // Performance tier based on RAM + Android version
        // Tier 0: Ultra-low (≤2GB RAM or very old Android ≤8.1)
        // Tier 1: Low (2-3GB RAM or old Android 9)
        // Tier 2: Mid (3-4GB RAM) — Oppo A16, Redmi 9 etc.
        // Tier 3: High (>4GB RAM) — modern mid-range and above
        if (_totalMemoryMB <= 2048 || _androidVersion <= 27) {
          _perfTier = 0;
        } else if (_totalMemoryMB <= 3072 || _androidVersion <= 28) {
          _perfTier = 1;
        } else if (_totalMemoryMB <= 4096) {
          _perfTier = 2;
        } else {
          _perfTier = 3;
        }

        _isLowEndDevice = _perfTier <= 1;
        // DO NOT auto-enable ECO mode — quality first!
        // User can toggle manually if needed.
        _ecoMode = false;
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

      // FIX: Wait for any previous Player to finish disposing before creating a new one.
      // This is critical for the re-entry crash fix — if we create a new Player while
      // the old one's native libmpv resources are still being released, the native engine
      // will crash (SIGSEGV), killing the entire app.
      // The lock is set in dispose() and released after 500ms delay.
      int waitCount = 0;
      while (_isPlayerDisposing && waitCount < 20) {
        await Future.delayed(const Duration(milliseconds: 100));
        waitCount++;
        if (_isDisposed) return; // Widget was disposed while waiting
      }

      // ==============================================================
      // IMPORTANT: Do NOT set output width/height in VideoControllerConfiguration!
      // Setting width/height FORCES mpv to downscale the video to that resolution,
      // which makes 1080p/4K video look blurry on low-end devices.
      // Instead, we let mpv render at the video's native resolution and use
      // mpv-level optimizations (frame dropping, skip filters) for performance.
      // This preserves full visual quality for ALL resolutions (480p-4K).
      // ==============================================================

      // Buffer size: must be large enough to prevent rebuffering,
      // but NOT so large that it exhausts RAM on low-end devices.
      // 4K HEVC at 20Mbps ≈ 2.5MB/sec. A 16MB buffer ≈ 6 seconds of 4K.
      // Key insight: large buffers don't help if the network can't fill them fast enough.
      // They just waste RAM → OOM → pixelation/artifacts on low-end devices.
      // However, with cache-pause enabled, larger buffers ensure smoother playback.
      final int bufferSizeBytes;
      switch (_perfTier) {
        case 0: // Ultra-low (≤2GB): 32MB — enough for ~10 sec of 4K
          bufferSizeBytes = 32 * 1024 * 1024;
          break;
        case 1: // Low (2-3GB): 48MB
          bufferSizeBytes = 48 * 1024 * 1024;
          break;
        case 2: // Mid (3-4GB): 64MB
          bufferSizeBytes = 64 * 1024 * 1024;
          break;
        default: // High (>4GB): 96MB
          bufferSizeBytes = 96 * 1024 * 1024;
          break;
      }

      // MX Player-style video output mode selection:
      // Mode 0: GPU rendering with hardware decoding (best quality)
      //         - Works great for 480p-1080p on all devices
      //         - May fail (black screen) for 4K on low-end/older devices
      // Mode 1: GPU rendering with downscaling (4K → 1080p output)
      //         - Uses HW decoder but downscales output for GPU compatibility
      //         - Good balance: HW decode speed + GPU compatibility
      // Mode 2: Software rendering (CPU-based, fallback)
      //         - Works everywhere but uses more CPU/battery
      //         - Last resort when GPU rendering completely fails

      final bool useHWAccel = !_useSoftwareDecoding;
      final String hwdecValue = _useSoftwareDecoding
          ? 'no'
          : (_androidVersion >= 29 ? 'auto' : 'auto-safe');

      // Select video output mode based on current fallback state
      String voValue;
      int? outputWidth;
      int? outputHeight;

      switch (_videoOutputMode) {
        case 0:
          // Mode 0: GPU rendering at native resolution (best quality)
          voValue = 'gpu';
          // No output width/height — render at native resolution
          break;
        case 1:
          // Mode 1: GPU rendering with downscaling for 4K content
          // This is like MX Player's "HW+" mode — HW decoder + downscaled output
          voValue = 'gpu';
          if (_isLowEndDevice || _perfTier <= 1) {
            // Low-end device: downscale to 720p for best compatibility
            outputWidth = 1280;
            outputHeight = 720;
          } else {
            // Mid/high device: downscale 4K to 1080p (still looks great)
            outputWidth = 1920;
            outputHeight = 1080;
          }
          break;
        default:
          // Mode 2: Software rendering (CPU fallback)
          // Like MX Player's "SW" mode
          voValue = 'libmpv';
          break;
      }

      debugPrint('Video output mode: $_videoOutputMode, vo: $voValue, hwdec: $hwdecValue, '
          'output: ${outputWidth ?? 'native'}x${outputHeight ?? 'native'}');

      _player = Player(
        configuration: PlayerConfiguration(
          bufferSize: bufferSizeBytes,
          title: 'CM Movies Player',
          logLevel: MPVLogLevel.error,
        ),
      );

      _controller = VideoController(
        _player,
        configuration: VideoControllerConfiguration(
          vo: voValue,
          hwdec: hwdecValue,
          enableHardwareAcceleration: useHWAccel,
          androidAttachSurfaceAfterVideoParameters: true,
          // MX Player-style: Set output dimensions only in Mode 1 (downscale)
          // Mode 0: native resolution (no downscaling = best quality)
          // Mode 1: downscale 4K → 1080p/720p for GPU compatibility
          // Mode 2: software rendering (no dimensions needed)
          width: outputWidth,
          height: outputHeight,
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
      _applyPerformanceTuningNonBlocking();

      // MX Player-style: Start black screen detection timer.
      // If no video output appears within 3 seconds (audio plays but screen is black),
      // automatically try the next video output mode (GPU → GPU+Downscale → SW).
      // This handles the common 4K black screen issue on low-end/older devices.
      if (!_blackScreenFallbackAttempted && _videoOutputMode < 2) {
        _blackScreenDetectionTimer?.cancel();
        _blackScreenDetectionTimer = Timer(const Duration(seconds: 3), () {
          if (_isDisposed || !mounted) return;
          // If still no video output after 3 seconds, try fallback mode
          if (!_hasVideoOutput && !_isBuffering) {
            debugPrint('BLACK SCREEN DETECTED: No video output after 3s. '
                'Trying fallback mode ${_videoOutputMode + 1}');
            _tryVideoOutputFallback();
          }
        });
      }

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
          // Phase 4.31: sanitize — exceptions can also embed the URL.
          _errorMessage = _sanitizeErrorMessage(e.toString());
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

  /// Applies MINIMAL mpv performance tuning — quality-first approach.
  ///
  /// Philosophy: mpv's defaults are already excellent. We only override
  /// the few properties that actually help on mobile without hurting quality.
  ///
  /// What we DO (all devices):
  ///   - VSync off (reduces micro-stutter, tearing invisible on mobile)
  ///   - PBO for faster GPU texture uploads
  ///   - Display-level frame drop when GPU falls behind
  ///   - Audio-desync tolerance (better than stuttering)
  ///
  /// What we DO NOT do (to preserve quality):
  ///   - NO bilinear scaling (mpv's default bicubic/spline64 is much better)
  ///   - NO output resolution downscaling
  ///   - NO skip non-reference frames (causes pixelation)
  ///   - NO disable debanding (causes visible banding)
  ///   - NO forced skiploopfilter=all (causes blocking artifacts)
  ///
  /// ECO mode (manual toggle only):
  ///   - Skip HEVC loop filter for non-reference frames only (skiploopfilter=nonref)
  ///     — saves ~20% CPU, minimal visual impact
  ///   - Display+decoder frame drop when behind
  ///   - Slightly reduced demuxer buffer to save RAM
  Future<void> _applyPerformanceTuning() async {
    try {
      if (_isDisposed) return;

      // Brief wait for video parameters — shorter than before for faster startup
      await Future.delayed(const Duration(milliseconds: 200));
      if (_isDisposed) return;

      final bool isEco = _ecoMode;
      final bool is4K = _isHighResVideo;

      debugPrint('Tuning: tier=$_perfTier, eco=$_ecoMode, is4K=$is4K, videoWidth=${_player.state.width}');

      // =============================================================
      // ALL DEVICES: Essential optimizations (zero quality loss)
      // These are the ONLY overrides we apply by default.
      // mpv's defaults are already great — don't override more than needed.
      // =============================================================

      // Network caching: 5 seconds buffer for smooth streaming
      // This prevents stuttering when network is slow or fluctuating
      await _setMpvProperty('demuxer-max-bytes', (50 * 1024 * 1024).toString()); // 50MB forward buffer
      await _setMpvProperty('demuxer-max-back-bytes', (25 * 1024 * 1024).toString()); // 25MB back buffer
      await _setMpvProperty('cache', 'yes');
      await _setMpvProperty('cache-secs', '5'); // 5 seconds cache
      await _setMpvProperty('cache-pause', 'yes'); // Auto-pause when cache runs low
      await _setMpvProperty('cache-pause-wait', '3'); // Wait up to 3s for cache to fill
      await _setMpvProperty('cache-pause-initial', 'yes'); // Pause at start until cache fills

      // Display-level frame drop: when the GPU can't keep up,
      // drop late frames at the display stage. This is the least
      // aggressive frame drop — invisible to the user, saves CPU.
      await _setMpvProperty('framedrop', 'vo');

      // VSync off — eliminates vsync-induced micro-stutter.
      // Tearing is invisible on mobile displays.
      await _setMpvProperty('opengl-swapinterval', '0');

      // Pixel Buffer Objects — faster GPU texture uploads.
      // Zero quality impact, just faster rendering.
      await _setMpvProperty('opengl-pbo', 'yes');

      // Tolerate slight A/V desync rather than stuttering.
      // audio-desync = resample audio to match video timing.
      await _setMpvProperty('video-sync', 'audio-desync');

      // =============================================================
      // ECO MODE ONLY (manual toggle):
      // Applied ONLY when user explicitly enables ECO mode.
      // These optimizations have MINIMAL visual impact:
      //   - skiploopfilter=nonref (not 'all'!) — only skip non-reference
      //     deblocking, saves ~20% HEVC CPU with barely visible effect
      //   - decoder frame drop when behind (in addition to display drop)
      //   - reduced buffer to save RAM on very low-end devices
      // =============================================================
      if (isEco) {
        // Frame drop at both display AND decoder level when behind
        // Only drops frames when actually lagging — doesn't skip proactively
        await _setMpvProperty('framedrop', 'decoder+vo');

        // Decoder-level frame drop: 'nonref' = only drop non-reference frames
        // This is safe — non-reference frames aren't needed for future decoding
        await _setMpvProperty('vd-lavc-framedrop', 'nonref');

        // Skip HEVC loop filter for NON-REFERENCE frames only.
        // NOT 'all' — 'all' causes visible blocking artifacts (pixelation).
        // 'nonref' saves ~20% HEVC CPU with barely visible quality impact.
        // For 4K specifically, we use 'bidir' which skips B-frame deblocking —
        // good balance between CPU savings and quality.
        await _setMpvProperty('vd-lavc-skiploopfilter', is4K ? 'bidir' : 'nonref');

        // Faster seeking — don't require exact keyframe alignment
        await _setMpvProperty('hr-seek', 'no');

        // Reasonable demuxer buffer — smaller to save RAM on low-end
        // Still large enough for smooth playback
        final backBytes = _perfTier <= 1
            ? (4 * 1024 * 1024).toString()     // 4MB back-buffer
            : (8 * 1024 * 1024).toString();     // 8MB back-buffer
        await _setMpvProperty('demuxer-max-back-bytes', backBytes);

        final maxBytes = _perfTier <= 1
            ? (16 * 1024 * 1024).toString()     // 16MB forward buffer
            : (24 * 1024 * 1024).toString();     // 24MB forward buffer
        await _setMpvProperty('demuxer-max-bytes', maxBytes);
      }

      debugPrint('Performance tuning applied: tier=$_perfTier, eco=$isEco, 4k=$is4K');
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

  /// MX Player-style: Try next video output mode when black screen detected
  /// or when GPU rendering fails. Modes: 0=GPU native → 1=GPU downscale → 2=SW
  void _tryVideoOutputFallback() {
    if (_isDisposed || !mounted) return;
    if (_videoOutputMode >= 2) return; // Already at SW mode, no more fallbacks

    _blackScreenFallbackAttempted = true;

    // Cancel stream subscriptions and clean up current player
    for (final sub in _streamSubscriptions) {
      try { sub.cancel(); } catch (_) {}
    }
    _streamSubscriptions.clear();

    try { _player.stop(); } catch (_) {}
    try { _player.pause(); } catch (_) {}
    try { _player.dispose(); } catch (_) {}

    // Move to next video output mode
    _videoOutputMode++;
    _hasVideoOutput = false;

    // If mode 2 (SW), also enable software decoding
    if (_videoOutputMode >= 2) {
      _useSoftwareDecoding = true;
    }

    debugPrint('Video output fallback: switching to mode $_videoOutputMode '
        '(${_videoOutputMode == 0 ? 'GPU native' : _videoOutputMode == 1 ? 'GPU downscale' : 'SW'})');

    // Delay before re-initializing to allow native cleanup
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted && !_isDisposed) {
        _initializePlayer();
      }
    });
  }

  void _handlePlayerError(String error) {
    // Phase 4.31 (2026-07-28): Sanitize the raw error before storing —
    // libmpv error messages often contain the full video URL (e.g.
    // "Failed to open https://stream.cmreel.com/file/...mp4"). Bro asked
    // for the real link to be hidden from end users; we keep only the
    // diagnostic keywords needed for the codec/render classification
    // below and discard the URL portion entirely.
    final sanitized = _sanitizeErrorMessage(error);

    final isCodecError = sanitized.contains('codec') ||
        sanitized.contains('Could not open') ||
        sanitized.contains('decoder') ||
        sanitized.contains('HEVC') ||
        sanitized.contains('H.265') ||
        sanitized.contains('h265') ||
        sanitized.contains('hevc') ||
        sanitized.contains('not supported') ||
        sanitized.contains('failed to initialize');

    // MX Player-style: Also treat GPU/render errors as needing output fallback
    final isRenderError = error.contains('gpu') ||
        error.contains('vulkan') ||
        error.contains('opengl') ||
        error.contains('surface') ||
        error.contains('EGL') ||
        error.contains('renderer');

    if ((isCodecError || isRenderError) && _retryCount < _maxRetries) {
      _retryCount++;

      // Cancel all stream subscriptions BEFORE disposing the player.
      for (final sub in _streamSubscriptions) {
        try { sub.cancel(); } catch (_) {}
      }
      _streamSubscriptions.clear();

      // Stop the player to release media resources, then dispose
      try { _player.stop(); } catch (_) {}
      try { _player.pause(); } catch (_) {}
      try { _player.dispose(); } catch (_) {}

      _hasVideoOutput = false;

      if (isRenderError && _videoOutputMode < 2) {
        // GPU render error: try next output mode
        _videoOutputMode++;
        if (_videoOutputMode >= 2) {
          _useSoftwareDecoding = true;
        }
      } else if (isCodecError && !_useSoftwareDecoding) {
        // Codec error: switch to SW decoding
        _useSoftwareDecoding = true;
        if (_videoOutputMode < 2) {
          _videoOutputMode = 2; // Go directly to SW mode for codec issues
        }
      }

      // Delay before re-initializing to allow native cleanup
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted && !_isDisposed) {
          _initializePlayer();
        }
      });
    } else if (mounted) {
      setState(() {
        _isInitialized = true;
        _errorMessage = sanitized; // Phase 4.31: sanitized (URL stripped)
      });
    }
  }

  /// Phase 4.31 (2026-07-28): Strip any http(s)://... URL from the raw
  /// libmpv error string and return only the diagnostic portion that's
  /// safe to show to end users. Bro explicitly requested that the real
  /// video link never appear in the error UI — both for security and to
  /// avoid confusing users with long opaque URLs.
  ///
  /// Examples:
  ///   "Failed to open https://stream.cmreel.com/file/x.mp4" → "Failed to open [link]"
  ///   "Could not open codec HEVC"                            → "Could not open codec HEVC"
  ///   "Server returned 404"                                  → "Server returned 404"
  String _sanitizeErrorMessage(String raw) {
    if (raw.isEmpty) return raw;
    // Match http(s)://host/path?query#fragment up to the first whitespace
    // or end-of-string. libmpv typically embeds the URL as a single token.
    final urlPattern = RegExp(r'https?://[^\s<>"]+');
    var cleaned = raw.replaceAll(urlPattern, '[link]');
    // Some libmpv variants quote the URL with single backticks or quotes.
    cleaned = cleaned.replaceAll(RegExp(r'`[^`]*`'), '[link]');
    // Trim trailing whitespace / punctuation artifacts left after removal.
    cleaned = cleaned.replaceAll(RegExp(r'\s{2,}'), ' ').trim();
    if (cleaned.isEmpty || cleaned == '[link]') {
      return 'Failed to load video';
    }
    return cleaned;
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
    // If external player was launched or is being prepared, show a loading screen
    if (_useExternalPlayer || _externalLaunched) {
      return PopScope(
        canPop: true,
        child: Scaffold(
          backgroundColor: Colors.black,
          body: Center(
            child: _externalLaunched
                ? const SizedBox.shrink()
                : const CircularProgressIndicator(color: Color(0xFFE50914)),
          ),
        ),
      );
    }

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
                // initialData prevents flash when controls are toggled
                initialData: _player.state.playing,
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

          // ====== LAYER 7: SW badge + Performance mode indicator + Video output mode ======
          if (_hasVideoOutput)
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
                    _videoOutputMode == 2
                        ? (_ecoMode ? 'SW · ECO' : 'SW')
                        : _videoOutputMode == 1
                            ? (_ecoMode ? 'HW+ · ECO' : 'HW+')
                            : (_ecoMode ? 'HW · ECO' : 'HW'),
                    style: TextStyle(
                        color: _videoOutputMode == 2
                            ? Colors.orange
                            : _videoOutputMode == 1
                                ? Colors.amber
                                : Colors.greenAccent,
                        fontSize: 10,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),
          // Show ECO mode badge when user has manually toggled ECO on
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
                  child: const Text(
                    'ECO',
                    style: TextStyle(
                        color: Colors.amber,
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
            // ECO Mode toggle — frame-drop optimization for smoother playback
            // Quality is preserved; only frame dropping and loop filter skipping are affected
            IconButton(
              icon: Icon(
                _ecoMode ? Icons.speed : Icons.speed_outlined,
                color: _ecoMode ? Colors.amber : Colors.white54,
                size: 22,
              ),
              onPressed: _toggleEcoMode,
              style: IconButton.styleFrom(
                  backgroundColor: _ecoMode
                      ? Colors.amber.withOpacity(0.2)
                      : Colors.black45,
                  padding: const EdgeInsets.all(8)),
              tooltip: _ecoMode ? 'ECO ON (smoother)' : 'ECO OFF (best quality)',
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
        // CRITICAL FIX: initialData prevents 00:00 flash when controls are toggled.
        // Without initialData, StreamBuilder starts with snapshot.data = null when
        // re-created (controls hidden then shown), causing position = Duration.zero.
        // Using _player.state.position as initialData gives the correct current position
        // immediately on first frame, eliminating the 00:00 → correct position jump.
        initialData: _player.state.position,
        stream: _player.stream.position,
        builder: (context, snapshot) {
          // Use snapshot data, but also check _player.state as fallback
          // This handles edge cases where stream might lag behind
          final position = snapshot.data ?? _player.state.position;
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
            // initialData prevents flash when controls are toggled
            initialData: _player.state.playing,
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
