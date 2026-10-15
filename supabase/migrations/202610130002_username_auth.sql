DROP TRIGGER IF EXISTS create_student_row_for_auth_user ON auth.users;
DROP FUNCTION IF EXISTS public.create_student_row_for_auth_user();
DROP FUNCTION IF EXISTS public.is_username_available(TEXT);
DROP FUNCTION IF EXISTS public.get_email_for_username(TEXT);
DROP INDEX IF EXISTS public.alumnos_username_case_insensitive_uidx;
