import 'dart:math' as math;

import 'package:flutter/material.dart';

class DesignFrame extends StatelessWidget {
  const DesignFrame({super.key, required this.child});

  static const Size designSize = Size(390, 884);

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final insets = MediaQuery.viewInsetsOf(context);
        final heightForScale = constraints.maxHeight + insets.bottom;
        final scale = math.min(
          constraints.maxWidth / designSize.width,
          heightForScale / designSize.height,
        );
        final scaledWidth = designSize.width * scale;
        final scaledHeight = designSize.height * scale;

        return Center(
          child: SizedBox(
            width: scaledWidth,
            height: scaledHeight,
            child: FittedBox(
              fit: BoxFit.contain,
              alignment: Alignment.topCenter,
              child: SizedBox(
                width: designSize.width,
                height: designSize.height,
                child: MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.noScaling),
                  child: child,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
