import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/meeting_model.dart';

/// Открывает панель воспроизведения с таймлайном и управлением.
Future<void> openMeetingPlayback(BuildContext context, Meeting meeting) async {
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (ctx) => MeetingPlaybackSheet(meeting: meeting),
  );
}

class MeetingPlaybackSheet extends StatefulWidget {
  const MeetingPlaybackSheet({super.key, required this.meeting});

  final Meeting meeting;

  @override
  State<MeetingPlaybackSheet> createState() => _MeetingPlaybackSheetState();
}

class _MeetingPlaybackSheetState extends State<MeetingPlaybackSheet> {
  late final AudioPlayer _player;
  final List<StreamSubscription<dynamic>> _subs = [];

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  PlayerState _playerState = PlayerState.stopped;
  bool _dragging = false;
  double _dragValueMs = 0;

  @override
  void initState() {
    super.initState();
    _player = AudioPlayer();
    _init();
  }

  Future<void> _init() async {
    final path = widget.meeting.filePath;
    if (!await File(path).exists()) {
      if (mounted) Navigator.of(context).pop();
      return;
    }

    _subs.add(_player.onPositionChanged.listen((d) {
      if (!_dragging && mounted) setState(() => _position = d);
    }));
    _subs.add(_player.onDurationChanged.listen((d) {
      if (mounted) setState(() => _duration = d);
    }));
    _subs.add(_player.onPlayerStateChanged.listen((s) {
      if (!mounted) return;
      setState(() {
        _playerState = s;
        if (s == PlayerState.completed && _duration > Duration.zero) {
          _position = _duration;
        }
      });
    }));

    try {
      await _player.play(DeviceFileSource(path));
      final d = await _player.getDuration();
      if (d != null && mounted) setState(() => _duration = d);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e')),
        );
        Navigator.of(context).pop();
      }
    }
  }

  Future<void> _togglePlayPause() async {
    if (_playerState == PlayerState.completed) {
      await _player.seek(Duration.zero);
      await _player.resume();
      return;
    }
    if (_playerState == PlayerState.playing) {
      await _player.pause();
    } else {
      await _player.resume();
    }
  }

  Future<void> _seekRelative(int seconds) async {
    final total = _duration.inMilliseconds > 0 ? _duration : const Duration(days: 1);
    var target = _position + Duration(seconds: seconds);
    if (target.isNegative) target = Duration.zero;
    if (target > total) target = total;
    await _player.seek(target);
  }

  Future<void> _onSeekSlider(double ms) async {
    await _player.seek(Duration(milliseconds: ms.round()));
  }

  Future<void> _stopAndClose() async {
    await _player.stop();
    if (mounted) Navigator.of(context).pop();
  }

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (h > 0) return '$h:$m:$s';
    return '$m:$s';
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    unawaited(_player.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final maxMs = _duration.inMilliseconds > 0
        ? _duration.inMilliseconds.toDouble()
        : 1.0;
    final posMs = _position.inMilliseconds
        .clamp(0, _duration.inMilliseconds > 0 ? _duration.inMilliseconds : 0)
        .toDouble();
    final sliderValue = _dragging ? _dragValueMs : posMs;

    final playing = _playerState == PlayerState.playing;
    final startedTitle =
        DateFormat('dd.MM.yy HH:mm').format(widget.meeting.startedAt.toLocal());

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 8,
        bottom: 16 + MediaQuery.paddingOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            startedTitle,
            style: Theme.of(context).textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            widget.meeting.meetingPlace,
            style: Theme.of(context).textTheme.bodySmall,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(_fmt(_position), style: Theme.of(context).textTheme.bodyMedium),
              Text(_fmt(_duration), style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
          Slider(
            value: sliderValue.clamp(0, maxMs),
            max: maxMs,
            onChangeStart: (_) {
              setState(() {
                _dragging = true;
                _dragValueMs = posMs;
              });
            },
            onChanged: (v) {
              setState(() => _dragValueMs = v);
            },
            onChangeEnd: (v) async {
              setState(() => _dragging = false);
              await _onSeekSlider(v);
            },
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton.filledTonal(
                iconSize: 36,
                onPressed: () => _seekRelative(-10),
                icon: const Icon(Icons.replay_10),
                tooltip: 'Назад 10 с',
              ),
              const SizedBox(width: 12),
              IconButton.filled(
                iconSize: 48,
                onPressed: _togglePlayPause,
                icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                tooltip: playing ? 'Пауза' : 'Воспроизведение',
              ),
              const SizedBox(width: 12),
              IconButton.filledTonal(
                iconSize: 36,
                onPressed: () => _seekRelative(10),
                icon: const Icon(Icons.forward_10),
                tooltip: 'Вперёд 10 с',
              ),
              const SizedBox(width: 12),
              IconButton(
                iconSize: 32,
                onPressed: _stopAndClose,
                icon: const Icon(Icons.stop),
                tooltip: 'Остановить и закрыть',
              ),
            ],
          ),
        ],
      ),
    );
  }
}
