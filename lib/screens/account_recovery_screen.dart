import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/auth_service.dart';
import '../theme/app_colors.dart';

class AccountRecoveryScreen extends StatefulWidget {
  const AccountRecoveryScreen({required this.onComplete, super.key});

  final VoidCallback onComplete;

  @override
  State<AccountRecoveryScreen> createState() => _AccountRecoveryScreenState();
}

class _AccountRecoveryScreenState extends State<AccountRecoveryScreen> {
  final _passwordFormKey = GlobalKey<FormState>();
  final _pinFormKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _pinController = TextEditingController();
  final _confirmPinController = TextEditingController();
  late final Future<String> _roleFuture = AuthService().getUserRole();
  bool _isLoading = false;
  bool _recoverPin = false;
  String? _errorMessage;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _pinController.dispose();
    _confirmPinController.dispose();
    super.dispose();
  }

  Future<void> _updatePassword() async {
    if (_passwordFormKey.currentState?.validate() != true) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(password: _passwordController.text),
      );
      if (!mounted) return;
      _complete('La contraseña se actualizó correctamente.');
    } on AuthException catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = 'No se pudo actualizar la contraseña: '
          '${error.message}');
    } on Exception catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = 'Error de conexión: $error');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _updatePin(String module) async {
    if (_pinFormKey.currentState?.validate() != true) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      await AuthService().resetModulePin(
        module: module,
        pin: _pinController.text,
      );
      if (!mounted) return;
      _complete('El PIN se restableció correctamente.');
    } on AuthException catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = error.message);
    } on Exception catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = 'No se pudo restablecer el PIN: $error');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _complete(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
    widget.onComplete();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: FutureBuilder<String>(
                future: _roleFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return _errorPanel(
                      'No se pudo verificar tu cuenta: ${snapshot.error}',
                    );
                  }

                  final role = snapshot.data ?? 'desconocido';
                  final canResetPin =
                      role == 'profesor' || role == 'administrador';
                  final isStudent = role == 'alumno';
                  if (!canResetPin && !isStudent) {
                    return _errorPanel(
                      'Esta cuenta no tiene un rol autorizado para recuperar '
                      'el acceso.',
                    );
                  }

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Icon(
                        Icons.lock_reset,
                        color: AppColors.neonAccent,
                        size: 52,
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Recuperar acceso',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (canResetPin) ...[
                        const Text(
                          'Elige qué credencial quieres recuperar.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppColors.softAccent),
                        ),
                        const SizedBox(height: 20),
                        SegmentedButton<bool>(
                          segments: const [
                            ButtonSegment(
                              value: false,
                              label: Text('Contraseña'),
                              icon: Icon(Icons.password),
                            ),
                            ButtonSegment(
                              value: true,
                              label: Text('PIN'),
                              icon: Icon(Icons.pin),
                            ),
                          ],
                          selected: {_recoverPin},
                          onSelectionChanged: _isLoading
                              ? null
                              : (selection) => setState(
                                  () => _recoverPin = selection.first,
                                ),
                        ),
                        const SizedBox(height: 20),
                      ],
                      if (_recoverPin && canResetPin)
                        _buildPinForm(role)
                      else
                        _buildPasswordForm(),
                      if (_errorMessage != null) ...[
                        const SizedBox(height: 16),
                        Text(
                          _errorMessage!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                      OutlinedButton(
                        onPressed: _isLoading ? null : widget.onComplete,
                        child: const Text('Cancelar'),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPasswordForm() {
    return Form(
      key: _passwordFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _recoveryField(
            controller: _passwordController,
            label: 'Nueva contraseña',
            validator: (value) {
              if ((value ?? '').length < 6) {
                return 'La contraseña debe tener al menos 6 caracteres.';
              }
              return null;
            },
          ),
          const SizedBox(height: 12),
          _recoveryField(
            controller: _confirmPasswordController,
            label: 'Confirmar contraseña',
            validator: (value) => value != _passwordController.text
                ? 'Las contraseñas no coinciden.'
                : null,
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _isLoading ? null : _updatePassword,
            child: _isLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Actualizar contraseña'),
          ),
        ],
      ),
    );
  }

  Widget _buildPinForm(String role) {
    final module = role == 'profesor' ? 'profesor' : 'administrador';
    return Form(
      key: _pinFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Ingresa un nuevo PIN para tu acceso de $role. Debe tener entre '
            '4 y 12 dígitos.',
            style: const TextStyle(color: AppColors.softAccent),
          ),
          const SizedBox(height: 12),
          _recoveryField(
            controller: _pinController,
            label: 'Nuevo PIN',
            obscureText: true,
            keyboardType: TextInputType.number,
            validator: (value) => RegExp(r'^\d{4,12}$').hasMatch(value ?? '')
                ? null
                : 'El PIN debe tener entre 4 y 12 dígitos.',
          ),
          const SizedBox(height: 12),
          _recoveryField(
            controller: _confirmPinController,
            label: 'Confirmar PIN',
            obscureText: true,
            keyboardType: TextInputType.number,
            validator: (value) => value != _pinController.text
                ? 'Los PIN no coinciden.'
                : null,
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _isLoading ? null : () => _updatePin(module),
            child: _isLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Restablecer PIN'),
          ),
        ],
      ),
    );
  }

  Widget _recoveryField({
    required TextEditingController controller,
    required String label,
    required String? Function(String?) validator,
    bool obscureText = false,
    TextInputType? keyboardType,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: const Icon(Icons.lock_outline),
        filled: true,
        fillColor: AppColors.panel,
        border: const OutlineInputBorder(),
      ),
      validator: validator,
    );
  }

  Widget _errorPanel(String message) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white),
        ),
        const SizedBox(height: 16),
        OutlinedButton(
          onPressed: widget.onComplete,
          child: const Text('Volver al inicio'),
        ),
      ],
    );
  }
}
