import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import 'app_branding.dart';

final _loginRe = RegExp(r'^[a-zA-Z0-9._@-]+$');

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _login = TextEditingController();
  final _server = TextEditingController();
  final _form = GlobalKey<FormState>();

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
                  hintText: 'латиница, цифры и символы',
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) {
                    return 'Укажите логин';
                  }
                  if (!_loginRe.hasMatch(v)) {
                    return 'Только латиница, цифры и ._@-';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _server,
                decoration: const InputDecoration(
                  labelText: 'URL сервера API',
                  hintText: 'https://api.example.com',
                ),
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
            ],
          ),
        ),
      ),
    );
  }
}
