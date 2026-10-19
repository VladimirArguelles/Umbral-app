CREATE OR REPLACE FUNCTION public.restablecer_pin_modulo(
  p_modulo TEXT,
  p_profile_id UUID,
  p_pin TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  expected_role TEXT;
BEGIN
  IF p_modulo IS NULL
     OR p_profile_id IS NULL
     OR p_pin IS NULL
     OR p_modulo NOT IN ('profesor', 'administrador')
     OR p_pin !~ '^[0-9]{4,12}$' THEN
    RETURN jsonb_build_object('status', 'invalid_identity');
  END IF;

  expected_role := p_modulo;
  IF NOT EXISTS (
    SELECT 1
    FROM public.perfiles AS perfil
    JOIN public.usuario_roles AS asignacion
      ON asignacion.usuario_id = perfil.id
    JOIN public.roles AS rol
      ON rol.id = asignacion.rol_id
    WHERE perfil.id = p_profile_id
      AND rol.codigo = expected_role
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
          ))) IN ('administrador', 'admin', 'super_admin', 'super-admin')
        )
      )
  ) THEN
    RETURN jsonb_build_object('status', 'invalid_identity');
  END IF;

  BEGIN
    INSERT INTO public.accesos_pin (
      modulo,
      profesor_id,
      pin_hash,
      pin_lookup_hash,
      activo,
      updated_at
    )
    VALUES (
      p_modulo,
      p_profile_id,
      extensions.crypt(p_pin, extensions.gen_salt('bf')),
      ENCODE(EXTENSIONS.DIGEST(CONVERT_TO(p_pin, 'UTF8'), 'sha256'), 'hex'),
      TRUE,
      NOW()
    )
    ON CONFLICT (modulo, profesor_id)
      WHERE profesor_id IS NOT NULL
    DO UPDATE SET
      pin_hash = EXCLUDED.pin_hash,
      pin_lookup_hash = EXCLUDED.pin_lookup_hash,
      activo = TRUE,
      updated_at = NOW();
  EXCEPTION
    WHEN unique_violation THEN
      RETURN jsonb_build_object('status', 'pin_in_use');
  END;

  RETURN jsonb_build_object('status', 'reset');
END;
$$;

REVOKE ALL ON FUNCTION public.restablecer_pin_modulo(TEXT, UUID, TEXT)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.restablecer_pin_modulo(TEXT, UUID, TEXT)
  TO service_role;
