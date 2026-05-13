import 'package:flutter/material.dart';

/// 시간대별 배경 그라데이션 - 실제 하늘 색감을 참고
class TimeGradient {
  static LinearGradient getTimeBasedGradient() {
    final hour = DateTime.now().hour;

    if (hour >= 0 && hour < 4) {
      // Late night (0 - 4)
      return const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color(0xFF0f172a), // slate-900
          Color(0xFF020617), // slate-950
          Color(0xFF000000), // black
        ],
      );
    } else if (hour >= 4 && hour < 5) {
      // 새벽 여명 (4-5시: 어둑한 보랏빛)
      return const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color(0xFF0f172a), // slate-900
          Color(0xFF312e81), // indigo-900
          Color(0xFF581c87), // purple-900
        ],
      );
    } else if (hour >= 5 && hour < 6) {
      // 해출 준비 (5-6시: 파란 새벽)
      return const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color(0xFF312e81), // indigo-900
          Color(0xFF581c87), // purple-900
          Color(0xFF1e293b), // slate-800
        ],
      );
    } else if (hour >= 6 && hour < 7) {
      // 일출 (6-7시: 붉은 태양)
      return const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color(0xFF6b21a8), // purple-800
          Color(0xFFe11d48), // rose-600
          Color(0xFFea580c), // orange-600
        ],
      );
    } else if (hour >= 7 && hour < 9) {
      // 이른 아침 (7-9시: 부드러운 주황빛)
      return const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color(0xFFfb923c), // orange-400
          Color(0xFFfbbf24), // amber-400
          Color(0xFF38bdf8), // sky-400
        ],
      );
    } else if (hour >= 9 && hour < 11) {
      // 오전 (9-11시: 맑은 하늘)
      return const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color(0xFF7dd3fc), // sky-300
          Color(0xFF60a5fa), // blue-400
          Color(0xFF22d3ee), // cyan-400
        ],
      );
    } else if (hour >= 11 && hour < 14) {
      // Midday (11 - 14)
      return const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color(0xFFe0f2fe), // sky-200
          Color(0xFF93c5fd), // blue-300
          Color(0xFF38bdf8), // sky-400
        ],
      );
    } else if (hour >= 14 && hour < 17) {
      // 오후 (14-17시: 따뜻한 하늘)
      return const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color(0xFF60a5fa), // blue-400
          Color(0xFF38bdf8), // sky-400
          Color(0xFF67e8f9), // cyan-300
        ],
      );
    } else if (hour >= 17 && hour < 18) {
      // 늦은 오후 (17-18시: 해질녘 직전)
      return const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color(0xFF38bdf8), // sky-400
          Color(0xFF60a5fa), // blue-400
          Color(0xFFfdba74), // orange-300
        ],
      );
    } else if (hour >= 18 && hour < 19) {
      // 초저녁 (18-19시: 차분한 노을)
      return const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color(0xFF3b82f6), // blue-500
          Color(0xFF6366f1), // indigo-500
          Color(0xFFfb923c), // orange-400
        ],
      );
    } else if (hour >= 19 && hour < 20) {
      // Early night (19 - 20)
      return const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color(0xFF1e40af), // blue-800
          Color(0xFF1e293b), // slate-800
          Color(0xFF0f172a), // slate-900
        ],
      );
    } else if (hour >= 20 && hour < 22) {
      // Night (20 - 22)
      return const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color(0xFF1e293b), // slate-800
          Color(0xFF0f172a), // slate-900
          Color(0xFF020617), // slate-950
        ],
      );
    } else {
      // Late night deep (22 - 24)
      return const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color(0xFF0f172a), // slate-900
          Color(0xFF020617), // slate-950
          Color(0xFF000000), // black
        ],
      );
    }
  }

  /// 시간대에 따라 태양을 노출할지 여부
  static bool get showSun {
    final hour = DateTime.now().hour;
    return hour >= 6 && hour < 19;
  }

  static bool get showMoon {
    final hour = DateTime.now().hour;
    return hour >= 20 || hour < 6;
  }

  static bool get showStars {
    final hour = DateTime.now().hour;
    return hour >= 19 || hour < 6;
  }
}



