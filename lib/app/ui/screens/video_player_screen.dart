import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// Professional Video Player using media_kit (libmpv/VLC engine)
/// Supports: MP4, MKV, HEVC (H.265), 4K, AC3/DTS audio, embedded subtitles
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
    _initializePlayer();
  }

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

      // Create player with optimized settings for 4K/MKV streaming
      _player = Player(
        configuration: const PlayerConfiguration(
          // 32MB buffer for 4K high-bitrate streams - prevents stuttering
          bufferSize: 32 * 1024 * 1024,
          title: 'CM Movies Player',
          // GPU video output driver - enables hardware rendering
          vo: 'gpu',
          // Show errors in log for debugging
          logLevel: MPVLogLevel.error,
        ),
      );

      // Create video controller with hardware-accelerated rendering
      // Key settings for 4K HEVC/MKV playback:
      // - vo: 'gpu' → Force GPU video output
      // - hwdec: 'auto' → Auto-select best hardware decoder (MediaCodec on Android)
      // - androidAttachSurfaceAfterVideoParameters: true → Wait for video info before rendering
      //   This fixes "Could not open codec" on some devices by allowing the surface
      //   to be configured with correct parameters before attaching
      _controller = VideoController(
        _player,
        configuration: const VideoControllerConfiguration(
          // Force GPU video output driver
          vo: 'gpu',
          // Auto hardware decoding: tries MediaCodec first, falls back to software
          // 'auto' is better than 'auto-safe' for 4K HEVC because it will attempt
          // hardware decode even if resolution seems high for the device
          hwdec: 'auto',
          // Enable hardware acceleration
          enableHardwareAcceleration: true,
          // On Android, wait for video parameters before attaching Surface.
          // This is crucial for 4K HEVC - the surface needs to know the video
          // dimensions before it can properly configure the hardware decoder
          androidAttachSurfaceAfterVideoParameters: true,
        ),
      );

      // Listen to player state for buffering indicator
      _player.stream.buffering.listen((buffering) {
        if (mounted) {
          setState(() {
            _isBuffering = buffering;
          });
          debugPrint('Buffering: $buffering');
        }
      });

      // Listen for errors
      _player.stream.error.listen((error) {
        if (mounted && error.isNotEmpty) {
          debugPrint('Player error: $error');
          setState(() {
            _errorMessage = error;
            _isInitialized = true;
          });
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
                    setState(() {
                      _isInitialized = false;
                      _errorMessage = null;
                      _hasVideoOutput = false;
                    });
                    _initializePlayer();
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
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
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: Color(0xFFE50914)),
          SizedBox(height: 12),
          Text(
            'Buffering...',
            style: TextStyle(color: Colors.white70, fontSize: 14),
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
