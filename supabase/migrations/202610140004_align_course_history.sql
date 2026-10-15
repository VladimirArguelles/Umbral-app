DO $$
BEGIN
  IF to_regclass('public.historial_cursos') IS NOT NULL
     AND EXISTS (
       SELECT 1
       FROM information_schema.columns
       WHERE table_schema = 'public'
         AND table_name = 'historial_cursos'
         AND column_name = 'alumno_id'
     )
     AND NOT EXISTS (
       SELECT 1
       FROM information_schema.columns
       WHERE table_schema = 'public'
         AND table_name = 'historial_cursos'
         AND column_name = 'user_id'
     ) THEN
    ALTER TABLE public.historial_cursos
      RENAME COLUMN alumno_id TO user_id;
  END IF;
END;
$$;

ALTER TABLE public.historial_cursos
  DROP CONSTRAINT IF EXISTS historial_cursos_alumno_id_fkey;
ALTER TABLE public.historial_cursos
  DROP CONSTRAINT IF EXISTS historial_cursos_user_id_fkey;
ALTER TABLE public.historial_cursos
  ADD CONSTRAINT historial_cursos_user_id_fkey
  FOREIGN KEY (user_id) REFERENCES public.alumnos(user_id) ON DELETE CASCADE;

DROP POLICY IF EXISTS "Students can read their own course history"
  ON public.historial_cursos;
CREATE POLICY "Students can read their own course history"
  ON public.historial_cursos
  FOR SELECT TO authenticated
  USING (user_id = (SELECT auth.uid()));

CREATE OR REPLACE FUNCTION public.record_completed_course_history()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF NEW.estado = 'finalizado'
     AND OLD.estado IS DISTINCT FROM NEW.estado THEN
    INSERT INTO public.historial_cursos (
      user_id,
      curso_id,
      fecha_inscripcion,
      fecha_finalizacion
    )
    SELECT
      alumno.user_id,
      NEW.id,
      NOW(),
      NOW()
    FROM public.alumnos AS alumno
    WHERE alumno.user_id IS NOT NULL
      AND alumno.curso_id = NEW.id
    ON CONFLICT (user_id, curso_id) DO NOTHING;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS record_completed_course_history ON public.cursos;
CREATE TRIGGER record_completed_course_history
  AFTER UPDATE OF estado ON public.cursos
  FOR EACH ROW
  EXECUTE FUNCTION public.record_completed_course_history();
