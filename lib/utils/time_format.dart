/// 格式化 ISO 8601 时间戳为中文格式：YYYY年MM月DD日 HH时MM分SS秒
String formatTimestamp(String? isoTimestamp) {
  if (isoTimestamp == null || isoTimestamp.isEmpty) return '';
  try {
    final dt = DateTime.parse(isoTimestamp);
    pad(int n) => n.toString().padLeft(2, '0');
    return '${dt.year}年${pad(dt.month)}月${pad(dt.day)}日 '
        '${pad(dt.hour)}时${pad(dt.minute)}分${pad(dt.second)}秒';
  } catch (_) {
    return isoTimestamp.length >= 16
        ? isoTimestamp.substring(0, 16)
        : isoTimestamp;
  }
}
