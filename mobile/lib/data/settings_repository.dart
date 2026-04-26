import 'package:shared_preferences/shared_preferences.dart';

class SettingsRepository {
  static const _kLogin = 'company_login';
  static const _kServer = 'server_base_url';

  Future<String?> getLogin() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_kLogin);
  }

  Future<void> setLogin(String v) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kLogin, v);
  }

  Future<String> getServerUrl() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_kServer) ?? '';
  }

  Future<void> setServerUrl(String v) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kServer, v);
  }
}
