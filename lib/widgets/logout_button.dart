import 'package:flutter/material.dart';

import '../main.dart';
import '../screens/login_screen.dart';
import '../services/auth_service.dart';

class LogoutButton extends StatefulWidget {
  const LogoutButton({super.key});

  static Future<void> logout(BuildContext context) async {
    try {
      await AuthService().logout();
    } catch (_) {
      // Local session clearing also works when the server is unreachable.
    }
    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
      MaterialPageRoute<void>(
        builder: (context) => Directionality(
          textDirection: TextDirection.rtl,
          child: LoginScreen(
            onThemeChanged: (theme) => MyApp.setTheme(context, theme),
          ),
        ),
      ),
      (_) => false,
    );
  }

  @override
  State<LogoutButton> createState() => _LogoutButtonState();
}

class _LogoutButtonState extends State<LogoutButton> {
  bool _busy = false;

  Future<void> _logout() async {
    if (_busy) return;
    setState(() => _busy = true);
    await LogoutButton.logout(context);
  }

  @override
  Widget build(BuildContext context) => TextButton.icon(
    onPressed: _busy ? null : _logout,
    icon: _busy
        ? const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : const Icon(Icons.logout_rounded),
    label: const Text('تسجيل الخروج'),
  );
}
