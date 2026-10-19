import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:umbral/main.dart';
import 'package:umbral/screens/home_screen.dart';
import 'package:umbral/screens/login_modal.dart';
import 'package:umbral/screens/module_pin_modal.dart';
import 'package:umbral/screens/register_modal.dart';
import 'package:umbral/screens/student_main_screen.dart';

void main() {
  setUpAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/shared_preferences'),
          (_) async => <String, Object>{},
        );
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'test-publishable-key',
    );
  });

  testWidgets('startup explains when Supabase configuration is missing', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const StartupProblemApp(
        message: 'Falta configurar SUPABASE_URL y SUPABASE_PUBLISHABLE_KEY.',
      ),
    );

    expect(
      find.text('No se pudo configurar la conexión con Supabase'),
      findsOneWidget,
    );
    expect(
      find.text('Falta configurar SUPABASE_URL y SUPABASE_PUBLISHABLE_KEY.'),
      findsOneWidget,
    );
  });

  testWidgets(
    'teacher module starts with PIN setup and identity confirmation',
    (WidgetTester tester) async {
      await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
      await tester.ensureVisible(find.text('Profesores'));
      await tester.tap(find.text('Profesores'));
      await tester.pumpAndSettle();

      expect(find.text('Crear PIN de acceso'), findsOneWidget);
      expect(find.text('Nombres'), findsOneWidget);
      expect(find.text('Apellidos'), findsOneWidget);
      expect(find.text('Confirmar PIN'), findsOneWidget);
    },
  );

  testWidgets('cancelling the teacher PIN returns to the home screen', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    await tester.ensureVisible(find.text('Profesores'));
    await tester.tap(find.text('Profesores'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();

    expect(find.text('Crear PIN de acceso'), findsNothing);
    expect(find.text('Entrar'), findsOneWidget);
  });

  testWidgets('admin module starts with identity and exclusive PIN setup', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    await tester.ensureVisible(find.text('Administrador'));
    await tester.tap(find.text('Administrador'));
    await tester.pumpAndSettle();

    expect(find.text('Crear PIN de acceso'), findsOneWidget);
    expect(find.text('Nombres'), findsOneWidget);
    expect(find.text('Apellidos'), findsOneWidget);
  });

  testWidgets('cancelling the admin PIN returns to the home screen', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    await tester.ensureVisible(find.text('Administrador'));
    await tester.tap(find.text('Administrador'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();

    expect(find.text('Crear PIN de acceso'), findsNothing);
    expect(find.text('Entrar'), findsOneWidget);
  });

  testWidgets('student module opens email login', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    await tester.tap(find.text('Entrar'));
    await tester.pumpAndSettle();

    expect(find.text('Correo electrónico'), findsOneWidget);
    expect(find.text('Contraseña'), findsOneWidget);
  });

  testWidgets('login offers password recovery by email', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: LoginModal())),
    );

    await tester.tap(find.text('¿Olvidaste tu contraseña?'));
    await tester.pumpAndSettle();

    expect(find.text('Recuperar acceso'), findsOneWidget);
    expect(find.text('Enviar enlace'), findsOneWidget);
  });

  testWidgets('teacher PIN login offers PIN recovery by email', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => const ModulePinModal(
                  module: 'profesor',
                  title: 'Acceso de profesor',
                ),
              ),
              child: const Text('Abrir PIN'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Abrir PIN'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('¿Olvidaste tu PIN?'));
    await tester.pumpAndSettle();

    expect(find.text('Recuperar acceso'), findsOneWidget);
    expect(find.text('Correo electrónico'), findsOneWidget);
    expect(find.text('Enviar enlace'), findsOneWidget);
  });

  testWidgets('student registration asks for email and national ID', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: RegisterModal())),
    );
    await tester.pumpAndSettle();

    expect(find.text('Correo Electrónico'), findsOneWidget);
    expect(find.text('Cédula'), findsOneWidget);
    expect(find.text('Username'), findsNothing);
  });

  testWidgets('student registration rejects an invalid national ID', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: RegisterModal())),
    );

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'María Pérez');
    await tester.enterText(fields.at(1), 'V-123');
    await tester.enterText(fields.at(2), '04121234567');
    await tester.enterText(fields.at(3), 'maria@example.com');
    await tester.enterText(fields.at(4), 'password123');
    await tester.ensureVisible(find.text('REGISTRARSE'));
    await tester.tap(find.text('REGISTRARSE'));
    await tester.pumpAndSettle();

    expect(find.text('Ingresa una cédula válida'), findsOneWidget);
  });

  testWidgets('student registration rejects an invalid phone number', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: RegisterModal())),
    );

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'María Pérez');
    await tester.enterText(fields.at(1), 'V-12345678');
    await tester.enterText(fields.at(2), '123');
    await tester.enterText(fields.at(3), 'maria@example.com');
    await tester.enterText(fields.at(4), 'password123');
    await tester.ensureVisible(find.text('REGISTRARSE'));
    await tester.tap(find.text('REGISTRARSE'));
    await tester.pumpAndSettle();

    expect(find.text('Ingresa un teléfono venezolano válido'), findsOneWidget);
  });

  testWidgets('student dashboard shows formation modules and opens courses', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: StudentMainScreen(username: 'María')),
    );
    await tester.pumpAndSettle();

    expect(find.text('FORMACIONES\nINMUJER'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is Image && widget.semanticLabel == 'Mujeres formándose en educación, cocina y formación profesional',
      ),
      findsOneWidget,
    );
    expect(find.text('MIS CURSOS'), findsOneWidget);

    await tester.ensureVisible(find.text('IR A MIS CURSOS'));
    await tester.tap(find.text('IR A MIS CURSOS'));
    await tester.pumpAndSettle();

    expect(find.text('No hay una sesión activa.'), findsOneWidget);

    await tester.tap(find.text('Inicio'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('MI ASISTENCIA'),
      220,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('MI ASISTENCIA'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('ENCUESTAS'),
      220,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('ENCUESTAS'), findsOneWidget);
  });
}
