import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../../controllers/notification_settings_controller.dart';
import '../../core/constants/app_colors.dart';
import '../../services/notification_prefs_service.dart';

class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends State<NotificationSettingsScreen> {
  late final NotificationSettingsController _c;
  final _fmt = DateFormat('dd/MM/yyyy HH:mm');

  @override
  void initState() {
    super.initState();
    _c = Get.put(NotificationSettingsController());
  }

  @override
  void dispose() {
    Get.delete<NotificationSettingsController>();
    super.dispose();
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _toggle(bool value) async {
    final ok = await _c.setEnabled(value);
    if (!ok) {
      _snack('Pengingat gagal diatur. Periksa izin notifikasi dan alarm.');
    } else {
      _snack(
        value
            ? 'Pengingat diaktifkan setiap hari pukul ${_c.timeLabel}'
            : 'Pengingat dimatikan',
      );
    }
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _c.hour.value, minute: _c.minute.value),
      helpText: 'Jam pengingat stok harian',
    );
    if (picked == null) return;
    final ok = await _c.setTime(picked.hour, picked.minute);
    _snack(
      ok
          ? 'Pengingat diatur pukul ${_c.timeLabel}'
          : 'Jam gagal disimpan. Periksa izin notifikasi dan alarm.',
    );
  }

  Future<void> _confirmClear() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Hapus riwayat?'),
        content: const Text('Semua catatan notifikasi akan dihapus.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (yes == true) await _c.clearHistory();
  }

  IconData _icon(String type) => switch (type) {
    'low_stock' => Icons.warning_amber_rounded,
    'daily' => Icons.alarm_rounded,
    _ => Icons.notifications_active_outlined,
  };

  String _label(String type) => switch (type) {
    'low_stock' => 'Stok menipis',
    'daily' => 'Pengingat harian',
    _ => 'Tes',
  };

  Widget _historySection() {
    return Obx(() {
      final items = _c.history;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Riwayat notifikasi',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
              ),
              if (items.isNotEmpty)
                TextButton(
                  onPressed: _confirmClear,
                  child: const Text('Hapus semua'),
                ),
            ],
          ),
          const SizedBox(height: 4),
          if (items.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  'Belum ada notifikasi.',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ),
            )
          else
            for (final n in items)
              Card(
                child: ListTile(
                  leading: Icon(_icon(n.type), color: AppColors.yellow),
                  title: Text(n.title),
                  subtitle: Text(
                    '${n.body}\n${_label(n.type)} • ${_fmt.format(n.time)}',
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                  isThreeLine: true,
                ),
              ),
        ],
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pengaturan Notifikasi')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Column(
              children: [
                Obx(
                  () => SwitchListTile(
                    value: _c.enabled.value,
                    onChanged: _c.busy.value ? null : _toggle,
                    secondary: const Icon(
                      Icons.alarm_rounded,
                      color: AppColors.yellow,
                    ),
                    title: const Text('Pengingat stok harian'),
                    subtitle: const Text(
                      'Ingatkan untuk cek stok setiap hari.',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  ),
                ),
                const Divider(height: 1, color: AppColors.border),
                Obx(
                  () => ListTile(
                    enabled: _c.enabled.value && !_c.busy.value,
                    leading: const Icon(
                      Icons.schedule_rounded,
                      color: AppColors.yellow,
                    ),
                    title: const Text('Jam pengingat'),
                    subtitle: const Text(
                      'Notifikasi muncul pada jam ini setiap hari.',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                    trailing: Text(
                      _c.timeLabel,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    onTap: _pickTime,
                  ),
                ),
                const Divider(height: 1, color: AppColors.border),
                ListTile(
                  leading: const Icon(
                    Icons.notifications_active_outlined,
                    color: AppColors.yellow,
                  ),
                  title: const Text('Kirim notifikasi tes'),
                  onTap: () async {
                    await _c.sendTest();
                    _snack('Notifikasi tes dikirim');
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          ValueListenableBuilder<int>(
            valueListenable: NotificationPrefsService.instance.historyVersion,
            builder: (_, __, ___) => _historySection(),
          ),
        ],
      ),
    );
  }
}
