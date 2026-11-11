String ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime? tryParseYmd(String s) {
  if (s.trim().isEmpty) return null;
  return DateTime.tryParse(s.trim());
}

String formatExpiryLabel(String? ymdStr) {
  final d = tryParseYmd(ymdStr ?? '');
  if (d == null) return '';
  return '${d.year}.${d.month.toString().padLeft(2, '0')}.${d.day.toString().padLeft(2, '0')}';
}

bool isExpiredYmd(String? ymdStr) {
  final d = tryParseYmd(ymdStr ?? '');
  if (d == null) return false;
  final today = DateTime.now();
  return DateTime(d.year, d.month, d.day)
      .isBefore(DateTime(today.year, today.month, today.day));
}
