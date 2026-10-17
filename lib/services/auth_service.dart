import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ModuleAccess {
  const ModuleAccess({
    required this.module,
    required this.pin,
    required this.profileId,
  });

  final String module;
  final String pin;
  final String profileId;
}

enum ModulePinSetupResult {
  created,
  alreadyConfigured,
  pinInUse,
  invalidIdentity,
}

class AuthService {
  final SupabaseClient _supabase = Supabase.instance.client;

  Future<void> sendAccountRecoveryEmail(String email) {
    return _supabase.auth.resetPasswordForEmail(
      email,
      redirectTo: kIsWeb ? Uri.base.origin : 'umbral://reset-password',
    );
  }

  Future<void> resetModulePin({
    required String module,
    required String pin,
  }) async {
    final response = await _supabase.functions.invoke(
      'verify-module-pin',
      body: {
        'module': module,
        'action': 'reset_pin',
        'pin': pin,
      },
    );
    final data = response.data;
    if (response.status < 200 || response.status >= 300 || data is! Map) {
      throw const AuthException('No se pudo restablecer el PIN.');
    }
    if (data['status'] == 'pin_in_use') {
      throw const AuthException(
        'Ese PIN ya está asignado. Elige otro PIN de acceso.',
      );
    }
    if (data['status'] != 'reset') {
      throw const AuthException(
        'Esta cuenta no tiene permiso para restablecer el PIN.',
      );
    }
  }

  Future<ModulePinSetupResult> createModulePin({
    required String module,
    required String nombres,
    required String apellidos,
    required String pin,
  }) async {
    final response = await _supabase.functions.invoke(
      'verify-module-pin',
      body: {
        'module': module,
        'action': 'create_pin',
        'nombres': nombres,
        'apellidos': apellidos,
        'pin': pin,
      },
    );

    final data = response.data;
    if (response.status < 200 ||
        response.status >= 300 ||
        data is! Map ||
        data['status'] is! String) {
      throw const AuthException('No se pudo crear el PIN del módulo.');
    }

    return switch (data['status']) {
      'created' => ModulePinSetupResult.created,
      'already_configured' => ModulePinSetupResult.alreadyConfigured,
      'pin_in_use' => ModulePinSetupResult.pinInUse,
      'invalid_identity' => ModulePinSetupResult.invalidIdentity,
      _ => throw const AuthException('Respuesta no válida al crear el PIN.'),
    };
  }

  Future<ModuleAccess?> validateModulePin({
    required String module,
    required String pin,
  }) async {
    final response = await _supabase.functions.invoke(
      'verify-module-pin',
      body: {'module': module, 'pin': pin},
    );

    final data = response.data;
    if (response.status < 200 ||
        response.status >= 300 ||
        data is! Map ||
        data['valid'] is! bool) {
      throw const AuthException('No se pudo validar el PIN del módulo.');
    }

    if (data['valid'] != true) return null;
    final profileId = data['profile_id'];
    if (profileId is! String) {
      throw const AuthException('El PIN no está vinculado a un perfil.');
    }
    return ModuleAccess(module: module, pin: pin, profileId: profileId);
  }

  Future<Map<String, dynamic>> runModuleAction({
    required ModuleAccess access,
    required String action,
    Map<String, dynamic> payload = const {},
  }) async {
    final response = await _supabase.functions.invoke(
      'verify-module-pin',
      body: {
        'module': access.module,
        'pin': access.pin,
        'action': action,
        'payload': payload,
      },
    );
    final data = response.data;
    if (response.status < 200 ||
        response.status >= 300 ||
        data is! Map ||
        data['valid'] != true ||
        data['result'] is! Map) {
      throw const AuthException(
        'No se pudo completar la operación del módulo.',
      );
    }
    return Map<String, dynamic>.from(data['result'] as Map);
  }

  Future<String> getUserRole() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return 'none';

    final assignments = await _supabase
        .from('usuario_roles')
        .select('roles!inner(codigo)')
        .eq('usuario_id', user.id);

    final assignedRoles = assignments
        .map((assignment) {
          final role = assignment['roles'];
          return role is Map ? role['codigo']?.toString() : null;
        })
        .whereType<String>()
        .toSet();

    for (final role in ['administrador', 'profesor', 'alumno']) {
      if (assignedRoles.contains(role)) return role;
    }
    return 'desconocido';
  }
}
