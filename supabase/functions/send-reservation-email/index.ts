// Sends a reservation-confirmation email via Resend.
//
// Deploy: Supabase Dashboard -> Edge Functions -> New Function ->
//   name it "send-reservation-email", paste this file's contents, Deploy.
// Then set the secret it needs: Project Settings -> Edge Functions -> Secrets
//   RESEND_API_KEY = <your Resend API key, from resend.com>
//
// Only admins can trigger this — it verifies the caller's JWT against
// admin_profiles before sending anything.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const RESEND_API_KEY = Deno.env.get("RESEND_API_KEY");
const FROM_EMAIL = "La Note Gourmande <reservations@lanotegourmande.com>";

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }

  const authHeader = req.headers.get("Authorization") || "";
  const jwt = authHeader.replace("Bearer ", "");
  const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

  const { data: userData, error: userError } = await admin.auth.getUser(jwt);
  if (userError || !userData.user) {
    return new Response(JSON.stringify({ error: "unauthorized" }), { status: 401 });
  }
  const { data: profile } = await admin
    .from("admin_profiles")
    .select("id")
    .eq("id", userData.user.id)
    .maybeSingle();
  if (!profile) {
    return new Response(JSON.stringify({ error: "forbidden" }), { status: 403 });
  }

  if (!RESEND_API_KEY) {
    return new Response(JSON.stringify({ error: "RESEND_API_KEY not configured" }), { status: 500 });
  }

  const { name, email, date, time, guests, seating } = await req.json();
  if (!name || !email || !date || !time || !guests) {
    return new Response(JSON.stringify({ error: "missing fields" }), { status: 400 });
  }

  const resp = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${RESEND_API_KEY}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      from: FROM_EMAIL,
      to: email,
      subject: "Votre réservation est confirmée — La Note Gourmande",
      html: `
        <div style="font-family:Georgia,serif;color:#2A2520;max-width:480px;margin:0 auto;padding:24px">
          <h2 style="color:#DE6326">La Note Gourmande</h2>
          <p>Bonjour ${name},</p>
          <p>Votre réservation est <strong>confirmée</strong> :</p>
          <ul>
            <li>Date : ${date}</li>
            <li>Heure : ${time}</li>
            <li>Convives : ${guests}</li>
            ${seating ? `<li>Emplacement : ${seating}</li>` : ""}
          </ul>
          <p>Adidogomé Atigangomé - Apédokoè, sur la route non goudronnée en face de la station Sanol, juste à 100 mètres.</p>
          <p>À très bientôt !</p>
        </div>
      `,
    }),
  });

  if (!resp.ok) {
    const body = await resp.text();
    return new Response(JSON.stringify({ error: "resend_failed", detail: body }), { status: 502 });
  }

  return new Response(JSON.stringify({ ok: true }), {
    headers: { "Content-Type": "application/json" },
  });
});
