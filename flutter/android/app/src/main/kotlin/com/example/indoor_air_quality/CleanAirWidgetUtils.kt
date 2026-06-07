package com.example.indoor_air_quality

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.graphics.Color
import android.os.Build

object CleanAirWidgetUtils {
    fun openAppIntent(context: Context): PendingIntent {
        val intent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                PendingIntent.FLAG_IMMUTABLE
            } else {
                0
            }
        return PendingIntent.getActivity(context, 0, intent, flags)
    }

    fun text(prefs: SharedPreferences, key: String, fallback: String = "--"): String {
        return prefs.getString(key, fallback)?.takeIf { it.isNotBlank() } ?: fallback
    }

    fun iaqiColor(label: String): Int {
        return when (label) {
            "좋음" -> Color.rgb(30, 196, 137)
            "보통" -> Color.rgb(245, 203, 54)
            "조금 나쁨" -> Color.rgb(255, 142, 18)
            "나쁨" -> Color.rgb(255, 65, 91)
            "상당히 나쁨" -> Color.rgb(190, 25, 31)
            "매우 나쁨" -> Color.rgb(143, 54, 226)
            else -> Color.rgb(0, 103, 125)
        }
    }

    fun metricColor(state: String): Int {
        return when (state) {
            "좋음" -> Color.rgb(30, 196, 137)
            "보통" -> Color.rgb(245, 203, 54)
            "조금 나쁨", "나쁨" -> Color.rgb(255, 142, 18)
            "상당히 나쁨", "매우 나쁨" -> Color.rgb(190, 25, 31)
            else -> Color.rgb(0, 103, 125)
        }
    }

    fun riskColor(label: String): Int {
        return when (label) {
            "화재 의심", "CO 위험" -> Color.rgb(190, 25, 31)
            "강한 경고" -> Color.rgb(255, 142, 18)
            "경고" -> Color.rgb(245, 128, 35)
            "주의" -> Color.rgb(245, 203, 54)
            else -> Color.rgb(0, 103, 125)
        }
    }

    fun nextTrendIntent(context: Context): PendingIntent {
        val intent = Intent(context, CleanAirTrendWidget::class.java).apply {
            action = CleanAirTrendWidget.ACTION_NEXT_PAGE
        }
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                PendingIntent.FLAG_IMMUTABLE
            } else {
                0
            }
        return PendingIntent.getBroadcast(context, 201, intent, flags)
    }

    fun refreshStatusIntent(context: Context): PendingIntent {
        val intent = Intent(context, CleanAirStatusWidget::class.java).apply {
            action = CleanAirStatusWidget.ACTION_REFRESH
        }
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                PendingIntent.FLAG_IMMUTABLE
            } else {
                0
            }
        return PendingIntent.getBroadcast(context, 202, intent, flags)
    }

    fun refreshTrendIntent(context: Context): PendingIntent {
        val intent = Intent(context, CleanAirTrendWidget::class.java).apply {
            action = CleanAirTrendWidget.ACTION_REFRESH
        }
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                PendingIntent.FLAG_IMMUTABLE
            } else {
                0
            }
        return PendingIntent.getBroadcast(context, 203, intent, flags)
    }
}
