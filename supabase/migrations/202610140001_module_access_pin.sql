CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;
ALTER EXTENSION pgcrypto SET SCHEMA extensions;

DROP FUNCTION IF EXISTS public.is_username_available(TEXT);
DROP FUNCTION IF EXISTS public.get_email_for_username(TEXT);

CREATE TABLE IF NOT EXISTS public.accesos_pin (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  modulo TEXT NOT NULL CHECK (modulo IN ('profesor', 'administrador')),
  profesor_id UUID REFERENCES public.perfiles(id) ON DELETE CASCADE,
  pin_hash TEXT NOT NULL,
  activo BOOLEAN NOT NULL DEFAULT TRUE,
  CONSTRAINT accesos_pin_module_identity_check CHECK (
    (modulo = 'profesor' AND profesor_id IS NOT NULL)
    OR (modulo = 'administrador' AND profesor_id IS NULL)
  ),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.accesos_pin
  ADD COLUMN IF NOT EXISTS modulo TEXT,
  ADD COLUMN IF NOT EXISTS profesor_id UUID REFERENCES public.perfiles(id) ON DELETE CASCADE,
  ADD COLUMN IF NOT EXISTS pin_hash TEXT,
  ADD COLUMN IF NOT EXISTS pin_lookup_hash TEXT,
  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW();

UPDATE public.accesos_pin AS acceso
SET modulo = COALESCE(acceso.modulo, NULLIF(TO_JSONB(acceso) ->> 'rol', '')),
    pin_hash = COALESCE(
      acceso.pin_hash,
      CASE
        WHEN NULLIF(TO_JSONB(acceso) ->> 'pin', '') IS NOT NULL
          THEN extensions.crypt(
            TO_JSONB(acceso) ->> 'pin',
            extensions.gen_salt('bf')
          )
        ELSE NULL
      END
    ),
    pin_lookup_hash = COALESCE(
      acceso.pin_lookup_hash,
      CASE
        WHEN NULLIF(TO_JSONB(acceso) ->> 'pin', '') IS NOT NULL
          THEN ENCODE(
            extensions.digest(
              CONVERT_TO(TO_JSONB(acceso) ->> 'pin', 'UTF8'),
              'sha256'
            ),
            'hex'
          )
        ELSE NULL
      END
    ),
    profesor_id = COALESCE(
      acceso.profesor_id,
      (
        SELECT (ARRAY_AGG(perfil.id ORDER BY perfil.id))[1]
        FROM public.perfiles AS perfil
        WHERE LOWER(BTRIM(COALESCE(
            TO_JSONB(perfil) ->> 'nombre_completo',
            TO_JSONB(perfil) ->> 'nombre',
            TO_JSONB(perfil) ->> 'full_name',
            TO_JSONB(perfil) ->> 'name',
            ''
          ))) = LOWER(BTRIM(COALESCE(
            TO_JSONB(acceso) ->> 'nombre',
            ''
          )))
          AND LOWER(BTRIM(COALESCE(
            TO_JSONB(perfil) ->> 'role',
            TO_JSONB(perfil) ->> 'rol',
            ''
          ))) IN (
            CASE
              WHEN COALESCE(acceso.modulo, TO_JSONB(acceso) ->> 'rol')
                   = 'profesor' THEN 'profesor'
              ELSE 'administrador'
            END,
            CASE
              WHEN COALESCE(acceso.modulo, TO_JSONB(acceso) ->> 'rol')
                   = 'profesor' THEN 'docente'
              ELSE 'admin'
            END,
            CASE
              WHEN COALESCE(acceso.modulo, TO_JSONB(acceso) ->> 'rol')
                   = 'profesor' THEN 'profesor'
              ELSE 'super_admin'
            END,
            CASE
              WHEN COALESCE(acceso.modulo, TO_JSONB(acceso) ->> 'rol')
                   = 'profesor' THEN 'profesor'
              ELSE 'super-admin'
            END
          )
        HAVING COUNT(*) = 1
      )
    ),
    updated_at = COALESCE(acceso.updated_at, NOW());

UPDATE public.accesos_pin
SET activo = FALSE
WHERE modulo NOT IN ('profesor', 'administrador')
   OR pin_hash IS NULL
   OR (modulo = 'profesor' AND profesor_id IS NULL)
   OR (modulo = 'administrador' AND profesor_id IS NULL);

DELETE FROM public.accesos_pin
WHERE pin_hash IS NULL;

WITH duplicate_profiles AS (
  SELECT id,
         ROW_NUMBER() OVER (
           PARTITION BY modulo, profesor_id
           ORDER BY id
         ) AS duplicate_number
  FROM public.accesos_pin
  WHERE profesor_id IS NOT NULL
)
UPDATE public.accesos_pin AS acceso
SET profesor_id = NULL,
    activo = FALSE
FROM duplicate_profiles AS duplicate
WHERE duplicate.id = acceso.id
  AND duplicate.duplicate_number > 1;

WITH duplicate_pins AS (
  SELECT id,
         ROW_NUMBER() OVER (
           PARTITION BY modulo, pin_lookup_hash
           ORDER BY id
         ) AS duplicate_number
  FROM public.accesos_pin
  WHERE pin_lookup_hash IS NOT NULL
)
UPDATE public.accesos_pin AS acceso
SET pin_lookup_hash = NULL,
    activo = FALSE
FROM duplicate_pins AS duplicate
WHERE duplicate.id = acceso.id
  AND duplicate.duplicate_number > 1;

ALTER TABLE public.accesos_pin
  DROP COLUMN IF EXISTS nombre,
  DROP COLUMN IF EXISTS rol,
  DROP COLUMN IF EXISTS pin;

ALTER TABLE public.accesos_pin
  ALTER COLUMN modulo SET NOT NULL,
  ALTER COLUMN pin_hash SET NOT NULL;

ALTER TABLE public.accesos_pin
  DROP CONSTRAINT IF EXISTS accesos_pin_module_identity_check;
ALTER TABLE public.accesos_pin
  ADD CONSTRAINT accesos_pin_module_identity_check CHECK (
    (modulo = 'profesor' AND (profesor_id IS NOT NULL OR NOT activo))
    OR (
      modulo = 'administrador'
      AND (
        profesor_id IS NOT NULL
        OR (profesor_id IS NULL AND NOT activo)
      )
    )
  );

CREATE UNIQUE INDEX IF NOT EXISTS accesos_pin_teacher_uidx
  ON public.accesos_pin (profesor_id)
  WHERE modulo = 'profesor';
CREATE UNIQUE INDEX IF NOT EXISTS accesos_pin_admin_uidx
  ON public.accesos_pin (profesor_id)
  WHERE modulo = 'administrador'
    AND profesor_id IS NOT NULL;

CREATE TABLE IF NOT EXISTS public.accesos_pin_intentos (
  client_hash TEXT NOT NULL,
  modulo TEXT NOT NULL CHECK (modulo IN ('profesor', 'administrador')),
  attempted_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS accesos_pin_intentos_recent_idx
  ON public.accesos_pin_intentos (client_hash, modulo, attempted_at DESC);

ALTER TABLE public.accesos_pin ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.accesos_pin_intentos ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.accesos_pin FROM PUBLIC, anon, authenticated;
REVOKE ALL ON TABLE public.accesos_pin_intentos FROM PUBLIC, anon, authenticated;

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

  SELECT pin_hash, profesor_id
    INTO pin_record
  FROM public.accesos_pin
  WHERE modulo = p_modulo
    AND activo
    AND (
      (
        p_modulo = 'administrador'
        AND profesor_id IS NOT NULL
        AND EXISTS (
          SELECT 1
          FROM public.perfiles AS perfil
          WHERE perfil.id = accesos_pin.profesor_id
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
        AND extensions.crypt(p_pin, pin_hash) = pin_hash
      )
      OR (
        p_modulo = 'profesor'
        AND profesor_id IS NOT NULL
        AND EXISTS (
          SELECT 1
          FROM public.perfiles AS perfil
          WHERE perfil.id = accesos_pin.profesor_id
            AND LOWER(BTRIM(COALESCE(
              TO_JSONB(perfil) ->> 'role',
              TO_JSONB(perfil) ->> 'rol',
              ''
            ))) IN ('profesor', 'docente')
        )
        AND extensions.crypt(p_pin, pin_hash) = pin_hash
      )
    )
  LIMIT 1;

  IF pin_record.pin_hash IS NOT NULL
     AND extensions.crypt(p_pin, pin_record.pin_hash) = pin_record.pin_hash THEN
    DELETE FROM public.accesos_pin_intentos
    WHERE client_hash = p_client_hash
      AND modulo = p_modulo;
    RETURN jsonb_build_object(
      'valid', TRUE,
      'profesor_id', pin_record.profesor_id
    );
  END IF;

  INSERT INTO public.accesos_pin_intentos (client_hash, modulo)
  VALUES (p_client_hash, p_modulo);

  RETURN jsonb_build_object('valid', FALSE);
END;
$$;

REVOKE ALL ON FUNCTION public.verificar_pin_modulo(TEXT, TEXT, TEXT)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.verificar_pin_modulo(TEXT, TEXT, TEXT)
  TO service_role;
