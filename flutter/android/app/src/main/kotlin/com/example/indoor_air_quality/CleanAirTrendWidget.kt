package com.example.indoor_air_quality

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider
import es.antonborri.home_widget.HomeWidgetPlugin
import kotlin.math.max
import kotlin.math.min

class CleanAirTrendWidget : HomeWidgetProvider() {
    companion object {
        const val ACTION_NEXT_PAGE = "com.example.indoor_air_quality.NEXT_WIDGET_PAGE"
        const val ACTION_REFRESH = "com.example.indoor_air_quality.REFRESH_TREND_WIDGET"
        private const val PAGE_KEY = "trend_page"
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == ACTION_NEXT_PAGE || intent.action == ACTION_REFRESH) {
            val prefs = HomeWidgetPlugin.getData(context)
            if (intent.action == ACTION_NEXT_PAGE) {
                val next = ((prefs.getInt(PAGE_KEY, 0) + 1) % MetricPage.pages.size)
                prefs.edit().putInt(PAGE_KEY, next).apply()
            }
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(ComponentName(context, CleanAirTrendWidget::class.java))
            onUpdate(context, manager, ids, prefs)
            return
        }
        super.onReceive(context, intent)
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        appWidgetIds.forEach { widgetId ->
            val views = RemoteViews(context.packageName, R.layout.cleanair_trend_widget)
            val pageIndex = widgetData.getInt(PAGE_KEY, 0).coerceIn(0, MetricPage.pages.lastIndex)
            val page = MetricPage.pages[pageIndex].resolve(widgetData)
            val updatedAt = CleanAirWidgetUtils.text(widgetData, "updated_at", "업데이트 대기")
            val location = CleanAirWidgetUtils.text(widgetData, "location_label", "실내")
            val values = parseValues(CleanAirWidgetUtils.text(widgetData, page.trendKey, ""))
            val color = if (page.key == "iaqi") {
                CleanAirWidgetUtils.iaqiColor(page.state)
            } else {
                CleanAirWidgetUtils.metricColor(page.state)
            }

            views.setTextViewText(R.id.widget_trend_location, location)
            views.setTextViewText(R.id.widget_trend_title, page.title)
            views.setTextViewText(R.id.widget_trend_value, page.value)
            views.setTextViewText(R.id.widget_trend_unit, page.unit)
            views.setTextViewText(R.id.widget_trend_state, page.state)
            views.setTextColor(R.id.widget_trend_value, color)
            views.setTextColor(R.id.widget_trend_state, color)
            views.setImageViewBitmap(R.id.widget_trend_graph, drawBars(values, color))
            setPageDots(views, pageIndex, color)
            views.setTextViewText(R.id.widget_trend_updated, updatedAt)
            views.setOnClickPendingIntent(R.id.widget_trend_root, CleanAirWidgetUtils.openAppIntent(context))
            views.setOnClickPendingIntent(R.id.widget_trend_refresh, CleanAirWidgetUtils.refreshTrendIntent(context))
            views.setOnClickPendingIntent(R.id.widget_trend_graph, CleanAirWidgetUtils.nextTrendIntent(context))
            views.setOnClickPendingIntent(R.id.widget_trend_change_area, CleanAirWidgetUtils.nextTrendIntent(context))

            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }

    private fun parseValues(raw: String): List<Float> {
        if (raw.isBlank()) return emptyList()
        return raw.split(",").mapNotNull { it.toFloatOrNull() }.filter { it.isFinite() }
    }

    private fun drawBars(values: List<Float>, color: Int): Bitmap {
        val width = 720
        val height = 260
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        canvas.drawColor(Color.TRANSPARENT)

        val muted = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            this.color = Color.argb(80, 222, 227, 230)
        }
        val active = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            this.color = color
        }

        val samples = values.takeLast(7)
        if (samples.isEmpty()) {
            val emptyPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                this.color = Color.rgb(91, 115, 122)
                textSize = 32f
                textAlign = Paint.Align.CENTER
            }
            canvas.drawText("최근 기록 대기 중", width / 2f, height / 2f + 10f, emptyPaint)
            return bitmap
        }

        var minValue = samples.minOrNull() ?: 0f
        var maxValue = samples.maxOrNull() ?: 1f
        if (maxValue - minValue < 0.2f) {
            minValue -= 0.1f
            maxValue += 0.1f
        }

        val gap = 18f
        val left = 28f
        val bottom = height - 18f
        val top = 20f
        val barWidth = (width - left * 2 - gap * (samples.size - 1)) / samples.size
        samples.forEachIndexed { index, value ->
            val normalized = ((value - minValue) / (maxValue - minValue)).coerceIn(0f, 1f)
            val barHeight = max(42f, normalized * (bottom - top))
            val x = left + index * (barWidth + gap)
            val paint = if (index == samples.lastIndex) active else muted
            canvas.drawRoundRect(
                RectF(x, bottom - barHeight, x + barWidth, bottom),
                8f,
                8f,
                paint,
            )
        }
        return bitmap
    }

    private fun setPageDots(views: RemoteViews, pageIndex: Int, color: Int) {
        val ids = intArrayOf(
            R.id.widget_trend_dot_1,
            R.id.widget_trend_dot_2,
            R.id.widget_trend_dot_3,
            R.id.widget_trend_dot_4,
            R.id.widget_trend_dot_5,
            R.id.widget_trend_dot_6,
        )
        ids.forEachIndexed { index, id ->
            val selected = pageIndex == index
            views.setTextViewText(id, if (selected) "━" else "•")
            views.setTextColor(id, if (selected) color else Color.rgb(188, 201, 206))
        }
    }

    private data class MetricPage(
        val key: String,
        val title: String,
        val valueKey: String,
        val trendKey: String,
        val unit: String,
        val stateOf: (Float?) -> String,
    ) {
        fun resolve(prefs: SharedPreferences): MetricDisplay {
            val rawValue = CleanAirWidgetUtils.text(prefs, valueKey)
            return MetricDisplay(
                key = key,
                title = title,
                value = rawValue,
                unit = unit,
                trendKey = trendKey,
                state = stateOf(rawValue.toFloatOrNull()),
            )
        }

        companion object {
            val pages = listOf(
                MetricPage("iaqi", "통합 대기질 (IAQI)", "iaqi_value", "trend_values", "") { value ->
                    when {
                        value == null -> "대기 중"
                        value < 0.5f -> "좋음"
                        value < 1.0f -> "보통"
                        value < 2.0f -> "조금 나쁨"
                        value < 3.0f -> "나쁨"
                        value < 4.0f -> "상당히 나쁨"
                        else -> "매우 나쁨"
                    }
                },
                MetricPage("pm25", "초미세먼지 (PM2.5)", "pm25_value", "trend_pm25_values", "µg/m³") { value ->
                    when {
                        value == null -> "대기 중"
                        value <= 15f -> "좋음"
                        value <= 35f -> "보통"
                        value <= 75f -> "나쁨"
                        else -> "매우 나쁨"
                    }
                },
                MetricPage("co2", "이산화탄소 (CO₂)", "co2_value", "trend_co2_values", "ppm") { value ->
                    when {
                        value == null -> "대기 중"
                        value <= 600f -> "좋음"
                        value <= 1000f -> "보통"
                        value <= 1500f -> "나쁨"
                        else -> "매우 나쁨"
                    }
                },
                MetricPage("tvoc", "TVOC", "tvoc_value", "trend_tvoc_values", "index") { value ->
                    when {
                        value == null -> "대기 중"
                        value <= 100f -> "좋음"
                        value <= 200f -> "보통"
                        value <= 350f -> "나쁨"
                        else -> "매우 나쁨"
                    }
                },
                MetricPage("nox", "NOx", "nox_value", "trend_nox_values", "index") { value ->
                    when {
                        value == null -> "대기 중"
                        value <= 1f -> "좋음"
                        value <= 2f -> "보통"
                        else -> "나쁨"
                    }
                },
                MetricPage("co", "일산화탄소 (CO)", "co_value", "trend_co_values", "ppm") { value ->
                    when {
                        value == null -> "대기 중"
                        value < 10f -> "좋음"
                        value < 35f -> "보통"
                        value < 100f -> "나쁨"
                        else -> "매우 나쁨"
                    }
                },
            )
        }
    }

    private data class MetricDisplay(
        val key: String,
        val title: String,
        val value: String,
        val unit: String,
        val trendKey: String,
        val state: String,
    )
}
