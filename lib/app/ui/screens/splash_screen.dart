// Phase 4.34: Premium animated splash screen.
//
// Design goals (per Bro's brief):
//   - "မထစ်အောင်" → no stutter on low-end devices (Oppo A16 class)
//   - "အလန်းစားဖြစ်ဖြစ်" → cinematic premium look (Disney+ / Netflix tier)
//   - 3 second total duration (matches _minSplashElapsed in main.dart)
//
// Why custom Flutter animation instead of Lottie:
//   - Lottie JSON parsing on first frame can cause an initial stutter on
//     cold start, especially on low-end devices. For a SPLASH screen where
//     every ms of perceived latency matters, this is the wrong tradeoff.
//   - Custom vector animation runs natively on the GPU via Flutter's
//     rendering pipeline → instant first frame, smooth 60fps.
//   - No asset to ship / decode → smaller APK, faster cold start.
//   - The visual quality matches what a hand-crafted Lottie would give
//     us, and the code is easier to tweak later.
//
// Animation layers:
//   1. Spotlight gradient background (subtle radial red glow on deep black)
//   2. Pulsing red glow halo behind the logo (breathing effect)
//   3. Three concentric expanding rings (staggered, ripple effect)
//   4. Logo: play_circle_fill with elastic scale-in + subtle pulse loop
//   5. "KMM" brand text with horizontal shimmer sweep
//   6. Three sequential loading dots at the bottom

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
                _buildPulseRings(),
                // Logo + brand text stacked vertically at screen center.
                // Loading dots are absolutely positioned at the bottom
                // for a separate "loading" visual zone.
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildCenterLogo(),
                      const SizedBox(height: 30),
                      _buildBrandText(),
                    ],
                  ),
                ),
                _buildLoadingDots(),
              ],
            );
          },
        ),
      ),
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
  // 2. Pulse rings — three concentric expanding circles, staggered.
  // ─────────────────────────────────────────────────────────────────────
  Widget _buildPulseRings() {
    // Three rings at 0.0, 0.33, 0.66 phase offset.
    final List<double> phases = [0.0, 0.33, 0.66];

    return Center(
      child: Stack(
        alignment: Alignment.center,
        children: phases.map((phase) {
          // Each ring's progress goes 0→1 over the loop, wrapped & offset.
          final t = (_loopController.value + phase) % 1.0;
          // Ease-out so the ring expands fast then slows.
          final eased = 1.0 - math.pow(1.0 - t, 2).toDouble();
          final size = 80.0 + eased * 220.0; // 80 → 300
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
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────
  // 3. Center logo — play_circle_fill with elastic scale-in + pulse.
  // ─────────────────────────────────────────────────────────────────────
  Widget _buildCenterLogo() {
    // Intro: scale from 0.0 → 1.0 with overshoot (elastic feel).
    // We use a custom curve: easeOutBack gives a slight overshoot.
    final introT = _introController.value;
    const curve = Curves.easeOutBack;
    final scale = 0.0 + (1.0 - 0.0) * curve.transform(introT);
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
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Soft halo behind the icon
            Container(
              width: 110,
              height: 110,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _brandRed.withOpacity(haloOpacity * 0.4),
                boxShadow: [
                  BoxShadow(
                    color: _brandRed.withOpacity(haloOpacity),
                    blurRadius: 45,
                    spreadRadius: 2,
                  ),
                ],
              ),
            ),
            // The icon itself
            const Icon(
              Icons.play_circle_fill,
              size: 80,
              color: _brandRedBright,
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────
  // 4. Brand text — "KMM" with shimmer sweep.
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
              fontSize: 38,
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
  // 5. Loading dots — three sequential pulsing dots at the bottom.
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
