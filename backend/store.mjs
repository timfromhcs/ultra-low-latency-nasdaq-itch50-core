// =============================================================================
// File: backend/store.mjs
// Description: Tiny atomic JSON store for the local cloud. No database, no
//              network, no directory traversal. One file per namespace under
//              CHIPLAB_DATA_DIR (default .data).
// =============================================================================
import fs from "node:fs";
import path from "node:path";

export const NAMESPACE_RE = /^[a-zA-Z0-9_-]{1,32}$/;
export const MAX_BYTES = 1024 * 1024;
export const MAX_NAMESPACES = 64;

export class LocalStore {
  constructor(dir) {
    this.dir = path.resolve(dir || process.env.CHIPLAB_DATA_DIR || ".data");
    fs.mkdirSync(this.dir, { recursive: true });
  }

  file(ns) {
    if (!NAMESPACE_RE.test(ns)) throw Object.assign(new Error("invalid namespace"), { status: 400 });
    return path.join(this.dir, `${ns}.json`);
  }

  list() {
    return fs.readdirSync(this.dir)
      .filter((f) => f.endsWith(".json"))
      .map((f) => f.slice(0, -5))
      .filter((n) => NAMESPACE_RE.test(n))
      .slice(0, MAX_NAMESPACES);
  }

  get(ns) {
    const p = this.file(ns);
    if (!fs.existsSync(p)) return null;
    try {
      const obj = JSON.parse(fs.readFileSync(p, "utf8"));
      if (!obj || typeof obj !== "object" || typeof obj.revision !== "number") return null;
      return obj;
    } catch {
      return null;
    }
  }

  put(ns, data, expectedRevision = null) {
    const current = this.get(ns);
    const revision = (current?.revision || 0) + 1;
    if (expectedRevision !== null && expectedRevision !== (current?.revision || 0)) {
      throw Object.assign(new Error("revision conflict"), { status: 409 });
    }
    const body = JSON.stringify({ revision, updatedAt: new Date().toISOString(), data }, null, 2);
    if (Buffer.byteLength(body) > MAX_BYTES) {
      throw Object.assign(new Error("store payload too large"), { status: 413 });
    }
    const p = this.file(ns);
    const tmp = `${p}.${process.pid}.${Date.now()}.tmp`;
    fs.writeFileSync(tmp, body, { encoding: "utf8", mode: 0o600 });
    fs.renameSync(tmp, p);
    return { revision, updatedAt: JSON.parse(body).updatedAt };
  }

  del(ns) {
    const p = this.file(ns);
    if (fs.existsSync(p)) fs.unlinkSync(p);
    return true;
  }
}
