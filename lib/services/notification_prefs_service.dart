import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'notification_service.dart';

/// Satu catatan di riwayat notifikasi.
class NotificationLog {
  final String type; // 'low_stock' | 'daily' | 'test'
  final String title;
  final String body;
  final DateTime time;

  const NotificationLog({
    required this.type,
    required this.title,
    required this.body,
    required this.time,
  });

  Map<String, dynamic> toMap() => {
    'type': type,
    'title': title,
    'body': body,
    'time': time.toIso8601String(),
  };

  factory NotificationLog.fromMap(Map<dynamic, dynamic> m) => NotificationLog(
    type: (m['type'] ?? '') as String,
    title: (m['title'] ?? '') as String,
    body: (m['body'] ?? '') as String,
    time: DateTime.tryParse((m['time'] ?? '') as String) ?? DateTime.now(),
  );
}

/// Pengaturan dan riwayat notifikasi, disimpan di Hive.
/// SQLite dan Supabase tidak disentuh sama sekali.
class NotificationPrefsService {
  NotificationPrefsService._();
  static final NotificationPrefsService instance = NotificationPrefsService._();

  static const _settingsBox = 'notification_settings';
  static const _historyBox = 'notification_history';
  static const _maxHistory = 100;

  static const _kEnabled = 'daily_enabled';
  static const _kHour = 'daily_hour';
  static const _kMinute = 'daily_minute';
  static const _kLastCheck = 'last_check';

  late Box _settings;
  late Box _history;
  bool _ready = false;

  /// Naik setiap kali riwayat berubah, supaya layar bisa ikut memperbarui diri.
  final ValueNotifier<int> historyVersion = ValueNotifier<int>(0);

  /// Panggil setelah Hive.initFlutter().
  Future<void> init() async {
    if (_ready) return;
    _settings = await Hive.openBox(_settingsBox);
    _history = await Hive.openBox(_historyBox);
    _ready = true;
  }

  // ---------------------------------------------------------------
  // Pengaturan pengingat harian
  // ---------------------------------------------------------------

  bool get enabled => _ready && (_settings.get(_kEnabled, defaultValue: false) as bool);
  int get hour => _ready ? (_settings.get(_kHour, defaultValue: 8) as int) : 8;
  int get minute => _ready ? (_settings.get(_kMinute, defaultValue: 0) as int) : 0;

  /// Menyimpan pengaturan lalu memasang atau membatalkan jadwal.
  /// Mengembalikan false jika penjadwalan gagal.
  Future<bool> saveDaily({
    required bool enabled,
    required int hour,
    required int minute,
  }) async {
    if (!_ready) return false;
    await _settings.put(_kEnabled, enabled);
    await _settings.put(_kHour, hour);
    await _settings.put(_kMinute, minute);
    // Riwayat pengingat dihitung mulai saat pengaturan diubah.
    await _settings.put(_kLastCheck, DateTime.now().toIso8601String());

    if (enabled) {
      return NotificationService.instance.scheduleDailyReminder(hour, minute);
    }
    await NotificationService.instance.cancelDailyReminder();
    return true;
  }

  /// Dipanggil saat aplikasi dibuka: mencatat pengingat yang sudah lewat
  /// dan memasang ulang jadwal (aman dipanggil berulang).
  Future<void> restore() async {
    if (!_ready) return;
    await logMissedReminders();
    if (enabled) {
      await NotificationService.instance.scheduleDailyReminder(hour, minute);
    }
  }

  // ---------------------------------------------------------------
  // Riwayat
  // ---------------------------------------------------------------

  List<NotificationLog> get history {
    if (!_ready) return const [];
    final list = _history.values
        .whereType<Map>()
        .map(NotificationLog.fromMap)
        .toList();
    list.sort((a, b) => b.time.compareTo(a.time)); // terbaru di atas
    return list;
  }

  Future<void> addHistory(NotificationLog log) async {
    if (!_ready) return;
    await _history.add(log.toMap());
    // Simpan paling banyak 100 catatan; yang terlama dibuang.
    while (_history.length > _maxHistory) {
      await _history.deleteAt(0);
    }
    historyVersion.value++;
  }

  Future<void> clearHistory() async {
    if (!_ready) return;
    await _history.clear();
    historyVersion.value++;
  }

  /// Notifikasi terjadwal muncul saat aplikasi mungkin sedang tertutup,
  /// jadi tidak ada kode yang bisa mencatatnya pada saat itu juga.
  /// Sebagai gantinya, saat aplikasi dibuka kita mencatat setiap jam
  /// pengingat yang sudah terlewat sejak pengecekan terakhir (asumsi: terkirim).
  Future<void> logMissedReminders() async {
    if (!_ready) return;
    final now = DateTime.now();
    final last =
        DateTime.tryParse((_settings.get(_kLastCheck) ?? '') as String) ?? now;
    await _settings.put(_kLastCheck, now.toIso8601String());
    if (!enabled) return;

    var day = DateTime(last.year, last.month, last.day);
    var count = 0;
    while (!day.isAfter(now) && count < 14) {
      final fireAt = DateTime(day.year, day.month, day.day, hour, minute);
      if (fireAt.isAfter(last) && !fireAt.isAfter(now)) {
        await addHistory(
          NotificationLog(
            type: 'daily',
            title: NotificationService.dailyTitle,
            body: NotificationService.dailyBody,
            time: fireAt,
          ),
        );
        count++;
      }
      day = day.add(const Duration(days: 1));
    }
  }
}
