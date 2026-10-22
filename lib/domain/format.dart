import 'dart:math' as math;

const poundsPerKg = 2.2046226;

/// Calendar days in local time. Day keys ("2026-10-20") index notes, activity and menus in trim.json.
class Day {
  static String key(DateTime d) {
    final l = d.toLocal();
    return '${l.year.toString().padLeft(4, '0')}-${_two(l.month)}-${_two(l.day)}';
  }

  static DateTime? date(String key) {
    final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(key);
    if (m == null) return null;
    return DateTime(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
  }

  static DateTime start(DateTime d) {
    final l = d.toLocal();
    return DateTime(l.year, l.month, l.day);
  }

  /// Calendar arithmetic, so a day across a daylight-saving change still lands on midnight.
  static DateTime add(int days, DateTime d) {
    final l = d.toLocal();
    return DateTime(l.year, l.month, l.day + days, l.hour, l.minute, l.second, l.millisecond);
  }

  /// Whole calendar days from a to b.
  static int between(DateTime a, DateTime b) {
    final x = a.toLocal(), y = b.toLocal();
    return DateTime.utc(y.year, y.month, y.day).difference(DateTime.utc(x.year, x.month, x.day)).inDays;
  }

  static bool same(DateTime a, DateTime b) => between(a, b) == 0;
  static bool isToday(DateTime d) => same(d, DateTime.now());

  static String _two(int n) => n.toString().padLeft(2, '0');
}

class Fmt {
  /// "1.25", "2", "12.5": trailing zeros dropped.
  static String amount(double v) {
    var s = v.toStringAsFixed(v < 10 ? 2 : 1);
    if (s.contains('.')) {
      s = s.replaceFirst(RegExp(r'0+$'), '');
      if (s.endsWith('.')) s = s.substring(0, s.length - 1);
    }
    return s;
  }

  /// Thousands separators: 12500 → "12,500".
  static String int_(int v) {
    final neg = v < 0;
    final digits = v.abs().toString();
    final out = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
      out.write(digits[i]);
    }
    return neg ? '-$out' : out.toString();
  }

  static String kcal(double v) => int_(v.round());
  static String grams(double v) => '${v.round()} g';

  static String weight(double kg, bool metric, {int digits = 1}) =>
      metric ? '${kg.toStringAsFixed(digits)} kg' : '${(kg * poundsPerKg).toStringAsFixed(digits)} lb';

  static double weightValue(double kg, bool metric) => metric ? kg : kg * poundsPerKg;
  static double kgFromDisplay(double v, bool metric) => metric ? v : v / poundsPerKg;
  static String weightUnit(bool metric) => metric ? 'kg' : 'lb';

  static String length(double cm, bool metric) =>
      metric ? '${cm.toStringAsFixed(1)} cm' : '${(cm / 2.54).toStringAsFixed(1)} in';

  static String height(double cm, bool metric) {
    if (metric) return '${cm.round()} cm';
    final inches = (cm / 2.54).round();
    return '${inches ~/ 12}′ ${inches % 12}″';
  }

  static double round1(double v) => (v * 10).roundToDouble() / 10;

  static String signedWeight(double kg, bool metric) => (kg > 0 ? '+' : '') + weight(kg, metric);

  static double clampD(double v, double lo, double hi) => math.min(hi, math.max(lo, v));
}
