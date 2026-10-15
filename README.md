# Umbral

## Configurar Supabase

La app necesita la URL del proyecto y su clave pública de cliente para conectarse
a Supabase. Obtén ambos valores en el panel del proyecto, en **Project Settings
> API**. No uses la URL genérica `https://supabase.co`.

`main.dart` lee ambos valores con `String.fromEnvironment`. Configura
`SUPABASE_URL` y `SUPABASE_PUBLISHABLE_KEY` como variables del entorno de usuario
o de la sesión, fuera del repositorio. La configuración de VS Code las pasa a
Flutter mediante `--dart-define` al iniciar con `F5`. VS Code debe iniciarse
después de configurar esas variables para que las reciba.

Para iniciar desde PowerShell, pasa las variables de entorno mediante
`--dart-define`:

```powershell
flutter run `
  --dart-define=SUPABASE_URL="$env:SUPABASE_URL" `
  --dart-define=SUPABASE_PUBLISHABLE_KEY="$env:SUPABASE_PUBLISHABLE_KEY"
```

La clave publishable (o la clave `anon` heredada) está diseñada para uso en el
cliente, pero no guardes sus valores en archivos de configuración planos ni en
el repositorio. Nunca pongas una clave `service_role` en la aplicación. Si falta
la configuración al iniciar, la aplicación mostrará instrucciones en pantalla
en lugar de cerrarse silenciosamente.

## Registro e inicio de sesión de alumnos

Los alumnos se registran e inician sesión con correo y contraseña. El registro
envía nombre, cédula y teléfono a Supabase Auth. La migración
`202610140002_link_student_on_signup.sql` vincula `auth.users.id` con
`alumnos.user_id` mediante la cédula; si todavía no existe la fila, la crea.
La migración `202610140003_student_data_policies.sql` aplica las políticas RLS
para que cada alumno consulte y actualice únicamente sus datos y comprobantes.

## Acceso de profesores y administradores

Ejecuta todas las migraciones SQL de `supabase/migrations` en orden desde el SQL
Editor del proyecto Supabase. La migración
`202610140001_module_access_pin.sql` crea `accesos_pin`; los PIN docentes son
individuales y se vinculan a `profiles.id`. Los PIN se almacenan como hashes
bcrypt y la tabla no es consultable desde la app.

Después de aplicar las migraciones, configura PIN individuales docentes y un
PIN de administrador desde el
SQL Editor. Sustituye los valores de ejemplo por PIN nuevos; no los guardes en
el código ni en el repositorio:

```powershell
INSERT INTO public.accesos_pin (modulo, profesor_id, pin_hash)
VALUES (
  'profesor',
  'UUID_DEL_PERFIL_DOCENTE',
  extensions.crypt('PIN_DOCENTE_NUEVO', extensions.gen_salt('bf'))
);

INSERT INTO public.accesos_pin (modulo, pin_hash)
VALUES (
  'administrador',
  extensions.crypt('PIN_ADMIN_NUEVO', extensions.gen_salt('bf'))
);
```

Despliega la función que valida los PIN con límite de intentos:

```powershell
supabase functions deploy verify-module-pin
```

La función usa `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY` y la clave pública
(`SUPABASE_PUBLISHABLE_KEY` o `SUPABASE_ANON_KEY`) configuradas en Supabase. La
clave `service_role` nunca debe incluirse en la aplicación Flutter.

La misma función valida el PIN en cada operación privilegiada. Así, los paneles
docente y administrativo pueden consultar y modificar cursos, asistencias,
encuestas y pagos sin conceder acceso `service_role` a la app.
