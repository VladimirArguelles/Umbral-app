import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../theme/app_colors.dart';

class ModulePinSetupModal extends StatefulWidget {
  const ModulePinSetupModal({required this.module, super.key});

  final String module;

  @override
  State<ModulePinSetupModal> createState() => _ModulePinSetupModalState();
}

class _ModulePinSetupModalState extends State<ModulePinSetupModal> {
  final _formKey = GlobalKey<FormState>();
  final _pinController = TextEditingController();
  final _confirmPinController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _pinController.dispose();
    _confirmPinController.dispose();
    super.dispose();
  }

  Future<void> _createPin() async {
    if (_formKey.currentState?.validate() != true) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await AuthService().createModulePin(
        module: widget.module,
        pin: _pinController.text,
      );

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ModulePinException catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = error.message);
    } on Exception catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = 'No se pudo configurar el PIN: $error');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final role = widget.module == 'profesor' ? 'profesor' : 'administrador';
    return AlertDialog(
      backgroundColor: AppColors.background,
      title: const Text('Configurar PIN de acceso'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Configura el PIN de acceso para el módulo de $role.'),
              const SizedBox(height: 16),
              _textField(
                controller: _pinController,
                label: 'PIN',
                icon: Icons.lock_outline,
                obscureText: true,
                keyboardType: TextInputType.number,
                validator: (value) {
                  if (!RegExp(r'^\d{4,12}$').hasMatch(value ?? '')) {
                    return 'El PIN debe tener entre 4 y 12 dígitos.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              _textField(
                controller: _confirmPinController,
                label: 'Confirmar PIN',
                icon: Icons.lock_outline,
                obscureText: true,
                keyboardType: TextInputType.number,
                validator: (value) {
                  if (value != _pinController.text) {
                    return 'Los PIN no coinciden.';
                  }
                  return null;
                },
                onFieldSubmitted: (_) => _createPin(),
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
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.of(context).pop(false),
          style: TextButton.styleFrom(foregroundColor: AppColors.softAccent),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _isLoading ? null : _createPin,
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
              : const Text('Configurar y continuar'),
        ),
      ],
    );
  }

  Widget _textField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required String? Function(String?) validator,
    bool obscureText = false,
    TextInputType? keyboardType,
    void Function(String)? onFieldSubmitted,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        filled: true,
        fillColor: AppColors.panel,
        border: const OutlineInputBorder(
          borderSide: BorderSide(color: AppColors.softAccent),
        ),
        enabledBorder: const OutlineInputBorder(
          borderSide: BorderSide(color: AppColors.softAccent),
        ),
        focusedBorder: const OutlineInputBorder(
          borderSide: BorderSide(color: AppColors.neonAccent, width: 2),
        ),
      ),
      validator: validator,
      onFieldSubmitted: onFieldSubmitted,
    );
  }
}
