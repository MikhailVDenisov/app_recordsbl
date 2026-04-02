import 'package:intl/intl.dart';

final _ruGroupedInt = NumberFormat('#,##0', 'ru_RU');

/// Целое число с разделителем разрядов (для ru — обычно пробел между группами).
String formatGroupedInt(int n) => _ruGroupedInt.format(n);

/// Мегабайты для подписей (округление до целого, с разрядами).
String formatGroupedMb(double megabytes) =>
    _ruGroupedInt.format(megabytes.round());
