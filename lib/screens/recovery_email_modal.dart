import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/auth_service.dart';
import '../theme/app_colors.dart';

class RecoveryEmailModal extends StatefulWidget {
  const RecoveryEmailModal({required this.credential, super.key});

  final String credential;

  @override
  State<RecoveryEmailModal> createState() => _RecoveryEmailModalState();
}

class _RecoveryEmailModalState extends State<RecoveryEmailModal> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _sendRecoveryEmail() async {
    if (_formKey.currentState?.validate() != true) return;

    setState(() => _isLoading = true);
    try {
      await AuthService().sendAccountRecoveryEmail(
        _emailController.text.trim(),
      );
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop();
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Si el correo está registrado, recibirás un enlace para recuperar '
            'tu acceso.',
          ),
        ),
      );
    } on AuthException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo enviar el correo: ${error.message}'),
          backgroundColor: Colors.red,
        ),
      );
    } on Exception catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error de conexión al enviar el correo: $error'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.background,
      title: const Text('Recuperar acceso'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Ingresa el correo vinculado a tu cuenta. Te enviaremos un '
              'enlace para recuperar ${widget.credential}.',
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _emailController,
              autofocus: true,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Correo electrónico',
                prefixIcon: Icon(Icons.mail_outline),
                filled: true,
                fillColor: AppColors.panel,
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                final email = value?.trim() ?? '';
                if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
                  return 'Ingresa un correo electrónico válido.';
                }
                return null;
              },
              onFieldSubmitted: (_) => _sendRecoveryEmail(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
          style: TextButton.styleFrom(foregroundColor: AppColors.softAccent),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _isLoading ? null : _sendRecoveryEmail,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.neonAccent,
            foregroundColor: Colors.white,
          ),
          child: _isLoading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Enviar enlace'),
        ),
      ],
    );
  }
}
