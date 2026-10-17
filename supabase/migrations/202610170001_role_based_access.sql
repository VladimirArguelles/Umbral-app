CREATE TABLE IF NOT EXISTS public.roles (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  codigo TEXT NOT NULL UNIQUE
    CHECK (codigo IN ('alumno', 'profesor', 'administrador')),
  nombre TEXT NOT NULL UNIQUE
);

INSERT INTO public.roles (codigo, nombre)
VALUES
  ('alumno', 'Alumno'),
  ('profesor', 'Profesor'),
  ('administrador', 'Administrador')
ON CONFLICT (codigo) DO UPDATE
SET nombre = EXCLUDED.nombre;

CREATE TABLE IF NOT EXISTS public.usuario_roles (
  usuario_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  rol_id UUID NOT NULL REFERENCES public.roles(id) ON DELETE CASCADE,
  asignado_en TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (usuario_id, rol_id)
);

CREATE INDEX IF NOT EXISTS usuario_roles_rol_id_idx
  ON public.usuario_roles (rol_id, usuario_id);

ALTER TABLE public.roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.usuario_roles ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.roles, public.usuario_roles
  FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE public.roles, public.usuario_roles
  TO authenticated, service_role;

DROP POLICY IF EXISTS "Users read their assigned roles" ON public.roles;
CREATE POLICY "Users read their assigned roles"
  ON public.roles FOR SELECT TO authenticated
  USING (EXISTS (
    SELECT 1
    FROM public.usuario_roles
    WHERE usuario_roles.rol_id = roles.id
      AND usuario_roles.usuario_id = (SELECT auth.uid())
  ));

DROP POLICY IF EXISTS "Users read their role assignments" ON public.usuario_roles;
CREATE POLICY "Users read their role assignments"
  ON public.usuario_roles FOR SELECT TO authenticated
  USING (usuario_id = (SELECT auth.uid()));

CREATE OR REPLACE FUNCTION public.tiene_rol(p_codigo TEXT)
RETURNS BOOLEAN
LANGUAGE SQL
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.usuario_roles AS asignacion
    JOIN public.roles AS rol ON rol.id = asignacion.rol_id
    WHERE asignacion.usuario_id = (SELECT auth.uid())
      AND rol.codigo = p_codigo
  );
$$;

REVOKE ALL ON FUNCTION public.tiene_rol(TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.tiene_rol(TEXT) TO authenticated, service_role;

INSERT INTO public.usuario_roles (usuario_id, rol_id)
SELECT perfil.id, rol.id
FROM (
  SELECT
    id,
    LOWER(BTRIM(COALESCE(
      TO_JSONB(perfiles) ->> 'rol',
      TO_JSONB(perfiles) ->> 'role',
      ''
    ))) AS codigo_legacy
  FROM public.perfiles
) AS perfil
JOIN auth.users AS usuario ON usuario.id = perfil.id
JOIN public.roles AS rol
  ON rol.codigo = CASE perfil.codigo_legacy
    WHEN 'admin' THEN 'administrador'
    WHEN 'administrador' THEN 'administrador'
    WHEN 'profesor' THEN 'profesor'
    WHEN 'docente' THEN 'profesor'
    WHEN 'alumno' THEN 'alumno'
    WHEN 'alumna' THEN 'alumno'
    WHEN 'alumnos' THEN 'alumno'
    WHEN 'estudiante' THEN 'alumno'
    WHEN 'estudiantes' THEN 'alumno'
    WHEN 'student' THEN 'alumno'
    WHEN 'students' THEN 'alumno'
    ELSE NULL
  END
ON CONFLICT DO NOTHING;

INSERT INTO public.usuario_roles (usuario_id, rol_id)
SELECT alumno.user_id, rol.id
FROM public.alumnos AS alumno
JOIN public.roles AS rol ON rol.codigo = 'alumno'
WHERE alumno.user_id IS NOT NULL
ON CONFLICT DO NOTHING;

INSERT INTO public.usuario_roles (usuario_id, rol_id)
SELECT usuario.id, rol.id
FROM auth.users AS usuario
CROSS JOIN public.roles AS rol
WHERE rol.codigo = 'alumno'
  AND NOT EXISTS (
    SELECT 1
    FROM public.usuario_roles AS asignacion
    WHERE asignacion.usuario_id = usuario.id
  )
ON CONFLICT DO NOTHING;

CREATE OR REPLACE FUNCTION public.asignar_rol_alumno_nuevo_usuario()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  INSERT INTO public.usuario_roles (usuario_id, rol_id)
  SELECT NEW.id, rol.id
  FROM public.roles AS rol
  WHERE rol.codigo = 'alumno'
  ON CONFLICT DO NOTHING;
  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.asignar_rol_alumno_nuevo_usuario()
  FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS asignar_rol_alumno_al_registrar ON auth.users;
CREATE TRIGGER asignar_rol_alumno_al_registrar
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.asignar_rol_alumno_nuevo_usuario();

DROP POLICY IF EXISTS "Students read own student record" ON public.alumnos;
CREATE POLICY "Students read own student record"
  ON public.alumnos FOR SELECT TO authenticated
  USING (
    user_id = (SELECT auth.uid())
    AND (SELECT public.tiene_rol('alumno'))
  );

DROP POLICY IF EXISTS "Students read enrolled course" ON public.cursos;
CREATE POLICY "Students read enrolled course"
  ON public.cursos FOR SELECT TO authenticated
  USING (
    (SELECT public.tiene_rol('alumno'))
    AND EXISTS (
      SELECT 1 FROM public.alumnos
      WHERE alumnos.curso_id = cursos.id
        AND alumnos.user_id = (SELECT auth.uid())
    )
  );

DROP POLICY IF EXISTS "Students read own attendance" ON public.asistencia;
CREATE POLICY "Students read own attendance"
  ON public.asistencia FOR SELECT TO authenticated
  USING (
    user_id = (SELECT auth.uid())
    AND (SELECT public.tiene_rol('alumno'))
  );

DROP POLICY IF EXISTS "Students mark own attendance" ON public.asistencia;
CREATE POLICY "Students mark own attendance"
  ON public.asistencia FOR INSERT TO authenticated
  WITH CHECK (
    user_id = (SELECT auth.uid())
    AND (SELECT public.tiene_rol('alumno'))
    AND asistio = TRUE
    AND EXISTS (
      SELECT 1 FROM public.alumnos
      WHERE alumnos.user_id = (SELECT auth.uid())
        AND alumnos.curso_id = asistencia.curso_id
    )
  );

DROP POLICY IF EXISTS "Students read enrolled participation surveys"
  ON public.encuestas_participacion;
CREATE POLICY "Students read enrolled participation surveys"
  ON public.encuestas_participacion FOR SELECT TO authenticated
  USING (
    (SELECT public.tiene_rol('alumno'))
    AND EXISTS (
      SELECT 1 FROM public.alumnos
      WHERE alumnos.user_id = (SELECT auth.uid())
        AND alumnos.curso_id = encuestas_participacion.curso_id
    )
  );

DROP POLICY IF EXISTS "Students read own survey responses"
  ON public.respuestas_encuesta;
CREATE POLICY "Students read own survey responses"
  ON public.respuestas_encuesta FOR SELECT TO authenticated
  USING (
    user_id = (SELECT auth.uid())
    AND (SELECT public.tiene_rol('alumno'))
  );

DROP POLICY IF EXISTS "Students answer enrolled surveys"
  ON public.respuestas_encuesta;
CREATE POLICY "Students answer enrolled surveys"
  ON public.respuestas_encuesta FOR INSERT TO authenticated
  WITH CHECK (
    user_id = (SELECT auth.uid())
    AND (SELECT public.tiene_rol('alumno'))
    AND EXISTS (
      SELECT 1
      FROM public.encuestas_participacion AS survey
      JOIN public.alumnos AS student ON student.curso_id = survey.curso_id
      WHERE survey.id = respuestas_encuesta.encuesta_id
        AND student.user_id = (SELECT auth.uid())
    )
  );

DROP POLICY IF EXISTS "Students update own survey answers"
  ON public.respuestas_encuesta;
CREATE POLICY "Students update own survey answers"
  ON public.respuestas_encuesta FOR UPDATE TO authenticated
  USING (
    user_id = (SELECT auth.uid())
    AND (SELECT public.tiene_rol('alumno'))
  )
  WITH CHECK (
    user_id = (SELECT auth.uid())
    AND (SELECT public.tiene_rol('alumno'))
    AND EXISTS (
      SELECT 1
      FROM public.encuestas_participacion AS survey
      JOIN public.alumnos AS student ON student.curso_id = survey.curso_id
      WHERE survey.id = respuestas_encuesta.encuesta_id
        AND student.user_id = (SELECT auth.uid())
    )
  );

DROP POLICY IF EXISTS "Students read own payments" ON public.pagos;
CREATE POLICY "Students read own payments"
  ON public.pagos FOR SELECT TO authenticated
  USING (
    user_id = (SELECT auth.uid())
    AND (SELECT public.tiene_rol('alumno'))
  );

DROP POLICY IF EXISTS "Students submit own payments" ON public.pagos;
CREATE POLICY "Students submit own payments"
  ON public.pagos FOR INSERT TO authenticated
  WITH CHECK (
    user_id = (SELECT auth.uid())
    AND (SELECT public.tiene_rol('alumno'))
    AND estado = 'pendiente'
    AND imagen_url LIKE (SELECT auth.uid())::TEXT || '/%'
    AND EXISTS (
      SELECT 1
      FROM public.encuestas_participacion AS survey
      JOIN public.alumnos AS student ON student.curso_id = survey.curso_id
      WHERE survey.id = pagos.encuesta_id
        AND student.user_id = (SELECT auth.uid())
        AND pagos.monto_aporte = survey.monto_aporte_individual
    )
  );

DROP POLICY IF EXISTS "Students update own unreviewed payments" ON public.pagos;
CREATE POLICY "Students update own unreviewed payments"
  ON public.pagos FOR UPDATE TO authenticated
  USING (
    user_id = (SELECT auth.uid())
    AND (SELECT public.tiene_rol('alumno'))
    AND estado IN ('pendiente', 'rechazado')
    AND imagen_url LIKE (SELECT auth.uid())::TEXT || '/%'
  )
  WITH CHECK (
    user_id = (SELECT auth.uid())
    AND (SELECT public.tiene_rol('alumno'))
    AND estado = 'pendiente'
    AND imagen_url LIKE (SELECT auth.uid())::TEXT || '/%'
    AND EXISTS (
      SELECT 1
      FROM public.encuestas_participacion AS survey
      JOIN public.alumnos AS student ON student.curso_id = survey.curso_id
      WHERE survey.id = pagos.encuesta_id
        AND student.user_id = (SELECT auth.uid())
        AND pagos.monto_aporte = survey.monto_aporte_individual
    )
  );

DROP POLICY IF EXISTS "Students delete own pending payments" ON public.pagos;
CREATE POLICY "Students delete own pending payments"
  ON public.pagos FOR DELETE TO authenticated
  USING (
    user_id = (SELECT auth.uid())
    AND (SELECT public.tiene_rol('alumno'))
    AND estado = 'pendiente'
  );

DROP POLICY IF EXISTS "Students manage own payment proofs"
  ON storage.objects;
CREATE POLICY "Students manage own payment proofs"
  ON storage.objects FOR ALL TO authenticated
  USING (
    bucket_id = 'comprobantes-pago'
    AND (storage.foldername(name))[1] = (SELECT auth.uid())::TEXT
    AND (SELECT public.tiene_rol('alumno'))
  )
  WITH CHECK (
    bucket_id = 'comprobantes-pago'
    AND (storage.foldername(name))[1] = (SELECT auth.uid())::TEXT
    AND (SELECT public.tiene_rol('alumno'))
  );
