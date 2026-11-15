import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, x-client-info, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), {
  status,
  headers: { ...corsHeaders, "Content-Type": "application/json" },
});

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  try {
    const openAiKey = Deno.env.get("OPENAI_API_KEY");
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const publishableKey = Deno.env.get("SUPABASE_ANON_KEY") ?? Deno.env.get("SUPABASE_PUBLISHABLE_KEY");
    if (!openAiKey) return json({ error: "AI service is not configured yet. Add OPENAI_API_KEY to Supabase Function Secrets." }, 503);
    if (!supabaseUrl || !publishableKey) return json({ error: "Supabase server configuration is incomplete." }, 500);

    const auth = req.headers.get("Authorization");
    if (!auth?.startsWith("Bearer ")) return json({ error: "Authentication required." }, 401);
    const token = auth.slice(7);
    const supabase = createClient(supabaseUrl, publishableKey, {
      global: { headers: { Authorization: auth } },
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data: { user }, error: userError } = await supabase.auth.getUser(token);
    if (userError || !user) return json({ error: "Please sign in to use BFB AI." }, 401);

    const [adminCheck, viewerCheck] = await Promise.all([
      supabase.rpc("is_bx_admin"),
      supabase.rpc("is_bx_approved_viewer"),
    ]);
    if (adminCheck.error || viewerCheck.error) {
      return json({ error: "Could not verify tracker access. Please sign in again." }, 403);
    }
    if (!adminCheck.data && !viewerCheck.data) {
      return json({ error: "BFB AI is available to approved tracker members. Please contact a BFB X Tracker admin for access." }, 403);
    }

    const body = await req.json();
    const message = typeof body.message === "string" ? body.message.trim() : "";
    const history = Array.isArray(body.history) ? body.history.slice(-8) : [];
    if (!message || message.length > 1500) {
      return json({ error: "Enter a message of up to 1,500 characters." }, 400);
    }

    // Run reads as the signed-in user so the project's existing RLS policies apply.
    // Deliberately exclude account details, player locations, admin logs, and free-text notes.
    const [players, combos, tournaments, matches, groups, participants, scoring] = await Promise.all([
      supabase.from("players").select("id,name,team,combos,decks").limit(100),
      supabase.from("combos").select("id,name,blade,ratchet,bit,type,owner_id").limit(150),
      supabase.from("tournaments").select("id,name,tournament_date,location,format")
        .order("tournament_date", { ascending: false }).limit(50),
      supabase.from("matches").select("match_date,tournament_id,group_id,round_name,player1_id,player2_id,player1_points,player2_points,finish_type")
        .order("match_date", { ascending: false }).limit(150),
      supabase.from("tournament_groups").select("id,tournament_id,name,sort_order").limit(100),
      supabase.from("tournament_participants").select("tournament_id,player_id,group_id,seed").limit(150),
      supabase.from("scoring").select("finish_type,points").limit(30),
    ]);
    for (const result of [players, combos, tournaments, matches, groups, participants, scoring]) {
      if (result.error) throw new Error("Could not load tracker data: " + result.error.message);
    }

    const trackerData = {
      players: players.data ?? [],
      combos: combos.data ?? [],
      tournaments: tournaments.data ?? [],
      matches: matches.data ?? [],
      groups: groups.data ?? [],
      participants: participants.data ?? [],
      finish_scoring: scoring.data ?? [],
    };
    const safeHistory = history
      .filter((m: any) => m && ["user", "assistant"].includes(m.role) && typeof m.content === "string")
      .map((m: any) => ({ role: m.role, content: m.content.slice(0, 1200) }));

    const response = await fetch("https://api.openai.com/v1/responses", {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${openAiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model: "gpt-5.4-mini",
        store: false,
        instructions: `You are BFB AI, the helpful assistant for Beyblade Fans BD's Beyblade X community tracker. Answer questions about Beyblade X and the supplied tracker records. Use only the supplied tracker data for claims about this league's players, combos, matches, rankings, and tournaments. Never invent records, rankings, outcomes, stats, dates, or combos. When data is insufficient, say so clearly. You are read-only: never claim to add, edit, delete, approve, or register anything. Do not reveal personal account information or admin activity. Keep responses friendly, concise, and useful. If asked outside Beyblade/tracker scope, politely steer back.`,
        input: [
          { role: "user", content: "Current read-only BFB X Tracker data (JSON):\n" + JSON.stringify(trackerData) },
          ...safeHistory,
          { role: "user", content: message },
        ],
        max_output_tokens: 500,
      }),
    });
    const result = await response.json();
    if (!response.ok) {
      console.error("OpenAI API error", response.status, result);
      return json({ error: "The AI service could not answer right now. Please try again shortly." }, 502);
    }
    const answer = (result.output ?? [])
      .flatMap((item: any) => item.content ?? [])
      .filter((item: any) => item.type === "output_text")
      .map((item: any) => item.text)
      .join("\n").trim();
    if (!answer) return json({ error: "The AI returned an empty answer. Please try again." }, 502);
    return json({ answer });
  } catch (error) {
    console.error("bfbx-ai-chat error", error);
    return json({ error: "Something went wrong while preparing your answer." }, 500);
  }
});
