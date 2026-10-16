import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:umbral/main.dart';
import 'package:umbral/screens/home_screen.dart';
import 'package:umbral/screens/register_modal.dart';

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
}
