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

CREATE UNIQUE INDEX IF NOT EXISTS accesos_pin_teacher_uidx
  ON public.accesos_pin (profesor_id)
  WHERE modulo = 'profesor';
CREATE UNIQUE INDEX IF NOT EXISTS accesos_pin_admin_uidx
  ON public.accesos_pin (modulo)
  WHERE modulo = 'administrador';

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
      (p_modulo = 'administrador' AND profesor_id IS NULL)
      OR (
        p_modulo = 'profesor'
        AND profesor_id IS NOT NULL
        AND EXISTS (
          SELECT 1
          FROM public.perfiles AS perfil
          WHERE perfil.id = accesos_pin.profesor_id
            AND LOWER(perfil.rol) = 'profesor'
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
