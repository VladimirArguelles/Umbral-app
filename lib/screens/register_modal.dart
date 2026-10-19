import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme/app_colors.dart';
import 'login_modal.dart';

class RegisterModal extends StatefulWidget {
  const RegisterModal({super.key});

  @override
  State<RegisterModal> createState() => _RegisterModalState();
}

class _RegisterModalState extends State<RegisterModal> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _cedulaController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  String _tipoDocumento = 'V';
  bool _obscurePassword = true;
  bool _isLoading = false;

  @override
  void dispose() {
    _nameController.dispose();
    _cedulaController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _signUp() async {
    if (_formKey.currentState?.validate() != true) return;

    setState(() => _isLoading = true);

    try {
      final numeroDocumento = _cedulaController.text.trim();
      final cedulaCompleta = '$_tipoDocumento$numeroDocumento';
      final emailInput = _emailController.text.trim();
      final passwordInput = _passwordController.text;
      final nameInput = _nameController.text.trim();
      final phoneInput = _normalizePhone(_phoneController.text);

      final preRegistrationIsValid = await Supabase.instance.client.rpc(
        'validar_preinscripcion_alumno',
        params: {'p_cedula': cedulaCompleta, 'p_correo': emailInput},
      );

      if (preRegistrationIsValid is! bool) {
        throw const FormatException(
          'La validación de preinscripción devolvió una respuesta no válida.',
        );
      }
      if (!preRegistrationIsValid) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'No se encontró una preinscripción disponible para esos datos.',
            ),
            backgroundColor: Colors.redAccent,
          ),
        );
        return;
      }

      final response = await Supabase.instance.client.auth.signUp(
        email: emailInput,
        password: passwordInput,
        data: {
          'full_name': nameInput,
          'cedula': cedulaCompleta,
          'phone': phoneInput,
        },
      );

      if (!mounted) return;
      final user = response.user;
      if (user == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Supabase no devolvió los datos de la cuenta.'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      final navigator = Navigator.of(context);
      final messenger = ScaffoldMessenger.of(context);
      navigator.pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            response.session == null
                ? 'Cuenta pre-inscrita validada. Revisa tu correo para confirmar el registro.'
                : '¡Registro exitoso! Se ha vinculado tu cuenta de alumna.',
          ),
        ),
      );
    } on AuthException catch (error, stackTrace) {
      debugPrint('ERROR DETALLADO DE SUPABASE: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo completar el registro: ${error.message}'),
          backgroundColor: Colors.red,
        ),
      );
    } on Exception catch (error, stackTrace) {
      debugPrint('ERROR DETALLADO DE SUPABASE: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error is FormatException
                ? error.message
                : 'Error de conexión durante el registro: $error',
          ),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showLogin() {
    final navigator = Navigator.of(context);
    final navigatorContext = navigator.context;
    navigator.pop();
    showDialog<void>(
      context: navigatorContext,
      builder: (_) => const LoginModal(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.background,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Cabecera
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Registrarse',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Crea tu cuenta en la plataforma',
                        style: TextStyle(
                          color: AppColors.softAccent,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: AppColors.softAccent),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Campo: Nombre Completo
              _buildTextField(
                label: 'Nombre Completo',
                hint: 'Tu nombre...',
                icon: Icons.person_outline,
                controller: _nameController,
                validator: (value) => _requiredField(value, 'nombre'),
              ),
              const SizedBox(height: 14),

              const Text(
                'Documento de Identidad',
                style: TextStyle(color: AppColors.softAccent, fontSize: 13),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: AppColors.panel,
                      border: Border.all(color: AppColors.softAccent),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _tipoDocumento,
                        dropdownColor: AppColors.panel,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                        icon: const Icon(
                          Icons.arrow_drop_down,
                          color: AppColors.softAccent,
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'V',
                            child: Text('V - Cédula'),
                          ),
                          DropdownMenuItem(
                            value: 'P',
                            child: Text('P - Pasaporte'),
                          ),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          setState(() {
                            _tipoDocumento = value;
                          });
                          _formKey.currentState?.validate();
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: _cedulaController,
                      keyboardType: _tipoDocumento == 'V'
                          ? TextInputType.number
                          : TextInputType.text,
                      style: const TextStyle(color: Colors.white),
                      validator: (value) {
                        final documento = value?.trim() ?? '';
                        if (documento.isEmpty) {
                          return _tipoDocumento == 'V'
                              ? 'Ingresa tu cédula'
                              : 'Ingresa tu pasaporte';
                        }
                        final isValid = _tipoDocumento == 'V'
                            ? RegExp(r'^\d{5,12}$').hasMatch(documento)
                            : RegExp(r'^[A-Za-z0-9]{5,20}$')
                                  .hasMatch(documento);
                        if (!isValid) {
                          return _tipoDocumento == 'V'
                              ? 'Ingresa una cédula válida (5 a 12 dígitos)'
                              : 'Ingresa un pasaporte válido (5 a 20 letras o números)';
                        }
                        return null;
                      },
                      decoration: InputDecoration(
                        hintText: _tipoDocumento == 'V'
                            ? 'Número de Cédula'
                            : 'Número de Pasaporte',
                        hintStyle: const TextStyle(color: Colors.white54),
                        filled: true,
                        fillColor: AppColors.panel,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(
                            color: AppColors.softAccent,
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(
                            color: AppColors.softAccent,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(
                            color: AppColors.neonAccent,
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Campo: Teléfono (WhatsApp) con selector VE +58
              const Text(
                'Teléfono (WhatsApp)',
                style: TextStyle(color: AppColors.softAccent, fontSize: 13),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.panel,
                      border: Border.all(color: AppColors.softAccent),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text(
                      'VE +58 ▾',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      style: const TextStyle(color: Colors.white),
                      validator: (value) {
                        if ((value ?? '').trim().isEmpty) {
                          return 'Ingresa tu teléfono';
                        }
                        try {
                          _normalizePhone(value!);
                        } on FormatException {
                          return 'Ingresa un teléfono venezolano válido';
                        }
                        return null;
                      },
                      decoration: InputDecoration(
                        hintText: 'Número de Teléfono',
                        hintStyle: const TextStyle(color: Colors.white54),
                        filled: true,
                        fillColor: AppColors.panel,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(
                            color: AppColors.softAccent,
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(
                            color: AppColors.softAccent,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(
                            color: AppColors.neonAccent,
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Campo: Correo Electrónico
              _buildTextField(
                label: 'Correo Electrónico',
                hint: 'correo@ejemplo.com',
                icon: Icons.mail_outline,
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                validator: (value) {
                  final email = value?.trim() ?? '';
                  if (email.isEmpty) return 'Ingresa tu correo electrónico';
                  if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
                    return 'Ingresa un correo electrónico válido';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 14),

              // Campo: Contraseña
              const Text(
                'Contraseña',
                style: TextStyle(color: AppColors.softAccent, fontSize: 13),
              ),
              const SizedBox(height: 6),
              TextFormField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                style: const TextStyle(color: Colors.white),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Ingresa una contraseña';
                  }
                  if (value.length < 6) {
                    return 'La contraseña debe tener al menos 6 caracteres';
                  }
                  return null;
                },
                decoration: InputDecoration(
                  hintText: '••••••••',
                  hintStyle: const TextStyle(color: Colors.white54),
                  prefixIcon: const Icon(
                    Icons.lock_outline,
                    color: AppColors.softAccent,
                  ),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_off
                          : Icons.visibility,
                      color: AppColors.softAccent,
                    ),
                    onPressed: () {
                      setState(() {
                        _obscurePassword = !_obscurePassword;
                      });
                    },
                  ),
                  filled: true,
                  fillColor: AppColors.panel,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: AppColors.softAccent),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: AppColors.softAccent),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(
                      color: AppColors.neonAccent,
                      width: 2,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Botón principal: REGISTRARSE ->
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.neonAccent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: _isLoading ? null : _signUp,
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'REGISTRARSE',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1,
                              ),
                            ),
                            SizedBox(width: 8),
                            Icon(Icons.arrow_forward, size: 18),
                          ],
                        ),
                ),
              ),
              const SizedBox(height: 20),

              // Enlace: ¿Ya tienes cuenta? Inicia sesión
              Center(
                child: TextButton(
                  onPressed: _showLogin,
                  child: RichText(
                    text: const TextSpan(
                      text: '¿Ya tienes cuenta? ',
                      style: TextStyle(color: Colors.white70, fontSize: 14),
                      children: [
                        TextSpan(
                          text: 'Inicia sesión',
                          style: TextStyle(
                            color: AppColors.softAccent,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Divider(color: AppColors.softAccent),
              const SizedBox(height: 8),

              // Soporte
              Center(
                child: TextButton.icon(
                  onPressed: () {},
                  icon: const Icon(
                    Icons.help_outline,
                    color: AppColors.softAccent,
                    size: 18,
                  ),
                  label: const Text(
                    'Help Center / Soporte',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required String label,
    required String hint,
    required IconData icon,
    required TextEditingController controller,
    String? Function(String?)? validator,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: AppColors.softAccent, fontSize: 13),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          style: const TextStyle(color: Colors.white),
          validator: validator,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: Colors.white54),
            prefixIcon: Icon(icon, color: AppColors.softAccent),
            filled: true,
            fillColor: AppColors.panel,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppColors.softAccent),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppColors.softAccent),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(
                color: AppColors.neonAccent,
                width: 2,
              ),
            ),
          ),
        ),
      ],
    );
  }

  String? _requiredField(String? value, String label) {
    if (value == null || value.trim().isEmpty) {
      return 'Ingresa tu $label';
    }
    return null;
  }

  String _normalizePhone(String value) {
    var digits = value.replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('58')) {
      digits = digits.substring(2);
    }
    if (digits.startsWith('0')) {
      digits = digits.substring(1);
    }
    if (!RegExp(r'^\d{10}$').hasMatch(digits)) {
      throw const FormatException('Invalid Venezuelan phone number.');
    }
    return '+58$digits';
  }
}
