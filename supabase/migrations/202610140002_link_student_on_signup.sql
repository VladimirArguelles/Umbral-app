DROP TRIGGER IF EXISTS create_student_row_for_auth_user ON auth.users;
DROP TRIGGER IF EXISTS vincular_alumno_existente ON auth.users;
DROP FUNCTION IF EXISTS public.create_student_row_for_auth_user();

CREATE UNIQUE INDEX IF NOT EXISTS alumnos_user_id_uidx
  ON public.alumnos(user_id);

UPDATE public.alumnos
SET registrado_en_app = TRUE
WHERE user_id IS NOT NULL
  AND registrado_en_app IS DISTINCT FROM TRUE;

CREATE OR REPLACE FUNCTION public.vincular_alumno_existente()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  student_cedula TEXT :=
    NULLIF(BTRIM(NEW.raw_user_meta_data ->> 'cedula'), '');
  matching_count INTEGER;
  existing_alumno_id UUID;
  existing_user_id UUID;
BEGIN
  IF student_cedula IS NULL THEN
    RAISE EXCEPTION 'Student registration requires a national ID';
  END IF;

  PERFORM pg_advisory_xact_lock(
    hashtextextended(regexp_replace(student_cedula, '\s+', '', 'g'), 0)
  );

  SELECT COUNT(*)::INTEGER
    INTO matching_count
  FROM public.alumnos
  WHERE regexp_replace(BTRIM(cedula::TEXT), '\s+', '', 'g')
    = regexp_replace(student_cedula, '\s+', '', 'g');

  IF matching_count > 1 THEN
    RAISE EXCEPTION 'More than one student record matches the national ID';
  END IF;

  SELECT id, user_id
    INTO existing_alumno_id, existing_user_id
  FROM public.alumnos
  WHERE regexp_replace(BTRIM(cedula::TEXT), '\s+', '', 'g')
    = regexp_replace(student_cedula, '\s+', '', 'g');

  IF existing_user_id IS NOT NULL AND existing_user_id <> NEW.id THEN
    RAISE EXCEPTION 'This student record is already linked to another account';
  END IF;

  IF existing_alumno_id IS NULL THEN
    INSERT INTO public.alumnos (
      user_id,
      nombre_completo,
      cedula,
      correo,
      telefono,
      curso_id,
      registrado_en_app
    )
    VALUES (
      NEW.id,
      COALESCE(NEW.raw_user_meta_data ->> 'full_name', ''),
      student_cedula,
      COALESCE(NEW.email, ''),
      COALESCE(NEW.raw_user_meta_data ->> 'phone', ''),
      NULL,
      TRUE
    );
  ELSE
    UPDATE public.alumnos
    SET user_id = NEW.id,
        nombre_completo = COALESCE(
          NULLIF(NEW.raw_user_meta_data ->> 'full_name', ''),
          nombre_completo
        ),
        correo = COALESCE(NEW.email, ''),
        telefono = COALESCE(
          NULLIF(NEW.raw_user_meta_data ->> 'phone', ''),
          telefono
        ),
        registrado_en_app = TRUE
    WHERE id = existing_alumno_id;
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER vincular_alumno_existente
  AFTER INSERT OR UPDATE OF raw_user_meta_data ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.vincular_alumno_existente();

REVOKE ALL ON FUNCTION public.vincular_alumno_existente()
  FROM PUBLIC, anon, authenticated;
