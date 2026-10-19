import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ModuleAccess {
  const ModuleAccess({required this.module, required this.pin});

  final String module;
  final String pin;
}

class ModulePinException implements Exception {
  const ModulePinException(this.message);

  final String message;

  @override
  String toString() => message;
}

class AuthService {
  final SupabaseClient _supabase = Supabase.instance.client;

  Future<void> sendAccountRecoveryEmail(String email) {
    return _supabase.auth.resetPasswordForEmail(
      email,
      redirectTo: kIsWeb
          ? Uri.base.replace(query: '', fragment: '').toString()
          : 'umbral://reset-password',
    );
  }

  Future<void> resetModulePin({
    required String module,
    required String pin,
  }) async {
    final response = await _supabase.functions.invoke(
      'verify-module-pin',
      body: {'module': module, 'action': 'reset_pin', 'pin': pin},
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

  Future<void> createModulePin({
    required String module,
    required String pin,
  }) async {
    final response = await _supabase.rpc(
      'verificar_o_configurar_pin',
      params: {'p_rol': module, 'p_pin': pin, 'p_accion': 'configurar'},
    );
    _requirePinRpcSuccess(response, 'No se pudo configurar el PIN.');
  }

  Future<ModuleAccess> validateModulePin({
    required String module,
    required String pin,
  }) async {
    final response = await _supabase.rpc(
      'verificar_o_configurar_pin',
      params: {'p_rol': module, 'p_pin': pin, 'p_accion': 'verificar'},
    );
    _requirePinRpcSuccess(response, 'No se pudo validar el PIN.');
    return ModuleAccess(module: module, pin: pin);
  }

  void _requirePinRpcSuccess(dynamic response, String fallbackMessage) {
    if (response is! Map || response['exito'] is! bool) {
      throw ModulePinException(fallbackMessage);
    }
    if (response['exito'] != true) {
      final message = response['mensaje'];
      throw ModulePinException(
        message is String && message.trim().isNotEmpty
            ? message
            : fallbackMessage,
      );
    }
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
