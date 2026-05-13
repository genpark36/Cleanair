/// Unified metric status labels — single source of truth.
///
/// Thresholds based on Node-RED alert engine & AirGradient sensor specs
/// (Sensirion SGP41 VOC/NOx Index).

/// PM2.5 status (µg/m³, 환경부 기준)
String pm25Status(double value) {
  if (value <= 15) return '좋음';
  if (value <= 35) return '보통';
  if (value <= 75) return '나쁨';
  return '매우 나쁨';
}

/// CO₂ status (ppm)
String co2Status(double value) {
  if (value <= 600) return '좋음';
  if (value <= 1000) return '보통';
  if (value <= 2000) return '높음';
  return '매우 높음';
}

/// TVOC status (SGP41 VOC Index, center 100, Node-RED thresholds 200/300/400)
String tvocStatus(double value) {
  if (value.isNaN) return '정보 없음';
  if (value <= 100) return '좋음';
  if (value <= 200) return '보통';
  if (value <= 300) return '주의';
  if (value <= 400) return '나쁨';
  return '매우 나쁨';
}

/// NOx status (SGP41 NOx Index, center 1, Node-RED alert >=2)
String noxStatus(double value) {
  if (value.isNaN) return '정보 없음';
  if (value <= 1) return '좋음';
  if (value <= 2) return '보통';
  return '주의';
}

/// Temperature status (°C, 실내 쾌적 기준)
String temperatureStatus(double value) {
  if (value < 18) return '서늘함';
  if (value <= 24) return '쾌적';
  if (value <= 28) return '따뜻함';
  return '더움';
}

/// Humidity status (%, 실내 쾌적 기준)
String humidityStatus(double value) {
  if (value < 30) return '건조';
  if (value <= 60) return '쾌적';
  if (value <= 70) return '약간 높음';
  return '높음';
}

/// Get status for any metric by id.
String metricStatus(String id, double value, {double humidity = 50}) {
  switch (id) {
    case 'pm25':
      return pm25Status(value);
    case 'co2':
      return co2Status(value);
    case 'tvoc':
      return tvocStatus(value);
    case 'nox':
      return noxStatus(value);
    case 'temperature':
      return temperatureStatus(value);
    case 'humidity':
      return humidityStatus(value);
    default:
      return '';
  }
}
