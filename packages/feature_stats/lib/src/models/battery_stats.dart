/// Charging state, from `dumpsys battery`'s numeric `status` field
/// (`BatteryManager.BATTERY_STATUS_*`).
enum BatteryStatus {
  unknown(1),
  charging(2),
  discharging(3),
  notCharging(4),
  full(5);

  const BatteryStatus(this.code);
  final int code;

  static BatteryStatus fromCode(int? code) => values.firstWhere(
    (s) => s.code == code,
    orElse: () => BatteryStatus.unknown,
  );
}

/// Battery health (`BatteryManager.BATTERY_HEALTH_*`).
enum BatteryHealth {
  unknown(1),
  good(2),
  overheat(3),
  dead(4),
  overVoltage(5),
  unspecifiedFailure(6),
  cold(7);

  const BatteryHealth(this.code);
  final int code;

  static BatteryHealth fromCode(int? code) => values.firstWhere(
    (h) => h.code == code,
    orElse: () => BatteryHealth.unknown,
  );
}

class BatteryStats {
  const BatteryStats({
    required this.level,
    required this.scale,
    required this.status,
    required this.health,
    required this.temperature,
    required this.voltage,
    required this.acPowered,
    required this.usbPowered,
    this.technology,
  });

  final int level;

  /// Almost always 100, but the API allows other scales, so percentage must be
  /// computed rather than assuming `level` is already a percent.
  final int scale;

  final BatteryStatus status;
  final BatteryHealth health;

  /// Degrees Celsius. `dumpsys` reports tenths of a degree; converted here.
  final double temperature;

  /// Millivolts as reported. Some devices report microvolts; values above
  /// 100000 are scaled down on parse.
  final int voltage;

  final bool acPowered;
  final bool usbPowered;
  final String? technology;

  double get percent => scale == 0 ? 0 : (level / scale).clamp(0.0, 1.0);

  bool get isCharging =>
      status == BatteryStatus.charging || status == BatteryStatus.full;

  bool get isPlugged => acPowered || usbPowered;

  /// Sustained operation above ~45 °C is where thermal throttling starts and
  /// where long-running benchmarks stop being trustworthy.
  bool get isHot => temperature >= 45;

  static const empty = BatteryStats(
    level: 0,
    scale: 100,
    status: BatteryStatus.unknown,
    health: BatteryHealth.unknown,
    temperature: 0,
    voltage: 0,
    acPowered: false,
    usbPowered: false,
  );
}
