import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/material_symbols_icons.dart';

class SetupColors {
  static const surface = Color(0xFFF5FAFD);
  static const onSurface = Color(0xFF171C1F);
  static const primary = Color(0xFF00677D);
  static const primaryContainer = Color(0xFF00B4D8);
  static const primaryFixed = Color(0xFFB3EBFF);
  static const secondary = Color(0xFF396472);
  static const muted = Color(0xFF6D858D);
  static const low = Color(0xFFEFF4F7);
  static const high = Color(0xFFE3E9EC);
  static const white = Color(0xFFFFFFFF);
  static const error = Color(0xFFBA1A1A);
}

class SetupFlowScaffold extends StatelessWidget {
  const SetupFlowScaffold({
    super.key,
    required this.step,
    required this.totalSteps,
    required this.title,
    required this.subtitle,
    required this.children,
    required this.primaryLabel,
    required this.onPrimary,
    this.onBack,
    this.primaryIcon = Symbols.arrow_forward,
    this.bottomExtra,
    this.headerTitle = 'CleanAir Setup',
  });

  final int step;
  final int totalSteps;
  final String title;
  final String subtitle;
  final List<Widget> children;
  final String primaryLabel;
  final IconData primaryIcon;
  final VoidCallback? onPrimary;
  final VoidCallback? onBack;
  final Widget? bottomExtra;
  final String headerTitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: SetupColors.surface,
      child: Stack(
        children: [
          Positioned.fill(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(32, 92, 32, 158),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SetupStepIndicator(step: step, totalSteps: totalSteps),
                  const SizedBox(height: 36),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                      height: 1.18,
                      color: SetupColors.onSurface,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    subtitle,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      height: 1.55,
                      color: SetupColors.secondary,
                    ),
                  ),
                  const SizedBox(height: 34),
                  ...children,
                ],
              ),
            ),
          ),
          const _SetupGlow(),
          _SetupHeader(title: headerTitle, onBack: onBack),
          _SetupBottomBar(
            primaryLabel: primaryLabel,
            primaryIcon: primaryIcon,
            onPrimary: onPrimary,
            onBack: onBack,
            bottomExtra: bottomExtra,
          ),
        ],
      ),
    );
  }
}

class SetupStepIndicator extends StatelessWidget {
  const SetupStepIndicator({
    super.key,
    required this.step,
    required this.totalSteps,
  });

  final int step;
  final int totalSteps;

  @override
  Widget build(BuildContext context) {
    final normalizedStep = step.clamp(1, totalSteps);
    return Column(
      children: [
        Text(
          'STEP ${normalizedStep.toString().padLeft(2, '0')} / ${totalSteps.toString().padLeft(2, '0')}',
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 2.1,
            color: SetupColors.primary,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: List.generate(totalSteps, (index) {
            final active = index < normalizedStep;
            return Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                height: 5,
                margin: EdgeInsets.only(right: index == totalSteps - 1 ? 0 : 7),
                decoration: BoxDecoration(
                  gradient: active
                      ? const LinearGradient(
                          colors: [
                            SetupColors.primary,
                            SetupColors.primaryContainer,
                          ],
                        )
                      : null,
                  color: active ? null : SetupColors.high,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            );
          }),
        ),
      ],
    );
  }
}

class SetupIconPlate extends StatelessWidget {
  const SetupIconPlate({
    super.key,
    required this.icon,
    this.size = 148,
  });

  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: SetupColors.primaryFixed.withValues(alpha: 0.32),
                shape: BoxShape.circle,
              ),
            ),
            Container(
              width: size * 0.76,
              height: size * 0.76,
              decoration: BoxDecoration(
                color: SetupColors.white,
                borderRadius: BorderRadius.circular(34),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x1600B4D8),
                    blurRadius: 24,
                    offset: Offset(0, 10),
                  ),
                ],
              ),
              child: Icon(
                icon,
                size: size * 0.42,
                color: SetupColors.primary,
                fill: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SetupInfoCard extends StatelessWidget {
  const SetupInfoCard({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    this.tint = SetupColors.primary,
  });

  final IconData icon;
  final String title;
  final String body;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: SetupColors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F171C1F),
            blurRadius: 22,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: tint.withValues(alpha: 0.13),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: tint, size: 23),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: SetupColors.onSurface,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  body,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    height: 1.45,
                    color: SetupColors.secondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class SetupOptionTile extends StatelessWidget {
  const SetupOptionTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.selected = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: SetupColors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0D171C1F),
              blurRadius: 20,
              offset: Offset(0, 10),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: selected ? SetupColors.primaryFixed : SetupColors.low,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 25, color: SetupColors.primary),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: SetupColors.onSurface,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      height: 1.35,
                      fontWeight: FontWeight.w600,
                      color: SetupColors.secondary,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              selected ? Symbols.check_circle : Symbols.chevron_right,
              fill: selected ? 1 : 0,
              color:
                  selected ? SetupColors.primaryContainer : SetupColors.muted,
            ),
          ],
        ),
      ),
    );
  }
}

class _SetupHeader extends StatelessWidget {
  const _SetupHeader({required this.title, required this.onBack});

  final String title;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            height: 64,
            padding: const EdgeInsets.symmetric(horizontal: 24),
            color: SetupColors.surface.withValues(alpha: 0.94),
            child: Row(
              children: [
                SizedBox(
                  width: 44,
                  height: 44,
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    onPressed: onBack,
                    icon: const Icon(
                      Symbols.arrow_back_ios_new,
                      size: 21,
                      color: SetupColors.primary,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.3,
                      color: SetupColors.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 44),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SetupBottomBar extends StatelessWidget {
  const _SetupBottomBar({
    required this.primaryLabel,
    required this.primaryIcon,
    required this.onPrimary,
    required this.onBack,
    required this.bottomExtra,
  });

  final String primaryLabel;
  final IconData primaryIcon;
  final VoidCallback? onPrimary;
  final VoidCallback? onBack;
  final Widget? bottomExtra;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            padding: const EdgeInsets.fromLTRB(28, 16, 28, 34),
            decoration: BoxDecoration(
              color: SetupColors.white.withValues(alpha: 0.94),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x0D171C1F),
                  blurRadius: 28,
                  offset: Offset(0, -8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    SizedBox(
                      width: 82,
                      height: 56,
                      child: TextButton.icon(
                        onPressed: onBack,
                        icon: const Icon(Symbols.arrow_back, size: 19),
                        label: const Text('이전'),
                        style: TextButton.styleFrom(
                          foregroundColor: SetupColors.secondary,
                          textStyle: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SizedBox(
                        height: 56,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: onPrimary == null
                                ? const LinearGradient(
                                    colors: [
                                      Color(0xFFBFC5C8),
                                      Color(0xFF9DA3A6),
                                    ],
                                  )
                                : const LinearGradient(
                                    colors: [
                                      SetupColors.primary,
                                      SetupColors.primaryContainer,
                                    ],
                                  ),
                            borderRadius: BorderRadius.circular(999),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x3300B4D8),
                                blurRadius: 18,
                                offset: Offset(0, 7),
                              ),
                            ],
                          ),
                          child: TextButton.icon(
                            onPressed: onPrimary,
                            icon: Icon(primaryIcon, size: 20),
                            label: Text(primaryLabel),
                            style: TextButton.styleFrom(
                              foregroundColor: SetupColors.white,
                              textStyle: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                if (bottomExtra != null) ...[
                  const SizedBox(height: 14),
                  bottomExtra!,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SetupGlow extends StatelessWidget {
  const _SetupGlow();

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 78,
      right: -86,
      child: IgnorePointer(
        child: Container(
          width: 210,
          height: 210,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                SetupColors.primaryFixed.withValues(alpha: 0.28),
                Colors.transparent,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
