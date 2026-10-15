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
  final _nombresController = TextEditingController();
  final _apellidosController = TextEditingController();
  final _pinController = TextEditingController();
  final _confirmPinController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _nombresController.dispose();
    _apellidosController.dispose();
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
      final result = await AuthService().createModulePin(
        module: widget.module,
        nombres: _nombresController.text.trim(),
        apellidos: _apellidosController.text.trim(),
        pin: _pinController.text,
      );

      if (!mounted) return;
      switch (result) {
        case ModulePinSetupResult.created:
        case ModulePinSetupResult.alreadyConfigured:
          Navigator.of(context).pop(true);
          return;
        case ModulePinSetupResult.pinInUse:
          setState(
            () => _errorMessage =
                'Ese PIN ya está asignado. Elige otro PIN de acceso.',
          );
        case ModulePinSetupResult.invalidIdentity:
          setState(
            () => _errorMessage =
                'El nombre y los apellidos no corresponden a un perfil '
                'autorizado para este módulo.',
          );
      }
    } on Exception catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = 'No se pudo crear el PIN: $error');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _requiredName(String? value, String label) {
    if (value == null || value.trim().isEmpty) {
      return 'Escribe $label.';
    }
    if (value.trim().length > 100) {
      return '$label no puede superar los 100 caracteres.';
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final role = widget.module == 'profesor' ? 'profesor' : 'administrador';
    return AlertDialog(
      backgroundColor: AppColors.background,
      title: const Text('Crear PIN de acceso'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Confirma tu identidad como $role. El sistema asociará '
                'automáticamente el ID único de tu perfil.',
              ),
              const SizedBox(height: 16),
              _textField(
                controller: _nombresController,
                label: 'Nombres',
                icon: Icons.person_outline,
                validator: (value) {
                  final error = _requiredName(value, 'tus nombres');
                  return error.isEmpty ? null : error;
                },
              ),
              const SizedBox(height: 12),
              _textField(
                controller: _apellidosController,
                label: 'Apellidos',
                icon: Icons.person_outline,
                validator: (value) {
                  final error = _requiredName(value, 'tus apellidos');
                  return error.isEmpty ? null : error;
                },
              ),
              const SizedBox(height: 12),
              _textField(
                controller: _pinController,
                label: 'Crear PIN',
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
              : const Text('Crear y continuar'),
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
