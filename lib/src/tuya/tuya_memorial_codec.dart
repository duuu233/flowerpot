import 'dart:convert';
import 'dart:typed_data';

/// Codec for the memorial-day DPs added by the 2026-09-03 export: the custom
/// entries on `memorial_set` (154) and the two fixed dates on
/// `memorial_birthday` (158) and `memorial_wedding` (159).
///
/// Frame of DP 154, from the export:
///
/// ```text
/// | ID(4B, 大端) | 日期(4B, 大端) | type(1B) | 内容长度(1B) | 内容(NB) |
/// ```
///
/// * `ID` — assigned by the app, any value; the device upserts by it.
/// * `日期` — `YYYYMMDD` as a number. `0` disables the entry but keeps it,
///   `111111` deletes it. Those two sentinels come from the export's
///   `000000` / `111111`, which is the same number written with the leading
///   digits the ASCII form would have.
/// * `type` — 1 text, 2 image. Ignored (0) on a disable/delete frame.
/// * `内容` — UTF-8 text, at most 15 CJK characters (45 bytes), or an image URL.
///
/// DP 158/159 are the same idea without the wrapper: 8 ASCII bytes `YYYYMMDD`,
/// `00000000` disables, `11111111` deletes.
abstract final class TuyaMemorialCodec {
  /// Date value that keeps an entry but stops the device showing it.
  static const int disabledDate = 0;

  /// Date value that removes the entry from the device.
  static const int deletedDate = 111111;

  static const String disabledAsciiDate = '00000000';
  static const String deletedAsciiDate = '11111111';

  /// The export's cap on custom text: 15 CJK characters, 45 bytes.
  static const int maxTextCharacters = 15;

  /// 同一条上限的**字节**那一半：`最多 15 个汉字(45 字节)`。
  ///
  /// ⚠️ 两个都要挡。15 个汉字正好 45 字节，但 15 个 emoji 是 60 字节——只按字数
  /// 挡的话，帧超长、固件那边会截断，用户看到的是一条被砍一半的祝福语。
  /// 反过来 15 个 ASCII 才 15 字节，也不该因为字节没到 45 就放宽到 45 个字符。
  static const int maxTextBytes = 45;

  /// Custom entries the device accepts on top of the two fixed dates.
  static const int maxCustomEntries = 10;

  /// Rows the 纪念日 page can ever show: [maxCustomEntries] plus the birthday
  /// and the wedding day, which live on their own DPs (158/159) and are always
  /// present. This is the number the page's counter is measured against — the
  /// list is 12 long when it is full, not 10.
  static const int maxEntries = maxCustomEntries + 2;

  /// Builds one `memorial_set` frame for an upsert.
  static Uint8List encodeEntry({
    required int id,
    required DateTime date,
    required MemorialContentType type,
    required String content,
    bool enabled = true,
  }) {
    final body = utf8.encode(content);
    // 内容长度是 1 个字节，物理上限 255；文字还另有 45 字节的产品上限。
    if (body.length > 255) {
      throw ArgumentError.value(content, 'content', '纪念日内容超过 255 字节');
    }
    if (enabled &&
        type == MemorialContentType.text &&
        body.length > maxTextBytes) {
      throw ArgumentError.value(
        content,
        'content',
        '纪念日文字超过 $maxTextBytes 字节（约 $maxTextCharacters 个汉字）',
      );
    }
    return _frame(
      id: id,
      date: enabled ? dateValue(date) : disabledDate,
      type: enabled ? type.code : 0,
      content: enabled ? body : const <int>[],
    );
  }

  /// Builds the delete frame for [id]. The device drops the entry entirely,
  /// unlike the disabled frame, which keeps it for a later re-enable.
  static Uint8List encodeDelete(int id) =>
      _frame(id: id, date: deletedDate, type: 0, content: const <int>[]);

  /// Reads one frame back. Returns null when the payload is missing or shorter
  /// than its own header claims — a device mid-upgrade must not take the page
  /// down.
  static MemorialEntry? decodeEntry(Object? value) {
    final bytes = decodeRaw(value);
    if (bytes == null || bytes.length < 10) return null;
    final id = _readUint32(bytes, 0);
    final date = _readUint32(bytes, 4);
    final type = bytes[8];
    final length = bytes[9];
    final end = 10 + length;
    final content = end <= bytes.length
        ? _utf8OrEmpty(bytes.sublist(10, end))
        : '';
    return MemorialEntry(
      id: id,
      date: dateFromValue(date),
      type: MemorialContentType.fromCode(type),
      content: content,
      enabled: date != disabledDate && date != deletedDate,
    );
  }

  /// `YYYYMMDD` as the number the frame carries, e.g. 2026-08-31 → 20260831.
  static int dateValue(DateTime date) =>
      date.year * 10000 + date.month * 100 + date.day;

  /// The inverse, or null for the sentinels and anything that is not a real
  /// date.
  static DateTime? dateFromValue(int value) {
    if (value == disabledDate || value == deletedDate) return null;
    final year = value ~/ 10000;
    final month = (value ~/ 100) % 100;
    final day = value % 100;
    if (year < 1900 || year > 2999) return null;
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;
    final parsed = DateTime(year, month, day);
    // DateTime rolls 2026-02-31 forward into March; that is a corrupt payload,
    // not a date the user picked.
    if (parsed.month != month || parsed.day != day) return null;
    return parsed;
  }

  /// `YYYYMMDD` payload for the two fixed dates (158/159). [date] null writes
  /// the disable sentinel.
  static Uint8List encodeFixedDate(DateTime? date) => Uint8List.fromList(
    ascii.encode(
      date == null
          ? disabledAsciiDate
          : dateValue(date).toString().padLeft(8, '0'),
    ),
  );

  /// Removes a fixed date from the device instead of only disabling it.
  static Uint8List encodeFixedDelete() =>
      Uint8List.fromList(ascii.encode(deletedAsciiDate));

  /// Reads 158/159 back. Null covers "not set", both sentinels and junk.
  static DateTime? decodeFixedDate(Object? value) {
    final bytes = decodeRaw(value);
    if (bytes == null || bytes.length < 8) return null;
    final text = _utf8OrEmpty(bytes.sublist(0, 8));
    final number = int.tryParse(text);
    return number == null ? null : dateFromValue(number);
  }

  /// Raw DP payloads arrive base64 encoded over the method channel, the same
  /// as the history DPs; a byte list is accepted so tests and any future
  /// binary channel work unchanged.
  static List<int>? decodeRaw(Object? value) {
    if (value is List<int>) return value;
    if (value is String && value.isNotEmpty) {
      try {
        return base64.decode(value);
      } on FormatException {
        return null;
      }
    }
    return null;
  }

  /// Writes go out as an upper-case hex string.
  ///
  /// Reports come back base64 but the SDK's `publishDps` takes raw values as
  /// hex — the two directions genuinely differ. Nothing in this project has
  /// written a raw DP against real hardware yet, so this is the documented
  /// convention rather than a verified one.
  static String encodeRaw(List<int> bytes) => <String>[
    for (final byte in bytes) byte.toRadixString(16).padLeft(2, '0'),
  ].join().toUpperCase();

  static Uint8List _frame({
    required int id,
    required int date,
    required int type,
    required List<int> content,
  }) {
    final bytes = BytesBuilder()
      ..add(_uint32(id))
      ..add(_uint32(date))
      ..addByte(type)
      ..addByte(content.length)
      ..add(content);
    return bytes.toBytes();
  }

  static List<int> _uint32(int value) => <int>[
    (value >> 24) & 0xFF,
    (value >> 16) & 0xFF,
    (value >> 8) & 0xFF,
    value & 0xFF,
  ];

  static int _readUint32(List<int> bytes, int offset) =>
      (bytes[offset] << 24) |
      (bytes[offset + 1] << 16) |
      (bytes[offset + 2] << 8) |
      bytes[offset + 3];

  static String _utf8OrEmpty(List<int> bytes) {
    try {
      return utf8.decode(bytes);
    } on FormatException {
      return '';
    }
  }
}

/// What a custom memorial day shows on the device.
enum MemorialContentType {
  text(1),
  image(2);

  const MemorialContentType(this.code);

  final int code;

  static MemorialContentType fromCode(int code) =>
      code == image.code ? image : text;
}

/// One memorial day as the device holds it.
class MemorialEntry {
  const MemorialEntry({
    required this.id,
    required this.date,
    required this.type,
    required this.content,
    this.enabled = true,
    this.title = '',
    this.kind = MemorialKind.custom,
  });

  /// App-assigned id the device upserts by. The two fixed dates use
  /// [MemorialKind.birthday]/[MemorialKind.wedding] and their own DPs, so
  /// their id is never sent.
  final int id;

  /// Null when the entry is disabled or was never set.
  final DateTime? date;
  final MemorialContentType type;
  final String content;
  final bool enabled;

  /// Shown in the list. The device does not store it — DP 154 carries only the
  /// content — so it lives in the app's own record of the entry.
  final String title;
  final MemorialKind kind;

  bool get isFixed => kind != MemorialKind.custom;

  /// `2026-08-31`, or an em dash when the entry has no date yet.
  String get dateLabel {
    final value = date;
    if (value == null) return '—';
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '${value.year}-$month-$day';
  }

  MemorialEntry copyWith({
    int? id,
    DateTime? date,
    bool clearDate = false,
    MemorialContentType? type,
    String? content,
    bool? enabled,
    String? title,
    MemorialKind? kind,
  }) => MemorialEntry(
    id: id ?? this.id,
    date: clearDate ? null : (date ?? this.date),
    type: type ?? this.type,
    content: content ?? this.content,
    enabled: enabled ?? this.enabled,
    title: title ?? this.title,
    kind: kind ?? this.kind,
  );
}

/// The two fixed rows the 纪念日 page always shows, plus everything the user
/// adds. The fixed pair is stored on its own DP and cannot be deleted, only
/// disabled or re-dated.
enum MemorialKind {
  birthday('生日'),
  wedding('结婚纪念日'),
  custom('自定义纪念日');

  const MemorialKind(this.label);

  final String label;
}
