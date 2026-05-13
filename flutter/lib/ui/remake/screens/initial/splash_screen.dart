import 'package:flutter/material.dart';

import '../shared/cleanair_stitch_widgets.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, this.onTap});

  final VoidCallback? onTap;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    Future<void>.delayed(const Duration(milliseconds: 900), () {
      if (mounted) widget.onTap?.call();
    });
  }

  @override
  Widget build(BuildContext context) {
    const background = Color(0xFFF8FAFB);
    const primary = Color(0xFF00677D);
    const secondary = Color(0xFF4A626D);

    return Container(
      color: background,
      child: Stack(
        children: [
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: RadialGradient(
                  colors: [Color(0x2600B4D8), Color(0x00F8FAFB)],
                  stops: [0.0, 0.7],
                ),
              ),
            ),
          ),
          Positioned(
            top: -80,
            right: -80,
            child: Container(
              width: 320,
              height: 320,
              decoration: BoxDecoration(
                color: primary.withValues(alpha: 0.05),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: primary.withValues(alpha: 0.08),
                    blurRadius: 80,
                    spreadRadius: 20,
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            bottom: -160,
            left: -160,
            child: Container(
              width: 384,
              height: 384,
              decoration: BoxDecoration(
                color: secondary.withValues(alpha: 0.05),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: secondary.withValues(alpha: 0.08),
                    blurRadius: 100,
                    spreadRadius: 20,
                  ),
                ],
              ),
            ),
          ),
          const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CleanAirParticleLogo(size: 168),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
