import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../theme/app_colors.dart';
import 'recovery_email_modal.dart';

class ModulePinModal extends StatefulWidget {
  const ModulePinModal({required this.module, required this.title, super.key});

  final String module;
  final String title;

  @override
  State<ModulePinModal> createState() => _ModulePinModalState();
}

class _ModulePinModalState extends State<ModulePinModal> {
  final _formKey = GlobalKey<FormState>();
  final _pinController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _validatePin() async {
    if (_formKey.currentState?.validate() != true) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final access = await AuthService().validateModulePin(
        module: widget.module,
        pin: _pinController.text,
      );

      if (!mounted) return;
      Navigator.of(context).pop(access);
    } on ModulePinException catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = error.message);
    } on Exception catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = 'No se pudo validar el PIN: $error');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _showPinRecovery() {
    return showDialog<void>(
      context: context,
      builder: (_) => const RecoveryEmailModal(credential: 'tu PIN'),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.background,
      title: Text(widget.title),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Ingresa el PIN de seguridad para continuar.'),
            const SizedBox(height: 16),
            TextFormField(
              controller: _pinController,
              autofocus: true,
              obscureText: true,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'PIN',
                prefixIcon: Icon(Icons.lock_outline),
                filled: true,
                fillColor: AppColors.panel,
                border: OutlineInputBorder(
                  borderSide: BorderSide(color: AppColors.softAccent),
                ),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: AppColors.softAccent),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: AppColors.neonAccent, width: 2),
                ),
              ),
              validator: (value) {
                final pin = value ?? '';
                if (!RegExp(r'^\d{4,12}$').hasMatch(pin)) {
                  return 'Ingresa un PIN de 4 a 12 dígitos.';
                }
                return null;
              },
              onFieldSubmitted: (_) => _validatePin(),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _isLoading ? null : _showPinRecovery,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.softAccent,
                ),
                child: const Text('¿Olvidaste tu PIN?'),
              ),
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              Text(
                _errorMessage!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.of(context).pop(null),
          style: TextButton.styleFrom(foregroundColor: AppColors.softAccent),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _isLoading ? null : _validatePin,
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
              : const Text('Validar'),
        ),
      ],
    );
  }
}
