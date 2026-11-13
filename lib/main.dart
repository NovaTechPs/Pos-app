import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:path_provider/path_provider.dart';

import 'screens/login_screen.dart';
import 'screens/pos_shell.dart';
import 'services/api_client.dart';
import 'services/offline_store.dart';
import 'services/theme_service.dart';
import 'services/windows_key_storage_stub.dart'
    if (dart.library.ffi) 'services/windows_key_storage.dart';
import 'theme/app_theme.dart';
import 'widgets/popup_arrow_navigation.dart';
import 'screens/sync_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // dart:io Platform checks throw on web.
  if (!kIsWeb) await WindowsKeyStorage.install();
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    try {
      final support = await getApplicationSupportDirectory();
      await OfflineStore.useFileCache(
        '${support.path}${Platform.pathSeparator}offline_cache',
      );
    } catch (_) {
      // Fall back to secure storage snapshots if the directory is unavailable.
    }
  }
  await ApiClient.initialize();
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  static void setTheme(BuildContext context, String themeName) {
    context.findAncestorStateOfType<_MyAppState>()?._setTheme(themeName);
  }

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  String _themeName = 'blue';
  final _navigatorKey = GlobalKey<NavigatorState>();
  final _popupFocus = PopupAutoFocusObserver();

  @override
  void initState() {
    super.initState();
    if (ApiClient.user != null) {
      ThemeService()
          .fetchTheme(int.tryParse('${ApiClient.user?['tenant_id']}'))
          .then((name) {
            if (mounted) _setTheme(name);
          });
    }
  }

  Future<void> _signInAgain() async {
    try {
      await ApiClient.clearSession();
    } catch (_) {
      // Memory is cleared even when the device cannot remove its stored session.
    }
    if (!mounted) return;
    _navigatorKey.currentState?.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => LoginScreen(onThemeChanged: _setTheme)),
      (_) => false,
    );
  }

  void _setTheme(String themeName) {
    if (!const {'blue', 'orange', 'green'}.contains(themeName)) return;
    setState(() => _themeName = themeName);
  }

  @override
  Widget build(BuildContext context) {
    final user = ApiClient.user;
    final home = user == null
        ? LoginScreen(onThemeChanged: _setTheme)
        : PosShell(user: user);
    return MaterialApp(
      title: 'Wasla POS',
      navigatorKey: _navigatorKey,
      navigatorObservers: [_popupFocus],
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightFor(_themeName),
      builder: (context, child) => Directionality(
        textDirection: TextDirection.rtl,
        child: ValueListenableBuilder<bool>(
          valueListenable: ApiClient.sessionExpired,
          builder: (context, expired, _) => Column(
            children: [
              ValueListenableBuilder<bool>(
                valueListenable: ApiClient.offline,
                builder: (context, offline, _) => offline
                    ? Material(
                        color: const Color(0xFFFEF3C7),
                        child: SafeArea(
                          bottom: false,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 4,
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.cloud_off_outlined, size: 18),
                                const SizedBox(width: 8),
                                const Expanded(
                                  child: Text(
                                    'دون اتصال — بيانات محفوظة على الجهاز',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                ),
                                TextButton(
                                  onPressed: () =>
                                      _navigatorKey.currentState?.push(
                                        MaterialPageRoute<void>(
                                          builder: (_) => const SyncScreen(),
                                        ),
                                      ),
                                  child: const Text('المزامنة'),
                                ),
                              ],
                            ),
                          ),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
              if (expired)
                Material(
                  color: Theme.of(context).colorScheme.errorContainer,
                  child: SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'انتهت الجلسة. عمليات البيع المحفوظة محلياً ستبقى للمراجعة.',
                            ),
                          ),
                          TextButton(
                            onPressed: _signInAgain,
                            child: const Text('تسجيل الدخول'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              Expanded(
                child: AbsorbPointer(
                  absorbing: expired,
                  child: PopupArrowNavigation(
                    child: child ?? const SizedBox.shrink(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      home: home,
    );
  }
}
