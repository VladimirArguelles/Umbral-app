import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

Deno.serve(async (request: Request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (request.method !== "POST") {
    return jsonResponse(405, { error: "Method not allowed" });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const publicKey =
    Deno.env.get("SUPABASE_PUBLISHABLE_KEY") ??
    Deno.env.get("SUPABASE_ANON_KEY");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !publicKey || !serviceRoleKey) {
    console.error("Module PIN function is missing Supabase environment variables.");
    return jsonResponse(500, { error: "Authentication service is unavailable." });
  }

  if (request.headers.get("apikey") !== publicKey) {
    return jsonResponse(401, { error: "Unauthorized" });
  }

  let module: string;
  let pin: string;
  let action: string;
  let payload: Record<string, unknown>;
  let nombres: string;
  let apellidos: string;
  try {
    const body = await request.json();
    module = typeof body.module === "string" ? body.module : "";
    pin = typeof body.pin === "string" ? body.pin : "";
    action = typeof body.action === "string" ? body.action : "verify";
    payload = isRecord(body.payload) ? body.payload : {};
    nombres = typeof body.nombres === "string" ? body.nombres.trim() : "";
    apellidos = typeof body.apellidos === "string"
      ? body.apellidos.trim()
      : "";
  } catch {
    return jsonResponse(400, { error: "Invalid request body." });
  }

  if (!["profesor", "administrador"].includes(module) ||
      !/^\d{4,12}$/.test(pin)) {
    return jsonResponse(400, { error: "Invalid module or PIN." });
  }
  if (
    action === "create_pin" &&
    (nombres.length === 0 ||
      nombres.length > 100 ||
      apellidos.length === 0 ||
      apellidos.length > 100)
  ) {
    return jsonResponse(400, { error: "Invalid profile name." });
  }

  const adminClient = createClient(supabaseUrl, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  if (action === "reset_pin") {
    const authorizationHeader = request.headers.get("Authorization") ?? "";
    const accessToken = authorizationHeader.match(/^Bearer\s+(.+)$/i)?.[1];
    if (!accessToken) {
      return jsonResponse(401, { error: "Authentication is required." });
    }

    const { data: userData, error: userError } =
      await adminClient.auth.getUser(accessToken);
    if (userError || !userData.user) {
      return jsonResponse(401, { error: "The recovery session is invalid." });
    }

    const expectedRole = module === "profesor"
      ? "profesor"
      : "administrador";
    try {
      if (!await hasAssignedRole(adminClient, userData.user.id, expectedRole)) {
        return jsonResponse(403, { error: "This account cannot reset this PIN." });
      }
    } catch (error) {
      console.error("Module PIN recovery role validation failed:", error);
      return jsonResponse(500, { error: "Could not validate the account role." });
    }

    const { data: reset, error: resetError } = await adminClient.rpc(
      "restablecer_pin_modulo",
      {
        p_modulo: module,
        p_profile_id: userData.user.id,
        p_pin: pin,
      },
    );
    if (resetError) {
      console.error("Module PIN reset failed:", resetError.message);
      return jsonResponse(500, { error: "Could not reset the PIN." });
    }
    if (!isRecord(reset) || typeof reset.status !== "string") {
      console.error("Module PIN reset returned an invalid response.");
      return jsonResponse(500, { error: "Could not reset the PIN." });
    }
    return jsonResponse(200, { status: reset.status });
  }

  const clientAddress =
    request.headers.get("cf-connecting-ip")?.trim() ??
    request.headers.get("x-real-ip")?.trim() ??
    request.headers.get("x-forwarded-for")?.split(",")[0].trim();
  if (!clientAddress) {
    console.error("Module PIN request did not include a client address.");
    return jsonResponse(503, { error: "Could not validate the PIN right now." });
  }

  const hashBuffer = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(`${serviceRoleKey}:${clientAddress}`),
  );
  const clientHash = Array.from(new Uint8Array(hashBuffer))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");

  if (action === "create_pin") {
    const { data: setup, error: setupError } = await adminClient.rpc(
      "crear_pin_modulo",
      {
        p_modulo: module,
        p_nombres: nombres,
        p_apellidos: apellidos,
        p_pin: pin,
        p_client_hash: clientHash,
      },
    );
    if (setupError) {
      console.error("Module PIN setup failed:", setupError.message);
      return jsonResponse(500, { error: "Could not create the PIN." });
    }
    if (!isRecord(setup) || typeof setup.status !== "string") {
      console.error("Module PIN setup returned an invalid response.");
      return jsonResponse(500, { error: "Could not create the PIN." });
    }
    return jsonResponse(200, { status: setup.status });
  }

  const { data: authorization, error: authorizationError } =
    await adminClient.rpc("verificar_pin_modulo", {
      p_modulo: module,
      p_pin: pin,
      p_client_hash: clientHash,
    });

  if (authorizationError) {
    console.error("Module PIN validation failed:", authorizationError.message);
    return jsonResponse(500, { error: "Could not validate the PIN." });
  }
  if (!isRecord(authorization) || authorization.valid !== true) {
    return jsonResponse(200, { valid: false });
  }

  const expectedRole = module === "profesor" ? "profesor" : "administrador";
  const profileId = authorization.profile_id;
  if (typeof profileId !== "string") {
    return jsonResponse(200, { valid: false });
  }
  let roleIsAssigned: boolean;
  try {
    roleIsAssigned = await hasAssignedRole(adminClient, profileId, expectedRole);
  } catch (error) {
    console.error("Module role validation failed:", error);
    return jsonResponse(500, { error: "Could not validate the module role." });
  }
  if (!roleIsAssigned) return jsonResponse(200, { valid: false });

  try {
    if (action === "verify") {
      return jsonResponse(200, {
        valid: true,
        profile_id: profileId,
        result: {},
      });
    }
    const result = module === "profesor"
      ? await runTeacherAction(
        adminClient,
        action,
        payload,
        profileId,
      )
      : await runAdminAction(adminClient, action, payload);
    return jsonResponse(200, { valid: true, result });
  } catch (error) {
    console.error("Module operation failed:", error);
    return jsonResponse(400, {
      error: error instanceof Error ? error.message : "Operation failed.",
    });
  }
});

async function hasAssignedRole(
  client: ReturnType<typeof createClient>,
  userId: string,
  roleCode: string,
): Promise<boolean> {
  const { data, error } = await client
    .from("usuario_roles")
    .select("roles!inner(codigo)")
    .eq("usuario_id", userId)
    .eq("roles.codigo", roleCode)
    .limit(1);
  if (error) throw error;
  return (data ?? []).length > 0;
}

async function runTeacherAction(
  client: ReturnType<typeof createClient>,
  action: string,
  payload: Record<string, unknown>,
  professorId: string,
): Promise<Record<string, unknown>> {
  if (action === "dashboard") {
    const { data: courses, error: coursesError } = await client
      .from("cursos")
      .select("id,nombre_curso,estado,horario_inicio,horario_fin,dias_clase")
      .eq("profesor_id", professorId)
      .order("nombre_curso");
    if (coursesError) throw coursesError;

    const courseIds = (courses ?? []).map((course) => course.id);
    if (courseIds.length === 0) {
      return {
        courses: [],
        students: [],
        attendance: [],
        surveys: [],
        responses: [],
      };
    }

    const [
      { data: students, error: studentsError },
      { data: attendance, error: attendanceError },
      { data: surveys, error: surveysError },
    ] = await Promise.all([
      client
        .from("alumnos")
        .select("user_id,curso_id,nombre_completo,cedula,correo,telefono")
        .in("curso_id", courseIds)
        .order("nombre_completo"),
      client
        .from("asistencia")
        .select("user_id,curso_id,clase_fecha,asistio")
        .in("curso_id", courseIds)
        .order("clase_fecha", { ascending: false })
        .limit(500),
      client
        .from("encuestas_participacion")
        .select("id,curso_id,clase_futura_fecha,costo_total_insumos,monto_aporte_individual,created_at")
        .in("curso_id", courseIds)
        .order("clase_futura_fecha", { ascending: true }),
    ]);
    if (studentsError) throw studentsError;
    if (attendanceError) throw attendanceError;
    if (surveysError) throw surveysError;
    const surveyIds = (surveys ?? []).map((survey) => survey.id);
    let responses: Record<string, unknown>[] = [];
    if (surveyIds.length > 0) {
      const { data, error } = await client
        .from("respuestas_encuesta")
        .select("encuesta_id,user_id,participara,fecha_respuesta")
        .in("encuesta_id", surveyIds);
      if (error) throw error;
      responses = data ?? [];
    }
    return {
      courses: courses ?? [],
      students: students ?? [],
      attendance: attendance ?? [],
      surveys: surveys ?? [],
      responses: responses ?? [],
    };
  }

  const courseId = requiredString(payload.course_id, "course_id");
  const { data: course, error: courseError } = await client
    .from("cursos")
    .select("id")
    .eq("id", courseId)
    .eq("profesor_id", professorId)
    .maybeSingle();
  if (courseError) throw courseError;
  if (!course) throw new Error("El curso no pertenece a este profesor.");

  if (action === "save_attendance") {
    const userId = requiredString(payload.user_id, "user_id");
    const date = requiredString(payload.clase_fecha, "clase_fecha");
    if (typeof payload.asistio !== "boolean") {
      throw new Error("El estado de asistencia no es válido.");
    }
    const { data: student, error: studentError } = await client
      .from("alumnos")
      .select("user_id")
      .eq("user_id", userId)
      .eq("curso_id", courseId)
      .maybeSingle();
    if (studentError) throw studentError;
    if (!student) throw new Error("El alumno no está inscrito en este curso.");

    const { data: existing, error: existingError } = await client
      .from("asistencia")
      .select("user_id")
      .eq("user_id", userId)
      .eq("curso_id", courseId)
      .eq("clase_fecha", date)
      .maybeSingle();
    if (existingError) throw existingError;

    const row = {
      user_id: userId,
      curso_id: courseId,
      clase_fecha: date,
      asistio: payload.asistio,
    };
    const query = existing
      ? client
        .from("asistencia")
        .update(row)
        .eq("user_id", userId)
        .eq("curso_id", courseId)
        .eq("clase_fecha", date)
      : client.from("asistencia").insert(row);
    const { error } = await query;
    if (error) throw error;
    return { saved: true };
  }

  if (action === "create_survey") {
    const date = requiredString(payload.clase_futura_fecha, "clase_futura_fecha");
    const totalCost = Number(payload.costo_total_insumos);
    const individualAmount = Number(payload.monto_aporte_individual);
    if (!Number.isFinite(totalCost) || totalCost < 0 ||
        !Number.isFinite(individualAmount) || individualAmount < 0) {
      throw new Error("Los montos de la encuesta no son válidos.");
    }
    const { data, error } = await client
      .from("encuestas_participacion")
      .insert({
        curso_id: courseId,
        clase_futura_fecha: date,
        costo_total_insumos: totalCost,
        monto_aporte_individual: individualAmount,
      })
      .select("id")
      .single();
    if (error) throw error;
    return { id: data.id };
  }

  throw new Error("Acción docente no reconocida.");
}

async function runAdminAction(
  client: ReturnType<typeof createClient>,
  action: string,
  payload: Record<string, unknown>,
): Promise<Record<string, unknown>> {
  if (action === "dashboard") {
    const [
      { data: courses, error: coursesError },
      { data: students, error: studentsError },
      { data: payments, error: paymentsError },
    ] = await Promise.all([
      client.from("cursos").select("id,nombre_curso,estado,profesor_id").order("nombre_curso"),
      client.from("alumnos").select("user_id,nombre_completo,cedula,correo,telefono,curso_id,registrado_en_app").order("nombre_completo"),
      client
        .from("pagos")
        .select("id,user_id,encuesta_id,monto_aporte,imagen_url,estado,created_at,alumnos(nombre_completo),encuestas_participacion(clase_futura_fecha,cursos(nombre_curso))")
        .order("created_at", { ascending: false }),
    ]);
    if (coursesError) throw coursesError;
    if (studentsError) throw studentsError;
    if (paymentsError) throw paymentsError;
    const paymentsWithSignedImages = await Promise.all(
      (payments ?? []).map(async (payment) => {
        const imagePath = payment.imagen_url;
        if (typeof imagePath !== "string" || imagePath.length === 0) {
          return payment;
        }
        if (imagePath.startsWith("http")) {
          return { ...payment, signed_image_url: imagePath };
        }
        const { data, error } = await client.storage
          .from("comprobantes-pago")
          .createSignedUrl(imagePath, 3600);
        if (error) throw error;
        return { ...payment, signed_image_url: data.signedUrl };
      }),
    );
    return {
      courses: courses ?? [],
      students: students ?? [],
      payments: paymentsWithSignedImages,
    };
  }

  if (action === "update_payment") {
    const paymentId = requiredString(payload.payment_id, "payment_id");
    const status = payload.estado;
    if (!["verificado", "rechazado"].includes(String(status))) {
      throw new Error("Estado de pago no válido.");
    }
    const { data, error } = await client
      .from("pagos")
      .update({ estado: status })
      .eq("id", paymentId)
      .select("id,estado")
      .maybeSingle();
    if (error) throw error;
    if (!data) throw new Error("No se encontró el pago.");
    return { payment: data };
  }

  if (action === "update_course_status") {
    const courseId = requiredString(payload.course_id, "course_id");
    const status = payload.estado;
    if (!["activo", "finalizado"].includes(String(status))) {
      throw new Error("Estado de curso no válido.");
    }
    const { data, error } = await client
      .from("cursos")
      .update({ estado: status })
      .eq("id", courseId)
      .select("id,estado")
      .maybeSingle();
    if (error) throw error;
    if (!data) throw new Error("No se encontró el curso.");
    return { course: data };
  }

  if (action === "assign_student_course") {
    const userId = requiredString(payload.user_id, "user_id");
    const courseId = payload.course_id == null
      ? null
      : requiredString(payload.course_id, "course_id");
    if (courseId != null) {
      const { data: course, error: courseError } = await client
        .from("cursos")
        .select("id")
        .eq("id", courseId)
        .maybeSingle();
      if (courseError) throw courseError;
      if (!course) throw new Error("No se encontró el curso seleccionado.");
    }
    const { data, error } = await client
      .from("alumnos")
      .update({ curso_id: courseId })
      .eq("user_id", userId)
      .select("user_id,curso_id")
      .maybeSingle();
    if (error) throw error;
    if (!data) throw new Error("No se encontró el alumno.");
    return { student: data };
  }

  throw new Error("Acción administrativa no reconocida.");
}

function requiredString(value: unknown, field: string): string {
  if (typeof value !== "string" || value.trim().length === 0) {
    throw new Error(`Falta el campo ${field}.`);
  }
  return value.trim();
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function jsonResponse(
  status: number,
  body: Record<string, unknown>,
): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
