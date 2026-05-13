import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class KakaoMapCoordinate {
  const KakaoMapCoordinate({
    required this.latitude,
    required this.longitude,
  });

  final double latitude;
  final double longitude;
}

class KakaoMapHeatPoint {
  const KakaoMapHeatPoint({
    required this.latitude,
    required this.longitude,
    required this.value,
    required this.label,
    required this.color,
    this.radiusMeters = 650,
    this.showValue = true,
    this.showLabel = true,
  });

  final double latitude;
  final double longitude;
  final double value;
  final String label;
  final Color color;
  final int radiusMeters;
  final bool showValue;
  final bool showLabel;
}

class KakaoMapPreview extends StatefulWidget {
  const KakaoMapPreview({
    super.key,
    required this.latitude,
    required this.longitude,
    required this.label,
    this.height = 320,
    this.heatPoints = const <KakaoMapHeatPoint>[],
    this.onCenterChanged,
    this.onHeatPointTap,
    this.onVisibleHeatPointLabels,
    this.onRequestCurrentLocation,
    this.interactive = true,
    this.enableMapTapSelection,
    this.compactControls = false,
  });

  final double latitude;
  final double longitude;
  final String label;
  final double height;
  final List<KakaoMapHeatPoint> heatPoints;
  final ValueChanged<KakaoMapCoordinate>? onCenterChanged;
  final ValueChanged<KakaoMapHeatPoint>? onHeatPointTap;
  final ValueChanged<List<String>>? onVisibleHeatPointLabels;
  final Future<KakaoMapCoordinate?> Function()? onRequestCurrentLocation;
  final bool interactive;
  final bool? enableMapTapSelection;
  final bool compactControls;

  @override
  State<KakaoMapPreview> createState() => _KakaoMapPreviewState();
}

class _KakaoMapPreviewState extends State<KakaoMapPreview> {
  static const _jsApiKey = String.fromEnvironment(
    'KAKAO_JS_API_KEY',
    defaultValue: '5eb3ce76ffce0fb5d178e668062bce67',
  );
  late final WebViewController _controller;
  int _mapLevel = 6;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFFF5FAFD))
      ..addJavaScriptChannel(
        'CleanAirMapCenter',
        onMessageReceived: _handleCenterMessage,
      )
      ..addJavaScriptChannel(
        'CleanAirMapEvent',
        onMessageReceived: _handleMapEventMessage,
      );
    _loadMap();
  }

  @override
  void didUpdateWidget(covariant KakaoMapPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    final locationChanged = oldWidget.latitude != widget.latitude ||
        oldWidget.longitude != widget.longitude;
    final shouldReloadForLocation =
        locationChanged && widget.onCenterChanged == null;
    if (shouldReloadForLocation || oldWidget.label != widget.label) {
      _loadMap();
    } else if (locationChanged && widget.onCenterChanged != null) {
      unawaited(_moveToCoordinate(widget.latitude, widget.longitude));
    } else if (oldWidget.heatPoints != widget.heatPoints) {
      unawaited(_updateHeatPoints());
    }
  }

  bool get _hasJsKey => _jsApiKey.trim().isNotEmpty;

  void _loadMap() {
    if (_hasJsKey) {
      _controller.loadHtmlString(_html(), baseUrl: 'https://localhost');
    }
  }

  Future<void> _updateHeatPoints() async {
    if (!_hasJsKey) return;
    await _controller.runJavaScript('''
      if (window.cleanairSetHeatPoints) {
        window.cleanairSetHeatPoints([${_heatPointJs()}]);
      }
    ''');
  }

  Future<void> _setMapLevel(int level) async {
    final nextLevel = level.clamp(2, 12).toInt();
    setState(() => _mapLevel = nextLevel);
    if (!_hasJsKey) return;
    await _controller.runJavaScript('''
      if (window.cleanairMap) {
        window.cleanairMap.setLevel($nextLevel, {animate: true});
      }
    ''');
  }

  Future<void> _fitHeatPoints() async {
    if (!_hasJsKey) return;
    await _controller.runJavaScript('''
      if (window.cleanairFitBounds) {
        window.cleanairFitBounds();
      }
    ''');
  }

  Future<void> _moveToCoordinate(double latitude, double longitude) async {
    if (!_hasJsKey) return;
    await _controller.runJavaScript('''
      if (window.cleanairMap && window.kakao) {
        var p = new kakao.maps.LatLng($latitude, $longitude);
        window.cleanairMap.setCenter(p);
        if (window.cleanairSelectedMarker) {
          window.cleanairSelectedMarker.setPosition(p);
        }
        if (window.cleanairRenderHeatmap) {
          setTimeout(window.cleanairRenderHeatmap, 80);
        }
      }
    ''');
  }

  Future<void> _moveToCurrentLocation() async {
    final request = widget.onRequestCurrentLocation;
    if (request == null || !_hasJsKey) return;
    final coordinate = await request();
    if (coordinate == null) return;
    await _controller.runJavaScript('''
      if (window.cleanairMap && window.kakao) {
        var p = new kakao.maps.LatLng(${coordinate.latitude}, ${coordinate.longitude});
        window.cleanairMap.setCenter(p);
        window.cleanairMap.setLevel(5, {animate: true});
        if (window.cleanairRenderHeatmap) {
          setTimeout(window.cleanairRenderHeatmap, 80);
        }
      }
    ''');
  }

  void _handleCenterMessage(JavaScriptMessage message) {
    final onCenterChanged = widget.onCenterChanged;
    if (onCenterChanged == null) return;
    try {
      final decoded = jsonDecode(message.message);
      if (decoded is! Map<String, dynamic>) return;
      final latitude = (decoded['latitude'] as num?)?.toDouble();
      final longitude = (decoded['longitude'] as num?)?.toDouble();
      if (latitude == null || longitude == null) return;
      onCenterChanged(
        KakaoMapCoordinate(latitude: latitude, longitude: longitude),
      );
    } catch (_) {
      return;
    }
  }

  void _handleMapEventMessage(JavaScriptMessage message) {
    try {
      final decoded = jsonDecode(message.message);
      if (decoded is! Map<String, dynamic>) return;
      final type = decoded['type'];
      if (type == 'visiblePoints') {
        final labels = decoded['labels'];
        if (labels is! List) return;
        final callback = widget.onVisibleHeatPointLabels;
        if (callback == null) return;
        callback(labels.whereType<String>().toList(growable: false));
        return;
      }
      if (type == 'pointTap') {
        final callback = widget.onHeatPointTap;
        if (callback == null) return;
        final latitude = (decoded['latitude'] as num?)?.toDouble();
        final longitude = (decoded['longitude'] as num?)?.toDouble();
        if (latitude == null || longitude == null) return;
        KakaoMapHeatPoint? best;
        var bestDistance = double.infinity;
        for (final point in widget.heatPoints) {
          final distance = (point.latitude - latitude).abs() +
              (point.longitude - longitude).abs();
          if (distance < bestDistance) {
            best = point;
            bestDistance = distance;
          }
        }
        if (best != null) callback(best);
      }
    } catch (_) {
      return;
    }
  }

  String _html() {
    final safeLabel =
        widget.label.trim().isEmpty ? '센서 설치 위치' : widget.label.trim();
    final escapedLabel = safeLabel
        .replaceAll('\\', '\\\\')
        .replaceAll("'", r"\'")
        .replaceAll('\n', ' ');
    final heatPointJs = _heatPointJs();
    final usesHeatLayer = widget.heatPoints.isNotEmpty;
    final allowMapTapSelection = widget.enableMapTapSelection ??
        (!usesHeatLayer && widget.onCenterChanged != null);
    final usesDynamicMap = usesHeatLayer ||
        widget.onCenterChanged != null ||
        widget.onRequestCurrentLocation != null ||
        widget.interactive;
    return '''
<!doctype html>
<html>
<head>
  <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
  <style>
    html, body, #wrap, #map { width: 100%; height: 100%; margin: 0; padding: 0; background: #f5fafd; }
    #wrap { position: relative; overflow: hidden; }
    #heat {
      position: absolute;
      inset: 0;
      width: 100%;
      height: 100%;
      pointer-events: none;
      mix-blend-mode: multiply;
      opacity: .86;
      z-index: 1;
    }
    .cleanair-label {
      padding: 6px 9px;
      border-radius: 999px;
      background: rgba(255,255,255,.92);
      color: #263238;
      font: 700 11px system-ui, -apple-system, BlinkMacSystemFont, sans-serif;
      box-shadow: 0 6px 14px rgba(0,103,125,.14);
      white-space: nowrap;
    }
    #map a[href*="map.kakao.com"] { pointer-events: none !important; }
  </style>
  <script src="https://dapi.kakao.com/v2/maps/sdk.js?appkey=$_jsApiKey&autoload=false"></script>
</head>
<body>
  <div id="wrap">
    <div id="map"></div>
    ${usesHeatLayer ? '<canvas id="heat"></canvas>' : ''}
  </div>
  <script>
    kakao.maps.load(function() {
      var center = new kakao.maps.LatLng(${widget.latitude}, ${widget.longitude});
      var map = ${usesDynamicMap ? 'new kakao.maps.Map' : 'new kakao.maps.StaticMap'}(document.getElementById('map'), {
        center: center,
        level: ${usesDynamicMap ? _mapLevel : 3}${usesDynamicMap ? '' : ",\n        marker: { position: center, text: '$escapedLabel' }"}
      });
      ${usesDynamicMap ? """
      window.cleanairMap = map;
      map.setDraggable(${widget.interactive ? 'true' : 'false'});
      map.setZoomable(${widget.interactive ? 'true' : 'false'});
      var points = [$heatPointJs];
      var bounds = new kakao.maps.LatLngBounds();
      var canvas = document.getElementById('heat');
      var ctx = canvas ? canvas.getContext('2d') : null;
      var renderQueued = false;
      var interactionDepth = 0;
      var settleTimer = null;
      function rebuildBounds() {
        bounds = new kakao.maps.LatLngBounds();
        points.forEach(function(point) {
          var position = new kakao.maps.LatLng(point.lat, point.lng);
          bounds.extend(position);
        });
      }
      window.cleanairSetHeatPoints = function(nextPoints) {
        points = nextPoints || [];
        rebuildBounds();
        scheduleRenderHeatmap();
        setTimeout(postVisiblePointLabels, 120);
      };
      function hexToRgb(hex) {
        var value = parseInt(hex.replace('#', ''), 16);
        return {
          r: (value >> 16) & 255,
          g: (value >> 8) & 255,
          b: value & 255
        };
      }
      function rgba(hex, alpha) {
        var c = hexToRgb(hex);
        return 'rgba(' + c.r + ',' + c.g + ',' + c.b + ',' + alpha + ')';
      }
      function pointToPixel(position) {
        var projection = map.getProjection();
        if (projection.containerPointFromCoords) {
          return projection.containerPointFromCoords(position);
        }
        return projection.pointFromCoords(position);
      }
      function heatRadius(point) {
        var level = map.getLevel();
        var base = point.radius / Math.pow(2, Math.max(0, level - 4));
        return Math.max(34, Math.min(260, base * 0.32));
      }
      function visiblePoints(rect) {
        var result = [];
        points.forEach(function(point) {
          if ((!point.showValue && !point.showLabel) || !isFinite(point.value)) {
            return;
          }
          var position = new kakao.maps.LatLng(point.lat, point.lng);
          var pixel = pointToPixel(position);
          if (pixel.x < -260 || pixel.y < -260 ||
              pixel.x > rect.width + 260 || pixel.y > rect.height + 260) {
            return;
          }
          result.push({
            point: point,
            x: pixel.x,
            y: pixel.y,
            rgb: hexToRgb(point.color),
            radius: heatRadius(point)
          });
        });
        return result;
      }
      function postVisiblePointLabels() {
        if (!canvas) return;
        var rect = canvas.getBoundingClientRect();
        var labels = visiblePoints(rect).map(function(item) {
          return item.point.label;
        });
        CleanAirMapEvent.postMessage(JSON.stringify({
          type: 'visiblePoints',
          labels: labels
        }));
      }
      function nearestHeatPoint(latLng) {
        if (!canvas || points.length === 0) return null;
        var clickPixel = pointToPixel(latLng);
        var rect = canvas.getBoundingClientRect();
        var screenPoints = visiblePoints(rect);
        var nearest = null;
        var nearestDistance = 99999;
        screenPoints.forEach(function(item) {
          var dx = item.x - clickPixel.x;
          var dy = item.y - clickPixel.y;
          var distance = Math.sqrt(dx * dx + dy * dy);
          var threshold = item.point.showLabel ? 34 : 24;
          if (distance < threshold && distance < nearestDistance) {
            nearest = item.point;
            nearestDistance = distance;
          }
        });
        return nearest;
      }
      function drawInterpolatedHeat(rect, screenPoints, quick) {
        var valued = screenPoints.filter(function(item) {
          return item.point.showValue && isFinite(item.point.value);
        });
        if (valued.length === 0) return;
        var level = map.getLevel();
        var blur = quick ? 0 : (level >= 8 ? 18 : level >= 6 ? 16 : 12);
        var alphaScale = quick ? 0.34 : 0.92;
        ctx.save();
        ctx.globalCompositeOperation = 'source-over';
        ctx.filter = blur > 0 ? 'blur(' + blur + 'px)' : 'none';
        valued.forEach(function(item) {
          var point = item.point;
          var x = item.x;
          var y = item.y;
          var radius = quick
            ? Math.max(28, Math.min(78, item.radius * 0.34))
            : Math.max(84, Math.min(310, item.radius * 1.34));
          var gradient = ctx.createRadialGradient(x, y, 0, x, y, radius);
          gradient.addColorStop(0, rgba(point.color, 0.34 * alphaScale));
          gradient.addColorStop(0.28, rgba(point.color, 0.24 * alphaScale));
          gradient.addColorStop(0.62, rgba(point.color, 0.11 * alphaScale));
          gradient.addColorStop(1, rgba(point.color, 0));
          ctx.fillStyle = gradient;
          ctx.beginPath();
          ctx.arc(x, y, radius, 0, Math.PI * 2);
          ctx.fill();
        });
        ctx.filter = 'none';
        ctx.restore();
      }
      function roundRect(x, y, width, height, radius) {
        ctx.beginPath();
        ctx.moveTo(x + radius, y);
        ctx.lineTo(x + width - radius, y);
        ctx.quadraticCurveTo(x + width, y, x + width, y + radius);
        ctx.lineTo(x + width, y + height - radius);
        ctx.quadraticCurveTo(x + width, y + height, x + width - radius, y + height);
        ctx.lineTo(x + radius, y + height);
        ctx.quadraticCurveTo(x, y + height, x, y + height - radius);
        ctx.lineTo(x, y + radius);
        ctx.quadraticCurveTo(x, y, x + radius, y);
        ctx.closePath();
      }
      function renderHeatmap() {
        renderQueued = false;
        if (!canvas || !ctx) return;
        var quick = interactionDepth > 0;
        var rect = canvas.getBoundingClientRect();
        var dpr = window.devicePixelRatio || 1;
        canvas.width = Math.max(1, Math.floor(rect.width * dpr));
        canvas.height = Math.max(1, Math.floor(rect.height * dpr));
        ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
        ctx.clearRect(0, 0, rect.width, rect.height);
        ctx.globalCompositeOperation = 'source-over';
        ctx.fillStyle = 'rgba(62, 170, 176, 0.025)';
        ctx.fillRect(0, 0, rect.width, rect.height);
        var screenPoints = visiblePoints(rect);
        drawInterpolatedHeat(rect, screenPoints, quick);
        screenPoints.forEach(function(item) {
          var point = item.point;
          if (!point.showValue && !point.showLabel) return;
          if (quick && !point.showLabel) return;
          var x = item.x;
          var y = item.y;
          var radius = quick
            ? Math.max(16, item.radius * 0.26)
            : Math.max(28, item.radius * 0.72);
          var gradient = ctx.createRadialGradient(x, y, 0, x, y, radius);
          gradient.addColorStop(0, rgba(point.color, quick ? 0.12 : 0.22));
          gradient.addColorStop(0.28, rgba(point.color, quick ? 0.07 : 0.14));
          gradient.addColorStop(0.66, rgba(point.color, quick ? 0.02 : 0.055));
          gradient.addColorStop(1, rgba(point.color, 0));
          ctx.fillStyle = gradient;
          ctx.beginPath();
          ctx.arc(x, y, radius, 0, Math.PI * 2);
          ctx.fill();
        });
        var level = map.getLevel();
        var labelEvery = level >= 8 ? 10 : level >= 7 ? 6 : level >= 6 ? 4 : level >= 5 ? 2 : 1;
        screenPoints.forEach(function(item, index) {
          var point = item.point;
          var x = item.x;
          var y = item.y;
          if (x < -80 || y < -50 || x > rect.width + 80 || y > rect.height + 50) {
            return;
          }
          ctx.shadowColor = quick ? 'transparent' : 'rgba(0, 0, 0, .18)';
          ctx.shadowBlur = quick ? 0 : 9;
          ctx.shadowOffsetY = quick ? 0 : 4;
          var markerRadius = point.showLabel ? 6 : 4.5;
          ctx.fillStyle = point.showLabel ? point.color : rgba(point.color, 0.82);
          ctx.beginPath();
          ctx.arc(x, y, markerRadius, 0, Math.PI * 2);
          ctx.fill();
          ctx.shadowColor = 'transparent';
          ctx.lineWidth = 2;
          ctx.strokeStyle = 'rgba(255,255,255,.96)';
          ctx.stroke();

          if (quick) return;
          var shouldLabel = point.showLabel &&
            (labelEvery === 1 || index % labelEvery === 0);
          if (!shouldLabel) return;
          var text = point.label + (point.showValue ? ' ' + Math.round(point.value) : '');
          ctx.font = '700 11px system-ui, -apple-system, BlinkMacSystemFont, sans-serif';
          var textWidth = ctx.measureText(text).width;
          var w = textWidth + 18;
          var h = 24;
          var lx = Math.max(8, Math.min(rect.width - w - 8, x - w / 2));
          var ly = Math.max(8, y - 38);
          ctx.shadowColor = 'rgba(0, 103, 125, .14)';
          ctx.shadowBlur = 12;
          ctx.shadowOffsetY = 5;
          ctx.fillStyle = 'rgba(255,255,255,.94)';
          roundRect(lx, ly, w, h, 12);
          ctx.fill();
          ctx.shadowColor = 'transparent';
          ctx.fillStyle = '#263238';
          ctx.fillText(text, lx + 9, ly + 16);
        });
      }
      function scheduleRenderHeatmap() {
        if (renderQueued) return;
        renderQueued = true;
        window.requestAnimationFrame(renderHeatmap);
      }
      function beginInteraction() {
        interactionDepth = 1;
        if (settleTimer) {
          clearTimeout(settleTimer);
          settleTimer = null;
        }
        scheduleRenderHeatmap();
      }
      function endInteractionSoon() {
        if (settleTimer) clearTimeout(settleTimer);
        settleTimer = setTimeout(function() {
          interactionDepth = 0;
          scheduleRenderHeatmap();
        }, 220);
      }
      window.cleanairRenderHeatmap = renderHeatmap;
      window.cleanairFitBounds = function() {
        if (points.length > 1 && points.length <= 30) {
          map.setBounds(bounds, 38, 38, 38, 38);
          setTimeout(renderHeatmap, 80);
        }
      };
      rebuildBounds();
      if (points.length > 1 && points.length <= 30) {
        window.cleanairFitBounds();
      } else {
        window.cleanairSelectedMarker = new kakao.maps.Marker({ map: map, position: center, title: '$escapedLabel' });
      }
      function postCenter() {
        var c = map.getCenter();
        CleanAirMapCenter.postMessage(JSON.stringify({
          latitude: c.getLat(),
          longitude: c.getLng()
        }));
      }
      kakao.maps.event.addListener(map, 'center_changed', function() {
        beginInteraction();
        scheduleRenderHeatmap();
      });
      kakao.maps.event.addListener(map, 'bounds_changed', scheduleRenderHeatmap);
      kakao.maps.event.addListener(map, 'idle', function() {
        endInteractionSoon();
        postCenter();
        postVisiblePointLabels();
      });
      kakao.maps.event.addListener(map, 'click', function(mouseEvent) {
        var heatPoint = nearestHeatPoint(mouseEvent.latLng);
        if (heatPoint) {
          CleanAirMapEvent.postMessage(JSON.stringify({
            type: 'pointTap',
            label: heatPoint.label,
            latitude: heatPoint.lat,
            longitude: heatPoint.lng
          }));
          return;
        }
        if (!${allowMapTapSelection ? 'true' : 'false'}) {
          return;
        }
        if (!window.cleanairSelectedMarker) {
          window.cleanairSelectedMarker = new kakao.maps.Marker({
            map: map,
            position: mouseEvent.latLng,
            title: '$escapedLabel'
          });
        }
        window.cleanairSelectedMarker.setPosition(mouseEvent.latLng);
        map.setCenter(mouseEvent.latLng);
        CleanAirMapCenter.postMessage(JSON.stringify({
          latitude: mouseEvent.latLng.getLat(),
          longitude: mouseEvent.latLng.getLng()
        }));
      });
      kakao.maps.event.addListener(map, 'zoom_changed', function() {
        beginInteraction();
        setTimeout(scheduleRenderHeatmap, 20);
        endInteractionSoon();
      });
      window.addEventListener('resize', scheduleRenderHeatmap);
      setTimeout(scheduleRenderHeatmap, 120);
      setTimeout(postVisiblePointLabels, 200);
      """ : ""}
      CleanAirMapCenter.postMessage(JSON.stringify({
        latitude: ${widget.latitude},
        longitude: ${widget.longitude}
      }));
    });
  </script>
</body>
</html>
''';
  }

  String _heatPointJs() {
    return widget.heatPoints
        .where((point) => point.latitude != 0 && point.longitude != 0)
        .map((point) {
      final label = point.label
          .replaceAll('\\', '\\\\')
          .replaceAll("'", r"\'")
          .replaceAll('\n', ' ');
      return "{lat:${point.latitude},lng:${point.longitude},value:${point.value},label:'$label',color:'${_hex(point.color)}',radius:${point.radiusMeters},showValue:${point.showValue ? 'true' : 'false'},showLabel:${point.showLabel ? 'true' : 'false'}}";
    }).join(',');
  }

  String _hex(Color color) {
    final rgb = color.toARGB32() & 0x00ffffff;
    return '#${rgb.toRadixString(16).padLeft(6, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: SizedBox(
        height: widget.height,
        child: Stack(
          children: [
            Positioned.fill(
              child: _hasJsKey
                  ? WebViewWidget(controller: _controller)
                  : _StaticKakaoMapCard(
                      latitude: widget.latitude,
                      longitude: widget.longitude,
                      label: widget.label,
                      heatPoints: widget.heatPoints,
                    ),
            ),
            if (_hasJsKey &&
                (widget.heatPoints.isNotEmpty || widget.interactive))
              Positioned(
                right: 12,
                top: 12,
                child: _MapControlPanel(
                  onZoomIn: () => _setMapLevel(_mapLevel - 1),
                  onZoomOut: () => _setMapLevel(_mapLevel + 1),
                  onLocate: widget.onRequestCurrentLocation == null
                      ? null
                      : () => _moveToCurrentLocation(),
                  onFit: _fitHeatPoints,
                  compact: widget.compactControls,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _MapControlPanel extends StatelessWidget {
  const _MapControlPanel({
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onLocate,
    required this.onFit,
    required this.compact,
  });

  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback? onLocate;
  final VoidCallback onFit;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Color(0x2400677D),
            blurRadius: 14,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _MapControlButton(
            icon: Icons.add_rounded,
            onTap: onZoomIn,
            compact: compact,
          ),
          _MapControlDivider(),
          _MapControlButton(
            icon: Icons.remove_rounded,
            onTap: onZoomOut,
            compact: compact,
          ),
          _MapControlDivider(),
          if (onLocate != null) ...[
            _MapControlButton(
              icon: Icons.my_location_rounded,
              onTap: onLocate!,
              compact: compact,
            ),
            _MapControlDivider(),
          ],
          _MapControlButton(
            icon: Icons.center_focus_strong_rounded,
            onTap: onFit,
            compact: compact,
          ),
        ],
      ),
    );
  }
}

class _MapControlButton extends StatelessWidget {
  const _MapControlButton({
    required this.icon,
    required this.onTap,
    required this.compact,
  });

  final IconData icon;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: compact ? 38 : 46,
          height: compact ? 38 : 46,
          child: Icon(icon, color: const Color(0xFF00677D), size: 22),
        ),
      ),
    );
  }
}

class _MapControlDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 26,
      height: 1,
      color: const Color(0xFFE2F0F4),
    );
  }
}

class _StaticKakaoMapCard extends StatelessWidget {
  const _StaticKakaoMapCard({
    required this.latitude,
    required this.longitude,
    required this.label,
    required this.heatPoints,
  });

  final double latitude;
  final double longitude;
  final String label;
  final List<KakaoMapHeatPoint> heatPoints;

  @override
  Widget build(BuildContext context) {
    final title = label.trim().isEmpty ? '센서 설치 위치' : label.trim();
    return Container(
      color: const Color(0xFFEAF6FA),
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _StaticMapPainter(
                centerLatitude: latitude,
                centerLongitude: longitude,
                heatPoints: heatPoints,
              ),
            ),
          ),
          if (heatPoints.isEmpty)
            Center(
              child: Container(
                width: 78,
                height: 78,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Color(0x2600677D),
                      blurRadius: 22,
                      offset: Offset(0, 8),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.location_on_rounded,
                  color: Color(0xFF00677D),
                  size: 48,
                ),
              ),
            ),
          Positioned(
            left: 14,
            right: 14,
            bottom: 14,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.94),
                borderRadius: BorderRadius.circular(18),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x1400677D),
                    blurRadius: 14,
                    offset: Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF263238),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '좌표 ${latitude.toStringAsFixed(5)}, ${longitude.toStringAsFixed(5)}',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF6B7A80),
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

class _StaticMapPainter extends CustomPainter {
  const _StaticMapPainter({
    required this.centerLatitude,
    required this.centerLongitude,
    required this.heatPoints,
  });

  final double centerLatitude;
  final double centerLongitude;
  final List<KakaoMapHeatPoint> heatPoints;

  @override
  void paint(Canvas canvas, Size size) {
    final road = Paint()
      ..color = Colors.white.withValues(alpha: 0.78)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 16
      ..strokeCap = StrokeCap.round;
    final minor = Paint()
      ..color = const Color(0xFFD4EDF4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(-20, size.height * 0.72),
      Offset(size.width * 0.96, size.height * 0.18),
      road,
    );
    canvas.drawLine(
      Offset(size.width * 0.08, -10),
      Offset(size.width * 0.86, size.height + 16),
      minor,
    );
    canvas.drawLine(
      Offset(-10, size.height * 0.34),
      Offset(size.width + 10, size.height * 0.46),
      minor,
    );
    for (final point in heatPoints) {
      final offset = _project(point, size);
      final glow = Paint()
        ..color = point.color.withValues(alpha: 0.26)
        ..style = PaintingStyle.fill;
      final core = Paint()
        ..color = point.color.withValues(alpha: 0.88)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(offset, 38, glow);
      canvas.drawCircle(offset, 8, core);
    }
  }

  Offset _project(KakaoMapHeatPoint point, Size size) {
    const latScale = 90000.0;
    const lngScale = 72000.0;
    final dx = (point.longitude - centerLongitude) * lngScale;
    final dy = (centerLatitude - point.latitude) * latScale;
    return Offset(
      (size.width / 2 + dx).clamp(18.0, size.width - 18),
      (size.height / 2 + dy).clamp(18.0, size.height - 18),
    );
  }

  @override
  bool shouldRepaint(covariant _StaticMapPainter oldDelegate) {
    return oldDelegate.centerLatitude != centerLatitude ||
        oldDelegate.centerLongitude != centerLongitude ||
        oldDelegate.heatPoints != heatPoints;
  }
}
