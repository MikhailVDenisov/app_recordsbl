import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../providers.dart';
import 'app_branding.dart';

final _loginRe = RegExp(r'^[A-Za-z0-9-]+\.[A-Za-z0-9-]+$');

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
  String? _appVersionLabel;
  Timer? _autosaveDebounce;
  bool _dirty = false;
  DateTime? _lastSavedAt;

  @override
  void initState() {
    super.initState();
    _load();
    _login.addListener(_scheduleAutosave);
    _server.addListener(_scheduleAutosave);
  }

  Future<void> _load() async {
    final s = ref.read(settingsRepositoryProvider);
    _login.text = await s.getLogin() ?? '';
    _server.text = await s.getServerUrl();
    try {
      final info = await PackageInfo.fromPlatform();
      final v = info.version;
      final b = info.buildNumber;
      _appVersionLabel = (b.isEmpty) ? v : '$v ($b)';
    } catch (_) {
      _appVersionLabel = null;
    }
    setState(() {});
  }

  @override
  void dispose() {
    _autosaveDebounce?.cancel();
    _login.dispose();
    _server.dispose();
    super.dispose();
  }

  String _normalizeBase(String raw) => raw.trim().replaceAll(RegExp(r'/$'), '');

  void _scheduleAutosave() {
    // If we are still loading initial values, avoid marking dirty.
    if (!mounted) return;
    _dirty = true;
    _autosaveDebounce?.cancel();
    _autosaveDebounce = Timer(const Duration(milliseconds: 500), () {
      unawaited(_autosaveIfValid());
    });
    setState(() {});
  }

  Future<void> _autosaveIfValid({bool immediate = false}) async {
    if (!mounted) return;
    if (!_dirty && !immediate) return;
    final form = _form.currentState;
    if (form == null) return;

    // Don't save invalid input (user still typing).
    if (!form.validate()) return;

    final s = ref.read(settingsRepositoryProvider);
    final login = _login.text.trim();
    final server = _server.text.trim();
    await s.setLogin(login);
    await s.setServerUrl(server);

    if (!mounted) return;
    _dirty = false;
    _lastSavedAt = DateTime.now();
    setState(() {});
  }

  ({String user, String support}) _friendlyNetworkError(Object e) {
    // Text for user + a compact block user can forward to support.
    if (e is DioException) {
      final status = e.response?.statusCode;
      if (status == 404) {
        return (
          user:
              'Сервер доступен, но не поддерживает проверку. Возможно, сервер не обновлён.',
          support:
              'code=HTTP_404\nroute=GET /api/v1/health/check\nserver=${_normalizeBase(_server.text)}',
        );
      }

      final type = e.type;
      if (type == DioExceptionType.connectionTimeout ||
          type == DioExceptionType.sendTimeout ||
          type == DioExceptionType.receiveTimeout) {
        return (
          user:
              'Не удалось подключиться к серверу: превышено время ожидания. Проверьте адрес сервера и доступ по сети/VPN.',
          support:
              'code=TIMEOUT\ntype=$type\nserver=${_normalizeBase(_server.text)}\nmessage=${e.message ?? ""}',
        );
      }

      if (type == DioExceptionType.connectionError) {
        return (
          user:
              'Не удалось подключиться к серверу. Проверьте адрес сервера и доступ по сети/VPN.',
          support:
              'code=CONNECTION_ERROR\ntype=$type\nserver=${_normalizeBase(_server.text)}\nmessage=${e.message ?? ""}\nerror=${e.error ?? ""}',
        );
      }

      final d = e.response?.data;
      final serverMsg =
          (d is Map && d['message'] is String) ? (d['message'] as String) : null;
      return (
        user: serverMsg ?? 'Ошибка при обращении к серверу.',
        support:
            'code=HTTP_${status ?? "unknown"}\ntype=$type\nserver=${_normalizeBase(_server.text)}\nmessage=${serverMsg ?? e.message ?? ""}',
      );
    }

    return (
      user:
          'Не удалось выполнить проверку. Проверьте подключение к сети и адрес сервера.',
      support:
          'code=UNKNOWN\nserver=${_normalizeBase(_server.text)}\nerror=${e.toString()}',
    );
  }

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
      final f = _friendlyNetworkError(e);
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Ошибка'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(f.user),
              const SizedBox(height: 12),
              Text(
                'Информация для поддержки:',
                style: Theme.of(ctx).textTheme.labelLarge,
              ),
              const SizedBox(height: 6),
              Text(
                f.support,
                style: Theme.of(ctx).textTheme.bodySmall,
              ),
            ],
          ),
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
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: IntrinsicHeight(
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
                              return 'Формат: XXX.XX (латиница/цифры/тире; точка обязательна)';
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
                                onFieldSubmitted: (_) => unawaited(_autosaveIfValid(immediate: true)),
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
                        Text(
                          _dirty
                              ? 'Изменения будут сохранены автоматически…'
                              : (_lastSavedAt != null
                                  ? 'Сохранено'
                                  : 'Изменения сохраняются автоматически'),
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                        ),
                        const SizedBox(height: 16),
                        OutlinedButton(
                          onPressed: _refreshMeetingPlaces,
                          child: const Text('Обновить список мест встречи'),
                        ),
                        const SizedBox(height: 12),
                        if (_appVersionLabel != null)
                          Text(
                            'Версия: $_appVersionLabel',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color:
                                      Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                          ),
                        const Spacer(),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
