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
El formulario de inicio envía un enlace de recuperación al correo registrado.
Al abrirlo, el alumno puede definir una contraseña nueva.

## Acceso de profesores y administradores

Ejecuta todas las migraciones SQL de `supabase/migrations` en orden desde el SQL
Editor del proyecto Supabase. La migración
`202610140001_module_access_pin.sql` crea `accesos_pin`; los PIN de profesores
y administradores son individuales y se vinculan a `perfiles.id`. Los PIN se
almacenan como hashes bcrypt y la tabla no es consultable desde la app.

La migración `202610170001_role_based_access.sql` crea los roles `alumno`,
`profesor` y `administrador`, y la relación `usuario_roles`. Migra los roles
existentes de `perfiles.rol`, asigna `alumno` a las cuentas de alumnos y a las
cuentas nuevas, y restringe las consultas del cliente mediante RLS. Los alumnos
solo pueden consultar sus propios datos y los cursos en los que están inscritos.
El acceso docente sigue limitado a cursos asociados al perfil vinculado al PIN;
las operaciones del administrador requieren el rol `administrador`.

Después de aplicar la migración, concede los roles del personal mediante el
SQL Editor, usando el UUID de cada cuenta de Supabase Auth. No asignes roles
elevados desde la app ni desde metadatos de registro:

```sql
INSERT INTO public.usuario_roles (usuario_id, rol_id)
SELECT 'UUID_DE_LA_CUENTA', id
FROM public.roles
WHERE codigo = 'profesor';
```

Usa `administrador` en lugar de `profesor` para conceder el rol administrativo.
Para retirar un rol, elimina únicamente la asignación correspondiente de
`public.usuario_roles`.

Después de aplicar las migraciones y asignar los roles, configura los PIN
individuales de profesores y administradores desde el SQL Editor. Sustituye
los valores de ejemplo por PIN nuevos; no los guardes en el código ni en el
repositorio:

```powershell
INSERT INTO public.accesos_pin (modulo, profesor_id, pin_hash)
VALUES (
  'profesor',
  'UUID_DEL_PERFIL_DOCENTE',
  extensions.crypt('PIN_DOCENTE_NUEVO', extensions.gen_salt('bf'))
);

INSERT INTO public.accesos_pin (modulo, profesor_id, pin_hash)
VALUES (
  'administrador',
  'UUID_DEL_PERFIL_ADMIN',
  extensions.crypt('PIN_ADMIN_NUEVO', extensions.gen_salt('bf'))
);
```

Despliega la función que valida los PIN con límite de intentos:

```powershell
supabase functions deploy verify-module-pin
```

Para habilitar la recuperación de PIN, ejecuta también la migración
`202610170002_module_pin_recovery.sql` y vuelve a desplegar
`verify-module-pin`. El enlace se envía al correo de la cuenta de Supabase Auth
vinculada al perfil del profesor o administrador; al abrirlo, la app permite
restablecer el PIN o la contraseña. El servidor valida la sesión, el rol y el
perfil antes de guardar el nuevo PIN.

En **Authentication > URL Configuration** de Supabase, agrega a las URL de
redirección permitidas el origen web donde se publica la app y
`umbral://reset-password` para Android/iOS. El enlace de recuperación de las
apps nativas usa ese esquema; la web usa su origen actual.

La función usa `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY` y la clave pública
(`SUPABASE_PUBLISHABLE_KEY` o `SUPABASE_ANON_KEY`) configuradas en Supabase. La
clave `service_role` nunca debe incluirse en la aplicación Flutter.

La misma función valida el PIN en cada operación privilegiada. Así, los paneles
docente y administrativo pueden consultar y modificar cursos, asistencias,
encuestas y pagos sin conceder acceso `service_role` a la app.
