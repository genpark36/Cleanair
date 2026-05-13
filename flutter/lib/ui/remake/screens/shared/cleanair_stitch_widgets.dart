import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/material_symbols_icons.dart';

class CleanColors {
  static const surface = Color(0xFFF5FAFD);
  static const surfaceLow = Color(0xFFEFF4F7);
  static const surfaceHigh = Color(0xFFE3E9EC);
  static const surfaceHighest = Color(0xFFDEE3E6);
  static const surfaceLowest = Color(0xFFFFFFFF);
  static const onSurface = Color(0xFF171C1F);
  static const onVariant = Color(0xFF3D494D);
  static const secondary = Color(0xFF396472);
  static const outline = Color(0xFF6D797E);
  static const outlineVariant = Color(0xFFBCC9CE);
  static const primary = Color(0xFF00677D);
  static const primaryContainer = Color(0xFF00B4D8);
  static const primaryFixed = Color(0xFFB3EBFF);
  static const error = Color(0xFFBA1A1A);
  static const errorContainer = Color(0xFFFFDAD6);
  static const tertiary = Color(0xFF914D00);
  static const tertiaryContainer = Color(0xFFFFDCC3);
}

class CleanAirParticleLogo extends StatelessWidget {
  const CleanAirParticleLogo({
    super.key,
    this.size = 32,
    this.backgroundColor,
    this.padding = 0,
  });

  final double size;
  final Color? backgroundColor;
  final double padding;

  @override
  Widget build(BuildContext context) {
    final logo = CustomPaint(
      painter: const _CleanAirParticleLogoPainter(),
      child: SizedBox(width: size, height: size),
    );
    if (backgroundColor == null && padding == 0) return logo;
    return Container(
      width: size + padding * 2,
      height: size + padding * 2,
      padding: EdgeInsets.all(padding),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular((size + padding * 2) / 3),
      ),
      child: logo,
    );
  }
}

class _CleanAirParticleLogoPainter extends CustomPainter {
  const _CleanAirParticleLogoPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    const colors = [
      Color(0x4D0EA5E9),
      Color(0x800EA5E9),
      Color(0xB306B6D4),
      Color(0xE606B6D4),
      Color(0xFF06B6D4),
    ];
    final centers = [
      Offset(size.width * 0.16, size.height * 0.50),
      Offset(size.width * 0.34, size.height * 0.46),
      Offset(size.width * 0.53, size.height * 0.50),
      Offset(size.width * 0.72, size.height * 0.46),
      Offset(size.width * 0.89, size.height * 0.50),
    ];
    final radii = [
      size.width * 0.095,
      size.width * 0.120,
      size.width * 0.145,
      size.width * 0.130,
      size.width * 0.090,
    ];
    for (var i = 0; i < centers.length; i++) {
      paint.color = colors[i];
      canvas.drawCircle(centers[i], radii[i], paint);
    }

    paint.color = const Color(0x6606B6D4);
    for (final dot in [
      (Offset(size.width * 0.25, size.height * 0.33), size.width * 0.045),
      (Offset(size.width * 0.43, size.height * 0.30), size.width * 0.052),
      (Offset(size.width * 0.62, size.height * 0.34), size.width * 0.045),
      (Offset(size.width * 0.80, size.height * 0.32), size.width * 0.040),
      (Offset(size.width * 0.25, size.height * 0.68), size.width * 0.052),
      (Offset(size.width * 0.43, size.height * 0.72), size.width * 0.060),
      (Offset(size.width * 0.62, size.height * 0.69), size.width * 0.052),
      (Offset(size.width * 0.80, size.height * 0.66), size.width * 0.046),
    ]) {
      canvas.drawCircle(dot.$1, dot.$2, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _CleanAirParticleLogoPainter oldDelegate) {
    return false;
  }
}

class MockScreenShell extends StatelessWidget {
  const MockScreenShell({
    super.key,
    required this.title,
    required this.children,
    this.leading = Symbols.location_on,
    this.trailing = Symbols.notifications_active,
    this.background = CleanColors.surface,
    this.bottomNav = true,
    this.activeNav = 0,
    this.titleColor = CleanColors.primary,
    this.horizontalPadding = 24,
    this.onLeadingTap,
    this.onTrailingTap,
  });

  final String title;
  final List<Widget> children;
  final IconData leading;
  final IconData trailing;
  final Color background;
  final bool bottomNav;
  final int activeNav;
  final Color titleColor;
  final double horizontalPadding;
  final VoidCallback? onLeadingTap;
  final VoidCallback? onTrailingTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: background,
      child: Stack(
        children: [
          Positioned.fill(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                88,
                horizontalPadding,
                bottomNav ? 122 : 32,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: children,
              ),
            ),
          ),
          _TopBar(
            title: title,
            leading: leading,
            trailing: trailing,
            background: background,
            titleColor: titleColor,
            onLeadingTap: onLeadingTap,
            onTrailingTap: onTrailingTap,
          ),
          if (bottomNav) CleanBottomNav(activeIndex: activeNav),
        ],
      ),
    );
  }
}

class MockHeader extends StatelessWidget {
  const MockHeader({
    super.key,
    required this.heading,
    this.subtitle,
    this.eyebrow,
    this.center = false,
  });

  final String heading;
  final String? subtitle;
  final String? eyebrow;
  final bool center;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment:
          center ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: [
        if (eyebrow != null) ...[
          Text(
            eyebrow!,
            textAlign: center ? TextAlign.center : TextAlign.start,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 2.2,
              color: CleanColors.secondary,
            ),
          ),
          const SizedBox(height: 8),
        ],
        Text(
          heading,
          textAlign: center ? TextAlign.center : TextAlign.start,
          style: const TextStyle(
            fontSize: 32,
            height: 1.12,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
            color: CleanColors.onSurface,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 12),
          Text(
            subtitle!,
            textAlign: center ? TextAlign.center : TextAlign.start,
            style: const TextStyle(
              fontSize: 15,
              height: 1.55,
              fontWeight: FontWeight.w500,
              color: CleanColors.secondary,
            ),
          ),
        ],
      ],
    );
  }
}

class MockCard extends StatelessWidget {
  const MockCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.color = CleanColors.surfaceLowest,
    this.radius = 18,
    this.borderColor,
  });

  final Widget child;
  final EdgeInsets padding;
  final Color color;
  final double radius;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(radius),
        border: borderColor == null ? null : Border.all(color: borderColor!),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A171C1F),
            blurRadius: 24,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }
}

class IconBubble extends StatelessWidget {
  const IconBubble({
    super.key,
    required this.icon,
    this.size = 48,
    this.iconSize = 24,
    this.color = CleanColors.primaryFixed,
    this.iconColor = CleanColors.primary,
  });

  final IconData icon;
  final double size;
  final double iconSize;
  final Color color;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(size / 3),
      ),
      child: Icon(icon, size: iconSize, color: iconColor, fill: 1),
    );
  }
}

class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    this.unit,
    this.icon,
    this.color = CleanColors.primary,
    this.compact = false,
  });

  final String label;
  final String value;
  final String? unit;
  final IconData? icon;
  final Color color;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return MockCard(
      padding: EdgeInsets.all(compact ? 12 : 16),
      color: CleanColors.surfaceLowest,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 17, color: color, fill: 1),
                const SizedBox(width: 6),
              ],
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                    color: CleanColors.secondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text.rich(
            TextSpan(
              text: value,
              style: TextStyle(
                fontSize: compact ? 22 : 28,
                fontWeight: FontWeight.w900,
                height: 1,
                color: CleanColors.onSurface,
              ),
              children: [
                if (unit != null)
                  TextSpan(
                    text: ' $unit',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: CleanColors.outline,
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

class InfoRow extends StatelessWidget {
  const InfoRow({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.color = CleanColors.primary,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconBubble(
          icon: icon,
          size: 42,
          iconSize: 21,
          color: color.withValues(alpha: 0.14),
          iconColor: color,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: CleanColors.onSurface,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(
                  subtitle!,
                  style: const TextStyle(
                    fontSize: 12,
                    height: 1.35,
                    color: CleanColors.secondary,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

class Pill extends StatelessWidget {
  const Pill({
    super.key,
    required this.text,
    this.color = CleanColors.surfaceHigh,
    this.textColor = CleanColors.secondary,
    this.icon,
  });

  final String text;
  final Color color;
  final Color textColor;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 15, color: textColor),
            const SizedBox(width: 5),
          ],
          Text(
            text,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4,
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }
}

class GradientButton extends StatelessWidget {
  const GradientButton({
    super.key,
    required this.label,
    this.icon = Symbols.arrow_forward,
    this.fullWidth = true,
    this.colorA = CleanColors.primary,
    this.colorB = CleanColors.primaryContainer,
    this.onTap,
  });

  final String label;
  final IconData icon;
  final bool fullWidth;
  final Color colorA;
  final Color colorB;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: fullWidth ? double.infinity : null,
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [colorA, colorB]),
          borderRadius: BorderRadius.circular(999),
          boxShadow: [
            BoxShadow(
              color: colorB.withValues(alpha: 0.22),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: fullWidth ? MainAxisSize.max : MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Icon(icon, color: Colors.white, size: 18),
          ],
        ),
      ),
    );
  }
}

class MiniChart extends StatelessWidget {
  const MiniChart({
    super.key,
    this.values = const [20, 38, 28, 54, 42, 70, 58],
    this.height = 130,
    this.color = CleanColors.primaryContainer,
    this.bar = false,
  });

  final List<double> values;
  final double height;
  final Color color;
  final bool bar;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: CustomPaint(
        painter: _MiniChartPainter(values: values, color: color, bar: bar),
        child: Container(),
      ),
    );
  }
}

class MiniGauge extends StatelessWidget {
  const MiniGauge({
    super.key,
    required this.value,
    required this.label,
    this.caption,
    this.color = CleanColors.primary,
  });

  final String value;
  final String label;
  final String? caption;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 210,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: const Size(220, 170),
            painter: _GaugePainter(color: color),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                value,
                style: const TextStyle(
                  fontSize: 58,
                  height: 1,
                  fontWeight: FontWeight.w900,
                  color: CleanColors.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Pill(
                text: label,
                color: CleanColors.tertiaryContainer.withValues(alpha: 0.5),
                textColor: CleanColors.tertiary,
              ),
              if (caption != null) ...[
                const SizedBox(height: 8),
                Text(
                  caption!,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: CleanColors.secondary,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class HeatMapGrid extends StatelessWidget {
  const HeatMapGrid({super.key});

  @override
  Widget build(BuildContext context) {
    const values = [
      22,
      34,
      58,
      112,
      64,
      42,
      38,
      71,
      156,
      205,
      58,
      0,
      32,
      75,
      120,
      48,
      22,
      88,
      142,
      66,
      41,
    ];
    return Wrap(
      spacing: 7,
      runSpacing: 7,
      children: [
        for (final value in values)
          Container(
            width: 39,
            height: 39,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _heatColor(value),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Text(
              value == 0 ? '--' : '$value',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: value > 130 ? Colors.white : CleanColors.onVariant,
              ),
            ),
          ),
      ],
    );
  }

  Color _heatColor(int value) {
    if (value == 0) return CleanColors.surfaceHigh;
    if (value < 50) return const Color(0xFFDFF7EA);
    if (value < 90) return const Color(0xFFFFF2C8);
    if (value < 150) return const Color(0xFFFFD8B3);
    return const Color(0xFFE05F4F);
  }
}

class FakeMap extends StatelessWidget {
  const FakeMap({super.key, this.height = 280, this.label = '서울시 강남구'});

  final double height;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFDDF5F8), Color(0xFFF3EFE3), Color(0xFFE8F3EC)],
        ),
      ),
      child: Stack(
        children: [
          for (var i = 0; i < 9; i++)
            Positioned(
              left: (i * 47) % 330,
              top: 26.0 + (i * 31) % math.max(1, height - 70),
              child: Transform.rotate(
                angle: (i.isEven ? -0.4 : 0.35),
                child: Container(
                  width: 140,
                  height: 7,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
            ),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(999),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x1A000000),
                        blurRadius: 12,
                        offset: Offset(0, 5),
                      ),
                    ],
                  ),
                  child: Text(
                    label,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: CleanColors.primary,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                const Icon(
                  Symbols.location_on,
                  size: 54,
                  color: CleanColors.primary,
                  fill: 1,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class CleanBottomNav extends StatelessWidget {
  const CleanBottomNav({super.key, required this.activeIndex});

  final int activeIndex;

  @override
  Widget build(BuildContext context) {
    final items = [
      (Symbols.dashboard, 'Home'),
      (Symbols.analytics, 'Analysis'),
      (Symbols.warning, 'Alerts'),
      (Symbols.settings_remote, 'Devices'),
      (Symbols.settings, 'Settings'),
    ];
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
            color: Colors.white.withValues(alpha: 0.88),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                for (var i = 0; i < items.length; i++)
                  _BottomNavItem(
                    icon: items[i].$1,
                    label: items[i].$2,
                    active: i == activeIndex,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.title,
    required this.leading,
    required this.trailing,
    required this.background,
    required this.titleColor,
    this.onLeadingTap,
    this.onTrailingTap,
  });

  final String title;
  final IconData leading;
  final IconData trailing;
  final Color background;
  final Color titleColor;
  final VoidCallback? onLeadingTap;
  final VoidCallback? onTrailingTap;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            height: 64,
            padding: const EdgeInsets.symmetric(horizontal: 22),
            color: background.withValues(alpha: 0.9),
            child: Row(
              children: [
                _TopBarIcon(
                  icon: leading,
                  color: CleanColors.primary,
                  onTap: onLeadingTap,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.2,
                      color: titleColor,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                _TopBarIcon(
                  icon: trailing,
                  color: CleanColors.secondary,
                  onTap: onTrailingTap,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TopBarIcon extends StatelessWidget {
  const _TopBarIcon({required this.icon, required this.color, this.onTap});

  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(7),
        child: Icon(icon, size: 23, color: color),
      ),
    );
  }
}

class _BottomNavItem extends StatelessWidget {
  const _BottomNavItem({
    required this.icon,
    required this.label,
    required this.active,
  });

  final IconData icon;
  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 64,
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: active ? CleanColors.surfaceLow : Colors.transparent,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 23,
            color: active ? CleanColors.primary : CleanColors.outline,
            fill: active ? 1 : 0,
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 9,
              fontWeight: active ? FontWeight.w800 : FontWeight.w600,
              color: active ? CleanColors.primary : CleanColors.outline,
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniChartPainter extends CustomPainter {
  const _MiniChartPainter({
    required this.values,
    required this.color,
    required this.bar,
  });

  final List<double> values;
  final Color color;
  final bool bar;

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = CleanColors.surfaceHigh
      ..strokeWidth = 1;
    for (var i = 1; i < 4; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }

    if (values.isEmpty) return;
    final maxValue = values.reduce(math.max);
    final minValue = values.reduce(math.min);
    final range = math.max(1, maxValue - minValue);
    final step = size.width / math.max(1, values.length - 1);

    if (bar) {
      final barWidth = size.width / (values.length * 1.8);
      final paint = Paint()..color = color.withValues(alpha: 0.75);
      for (var i = 0; i < values.length; i++) {
        final normalized = (values[i] - minValue) / range;
        final height = 18 + normalized * (size.height - 24);
        final x = i * step - barWidth / 2;
        final rect = RRect.fromRectAndRadius(
          Rect.fromLTWH(x, size.height - height, barWidth, height),
          const Radius.circular(8),
        );
        canvas.drawRRect(rect, paint);
      }
      return;
    }

    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final normalized = (values[i] - minValue) / range;
      final point = Offset(i * step, size.height - normalized * size.height);
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    final fillPath = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(fillPath, Paint()..color = color.withValues(alpha: 0.12));
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..strokeWidth = 4
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _MiniChartPainter oldDelegate) {
    return values != oldDelegate.values ||
        color != oldDelegate.color ||
        bar != oldDelegate.bar;
  }
}

class _GaugePainter extends CustomPainter {
  const _GaugePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(8, 16, size.width - 16, size.height * 1.5);
    final bg = Paint()
      ..color = CleanColors.surfaceHigh
      ..style = PaintingStyle.stroke
      ..strokeWidth = 18
      ..strokeCap = StrokeCap.round;
    final fg = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFF3DDC97), Color(0xFFFFD166), Color(0xFFEF476F)],
      ).createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 18
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, math.pi, math.pi, false, bg);
    canvas.drawArc(rect, math.pi, math.pi * 0.58, false, fg);
  }

  @override
  bool shouldRepaint(covariant _GaugePainter oldDelegate) {
    return color != oldDelegate.color;
  }
}
