ALTER TABLE public.accesos_pin
  ADD COLUMN IF NOT EXISTS pin_lookup_hash TEXT;

UPDATE public.accesos_pin
SET activo = FALSE
WHERE modulo = 'administrador'
  AND profesor_id IS NULL;

ALTER TABLE public.accesos_pin
  DROP CONSTRAINT IF EXISTS accesos_pin_module_identity_check;

ALTER TABLE public.accesos_pin
  ADD CONSTRAINT accesos_pin_module_identity_check CHECK (
    (
      modulo = 'profesor'
      AND (profesor_id IS NOT NULL OR NOT activo)
    )
    OR (
      modulo = 'administrador'
      AND (
        profesor_id IS NOT NULL
        OR (profesor_id IS NULL AND NOT activo)
      )
    )
  );

DROP INDEX IF EXISTS public.accesos_pin_teacher_uidx;
DROP INDEX IF EXISTS public.accesos_pin_admin_uidx;

CREATE UNIQUE INDEX IF NOT EXISTS accesos_pin_profile_uidx
  ON public.accesos_pin (modulo, profesor_id)
  WHERE profesor_id IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS accesos_pin_lookup_uidx
  ON public.accesos_pin (modulo, pin_lookup_hash)
  WHERE pin_lookup_hash IS NOT NULL;

CREATE OR REPLACE FUNCTION public.crear_pin_modulo(
  p_modulo TEXT,
  p_nombres TEXT,
  p_apellidos TEXT,
  p_pin TEXT,
  p_client_hash TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  profile_count INTEGER;
  matched_profile_id UUID;
  recent_attempts INTEGER;
  inserted_rows INTEGER;
  normalized_nombres TEXT;
  normalized_apellidos TEXT;
BEGIN
  IF p_modulo IS NULL
     OR p_nombres IS NULL
     OR p_apellidos IS NULL
     OR p_pin IS NULL
     OR p_client_hash IS NULL
     OR p_modulo NOT IN ('profesor', 'administrador')
     OR BTRIM(p_nombres) = ''
     OR BTRIM(p_apellidos) = ''
     OR LENGTH(BTRIM(p_nombres)) > 100
     OR LENGTH(BTRIM(p_apellidos)) > 100
     OR p_pin !~ '^[0-9]{4,12}$'
     OR p_client_hash !~ '^[0-9a-f]{64}$' THEN
    RETURN jsonb_build_object('status', 'invalid_identity');
  END IF;

  normalized_nombres :=
    REGEXP_REPLACE(LOWER(BTRIM(p_nombres)), '\s+', ' ', 'g');
  normalized_apellidos :=
    REGEXP_REPLACE(LOWER(BTRIM(p_apellidos)), '\s+', ' ', 'g');

  PERFORM pg_advisory_xact_lock(
    hashtextextended(p_client_hash || ':' || p_modulo, 0)
  );

  DELETE FROM public.accesos_pin_intentos
  WHERE client_hash = p_client_hash
    AND modulo = p_modulo
    AND attempted_at < NOW() - INTERVAL '15 minutes';

  SELECT COUNT(*)::INTEGER
    INTO recent_attempts
  FROM public.accesos_pin_intentos
  WHERE client_hash = p_client_hash
    AND modulo = p_modulo
    AND attempted_at >= NOW() - INTERVAL '15 minutes';

  IF recent_attempts >= 5 THEN
    RETURN jsonb_build_object('status', 'invalid_identity');
  END IF;

  WITH profile_values AS (
    SELECT
      perfil.id,
      LOWER(BTRIM(COALESCE(
        TO_JSONB(perfil) ->> 'rol',
        TO_JSONB(perfil) ->> 'role',
        ''
      ))) AS role_name,
      TO_JSONB(perfil) AS profile_data
    FROM public.perfiles AS perfil
  ),
  profile_names AS (
    SELECT
      id,
      role_name,
      REGEXP_REPLACE(LOWER(BTRIM(COALESCE(
        profile_data ->> 'nombres',
        profile_data ->> 'first_name',
        profile_data ->> 'first_names',
        ''
      ))), '\s+', ' ', 'g') AS first_names,
      REGEXP_REPLACE(LOWER(BTRIM(COALESCE(
        profile_data ->> 'apellidos',
        profile_data ->> 'apellido',
        profile_data ->> 'last_name',
        profile_data ->> 'last_names',
        ''
      ))), '\s+', ' ', 'g') AS last_names,
      REGEXP_REPLACE(LOWER(BTRIM(COALESCE(
        profile_data ->> 'nombre_completo',
        profile_data ->> 'nombre',
        profile_data ->> 'nombres_y_apellidos',
        profile_data ->> 'full_name',
        profile_data ->> 'name',
        ''
      ))), '\s+', ' ', 'g') AS full_name
    FROM profile_values
  )
  SELECT COUNT(*)::INTEGER
    INTO profile_count
  FROM profile_names
  WHERE (
      (p_modulo = 'profesor' AND role_name = 'profesor')
      OR (
        p_modulo = 'administrador'
        AND role_name IN (
          'administrador',
          'admin',
          'super_admin',
          'super-admin'
        )
      )
    )
    AND (
      (
        first_names <> ''
        AND last_names <> ''
        AND first_names = normalized_nombres
        AND last_names = normalized_apellidos
      )
      OR (
        (first_names = '' OR last_names = '')
        AND full_name <> ''
        AND full_name = normalized_nombres || ' ' || normalized_apellidos
      )
      OR (
        first_names <> ''
        AND last_names = ''
        AND first_names = normalized_nombres || ' ' || normalized_apellidos
      )
    );

  IF profile_count <> 1 THEN
    INSERT INTO public.accesos_pin_intentos (client_hash, modulo)
    VALUES (p_client_hash, p_modulo);
    RETURN jsonb_build_object('status', 'invalid_identity');
  END IF;

  WITH profile_values AS (
    SELECT
      perfil.id,
      LOWER(BTRIM(COALESCE(
        TO_JSONB(perfil) ->> 'rol',
        TO_JSONB(perfil) ->> 'role',
        ''
      ))) AS role_name,
      TO_JSONB(perfil) AS profile_data
    FROM public.perfiles AS perfil
  ),
  profile_names AS (
    SELECT
      id,
      role_name,
      REGEXP_REPLACE(LOWER(BTRIM(COALESCE(
        profile_data ->> 'nombres',
        profile_data ->> 'first_name',
        profile_data ->> 'first_names',
        ''
      ))), '\s+', ' ', 'g') AS first_names,
      REGEXP_REPLACE(LOWER(BTRIM(COALESCE(
        profile_data ->> 'apellidos',
        profile_data ->> 'apellido',
        profile_data ->> 'last_name',
        profile_data ->> 'last_names',
        ''
      ))), '\s+', ' ', 'g') AS last_names,
      REGEXP_REPLACE(LOWER(BTRIM(COALESCE(
        profile_data ->> 'nombre_completo',
        profile_data ->> 'nombre',
        profile_data ->> 'nombres_y_apellidos',
        profile_data ->> 'full_name',
        profile_data ->> 'name',
        ''
      ))), '\s+', ' ', 'g') AS full_name
    FROM profile_values
  )
  SELECT id
    INTO matched_profile_id
  FROM profile_names
  WHERE (
      (p_modulo = 'profesor' AND role_name = 'profesor')
      OR (
        p_modulo = 'administrador'
        AND role_name IN (
          'administrador',
          'admin',
          'super_admin',
          'super-admin'
        )
      )
    )
    AND (
      (
        first_names <> ''
        AND last_names <> ''
        AND first_names = normalized_nombres
        AND last_names = normalized_apellidos
      )
      OR (
        (first_names = '' OR last_names = '')
        AND full_name <> ''
        AND full_name = normalized_nombres || ' ' || normalized_apellidos
      )
      OR (
        first_names <> ''
        AND last_names = ''
        AND first_names = normalized_nombres || ' ' || normalized_apellidos
      )
    )
  LIMIT 1;

  IF EXISTS (
    SELECT 1
    FROM public.accesos_pin
    WHERE modulo = p_modulo
      AND profesor_id = matched_profile_id
  ) THEN
    RETURN jsonb_build_object('status', 'already_configured');
  END IF;

  INSERT INTO public.accesos_pin (
    modulo,
    profesor_id,
    pin_hash,
    pin_lookup_hash
  )
  VALUES (
    p_modulo,
    matched_profile_id,
    EXTENSIONS.CRYPT(p_pin, EXTENSIONS.GEN_SALT('bf')),
    ENCODE(EXTENSIONS.DIGEST(CONVERT_TO(p_pin, 'UTF8'), 'sha256'), 'hex')
  )
  ON CONFLICT DO NOTHING;

  GET DIAGNOSTICS inserted_rows = ROW_COUNT;
  IF inserted_rows = 1 THEN
    RETURN jsonb_build_object('status', 'created');
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.accesos_pin
    WHERE modulo = p_modulo
      AND profesor_id = matched_profile_id
  ) THEN
    RETURN jsonb_build_object('status', 'already_configured');
  END IF;

  RETURN jsonb_build_object('status', 'pin_in_use');
END;
$$;

CREATE OR REPLACE FUNCTION public.verificar_pin_modulo(
  p_modulo TEXT,
  p_pin TEXT,
  p_client_hash TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  pin_record RECORD;
  recent_attempts INTEGER;
  computed_pin_lookup_hash TEXT;
BEGIN
  IF p_modulo IS NULL
     OR p_pin IS NULL
     OR p_client_hash IS NULL
     OR p_modulo NOT IN ('profesor', 'administrador')
     OR p_pin !~ '^[0-9]{4,12}$'
     OR p_client_hash !~ '^[0-9a-f]{64}$' THEN
    RETURN jsonb_build_object('valid', FALSE);
  END IF;

  PERFORM pg_advisory_xact_lock(
    hashtextextended(p_client_hash || ':' || p_modulo, 0)
  );

  DELETE FROM public.accesos_pin_intentos
  WHERE client_hash = p_client_hash
    AND modulo = p_modulo
    AND attempted_at < NOW() - INTERVAL '15 minutes';

  SELECT COUNT(*)::INTEGER
    INTO recent_attempts
  FROM public.accesos_pin_intentos
  WHERE client_hash = p_client_hash
    AND modulo = p_modulo
    AND attempted_at >= NOW() - INTERVAL '15 minutes';

  IF recent_attempts >= 5 THEN
    RETURN jsonb_build_object('valid', FALSE);
  END IF;

  computed_pin_lookup_hash :=
    ENCODE(EXTENSIONS.DIGEST(CONVERT_TO(p_pin, 'UTF8'), 'sha256'), 'hex');

  SELECT accesos_pin.pin_hash, accesos_pin.profesor_id
    INTO pin_record
  FROM public.accesos_pin
  JOIN public.perfiles AS perfil
    ON perfil.id = accesos_pin.profesor_id
  WHERE accesos_pin.modulo = p_modulo
    AND accesos_pin.activo
    AND accesos_pin.profesor_id IS NOT NULL
    AND (
      (
        p_modulo = 'profesor'
        AND LOWER(BTRIM(COALESCE(
          TO_JSONB(perfil) ->> 'role',
          TO_JSONB(perfil) ->> 'rol',
          ''
        ))) IN ('profesor', 'docente')
      )
      OR (
        p_modulo = 'administrador'
        AND LOWER(BTRIM(COALESCE(
          TO_JSONB(perfil) ->> 'role',
          TO_JSONB(perfil) ->> 'rol',
          ''
        ))) IN (
          'administrador',
          'admin',
          'super_admin',
          'super-admin'
        )
      )
    )
    AND (
      accesos_pin.pin_lookup_hash = computed_pin_lookup_hash
      OR (
        accesos_pin.pin_lookup_hash IS NULL
        AND EXTENSIONS.CRYPT(p_pin, accesos_pin.pin_hash)
          = accesos_pin.pin_hash
      )
    )
  LIMIT 1;

  IF pin_record.pin_hash IS NOT NULL THEN
    DELETE FROM public.accesos_pin_intentos
    WHERE client_hash = p_client_hash
      AND modulo = p_modulo;
    RETURN jsonb_build_object(
      'valid', TRUE,
      'profile_id', pin_record.profesor_id
    );
  END IF;

  INSERT INTO public.accesos_pin_intentos (client_hash, modulo)
  VALUES (p_client_hash, p_modulo);

  RETURN jsonb_build_object('valid', FALSE);
END;
$$;

REVOKE ALL ON FUNCTION public.crear_pin_modulo(
  TEXT, TEXT, TEXT, TEXT, TEXT
) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.crear_pin_modulo(
  TEXT, TEXT, TEXT, TEXT, TEXT
) TO service_role;

REVOKE ALL ON FUNCTION public.verificar_pin_modulo(TEXT, TEXT, TEXT)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.verificar_pin_modulo(TEXT, TEXT, TEXT)
  TO service_role;
