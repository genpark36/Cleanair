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
import kotlin.math.min

class CleanAirStatusWidget : HomeWidgetProvider() {
    companion object {
        const val ACTION_REFRESH = "com.example.indoor_air_quality.REFRESH_STATUS_WIDGET"
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == ACTION_REFRESH) {
            val prefs = HomeWidgetPlugin.getData(context)
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(ComponentName(context, CleanAirStatusWidget::class.java))
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
            val views = RemoteViews(context.packageName, R.layout.cleanair_status_widget)
            val iaqi = CleanAirWidgetUtils.text(widgetData, "iaqi_value")
            val iaqiLabel = CleanAirWidgetUtils.text(widgetData, "iaqi_label", "대기 중")
            val disasterLabel = CleanAirWidgetUtils.text(widgetData, "disaster_label", "대기 중")
            val updatedAt = CleanAirWidgetUtils.text(widgetData, "updated_at", "업데이트 대기")
            val pm25 = CleanAirWidgetUtils.text(widgetData, "pm25_value")
            val co2 = CleanAirWidgetUtils.text(widgetData, "co2_value")
            val co = CleanAirWidgetUtils.text(widgetData, "co_value")
            val tvoc = CleanAirWidgetUtils.text(widgetData, "tvoc_value")
            val nox = CleanAirWidgetUtils.text(widgetData, "nox_value")
            val temperature = CleanAirWidgetUtils.text(widgetData, "temperature_value")
            val humidity = CleanAirWidgetUtils.text(widgetData, "humidity_value")
            val location = CleanAirWidgetUtils.text(widgetData, "location_label", "실내")
            val iaqiColor = CleanAirWidgetUtils.iaqiColor(iaqiLabel)

            views.setTextViewText(R.id.widget_status_location, location)
            views.setTextViewText(R.id.widget_status_iaqi, iaqi)
            views.setTextViewText(R.id.widget_status_iaqi_label, iaqiLabel)
            views.setTextColor(R.id.widget_status_iaqi, iaqiColor)
            views.setTextColor(R.id.widget_status_iaqi_label, iaqiColor)
            views.setImageViewBitmap(R.id.widget_status_gauge, drawGauge(iaqi.toFloatOrNull(), iaqiColor))
            views.setTextViewText(R.id.widget_status_temperature, "$temperature°C")
            views.setTextViewText(R.id.widget_status_humidity, "$humidity%")
            views.setTextViewText(R.id.widget_status_disaster, "방재 $disasterLabel")
            views.setTextColor(R.id.widget_status_disaster, CleanAirWidgetUtils.riskColor(disasterLabel))
            views.setTextViewText(R.id.widget_status_pm25, "$pm25 µg/m³")
            views.setTextViewText(R.id.widget_status_co2, "$co2 ppm")
            views.setTextViewText(R.id.widget_status_tvoc, "$tvoc index")
            views.setTextViewText(R.id.widget_status_nox, "$nox index")
            views.setTextViewText(R.id.widget_status_co, "$co ppm")
            views.setTextViewText(R.id.widget_status_updated, updatedAt)
            views.setOnClickPendingIntent(R.id.widget_status_root, CleanAirWidgetUtils.openAppIntent(context))
            views.setOnClickPendingIntent(R.id.widget_status_refresh, CleanAirWidgetUtils.refreshStatusIntent(context))

            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }

    private fun drawGauge(value: Float?, color: Int): Bitmap {
        val size = 220
        val stroke = 18f
        val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        val bounds = RectF(stroke, stroke, size - stroke, size - stroke)
        val track = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeWidth = stroke
            strokeCap = Paint.Cap.ROUND
            this.color = Color.rgb(222, 227, 230)
        }
        val progress = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeWidth = stroke
            strokeCap = Paint.Cap.ROUND
            this.color = color
        }
        canvas.drawArc(bounds, 135f, 270f, false, track)
        val ratio = min(((value ?: 0f) / 5f).coerceAtLeast(0f), 1f)
        canvas.drawArc(bounds, 135f, 270f * ratio, false, progress)
        return bitmap
    }
}
