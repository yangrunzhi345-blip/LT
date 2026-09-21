/// BCP-47 语言标签的归一化与解析。
///
/// 朗读系统需要在三类来源之间做可靠比较：
/// 1. 用户配置 / 持久化的 tag；
/// 2. 自动检测得到的 tag；
/// 3. 系统 TTS 后端真实上报的语言列表。
///
/// 不同平台会返回 `zh_CN`、`en_US`、`ZH-cn`、`zh-Hans-CN` 等大小写与分隔符
/// 不一致的写法。直接用裸字符串相等判断会把“系统其实支持”误判为 unsupported，
/// 因此这里集中一个确定性的归一化实现，作为全项目唯一比较入口。
///
/// 本文件是纯 Dart、无 Flutter / 无网络依赖，可独立单测。
library;

/// 归一化为标准 BCP-47 形式：
///
/// - 分隔符统一为 `-`（`zh_CN` → `zh-CN`）；
/// - 主语言子标签小写（`ZH` → `zh`）；
/// - 长度为 4 的字母子标签按 script 处理，首字母大写（`hans` → `Hans`）；
/// - 长度为 2 的字母子标签按 region 处理，全大写（`cn` → `CN`）；
/// - 长度为 3 的数字子标签（UN M.49 region）保持原样（`419`）；
/// - 其余子标签（variant / extension）小写保留。
///
/// 非法或空输入返回空字符串，调用方据此回退，不得把空 tag 当成可用语言。
///
/// `zh-Hans-CN` / `zh-Hant-TW` 这类带 script 的标签语义被完整保留。
String normalizeBcp47(String? tag) {
  if (tag == null) return '';
  final trimmed = tag.trim();
  if (trimmed.isEmpty) return '';

  final parts = trimmed
      .split(RegExp(r'[-_\s]+'))
      .where((part) => part.isNotEmpty)
      .toList(growable: false);
  if (parts.isEmpty) return '';

  final primary = parts.first;
  // 主语言子标签必须是 2–8 位纯字母；否则视为非法标签。
  if (primary.length < 2 || primary.length > 8 || !_isLetters(primary)) {
    return '';
  }

  final buffer = StringBuffer(primary.toLowerCase());
  for (var i = 1; i < parts.length; i++) {
    final part = parts[i];
    buffer.write('-');
    if (_isLetters(part)) {
      if (part.length == 4) {
        // script（BCP-47 中 script 固定 4 位字母，Title Case）
        buffer.write(part[0].toUpperCase());
        buffer.write(part.substring(1).toLowerCase());
      } else if (part.length == 2) {
        buffer.write(part.toUpperCase());
      } else {
        buffer.write(part.toLowerCase());
      }
    } else if (part.length == 3 && _isDigits(part)) {
      buffer.write(part);
    } else {
      buffer.write(part.toLowerCase());
    }
  }
  return buffer.toString();
}

/// 标签是否可归一化为合法 BCP-47。
bool isValidBcp47(String? tag) => normalizeBcp47(tag).isNotEmpty;

/// 语言家族（primary subtag）小写形式，例如 `zh-Hant-TW` → `zh`。
///
/// 无法解析时返回 `null`。用于“同语言家族 locale”的 fallback 判断，例如
/// `en-GB` 在只有 `en-US` 的设备上可以降级。
String? languageFamily(String? tag) {
  final normalized = normalizeBcp47(tag);
  if (normalized.isEmpty) return null;
  final index = normalized.indexOf('-');
  return index < 0 ? normalized : normalized.substring(0, index);
}

/// 标签的 script 子标签（若存在），例如 `zh-Hant-TW` → `Hant`。
String? languageScript(String? tag) {
  final normalized = normalizeBcp47(tag);
  if (normalized.isEmpty) return null;
  for (final part in normalized.split('-').skip(1)) {
    if (part.length == 4 && _isLetters(part)) return part;
  }
  return null;
}

/// 两个标签是否属于同一语言家族（大小写/分隔符无关）。
bool sameLanguageFamily(String? a, String? b) {
  final familyA = languageFamily(a);
  final familyB = languageFamily(b);
  return familyA != null && familyA == familyB;
}

bool _isLetters(String value) {
  for (final unit in value.codeUnits) {
    final isUpper = unit >= 0x41 && unit <= 0x5A;
    final isLower = unit >= 0x61 && unit <= 0x7A;
    if (!isUpper && !isLower) return false;
  }
  return value.isNotEmpty;
}

bool _isDigits(String value) {
  for (final unit in value.codeUnits) {
    if (unit < 0x30 || unit > 0x39) return false;
  }
  return value.isNotEmpty;
}
