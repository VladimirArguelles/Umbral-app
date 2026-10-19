ALTER TABLE public.asistencia
  ADD COLUMN IF NOT EXISTS user_id UUID
    REFERENCES auth.users(id) ON DELETE CASCADE;
ALTER TABLE public.respuestas_encuesta
  ADD COLUMN IF NOT EXISTS user_id UUID
    REFERENCES auth.users(id) ON DELETE CASCADE;
ALTER TABLE public.pagos
  ADD COLUMN IF NOT EXISTS user_id UUID
    REFERENCES auth.users(id) ON DELETE CASCADE;

UPDATE public.asistencia AS asistencia
SET user_id = alumno.user_id
FROM public.alumnos AS alumno
WHERE asistencia.alumno_id = alumno.id
  AND asistencia.user_id IS NULL
  AND alumno.user_id IS NOT NULL;

UPDATE public.respuestas_encuesta AS respuesta
SET user_id = alumno.user_id
FROM public.alumnos AS alumno
WHERE respuesta.alumno_id = alumno.id
  AND respuesta.user_id IS NULL
  AND alumno.user_id IS NOT NULL;

UPDATE public.pagos AS pago
SET user_id = alumno.user_id
FROM public.alumnos AS alumno
WHERE pago.alumno_id = alumno.id
  AND pago.user_id IS NULL
  AND alumno.user_id IS NOT NULL;

CREATE OR REPLACE FUNCTION public.sync_student_user_reference()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = ''
AS $$
DECLARE
  matched_student_id UUID;
  matched_user_id UUID;
BEGIN
  IF NEW.user_id IS NOT NULL THEN
    SELECT alumno.id, alumno.user_id
      INTO matched_student_id, matched_user_id
    FROM public.alumnos AS alumno
    WHERE alumno.user_id = NEW.user_id;

    IF matched_student_id IS NULL THEN
      RAISE EXCEPTION 'The user is not linked to a student record';
    END IF;
    IF NEW.alumno_id IS NOT NULL AND NEW.alumno_id <> matched_student_id THEN
      RAISE EXCEPTION 'The student and user references do not match';
    END IF;
    NEW.alumno_id := matched_student_id;
  ELSIF NEW.alumno_id IS NOT NULL THEN
    SELECT alumno.user_id
      INTO matched_user_id
    FROM public.alumnos AS alumno
    WHERE alumno.id = NEW.alumno_id;
    NEW.user_id := matched_user_id;
  END IF;

  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.sync_student_user_reference()
  FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS sync_asistencia_student_reference
  ON public.asistencia;
CREATE TRIGGER sync_asistencia_student_reference
  BEFORE INSERT OR UPDATE ON public.asistencia
  FOR EACH ROW
  EXECUTE FUNCTION public.sync_student_user_reference();

DROP TRIGGER IF EXISTS sync_respuestas_encuesta_student_reference
  ON public.respuestas_encuesta;
CREATE TRIGGER sync_respuestas_encuesta_student_reference
  BEFORE INSERT OR UPDATE ON public.respuestas_encuesta
  FOR EACH ROW
  EXECUTE FUNCTION public.sync_student_user_reference();

DROP TRIGGER IF EXISTS sync_pagos_student_reference
  ON public.pagos;
CREATE TRIGGER sync_pagos_student_reference
  BEFORE INSERT OR UPDATE ON public.pagos
  FOR EACH ROW
  EXECUTE FUNCTION public.sync_student_user_reference();

CREATE UNIQUE INDEX IF NOT EXISTS respuestas_encuesta_user_survey_uidx
  ON public.respuestas_encuesta (user_id, encuesta_id);
CREATE UNIQUE INDEX IF NOT EXISTS pagos_user_survey_uidx
  ON public.pagos (user_id, encuesta_id);
CREATE UNIQUE INDEX IF NOT EXISTS asistencia_user_course_date_uidx
  ON public.asistencia (user_id, curso_id, clase_fecha);

INSERT INTO storage.buckets (id, name, public)
VALUES ('comprobantes-pago', 'comprobantes-pago', FALSE)
ON CONFLICT (id) DO UPDATE SET public = FALSE;

ALTER TABLE public.alumnos ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.perfiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.cursos ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.asistencia ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.encuestas_participacion ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.respuestas_encuesta ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pagos ENABLE ROW LEVEL SECURITY;

GRANT SELECT ON public.perfiles, public.alumnos, public.cursos,
  public.asistencia, public.encuestas_participacion,
  public.respuestas_encuesta, public.pagos TO authenticated;
GRANT INSERT ON public.asistencia, public.respuestas_encuesta,
  public.pagos TO authenticated;
REVOKE UPDATE ON public.respuestas_encuesta, public.pagos FROM authenticated;
GRANT UPDATE (participara) ON public.respuestas_encuesta TO authenticated;
GRANT UPDATE (imagen_url, monto_aporte, estado)
  ON public.pagos TO authenticated;
GRANT DELETE ON public.pagos TO authenticated;

REVOKE SELECT ON TABLE public.perfiles FROM PUBLIC, anon, authenticated;

DROP POLICY IF EXISTS "Users read own profile" ON public.perfiles;
CREATE POLICY "Users read own profile"
  ON public.perfiles FOR SELECT TO authenticated
  USING (id = (SELECT auth.uid()));

DROP POLICY IF EXISTS "Students read own student record" ON public.alumnos;
CREATE POLICY "Students read own student record"
  ON public.alumnos FOR SELECT TO authenticated
  USING (user_id = (SELECT auth.uid()));

DROP POLICY IF EXISTS "Students read enrolled course" ON public.cursos;
CREATE POLICY "Students read enrolled course"
  ON public.cursos FOR SELECT TO authenticated
  USING (EXISTS (
    SELECT 1 FROM public.alumnos
    WHERE alumnos.curso_id = cursos.id
      AND alumnos.user_id = (SELECT auth.uid())
  ));

DROP POLICY IF EXISTS "Students read own attendance" ON public.asistencia;
CREATE POLICY "Students read own attendance"
  ON public.asistencia FOR SELECT TO authenticated
  USING (user_id = (SELECT auth.uid()));

DROP POLICY IF EXISTS "Students mark own attendance" ON public.asistencia;
CREATE POLICY "Students mark own attendance"
  ON public.asistencia FOR INSERT TO authenticated
  WITH CHECK (
    user_id = (SELECT auth.uid())
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
    activa
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
  USING (user_id = (SELECT auth.uid()));

DROP POLICY IF EXISTS "Students answer enrolled surveys"
  ON public.respuestas_encuesta;
CREATE POLICY "Students answer enrolled surveys"
  ON public.respuestas_encuesta FOR INSERT TO authenticated
  WITH CHECK (
    user_id = (SELECT auth.uid())
    AND EXISTS (
      SELECT 1
      FROM public.encuestas_participacion AS survey
      JOIN public.alumnos AS student
        ON student.curso_id = survey.curso_id
      WHERE survey.id = respuestas_encuesta.encuesta_id
        AND survey.activa
        AND student.user_id = (SELECT auth.uid())
    )
  );

DROP POLICY IF EXISTS "Students update own survey answers"
  ON public.respuestas_encuesta;
CREATE POLICY "Students update own survey answers"
  ON public.respuestas_encuesta FOR UPDATE TO authenticated
  USING (user_id = (SELECT auth.uid()))
  WITH CHECK (
    user_id = (SELECT auth.uid())
    AND EXISTS (
      SELECT 1
      FROM public.encuestas_participacion AS survey
      JOIN public.alumnos AS student
        ON student.curso_id = survey.curso_id
      WHERE survey.id = respuestas_encuesta.encuesta_id
        AND survey.activa
        AND student.user_id = (SELECT auth.uid())
    )
  );

DROP POLICY IF EXISTS "Students read own payments" ON public.pagos;
CREATE POLICY "Students read own payments"
  ON public.pagos FOR SELECT TO authenticated
  USING (user_id = (SELECT auth.uid()));

DROP POLICY IF EXISTS "Students submit own payments" ON public.pagos;
CREATE POLICY "Students submit own payments"
  ON public.pagos FOR INSERT TO authenticated
  WITH CHECK (
    user_id = (SELECT auth.uid())
    AND estado = 'pendiente'
    AND imagen_url LIKE (SELECT auth.uid())::TEXT || '/%'
    AND EXISTS (
      SELECT 1
      FROM public.encuestas_participacion AS survey
      JOIN public.alumnos AS student
        ON student.curso_id = survey.curso_id
      WHERE survey.id = pagos.encuesta_id
        AND survey.activa
        AND student.user_id = (SELECT auth.uid())
        AND pagos.monto_aporte = survey.monto_aporte_individual
    )
  );

DROP POLICY IF EXISTS "Students update own unreviewed payments" ON public.pagos;
CREATE POLICY "Students update own unreviewed payments"
  ON public.pagos FOR UPDATE TO authenticated
  USING (
    user_id = (SELECT auth.uid())
    AND estado IN ('pendiente', 'rechazado')
    AND imagen_url LIKE (SELECT auth.uid())::TEXT || '/%'
  )
  WITH CHECK (
    user_id = (SELECT auth.uid())
    AND estado = 'pendiente'
    AND imagen_url LIKE (SELECT auth.uid())::TEXT || '/%'
    AND EXISTS (
      SELECT 1
      FROM public.encuestas_participacion AS survey
      JOIN public.alumnos AS student
        ON student.curso_id = survey.curso_id
      WHERE survey.id = pagos.encuesta_id
        AND survey.activa
        AND student.user_id = (SELECT auth.uid())
        AND pagos.monto_aporte = survey.monto_aporte_individual
    )
  );

DROP POLICY IF EXISTS "Students delete own pending payments" ON public.pagos;
CREATE POLICY "Students delete own pending payments"
  ON public.pagos FOR DELETE TO authenticated
  USING (user_id = (SELECT auth.uid()) AND estado = 'pendiente');

DROP POLICY IF EXISTS "Students manage own payment proofs"
  ON storage.objects;
CREATE POLICY "Students manage own payment proofs"
  ON storage.objects FOR ALL TO authenticated
  USING (
    bucket_id = 'comprobantes-pago'
    AND (storage.foldername(name))[1] = (SELECT auth.uid())::TEXT
  )
  WITH CHECK (
    bucket_id = 'comprobantes-pago'
    AND (storage.foldername(name))[1] = (SELECT auth.uid())::TEXT
  );
