import 'package:get/get.dart';

import '../services/notification_prefs_service.dart';
import '../services/notification_service.dart';

/// Keadaan layar Pengaturan Notifikasi. Data disimpan di Hive lewat
/// [NotificationPrefsService]; SQLite dan Supabase tidak dipakai.
class NotificationSettingsController extends GetxController {
  final _prefs = NotificationPrefsService.instance;

  final enabled = false.obs;
  final hour = 8.obs;
  final minute = 0.obs;
  final history = <NotificationLog>[].obs;
  final busy = false.obs;

  String get timeLabel =>
      '${hour.value.toString().padLeft(2, '0')}:${minute.value.toString().padLeft(2, '0')}';

  @override
  void onInit() {
    super.onInit();
    _prefs.historyVersion.addListener(_loadHistory);
    _init();
  }

  @override
  void onClose() {
    _prefs.historyVersion.removeListener(_loadHistory);
    super.onClose();
  }

  Future<void> _init() async {
    // Catat pengingat yang terlewat saat aplikasi tertutup, lalu tampilkan.
    await _prefs.logMissedReminders();
    enabled.value = _prefs.enabled;
    hour.value = _prefs.hour;
    minute.value = _prefs.minute;
    _loadHistory();
  }

  void _loadHistory() => history.assignAll(_prefs.history);

  /// Mengembalikan false jika jadwal gagal dipasang.
  Future<bool> setEnabled(bool value) async {
    if (busy.value) return true;
    busy.value = true;
    try {
      final ok = await _prefs.saveDaily(
        enabled: value,
        hour: hour.value,
        minute: minute.value,
      );
      if (ok) enabled.value = value;
      return ok;
    } finally {
      busy.value = false;
    }
  }

  Future<bool> setTime(int h, int m) async {
    if (busy.value) return true;
    busy.value = true;
    try {
      final ok = await _prefs.saveDaily(
        enabled: enabled.value,
        hour: h,
        minute: m,
      );
      if (ok) {
        hour.value = h;
        minute.value = m;
      }
      return ok;
    } finally {
      busy.value = false;
    }
  }

  Future<void> sendTest() => NotificationService.instance.showTestReminder();

  Future<void> clearHistory() => _prefs.clearHistory();
}
