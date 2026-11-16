/// Exact monetary value in sen (1/100 rupiah), stored as an integer.
///
/// Mirrors the backend `money.Amount` (audit DMB-015): values are never kept or
/// computed as floating point. JSON numbers decoded by Dart as `double` are parsed
/// through their shortest decimal representation, so `15000.5` stays exactly
/// 1 500 050 sen. More than two decimals is rejected.
class Money implements Comparable<Money> {
  /// Amount in sen.
  final int sen;

  const Money.sen(this.sen);
  const Money.zero() : sen = 0;

  /// Whole rupiah.
  factory Money.rupiah(int rupiah) => Money.sen(rupiah * 100);

  static final RegExp _decimal = RegExp(r'^(-?)(\d+)(?:\.(\d{1,2}))?$');

  /// Parses an API value (int, double or numeric string). Throws [FormatException].
  static Money parse(dynamic value) {
    if (value is Money) return value;
    if (value is int) return Money.rupiah(value);
    String text;
    if (value is double) {
      if (value.isNaN || value.isInfinite) throw const FormatException('nominal tidak valid');
      text = value.toString();
      if (text.endsWith('.0')) text = text.substring(0, text.length - 2);
    } else if (value is String) {
      text = value.trim();
    } else {
      throw FormatException('nominal tidak valid: $value');
    }
    final m = _decimal.firstMatch(text);
    if (m == null) throw FormatException('nominal tidak valid: $text');
    final whole = int.parse(m.group(2)!);
    final frac = (m.group(3) ?? '').padRight(2, '0');
    final sen = whole * 100 + (frac.isEmpty ? 0 : int.parse(frac));
    return Money.sen(m.group(1) == '-' ? -sen : sen);
  }

  /// Like [parse] but returns null for a missing or malformed value — callers then
  /// display "-" instead of inventing a zero amount.
  static Money? tryParse(dynamic value) {
    if (value == null) return null;
    try {
      return parse(value);
    } on FormatException {
      return null;
    }
  }

  bool get isZero => sen == 0;
  bool get isNegative => sen < 0;
  bool get isWholeRupiah => sen % 100 == 0;

  /// Whole rupiah part (only meaningful when [isWholeRupiah]).
  int get wholeRupiah => sen ~/ 100;

  Money operator +(Money other) => Money.sen(sen + other.sen);
  Money operator -(Money other) => Money.sen(sen - other.sen);
  bool operator <(Money other) => sen < other.sen;
  bool operator <=(Money other) => sen <= other.sen;
  bool operator >(Money other) => sen > other.sen;
  bool operator >=(Money other) => sen >= other.sen;

  /// Ratio for UI progress indicators only (not a monetary computation).
  double ratioOf(Money total) => total.sen == 0 ? 0 : (sen / total.sen).clamp(0, 1).toDouble();

  /// Exact decimal string for the API ("15000", "15000.5").
  String toApiString() {
    final abs = sen.abs();
    var s = '${abs ~/ 100}';
    final frac = abs % 100;
    if (frac != 0) s += '.${frac.toString().padLeft(2, '0').replaceAll(RegExp(r'0$'), '')}';
    return sen < 0 ? '-$s' : s;
  }

  @override
  int compareTo(Money other) => sen.compareTo(other.sen);

  @override
  bool operator ==(Object other) => other is Money && other.sen == sen;

  @override
  int get hashCode => sen.hashCode;

  @override
  String toString() => toApiString();
}
