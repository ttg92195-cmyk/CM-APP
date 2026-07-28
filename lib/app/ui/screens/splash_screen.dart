// Phase 4.34: Premium animated splash screen.
//
// Design goals (per Bro's brief):
//   - "မထစ်အောင်" → no stutter on low-end devices (Oppo A16 class)
//   - "အလန်းစားဖြစ်ဖြစ်" → cinematic premium look (Disney+ / Netflix tier)
//   - 3 second total duration (matches _minSplashElapsed in main.dart)
//   - Phase 4.34.1: precise centering — rings, halo, icon, and KMM text
//     must all share the same horizontal axis, with the logo at exact
//     screen center and the text just below the logo's bottom edge.
//
// Why custom Flutter animation instead of Lottie:
//   - Lottie JSON parsing on first frame can cause an initial stutter on
//     cold start, especially on low-end devices. For a SPLASH screen where
//     every ms of perceived latency matters, this is the wrong tradeoff.
//   - Custom vector animation runs natively on the GPU via Flutter's
//     rendering pipeline → instant first frame, smooth 60fps.
//   - No asset to ship / decode → smaller APK, faster cold start.
//
// Animation layers:
//   1. Spotlight gradient background (subtle radial red glow on deep black)
//   2. Three concentric expanding rings (staggered, ripple effect)
//   3. Pulsing red glow halo behind the logo (breathing effect)
//   4. Logo: play_circle_fill with elastic scale-in + subtle pulse loop
//   5. "KMM" brand text with horizontal shimmer sweep
//   6. Three sequential loading dots at the bottom
//
// Layout (Phase 4.34.1):
//   - Logo composition (rings + halo + icon) is positioned at EXACT screen
//     center using LayoutBuilder + Positioned. This guarantees the rings
//     and halo share the same center, regardless of what's below them.
//   - KMM text is positioned just below the logo's bottom edge (logo_size/2
//     + gap), so it tracks the logo's position rather than being pushed
//     down by Column centering math.
//   - Previously, putting rings in a separate Center widget + halo/text in
//     a Column caused the rings' center (screen center) to mismatch the
//     halo's center (column center, which is offset by the text below).

import 'dart:math' as math;
import 'package:flutter/material.dart';

class SplashScreen extends StatefulWidget {
  // Theme is intentionally ignored — splash is always cinematic dark, like
  // Netflix / Disney+ / Prime Video. This avoids light-mode readability
  // issues with the brand shimmer text and keeps the visual identity
  // consistent on every launch.
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  // Intro controller: runs once, drives the initial reveal (1.4s).
  late final AnimationController _introController;

  // Loop controller: drives continuous animations (pulse, rings, shimmer).
  // Repeats indefinitely until the widget is disposed.
  late final AnimationController _loopController;

  // Brand colors.
  static const Color _brandRed = Color(0xFFE50914);
  static const Color _brandRedBright = Color(0xFFFF2A36);

  // Logo composition dimensions. All visual layers (rings, halo, icon)
  // are sized relative to these constants so the whole composition
  // scales together if we tweak it later.
  static const double _compositionSize = 200.0; // SizedBox footprint
  static const double _haloSize = 100.0;
  static const double _iconSize = 72.0;
  static const double _ringMinSize = 60.0;
  static const double _ringMaxSize = 200.0; // fits inside composition
  static const double _textGap = 14.0; // gap between logo bottom and text

  @override
  void initState() {
    super.initState();

    _introController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );

    _loopController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    );

    // Kick off both controllers immediately so the very first frame is
    // already mid-animation (no static "flash" before things start moving).
    _introController.forward();
    _loopController.repeat();
  }

  @override
  void dispose() {
    _introController.dispose();
    _loopController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const bgColor = Color(0xFF050505);

    return Scaffold(
      backgroundColor: bgColor,
      // RepaintBoundary isolates the splash's painting from the rest of
      // the app's render tree — useful because the splash is replaced
      // mid-flight by HomePage/LoginPage, and we don't want the
      // animation's repaints to bleed into sibling layers.
      body: RepaintBoundary(
        child: AnimatedBuilder(
          animation: Listenable.merge([_introController, _loopController]),
          builder: (context, _) {
            return Stack(
              fit: StackFit.expand,
              children: [
                _buildSpotlightBackground(bgColor),
                _buildCenteredComposition(),
                _buildLoadingDots(),
              ],
            );
          },
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────
  // Composition: logo at exact screen center, text just below.
  //
  // We use LayoutBuilder + Positioned instead of a Column because:
  //   - A Column centers its CHILDREN as a group, so the logo ends up
  //     above screen center (because text pushes the column's center
  //     down). This is what caused Bro to see the icon "above" the
  //     pulse rings and the text "too low".
  //   - LayoutBuilder gives us the screen height, so we can position
  //     the logo at exact screen center (height/2 - logoSize/2) and
  //     the text at exact (height/2 + logoSize/2 + gap). This works
  //     on any screen size.
  // ─────────────────────────────────────────────────────────────────────
  Widget _buildCenteredComposition() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final screenHeight = constraints.maxHeight;
        final screenCenter = screenHeight / 2;

        return Stack(
          children: [
            // Logo composition (rings + halo + icon) centered on screen.
            // Positioned with explicit top + height so the composition's
            // CENTER aligns with screen center, regardless of what's
            // above or below it.
            Positioned(
              left: 0,
              right: 0,
              top: screenCenter - _compositionSize / 2,
              height: _compositionSize,
              child: Center(child: _buildLogoComposition()),
            ),
            // KMM text positioned just below the logo's bottom edge.
            // logo bottom = screenCenter + compositionSize/2.
            // text top = logo bottom + _textGap.
            Positioned(
              left: 0,
              right: 0,
              top: screenCenter + _compositionSize / 2 + _textGap,
              child: Center(child: _buildBrandText()),
            ),
          ],
        );
      },
    );
  }

  // ─────────────────────────────────────────────────────────────────────
  // 1. Spotlight background — radial red glow on deep black.
  // ─────────────────────────────────────────────────────────────────────
  Widget _buildSpotlightBackground(Color baseColor) {
    // The glow intensity gently breathes with the loop controller so the
    // background never feels completely static.
    final breath = 0.6 + 0.25 * _loopController.value;

    return Container(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: Alignment.center,
          radius: 0.75,
          colors: [
            _brandRed.withOpacity(0.18 * breath),
            _brandRed.withOpacity(0.06 * breath),
            baseColor,
            const Color(0xFF000000),
          ],
          stops: const [0.0, 0.35, 0.75, 1.0],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────
  // 2-4. Logo composition — rings + halo + icon in one Stack.
  //
  // All three layers share the SAME center because they're inside one
  // Stack with `alignment: Alignment.center`. The SizedBox gives the
  // Stack a fixed footprint so the LayoutBuilder positioning above
  // remains stable regardless of ring expansion.
  // ─────────────────────────────────────────────────────────────────────
  Widget _buildLogoComposition() {
    return SizedBox(
      width: _compositionSize,
      height: _compositionSize,
      child: Stack(
        alignment: Alignment.center,
        children: [
          _buildPulseRings(),
          _buildHaloWithIcon(),
        ],
      ),
    );
  }

  // Pulse rings — three concentric expanding circles, staggered.
  Widget _buildPulseRings() {
    final List<double> phases = [0.0, 0.33, 0.66];

    return Stack(
      alignment: Alignment.center,
      children: phases.map((phase) {
        // Each ring's progress goes 0→1 over the loop, wrapped & offset.
        final t = (_loopController.value + phase) % 1.0;
        // Ease-out so the ring expands fast then slows.
        final eased = 1.0 - math.pow(1.0 - t, 2).toDouble();
        // Ring expands from _ringMinSize to _ringMaxSize.
        final size = _ringMinSize + eased * (_ringMaxSize - _ringMinSize);
        final opacity = (1.0 - t) * 0.45; // fade out as it expands

        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: _brandRed.withOpacity(opacity),
              width: 1.5,
            ),
          ),
        );
      }).toList(),
    );
  }

  // Halo + icon — uses Container with the icon as its child via Center,
  // instead of a Stack with halo + icon as siblings. This guarantees
  // the icon is perfectly centered within the halo (Stack centering can
  // have subtle offsets due to font glyph metrics).
  Widget _buildHaloWithIcon() {
    // Intro: scale from 0.0 → 1.0 with overshoot (elastic feel).
    final introT = _introController.value;
    const curve = Curves.easeOutBack;
    final scale = curve.transform(introT);
    final introOpacity = introT.clamp(0.0, 1.0);

    // Loop: subtle breathing pulse on top of the intro scale.
    final pulse = 1.0 + 0.05 * math.sin(_loopController.value * 2 * math.pi);

    // Halo opacity also pulses with the loop, slightly offset from the
    // logo's scale pulse so they feel layered rather than synced.
    final haloOpacity = 0.35 + 0.20 * math.sin(
        _loopController.value * 2 * math.pi + math.pi / 3);

    return Opacity(
      opacity: introOpacity,
      child: Transform.scale(
        scale: scale * pulse,
        child: Container(
          width: _haloSize,
          height: _haloSize,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _brandRed.withOpacity(haloOpacity * 0.4),
            boxShadow: [
              BoxShadow(
                color: _brandRed.withOpacity(haloOpacity),
                blurRadius: 40,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Center(
            child: Icon(
              Icons.play_circle_fill,
              size: _iconSize,
              color: _brandRedBright,
            ),
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────
  // 5. Brand text — "KMM" with shimmer sweep.
  // ─────────────────────────────────────────────────────────────────────
  Widget _buildBrandText() {
    // Reveal text starting at 50% of the intro, full opacity by end of intro.
    final textIntro = (_introController.value - 0.5).clamp(0.0, 1.0);
    final textOpacity = textIntro * 2.0; // full opacity by end of intro
    // Slide up from +24px to 0px during reveal.
    final slideY = 24.0 * (1.0 - textIntro);

    // Shimmer sweep: the sweep moves from -1 → 2 (in fractions of text width)
    // over each loop cycle.
    final sweep = (_loopController.value * 3.0) - 1.0; // -1 → 2

    return Opacity(
      opacity: textOpacity,
      child: Transform.translate(
        offset: Offset(0, slideY),
        child: ShaderMask(
          shaderCallback: (Rect bounds) {
            // Sweep gradient: dark → bright white → brand red → dark.
            // The horizontal position of the bright band moves with
            // `sweep`, producing a left-to-right shimmer sweep.
            return LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.topRight,
              colors: const [
                Color(0xFFFFFFFF),
                Color(0xFFFFE8B0),
                Color(0xFFFFC1C1),
                Color(0xFFFFFFFF),
              ],
              stops: [
                (sweep - 0.3).clamp(0.0, 1.0),
                sweep.clamp(0.0, 1.0),
                (sweep + 0.15).clamp(0.0, 1.0),
                (sweep + 0.45).clamp(0.0, 1.0),
              ],
            ).createShader(bounds);
          },
          blendMode: BlendMode.srcATop,
          child: const Text(
            'KMM',
            style: TextStyle(
              fontSize: 36,
              fontWeight: FontWeight.w900,
              letterSpacing: 6.0,
              color: Color(0xFFFFFFFF), // ShaderMask will overlay this
              decoration: TextDecoration.none,
            ),
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────
  // 6. Loading dots — three sequential pulsing dots at the bottom.
  // ─────────────────────────────────────────────────────────────────────
  Widget _buildLoadingDots() {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 80,
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: List.generate(3, (i) {
            // Each dot's pulse is offset by 0.2 in phase.
            final phase = i * 0.2;
            final t = (_loopController.value + phase) % 1.0;
            // Smooth pulse using a sine wave (0 → 1 → 0 over the cycle).
            final pulse = (math.sin(t * 2 * math.pi) + 1.0) / 2.0;
            final scale = 0.6 + 0.4 * pulse;
            final opacity = 0.4 + 0.6 * pulse;

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5),
              child: Transform.scale(
                scale: scale,
                child: Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: _brandRed.withOpacity(opacity),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}
