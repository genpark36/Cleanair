import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/material_symbols_icons.dart';

class SensorPinScreen extends StatelessWidget {
  const SensorPinScreen({
    super.key,
    this.onBack,
    this.onNext,
    this.onRetryAutoDetect,
  });

  final VoidCallback? onBack;
  final VoidCallback? onNext;
  final VoidCallback? onRetryAutoDetect;

  @override
  Widget build(BuildContext context) {
    const background = Color(0xFFF5FAFD);
    const onSurface = Color(0xFF171C1F);
    const onSurfaceVariant = Color(0xFF3D494D);
    const primary = Color(0xFF00677D);
    const primaryContainer = Color(0xFF00B4D8);
    const primaryFixedDim = Color(0xFF4CD6FB);
    const secondary = Color(0xFF396472);
    const surfaceContainerHigh = Color(0xFFE3E9EC);
    const surfaceContainerLow = Color(0xFFEFF4F7);
    const surfaceContainerHighest = Color(0xFFDEE3E6);

    return Container(
      color: background,
      child: Stack(
        children: [
          Positioned(
            top: -120,
            right: -120,
            child: Container(
              width: 320,
              height: 320,
              decoration: BoxDecoration(
                color: primaryFixedDim.withValues(alpha: 0.3),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: primaryFixedDim.withValues(alpha: 0.3),
                    blurRadius: 120,
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
              width: 320,
              height: 320,
              decoration: BoxDecoration(
                color: const Color(0xFFBDEAFB).withValues(alpha: 0.4),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFBDEAFB).withValues(alpha: 0.4),
                    blurRadius: 120,
                    spreadRadius: 20,
                  ),
                ],
              ),
            ),
          ),
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(32, 96, 32, 120),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 64,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFB3EBFF),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        width: 64,
                        height: 4,
                        decoration: BoxDecoration(
                          color: primary,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    '6자리 PIN 번호 입력',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.5,
                      height: 1.2,
                      color: onSurface,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '센서 디스플레이 상단에 표시된 6자리 숫자를 입력해 주세요. (2분간 표시)',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                      height: 1.6,
                      color: secondary,
                    ),
                  ),
                  const SizedBox(height: 32),
                  Row(
                    children: List.generate(6, (index) {
                      return Expanded(
                        child: Container(
                          margin: EdgeInsets.only(right: index == 5 ? 0 : 10),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          decoration: const BoxDecoration(
                            border: Border(
                              bottom: BorderSide(
                                color: surfaceContainerHighest,
                                width: 2,
                              ),
                            ),
                          ),
                          alignment: Alignment.center,
                          child: const Text(
                            '·',
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w700,
                              color: primary,
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 32),
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: surfaceContainerLow,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Stack(
                      children: [
                        Positioned(
                          right: -12,
                          bottom: -12,
                          child: Container(
                            width: 96,
                            height: 96,
                            decoration: BoxDecoration(
                              color: primaryFixedDim.withValues(alpha: 0.3),
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Help Center',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 2.0,
                                      color: secondary,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  const Text(
                                    '센서가 안 잡히나요?',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: onSurfaceVariant,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTap: onRetryAutoDetect,
                                    child: const Row(
                                      children: [
                                        Text(
                                          '자동 감지 다시 시도',
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w700,
                                            color: primary,
                                          ),
                                        ),
                                        SizedBox(width: 6),
                                        Icon(
                                          Symbols.refresh,
                                          size: 16,
                                          color: primary,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              width: 64,
                              height: 64,
                              decoration: BoxDecoration(
                                color: surfaceContainerHigh,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.5),
                                ),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Color(0x14000000),
                                    blurRadius: 8,
                                    offset: Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Symbols.sensors,
                                size: 28,
                                color: primaryContainer,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: surfaceContainerLow,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Row(
                      children: [
                        Icon(Symbols.info, size: 18, color: secondary),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '등록을 완료하면 앱에서 실시간 데이터를 확인할 수 있습니다.',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: secondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Container(
                  height: 64,
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  color: Colors.white.withValues(alpha: 0.94),
                  child: Row(
                    children: [
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: onBack,
                        child: const Icon(
                          Symbols.arrow_back,
                          size: 22,
                          color: secondary,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        'STEP 06 / 06',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.3,
                          color: primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: ClipRRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
                  color: background.withValues(alpha: 0.8),
                  child: Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: onBack,
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Symbols.arrow_back,
                                size: 18,
                                color: secondary,
                              ),
                              SizedBox(width: 8),
                              Text(
                                '이전',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: secondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: onNext,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [primary, primaryContainer],
                              ),
                              borderRadius: BorderRadius.circular(999),
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x3300B4D8),
                                  blurRadius: 16,
                                  offset: Offset(0, 6),
                                ),
                              ],
                            ),
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  '다음',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 1.4,
                                    color: Colors.white,
                                  ),
                                ),
                                SizedBox(width: 6),
                                Icon(
                                  Symbols.arrow_forward,
                                  size: 18,
                                  color: Colors.white,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
