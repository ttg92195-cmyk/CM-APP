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
/// - Manual toggle controls (tap to show/hide, NO auto-hide, NO pause on toggle)
/// - Audio Boost up to 300% (vertical drag on right 30% of screen)
/// - Volume side indicator (right edge, doesn't cover video)
/// - Hardware decoding first, software fallback if HW fails
/// - Video fit: BoxFit.contain for proper landscape/portrait display
/// - Subtitle margin above bottom bar
/// - Playback Speed bottom sheet (50% width, centered, scrollable)
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
  bool _showControls = true;
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
  double _currentVolume = 100.0;
  static const double _maxVolume = 300.0;
  static const double _normalVolume = 100.0;
  bool _isVolumeBoosted = false;
  bool _showVolumeIndicator = false;
  Timer? _volumeIndicatorTimer;

  // Volume drag tracking — only active on right 30% of screen
  bool _isDraggingVolume = false;

  // App lifecycle
  bool _wasPlayingBeforePause = false;

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
    _detectDeviceAndInitialize();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
        _wasPlayingBeforePause = _player.state.playing;
        if (_player.state.playing) {
          _player.pause();
        }
        break;
      case AppLifecycleState.resumed:
        if (_wasPlayingBeforePause && mounted) {
          _player.play();
        }
        _wasPlayingBeforePause = false;
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        break;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _volumeIndicatorTimer?.cancel();
    _player.dispose();
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
    super.dispose();
  }

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
        _isLowEndDevice = _androidVersion <= 29 ||
            _screenWidth < 1080 ||
            _screenHeight < 1920;
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

      int? outputWidth;
      int? outputHeight;
      if (_isLowEndDevice) {
        outputWidth = 1280;
        outputHeight = 720;
      } else if (_screenWidth <= 1080) {
        outputWidth = 1920;
        outputHeight = 1080;
      }

      final bool useHWAccel = !_useSoftwareDecoding;
      final String hwdecValue = _useSoftwareDecoding ? 'no' : 'auto';

      _player = Player(
        configuration: PlayerConfiguration(
          bufferSize: 64 * 1024 * 1024,
          title: 'CM Movies Player',
          vo: 'gpu',
          logLevel: MPVLogLevel.error,
        ),
      );

      // FIX #2: Push subtitles above the bottom player bar (80px bottom margin)
      _player.setProperty('sub-margin-y', '80');

      _controller = VideoController(
        _player,
        configuration: VideoControllerConfiguration(
          vo: 'gpu',
          hwdec: hwdecValue,
          enableHardwareAcceleration: useHWAccel,
          androidAttachSurfaceAfterVideoParameters: true,
          width: outputWidth,
          height: outputHeight,
        ),
      );

      _player.stream.buffering.listen((buffering) {
        if (mounted) setState(() => _isBuffering = buffering);
      });

      _player.stream.error.listen((error) {
        if (mounted && error.isNotEmpty) _handlePlayerError(error);
      });

      _player.stream.completed.listen((completed) {
        if (completed && mounted) debugPrint('Video playback completed');
      });

      _player.stream.playing.listen((playing) {
        if (playing && !_hasVideoOutput && mounted) {
          setState(() => _hasVideoOutput = true);
        }
      });

      _player.stream.width.listen((width) {
        if (width != null && width > 0 && !_hasVideoOutput && mounted) {
          setState(() => _hasVideoOutput = true);
        }
      });

      _player.stream.volume.listen((volume) {
        if (mounted) {
          setState(() {
            _currentVolume = volume;
            _isVolumeBoosted = volume > _normalVolume;
          });
        }
      });

      await _player.open(Media(widget.videoUrl));
      await _player.play();

      if (mounted) {
        setState(() {
          _isInitialized = true;
          _showControls = true;
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

  // FIX #5: ONLY toggle controls visibility — NEVER pause the video
  void _toggleControls() {
    setState(() => _showControls = !_showControls);
  }

  // Volume drag handler — only processes if drag started on right 30% of screen
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
    });
    _volumeIndicatorTimer?.cancel();
    _volumeIndicatorTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _showVolumeIndicator = false);
    });
  }

  void _handleVolumeSliderChange(double value) {
    _player.setVolume(value);
    setState(() {
      _currentVolume = value;
      _isVolumeBoosted = value > _normalVolume;
    });
  }

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

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    if (hours > 0) return '$hours:${twoDigits(minutes)}:${twoDigits(seconds)}';
    return '${twoDigits(minutes)}:${twoDigits(seconds)}';
  }

  // ==============================================================
  // BUILD — Layer ordering for correct touch handling
  //
  // Layer 1: Video (IgnorePointer) — BOTTOM — never consumes taps
  // Layer 2: GestureDetector (opaque) — catches taps on empty areas
  //          onTap: ONLY toggles controls (FIX #5 — no pause!)
  //          onVerticalDrag: Volume on right 30% only
  // Layer 3: Controls (when _showControls) — interactive buttons/sliders
  //          ABOVE GestureDetector so they absorb their own taps
  //          Decorative backgrounds use IgnorePointer (taps pass through)
  // Layer 4: Volume side indicator (IgnorePointer) — right edge (FIX #3)
  // Layer 5: Buffering indicator (IgnorePointer)
  // Layer 6: SW badge (IgnorePointer)
  // ==============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // ====== LAYER 1: Video (IgnorePointer) ======
          Positioned.fill(
            child: IgnorePointer(
              child: _buildVideoLayer(),
            ),
          ),

          // ====== LAYER 2: GestureDetector (BELOW controls) ======
          // Catches taps on EMPTY areas. Controls in Layer 3 get hit FIRST
          // because they're above in the Stack.
          // FIX #1: Positioned.fill + opaque for reliable toggle
          // FIX #5: onTap ONLY toggles controls — NO pause, NO double-tap seek
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              // FIX #5: ONLY toggle controls, NEVER pause video
              onTap: _toggleControls,
              // Volume drag: only on right 30% of screen
              onVerticalDragStart: (details) {
                final screenWidth = MediaQuery.of(context).size.width;
                _isDraggingVolume =
                    details.globalPosition.dx > screenWidth * 0.7;
              },
              onVerticalDragUpdate: _handleVolumeDrag,
              onVerticalDragEnd: (_) {
                _isDraggingVolume = false;
              },
              child: Container(color: Colors.transparent),
            ),
          ),

          // ====== LAYER 3: Controls (when visible) ======
          // Interactive elements (buttons, sliders) absorb their own taps.
          // Decorative backgrounds (gradients) use IgnorePointer → taps pass
          // through to Layer 2 GestureDetector.
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
            // FIX #5: Icon ALWAYS reflects player.state.playing
            Center(
              child: StreamBuilder<bool>(
                stream: _player.stream.playing,
                builder: (context, snapshot) {
                  // FIX #5: Always use player.state.playing for icon state
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

          // ====== LAYER 4: Volume side indicator ======
          // FIX #3: Volume indicator on RIGHT edge, does NOT cover video center
          if (_showVolumeIndicator)
            Positioned(
              right: 16,
              top: 0,
              bottom: 0,
              width: 56,
              child: IgnorePointer(
                child: _buildVolumeSideIndicator(),
              ),
            ),

          // ====== LAYER 5: Buffering indicator ======
          if (_isBuffering)
            const Positioned.fill(
              child: IgnorePointer(
                child: Center(
                  child: CircularProgressIndicator(color: Color(0xFFE50914)),
                ),
              ),
            ),

          // ====== LAYER 6: SW badge ======
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
                  child: const Text(
                    'SW',
                    style: TextStyle(
                        color: Colors.orange,
                        fontSize: 10,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ====== Video Layer ======
  // FIX #2: BoxFit.contain for proper video fit in landscape mode
  Widget _buildVideoLayer() {
    if (!_isInitialized) return _buildLoadingScreen();
    if (_errorMessage != null) return _buildErrorScreen();
    return Center(
      child: AspectRatio(
        aspectRatio: _player.state.width != null &&
                _player.state.height != null &&
                _player.state.height! > 0
            ? _player.state.width! / _player.state.height!
            : 16 / 9,
        child: Video(
          controller: _controller,
          controls: NoVideoControls,
          fit: BoxFit.contain,
        ),
      ),
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
                  onPressed: () => Navigator.pop(context),
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

  // ====== Top Bar ======

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
                    fontWeight: FontWeight.w600),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // Audio track button
            IconButton(
              icon: const Icon(Icons.audiotrack, color: Colors.white, size: 22),
              onPressed: _showAudioTrackSheet,
              style: IconButton.styleFrom(
                  backgroundColor: Colors.black45,
                  padding: const EdgeInsets.all(8)),
            ),
            const SizedBox(width: 4),
            // Subtitle button
            IconButton(
              icon:
                  const Icon(Icons.subtitles, color: Colors.white, size: 22),
              onPressed: _showSubtitleTrackSheet,
              style: IconButton.styleFrom(
                  backgroundColor: Colors.black45,
                  padding: const EdgeInsets.all(8)),
            ),
            const SizedBox(width: 4),
            // Speed button
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

  // ====== Bottom Bar ======

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
          final progress = duration.inMilliseconds > 0
              ? position.inMilliseconds / duration.inMilliseconds
              : 0.0;

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
                  onChanged: (value) {
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
                    Text(_formatDuration(position),
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
          // FIX #5: Icon ALWAYS reflects player.state.playing
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

  // ====== Volume Slider with Boost (in bottom bar) ======

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

  // ====== Volume Side Indicator (right edge — FIX #3) ======
  // Appears when dragging volume on right 30% of screen
  // Positioned on the RIGHT edge so it does NOT cover the video center

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
            // Vertical volume bar
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
                  // Normal volume (100%) marker line
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

  // ====== Bottom Sheet: Audio Track (FIX #4 — scrollable, constrained) ======

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
                child: Text('Audio Track',
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

        // FIX #4: In landscape, constrain to 50% width and center
        if (isLandscape) {
          return Center(
            child: SizedBox(
              width: screenWidth * 0.5,
              child: content,
            ),
          );
        }
        return content;
      },
    );
  }

  // ====== Bottom Sheet: Subtitles (FIX #4 — scrollable, constrained) ======

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
                child: Text('Subtitles',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w600)),
              ),
              const Divider(color: Colors.white12, height: 1),
              // "Off" option
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

        // FIX #4: In landscape, constrain to 50% width and center
        if (isLandscape) {
          return Center(
            child: SizedBox(
              width: screenWidth * 0.5,
              child: content,
            ),
          );
        }
        return content;
      },
    );
  }

  // ====== Bottom Sheet: Playback Speed (FIX #4 — scrollable, 50% width, centered) ======

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
                child: Text('Playback Speed',
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

        // FIX #4: In landscape, constrain to 50% width and center
        if (isLandscape) {
          return Center(
            child: SizedBox(
              width: screenWidth * 0.5,
              child: content,
            ),
          );
        }
        return content;
      },
    );
  }
}
