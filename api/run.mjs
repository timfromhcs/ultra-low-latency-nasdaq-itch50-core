import { run } from "./_core.mjs";
export default async function handler(req, res) {
  res.setHeader("access-control-allow-origin", "*");
  if (req.method === "OPTIONS") return res.status(204).end();
  if (req.method !== "POST") return res.status(405).json({ ok: false, error: "POST only" });
  try { return res.status(200).json(await run(req.body || {})); }
  catch (e) { return res.status(500).json({ ok: false, error: String(e?.message || e) }); }
}
