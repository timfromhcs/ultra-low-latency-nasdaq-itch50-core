import { health } from "./_core.mjs";
export default function handler(req, res) {
  res.setHeader("access-control-allow-origin", "*");
  res.status(200).json(health());
}
