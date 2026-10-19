DROP FUNCTION IF EXISTS public.validar_preinscripcion_alumno(TEXT, TEXT);

CREATE OR REPLACE FUNCTION public.validar_preinscripcion_alumno(
  p_cedula TEXT,
  p_correo TEXT
)
RETURNS BOOLEAN
LANGUAGE PLPGSQL
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  normalized_cedula TEXT;
  matching_cedula TEXT;
  normalized_email TEXT;
  is_valid BOOLEAN;
BEGIN
  normalized_cedula := REGEXP_REPLACE(
    UPPER(BTRIM(COALESCE(p_cedula, ''))),
    '[^A-Z0-9]',
    '',
    'g'
  );
  matching_cedula := CASE
    WHEN normalized_cedula ~ '^[VEJG][0-9]{5,12}$'
      THEN SUBSTRING(normalized_cedula FROM 2)
    ELSE normalized_cedula
  END;
  normalized_email := LOWER(BTRIM(COALESCE(p_correo, '')));

  IF normalized_cedula !~ '^([VEJG][0-9]{5,12}|[0-9]{5,12}|P[A-Z0-9]{5,20})$'
     OR normalized_email = ''
     OR POSITION('@' IN normalized_email) < 2
     OR normalized_email ~ '\s' THEN
    RETURN FALSE;
  END IF;

  SELECT
    COUNT(*) = 1
    AND BOOL_AND(
      alumno.user_id IS NULL
      AND NOT COALESCE(alumno.registrado_en_app, FALSE)
      AND (
        NULLIF(BTRIM(alumno.correo), '') IS NULL
        OR LOWER(BTRIM(alumno.correo)) = normalized_email
      )
    )
    INTO is_valid
  FROM public.alumnos AS alumno
  WHERE CASE
    WHEN REGEXP_REPLACE(
      UPPER(BTRIM(alumno.cedula::TEXT)),
      '[^A-Z0-9]',
      '',
      'g'
    ) ~ '^[VEJG][0-9]{5,12}$'
    THEN SUBSTRING(REGEXP_REPLACE(
      UPPER(BTRIM(alumno.cedula::TEXT)),
      '[^A-Z0-9]',
      '',
      'g'
    ) FROM 2)
    ELSE REGEXP_REPLACE(
      UPPER(BTRIM(alumno.cedula::TEXT)),
      '[^A-Z0-9]',
      '',
      'g'
    )
  END = matching_cedula;

  RETURN COALESCE(is_valid, FALSE);
END;
$$;

CREATE OR REPLACE FUNCTION public.vincular_alumno_existente()
RETURNS TRIGGER
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  student_cedula TEXT :=
    NULLIF(BTRIM(NEW.raw_user_meta_data ->> 'cedula'), '');
  normalized_cedula TEXT;
  matching_cedula TEXT;
  normalized_email TEXT := LOWER(BTRIM(COALESCE(NEW.email, '')));
  matching_count INTEGER;
  existing_alumno_id UUID;
  existing_user_id UUID;
  existing_email TEXT;
  already_registered BOOLEAN;
BEGIN
  IF student_cedula IS NULL THEN
    RAISE EXCEPTION 'Student registration requires an identification document';
  END IF;

  normalized_cedula := REGEXP_REPLACE(
    UPPER(student_cedula),
    '[^A-Z0-9]',
    '',
    'g'
  );
  IF normalized_cedula !~ '^([VEJG][0-9]{5,12}|[0-9]{5,12}|P[A-Z0-9]{5,20})$' THEN
    RAISE EXCEPTION 'Student registration requires a valid identification document';
  END IF;

  matching_cedula := CASE
    WHEN normalized_cedula ~ '^[VEJG][0-9]{5,12}$'
      THEN SUBSTRING(normalized_cedula FROM 2)
    ELSE normalized_cedula
  END;

  PERFORM pg_advisory_xact_lock(hashtextextended(matching_cedula, 0));

  SELECT COUNT(*)::INTEGER
    INTO matching_count
  FROM public.alumnos AS alumno
  WHERE CASE
    WHEN REGEXP_REPLACE(
      UPPER(BTRIM(alumno.cedula::TEXT)),
      '[^A-Z0-9]',
      '',
      'g'
    ) ~ '^[VEJG][0-9]{5,12}$'
    THEN SUBSTRING(REGEXP_REPLACE(
      UPPER(BTRIM(alumno.cedula::TEXT)),
      '[^A-Z0-9]',
      '',
      'g'
    ) FROM 2)
    ELSE REGEXP_REPLACE(
      UPPER(BTRIM(alumno.cedula::TEXT)),
      '[^A-Z0-9]',
      '',
      'g'
    )
  END = matching_cedula;

  IF matching_count <> 1 THEN
    RAISE EXCEPTION 'No unique student pre-registration matches this document';
  END IF;

  SELECT
    alumno.id,
    alumno.user_id,
    LOWER(BTRIM(COALESCE(alumno.correo, ''))),
    COALESCE(alumno.registrado_en_app, FALSE)
    INTO
      existing_alumno_id,
      existing_user_id,
      existing_email,
      already_registered
  FROM public.alumnos AS alumno
  WHERE CASE
    WHEN REGEXP_REPLACE(
      UPPER(BTRIM(alumno.cedula::TEXT)),
      '[^A-Z0-9]',
      '',
      'g'
    ) ~ '^[VEJG][0-9]{5,12}$'
    THEN SUBSTRING(REGEXP_REPLACE(
      UPPER(BTRIM(alumno.cedula::TEXT)),
      '[^A-Z0-9]',
      '',
      'g'
    ) FROM 2)
    ELSE REGEXP_REPLACE(
      UPPER(BTRIM(alumno.cedula::TEXT)),
      '[^A-Z0-9]',
      '',
      'g'
    )
  END = matching_cedula;

  IF existing_user_id IS NOT NULL AND existing_user_id <> NEW.id THEN
    RAISE EXCEPTION 'This student record is already linked to another account';
  END IF;
  IF existing_user_id IS NULL AND already_registered THEN
    RAISE EXCEPTION 'This student record is already registered';
  END IF;
  IF existing_email <> ''
     AND existing_email <> normalized_email THEN
    RAISE EXCEPTION 'The email does not match the student pre-registration';
  END IF;

  UPDATE public.alumnos
  SET user_id = NEW.id,
      nombre_completo = COALESCE(
        NULLIF(BTRIM(NEW.raw_user_meta_data ->> 'full_name'), ''),
        nombre_completo
      ),
      correo = COALESCE(NEW.email, correo),
      telefono = COALESCE(
        NULLIF(BTRIM(NEW.raw_user_meta_data ->> 'phone'), ''),
        telefono
      ),
      registrado_en_app = TRUE
  WHERE id = existing_alumno_id;

  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.validar_preinscripcion_alumno(TEXT, TEXT)
  FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.validar_preinscripcion_alumno(TEXT, TEXT)
  TO anon, authenticated;

REVOKE ALL ON FUNCTION public.vincular_alumno_existente()
  FROM PUBLIC, anon, authenticated;
