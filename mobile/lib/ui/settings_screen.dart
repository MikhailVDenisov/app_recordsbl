import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';

import '../providers.dart';
import 'app_branding.dart';

final _loginRe = RegExp(r'^[A-Za-z0-9-]{3}\.[A-Za-z0-9-]{2}$');

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _login = TextEditingController();
  final _server = TextEditingController();
  final _form = GlobalKey<FormState>();
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = ref.read(settingsRepositoryProvider);
    _login.text = await s.getLogin() ?? '';
    _server.text = await s.getServerUrl();
    setState(() {});
  }

  @override
  void dispose() {
    _login.dispose();
    _server.dispose();
    super.dispose();
  }

  String _normalizeBase(String raw) => raw.trim().replaceAll(RegExp(r'/$'), '');

  Future<void> _checkServer() async {
    if (_checking) return;
    final base = _normalizeBase(_server.text);
    if (base.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Укажите адрес сервера')),
      );
      return;
    }
    setState(() => _checking = true);
    try {
      final dio = ref.read(dioProvider);
      final resp = await dio.get<Map<String, dynamic>>('$base/api/v1/health/check');
      final data = resp.data ?? const <String, dynamic>{};
      final ok = data['ok'] == true;
      final message = (data['message'] as String?) ?? (ok ? 'Проверка прошла успешно' : 'Ошибка');
      if (context.mounted) {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(ok ? 'Проверка прошла успешно' : 'Ошибка'),
            content: Text(ok ? 'Проверка прошла успешно' : message),
            actions: [
              TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Ок')),
            ],
          ),
        );
      }
    } catch (e) {
      String details = 'Сервер недоступен';
      if (e is DioException) {
        final status = e.response?.statusCode;
        if (status == 404) {
          details =
              'Сервер доступен, но не поддерживает проверку (маршрут /api/v1/health/check не найден). '
              'Возможно, сервер не обновлён. Передайте это сообщение в поддержку.';
        }
        final d = e.response?.data;
        if (status != 404 && d is Map && d['message'] is String) {
          details = d['message'] as String;
        } else if (status != 404) {
          details = '${e.message ?? e.error ?? e.type}';
        }
      } else {
        details = e.toString();
      }
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Ошибка'),
          content: Text(details),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Ок')),
          ],
        ),
      );
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _refreshMeetingPlaces() async {
    try {
      final svc = ref.read(meetingPlacesServiceProvider);
      await svc.ensureServerReachable();
      final r = await svc.refreshFromServer();
      ref.invalidate(meetingPlacesProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Места обновлены. Добавлено: ${r.added}, удалено: ${r.removed}, изменено: ${r.changed}',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      String msg = 'Ошибка обновления мест';
      if (e is DioException) {
        msg = 'Сервер недоступен: ${e.message ?? e.error ?? e.type}';
      } else if (e is StateError) {
        msg = e.message;
      } else {
        msg = 'Ошибка: $e';
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const AistAppBarTitle()),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Настройки',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _login,
                decoration: const InputDecoration(
                  labelText: 'Логин в сети компании',
                  hintText: 'XXX.XX',
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) {
                    return 'Укажите логин';
                  }
                  if (!_loginRe.hasMatch(v)) {
                    return 'Формат: XXX.XX (латиница/цифры/тире)';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _server,
                      decoration: const InputDecoration(
                        labelText: 'Адрес сервера',
                        hintText: 'https://vm.example.com:3000',
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) {
                          return 'Укажите адрес сервера';
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: FilledButton.tonal(
                      onPressed: _checking ? null : _checkServer,
                      child: Text(_checking ? 'Проверяем…' : 'Проверить'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () async {
                  if (!_form.currentState!.validate()) return;
                  final s = ref.read(settingsRepositoryProvider);
                  await s.setLogin(_login.text.trim());
                  await s.setServerUrl(_server.text.trim());
                  if (context.mounted) Navigator.of(context).pop();
                },
                child: const Text('Сохранить'),
              ),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: _refreshMeetingPlaces,
                child: const Text('Обновить список мест встречи'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
