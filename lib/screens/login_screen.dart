import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../services/auth_service.dart';
import '../services/api_client.dart';
import '../services/branch_service.dart';
import '../services/theme_service.dart';
import 'pos_shell.dart';

class LoginScreen extends StatefulWidget {
  final ValueChanged<String> onThemeChanged;

  const LoginScreen({super.key, required this.onThemeChanged});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _twoFactorController = TextEditingController();
  final _authService = AuthService();
  bool _isLoading = false;
  bool _hidePassword = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _errorMessage = ApiClient.initializationError;
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _twoFactorController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (_isLoading) return;
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final result = await _authService.login(
      _emailController.text.trim(),
      _passwordController.text,
      code: _twoFactorController.text.trim(),
    );
    if (result['success'] == true && result['user'] is Map<String, dynamic>) {
      final user = result['user'] as Map<String, dynamic>;
      if (user['branch_id'] == null) {
        try {
          final branches = await BranchService().fetchBranches();
          if (branches.length == 1) {
            user['branch_id'] = branches.first['id'];
            await ApiClient.saveSession(
              token: ApiClient.token!,
              session: {...ApiClient.session!, 'user': user},
            );
          } else if (branches.length > 1) {
            if (!mounted) return;
            final selectedBranch = await showDialog<Map<String, dynamic>>(
              context: context,
              barrierDismissible: false,
              builder: (context) => AlertDialog(
                title: const Text('اختر الفرع'),
                content: SizedBox(
                  width: 360,
                  child: ListView(
                    shrinkWrap: true,
                    children: branches
                        .map(
                          (branch) => ListTile(
                            title: Text(branch['name']?.toString() ?? 'فرع'),
                            onTap: () => Navigator.pop(context, branch),
                          ),
                        )
                        .toList(),
                  ),
                ),
              ),
            );
            if (selectedBranch != null) {
              user['branch_id'] = selectedBranch['id'];
              await ApiClient.saveSession(
                token: ApiClient.token!,
                session: {...ApiClient.session!, 'user': user},
              );
            }
          }
          if (user['branch_id'] == null) {
            throw Exception('لم يتم العثور على فرع متاح لهذا المستخدم.');
          }
        } catch (error) {
          if (!mounted) return;
          setState(() {
            _isLoading = false;
            _errorMessage = 'تعذر تحميل الفروع: $error';
          });
          return;
        }
      }
      final tenantId = int.tryParse(user['tenant_id']?.toString() ?? '');
      if (!mounted) return;
      // Opening the POS must not wait for a cosmetic settings request.
      unawaited(
        ThemeService().fetchTheme(tenantId).then(widget.onThemeChanged),
      );
      setState(() => _isLoading = false);
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => PosShell(user: user)),
      );
    } else {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage =
            result['message']?.toString() ??
            'تعذر تسجيل الدخول. حاول مرة أخرى.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Center(
                          child: SvgPicture.asset(
                            'assets/images/wasla-logo.svg',
                            height: 76,
                          ),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          'مرحباً بعودتك',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'سجّل الدخول للمتابعة إلى نظام وصلة',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.blueGrey.shade600),
                        ),
                        const SizedBox(height: 26),
                        if (_errorMessage != null) ...[
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.red.shade50,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              _errorMessage!,
                              style: TextStyle(color: Colors.red.shade800),
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                        TextFormField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'البريد الإلكتروني',
                            prefixIcon: Icon(Icons.alternate_email_rounded),
                          ),
                          validator: (value) =>
                              value == null || value.trim().isEmpty
                              ? 'أدخل البريد الإلكتروني'
                              : null,
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _passwordController,
                          obscureText: _hidePassword,
                          textInputAction: TextInputAction.done,
                          onFieldSubmitted: (_) => _handleLogin(),
                          decoration: InputDecoration(
                            labelText: 'كلمة المرور',
                            prefixIcon: const Icon(Icons.lock_outline_rounded),
                            suffixIcon: IconButton(
                              onPressed: () => setState(
                                () => _hidePassword = !_hidePassword,
                              ),
                              icon: Icon(
                                _hidePassword
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                              ),
                            ),
                          ),
                          validator: (value) => value == null || value.isEmpty
                              ? 'أدخل كلمة المرور'
                              : null,
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _twoFactorController,
                          keyboardType: TextInputType.number,
                          textDirection: TextDirection.ltr,
                          maxLength: 6,
                          decoration: const InputDecoration(
                            labelText: 'رمز المصادقة الثنائية (إن كان مفعلاً)',
                            counterText: '',
                          ),
                          validator: (value) =>
                              value != null &&
                                  value.isNotEmpty &&
                                  !RegExp(r'^\d{6}$').hasMatch(value)
                              ? 'أدخل الرمز المكوّن من 6 أرقام'
                              : null,
                        ),
                        const SizedBox(height: 22),
                        SizedBox(
                          height: 54,
                          child: FilledButton(
                            onPressed: _isLoading ? null : _handleLogin,
                            child: _isLoading
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Text('تسجيل الدخول'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
