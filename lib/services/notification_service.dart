import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../models/product_model.dart';
import 'notification_prefs_service.dart';

/// Pembungkus flutter_local_notifications. Dua jenis notifikasi:
/// 1) produk yang stoknya mencapai batas minimum (PBI-09.2), tampil langsung;
/// 2) pengingat cek stok harian pada jam yang dipilih pengguna (terjadwal).
/// Semua pemanggilan aman: kegagalan hanya dicatat, tidak membuat aplikasi crash.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  static const _channelId = 'low_stock';
  static const _channelName = 'Stok menipis';
  static const _channelDesc =
      'Pemberitahuan saat stok produk mencapai batas minimum';

  static const _dailyChannelId = 'daily_reminder';
  static const _dailyChannelName = 'Pengingat harian';
  static const _dailyChannelDesc = 'Pengingat cek stok pada jam yang dipilih';
  static const _dailyId = 1001;

  static const dailyTitle = 'Waktunya cek stok';
  static const dailyBody =
      'Buka Noir untuk melihat produk yang stoknya menipis hari ini.';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _ready = false;

  /// Menyiapkan plugin. Aman dipanggil berulang.
  Future<void> init() async {
    if (_ready) return;
    await _initTimeZone();
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
      );
      _ready = true;
    } catch (e) {
      debugPrint('Notifikasi gagal diinisialisasi: $e');
    }
  }

  /// Zona waktu perangkat, dipakai untuk jadwal harian. Jika gagal dibaca,
  /// dipakai Asia/Jakarta agar jadwal tetap berjalan.
  Future<void> _initTimeZone() async {
    try {
      tzdata.initializeTimeZones();
      final name = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(name));
    } catch (e) {
      debugPrint('Zona waktu perangkat gagal dibaca: $e');
      try {
        tz.setLocalLocation(tz.getLocation('Asia/Jakarta'));
      } catch (_) {}
    }
  }

  /// Android 13+ meminta izin POST_NOTIFICATIONS saat runtime.
  /// Mengembalikan true jika diizinkan (atau tidak perlu izin).
  Future<bool> requestPermission() async {
    try {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      final granted = await android?.requestNotificationsPermission();
      return granted ?? true;
    } catch (e) {
      debugPrint('Izin notifikasi gagal diminta: $e');
      return false;
    }
  }

  /// Menampilkan satu notifikasi untuk produk yang BARU menipis.
  /// Satu produk: nama dan sisa stok. Beberapa produk: ringkasan berisi daftar.
  Future<void> showLowStock(List<ProductModel> products) async {
    if (products.isEmpty) return;
    if (!_ready) await init();
    if (!_ready) return;

    final String title;
    final String body;
    InboxStyleInformation? style;

    if (products.length == 1) {
      final p = products.first;
      title = p.isOutOfStock ? 'Stok habis' : 'Stok menipis';
      body = '${p.name}: sisa ${p.stock} (minimum ${p.minStock})';
    } else {
      title = '${products.length} produk stoknya menipis';
      final lines = products
          .take(6)
          .map((p) => '${p.name}: sisa ${p.stock}/${p.minStock}')
          .toList();
      if (products.length > 6) {
        lines.add('dan ${products.length - 6} produk lainnya');
      }
      body = lines.first;
      style = InboxStyleInformation(
        lines,
        contentTitle: title,
        summaryText: 'Stok menipis',
      );
    }

    try {
      await _plugin.show(
        id: _newId(),
        title: title,
        body: body,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            channelDescription: _channelDesc,
            importance: Importance.high,
            priority: Priority.high,
            styleInformation: style,
          ),
        ),
      );
      await NotificationPrefsService.instance.addHistory(
        NotificationLog(
          type: 'low_stock',
          title: title,
          body: products.length == 1
              ? body
              : products
                    .take(6)
                    .map((p) => '${p.name}: sisa ${p.stock}/${p.minStock}')
                    .join('\n'),
          time: DateTime.now(),
        ),
      );
    } catch (e) {
      debugPrint('Notifikasi gagal ditampilkan: $e');
    }
  }

  // ------------------------------------------------------------------
  // Pengingat harian (terjadwal)
  // ------------------------------------------------------------------

  /// Jadwal berikutnya untuk jam:menit hari ini, atau besok jika sudah lewat.
  tz.TZDateTime _nextInstance(int hour, int minute) {
    final now = tz.TZDateTime.now(tz.local);
    var at = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (!at.isAfter(now)) at = at.add(const Duration(days: 1));
    return at;
  }

  /// Memasang pengingat yang berulang setiap hari pada [hour]:[minute].
  /// Memakai id tetap, jadi memanggil lagi akan menggantikan jadwal lama.
  /// Mengembalikan false jika gagal.
  Future<bool> scheduleDailyReminder(int hour, int minute) async {
    if (!_ready) await init();
    if (!_ready) return false;

    try {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();

      // Alarm tepat waktu butuh izin khusus di Android 12+.
      // Jika belum diizinkan, minta sekali; kalau tetap ditolak, jam bisa
      // meleset beberapa menit (mode inexact) tetapi notifikasi tetap tampil.
      var exact = await android?.canScheduleExactNotifications() ?? true;
      if (!exact) {
        await android?.requestExactAlarmsPermission();
        exact = await android?.canScheduleExactNotifications() ?? false;
      }

      await _plugin.zonedSchedule(
        id: _dailyId,
        title: dailyTitle,
        body: dailyBody,
        scheduledDate: _nextInstance(hour, minute),
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            _dailyChannelId,
            _dailyChannelName,
            channelDescription: _dailyChannelDesc,
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
        androidScheduleMode: exact
            ? AndroidScheduleMode.exactAllowWhileIdle
            : AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time, // ulang tiap hari
      );
      return true;
    } catch (e) {
      debugPrint('Pengingat harian gagal dijadwalkan: $e');
      return false;
    }
  }

  Future<void> cancelDailyReminder() async {
    try {
      await _plugin.cancel(id: _dailyId);
    } catch (e) {
      debugPrint('Pengingat harian gagal dibatalkan: $e');
    }
  }

  /// Menampilkan notifikasi pengingat sekarang juga (untuk mencoba).
  Future<void> showTestReminder() async {
    if (!_ready) await init();
    if (!_ready) return;
    try {
      await _plugin.show(
        id: _newId(),
        title: dailyTitle,
        body: dailyBody,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            _dailyChannelId,
            _dailyChannelName,
            channelDescription: _dailyChannelDesc,
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
      );
      await NotificationPrefsService.instance.addHistory(
        NotificationLog(
          type: 'test',
          title: dailyTitle,
          body: '$dailyBody (tes)',
          time: DateTime.now(),
        ),
      );
    } catch (e) {
      debugPrint('Notifikasi tes gagal ditampilkan: $e');
    }
  }

  /// ID unik per notifikasi agar yang lama tidak tertimpa.
  int _newId() => (DateTime.now().millisecondsSinceEpoch ~/ 1000) & 0x7fffffff;
}
