CREATE UNIQUE INDEX IF NOT EXISTS alumnos_user_id_uidx
  ON public.alumnos(user_id);

ALTER TABLE public.cursos
  ADD COLUMN IF NOT EXISTS descripcion TEXT,
  ADD COLUMN IF NOT EXISTS estado TEXT NOT NULL DEFAULT 'activo';

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conrelid = 'public.cursos'::regclass
      AND conname = 'cursos_estado_check'
  ) THEN
    ALTER TABLE public.cursos
      ADD CONSTRAINT cursos_estado_check
      CHECK (estado IN ('activo', 'finalizado'));
  END IF;
END;
$$;

CREATE TABLE IF NOT EXISTS public.historial_cursos (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES public.alumnos(user_id) ON DELETE CASCADE,
  curso_id UUID NOT NULL REFERENCES public.cursos(id) ON DELETE CASCADE,
  fecha_inscripcion TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  fecha_finalizacion TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (user_id, curso_id)
);

ALTER TABLE public.historial_cursos ENABLE ROW LEVEL SECURITY;

GRANT SELECT ON public.historial_cursos TO authenticated;

CREATE POLICY "Students can read their own course history"
  ON public.historial_cursos
  FOR SELECT
  TO authenticated
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

CREATE TRIGGER record_completed_course_history
  AFTER UPDATE OF estado ON public.cursos
  FOR EACH ROW
  EXECUTE FUNCTION public.record_completed_course_history();
