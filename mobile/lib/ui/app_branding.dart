import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:dio/dio.dart';

import '../core/format_duration.dart';
import '../providers.dart';

/// См. `assets/branding/aist_logo.png` (оригинал 1453×1390, прозрачный фон).
const String kAistLogoAsset = 'assets/branding/aist_logo.png';

/// Соотношение сторон логотипа (ширина / высота) для корректного масштаба в шапке.
const double kAistLogoAspect = 1453 / 1390;

const String kAppTitle = 'АИСТ';

/// Заголовок с логотипом для AppBar.
class AistAppBarTitle extends ConsumerStatefulWidget {
  const AistAppBarTitle({super.key, this.logoHeight = 36});

  final double logoHeight;

  @override
  ConsumerState<AistAppBarTitle> createState() => _AistAppBarTitleState();
}

class _AistAppBarTitleState extends ConsumerState<AistAppBarTitle> {
  int _tapCount = 0;
  DateTime? _firstTapAt;

  Future<void> _onLogoTap() async {
    final now = DateTime.now();
    final first = _firstTapAt;
    if (first == null || now.difference(first) > const Duration(seconds: 2)) {
      _tapCount = 0;
      _firstTapAt = now;
    }

    _tapCount++;
    if (_tapCount < 3) return;

    _tapCount = 0;
    _firstTapAt = null;

    final settings = ref.read(settingsRepositoryProvider);
    final server = (await settings.getServerUrl()).trim().replaceAll(RegExp(r'/$'), '');
    if (server.isEmpty) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Последние 10 записей'),
          content: const Text('Укажите адрес сервера в настройках.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Закрыть'),
            ),
          ],
        ),
      );
      return;
    }

    final dio = ref.read(dioProvider);
    List<_RecentServerMeeting> last = const [];
    String? errorText;
    try {
      final resp = await dio.get<Map<String, dynamic>>(
        '$server/api/v1/meetings/recent',
        queryParameters: const {'limit': 10},
      );
      final data = resp.data ?? const <String, dynamic>{};
      final items = (data['items'] as List<dynamic>? ?? const <dynamic>[])
          .cast<Map<String, dynamic>>();
      last = items.map(_RecentServerMeeting.fromJson).toList();
    } catch (e) {
      if (e is DioException) {
        final status = e.response?.statusCode;
        if (status == 404) {
          errorText =
              'Сервер доступен, но не поддерживает получение последних записей. Возможно, сервер не обновлён.';
        } else if (e.type == DioExceptionType.connectionTimeout ||
            e.type == DioExceptionType.sendTimeout ||
            e.type == DioExceptionType.receiveTimeout ||
            e.type == DioExceptionType.connectionError) {
          errorText =
              'Не удалось подключиться к серверу. Проверьте адрес сервера и доступ по сети/VPN.';
        } else {
          errorText = 'Ошибка сервера: ${e.message ?? e.type}';
        }
      } else {
        errorText = 'Ошибка: $e';
      }
    }
    if (!mounted) return;

    final fmt = DateFormat('dd.MM.yy HH:mm');
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Последние 10 записей'),
        content: SizedBox(
          width: 420,
          child: errorText != null
              ? Text(errorText!)
              : last.isEmpty
                  ? const Text('Записей пока нет')
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: last.length,
                  separatorBuilder: (_, __) => const Divider(height: 16),
                  itemBuilder: (_, i) {
                    final m = last[i];
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          m.userLogin,
                          style: Theme.of(ctx).textTheme.titleSmall,
                        ),
                        Text('Когда: ${fmt.format(m.startedAt.toLocal())}'),
                        Text(
                          'Длительность: ${formatDurationSeconds(m.durationSeconds)}',
                        ),
                      ],
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Закрыть'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.titleLarge;
    final logoW = widget.logoHeight * kAistLogoAspect;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: _onLogoTap,
          child: SizedBox(
            height: widget.logoHeight,
            width: logoW,
            child: Image.asset(
              kAistLogoAsset,
              fit: BoxFit.contain,
              alignment: Alignment.centerLeft,
              filterQuality: FilterQuality.high,
              isAntiAlias: true,
              gaplessPlayback: true,
              errorBuilder: (context, error, stackTrace) {
                return Icon(
                  Icons.broken_image_outlined,
                  size: widget.logoHeight * 0.85,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                );
              },
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text(kAppTitle, style: style),
      ],
    );
  }
}

class _RecentServerMeeting {
  const _RecentServerMeeting({
    required this.userLogin,
    required this.startedAt,
    required this.durationSeconds,
  });

  final String userLogin;
  final DateTime startedAt;
  final int durationSeconds;

  static _RecentServerMeeting fromJson(Map<String, dynamic> json) {
    final startedRaw = (json['startedAt'] as String?) ?? '';
    final started = DateTime.tryParse(startedRaw) ?? DateTime.fromMillisecondsSinceEpoch(0);
    return _RecentServerMeeting(
      userLogin: (json['userLogin'] as String?) ?? 'unknown',
      startedAt: started,
      durationSeconds: (json['durationSeconds'] as num?)?.toInt() ?? 0,
    );
  }
}
