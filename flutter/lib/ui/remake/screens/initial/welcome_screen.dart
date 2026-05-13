import 'package:flutter/material.dart';

import '../shared/cleanair_stitch_widgets.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key, this.onStart});

  final VoidCallback? onStart;

  @override
  Widget build(BuildContext context) {
    const background = Color(0xFFF8FAFB);
    const onBackground = Color(0xFF191C1D);
    const primary = Color(0xFF00677D);
    const onSurfaceVariant = Color(0xFF3D494D);

    return Container(
      color: background,
      child: Stack(
        children: [
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: RadialGradient(
                  colors: [Color(0x1A00B4D8), Color(0x00F8FAFB)],
                  stops: [0.0, 0.7],
                ),
              ),
            ),
          ),
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Column(
                    children: [
                      Container(
                        width: 128,
                        height: 128,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(36),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x2600B4D8),
                              blurRadius: 24,
                              offset: Offset(0, 10),
                            ),
                          ],
                        ),
                        child: const CleanAirParticleLogo(size: 86),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'CleanAir',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.4,
                          color: primary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 48),
                  const Column(
                    children: [
                      Text(
                        '깨끗한 공기,\n스마트한 관리',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.6,
                          height: 1.2,
                          color: onBackground,
                        ),
                      ),
                      SizedBox(height: 12),
                      Text(
                        'CleanAir와 함께하세요',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w500,
                          color: onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 80),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: onStart,
                    child: SizedBox(
                      width: double.infinity,
                      height: 60,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF008BA3), Color(0xFF00B4D8)],
                          ),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x3300677D),
                              blurRadius: 16,
                              offset: Offset(0, 6),
                            ),
                          ],
                        ),
                        child: const Center(
                          child: Text(
                            '시작하기',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
