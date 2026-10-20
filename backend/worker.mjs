const TTL = 60;
const MAX_BODY = 2048;
const slots = new Map();
let nextCleanup = 0;
const headers = { 'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff' };
function json(value, status = 200) { return Response.json(value, { status, headers }); }
function limited(ip) {
  const now = Date.now();
  if (slots.size > 4096) {
    for (const [k, s] of slots) if (s.until <= now) slots.delete(k);
    if (slots.size > 4096) return true;
  }
  let s = slots.get(ip);
  if (!s || now >= s.until) { s = { until: now + 60000, count: 0 }; slots.set(ip, s); }
  return ++s.count > 12;
}
async function hash(token) {
  const bytes = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(token));
  return Array.from(new Uint8Array(bytes), b => b.toString(16).padStart(2, '0')).join('');
}
function token() {
  return Array.from(crypto.getRandomValues(new Uint8Array(32)), b => b.toString(16).padStart(2, '0')).join('');
}
async function body(request) {
  if (!request.headers.get('content-type')?.toLowerCase().startsWith('application/json')) throw new Error('content_type');
  if (Number(request.headers.get('content-length')) > MAX_BODY) throw new Error('too_large');
  if (!request.body) throw new Error('invalid_body');
  const reader = request.body.getReader(); let size = 0; const chunks = [];
  try {
    while (true) {
      const { done, value } = await reader.read(); if (done) break;
      size += value.byteLength;
      if (size > MAX_BODY) { await reader.cancel(); throw new Error('too_large'); }
      chunks.push(value);
    }
  } finally { reader.releaseLock(); }
  const bytes = new Uint8Array(size); let offset = 0;
  for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.length; }
  const data = JSON.parse(new TextDecoder().decode(bytes));
  if (!data || typeof data !== 'object' || Array.isArray(data)) throw new Error('invalid_body');
  return data;
}
export default {
  async fetch(request, env) {
    const path = new URL(request.url).pathname;
    if (request.method === 'GET' && path === '/') return json({service:'ClaudeHub presence', version:'1.0.0', identityVerified:false});
    if (request.method === 'GET' && path === '/health') {
      try { await env.DB.prepare('SELECT session_hash FROM presence_sessions LIMIT 0').all(); return json({ok:true}); }
      catch { return json({ok:false},503); }
    }
    if (!['/v1/heartbeat','/v1/leave'].includes(path)) return json({error:'not_found'},404);
    if (request.method !== 'POST') return json({error:'method_not_allowed'},405);
    // Best-effort per-isolate abuse limit, NOT a global WAF/rate-limit guarantee.
    if (limited(request.headers.get('CF-Connecting-IP') || 'unknown')) return json({error:'rate_limited'},429);
    let d;
    try { d = await body(request); } catch { return json({error:'invalid_request'},400); }
    if (d.token !== undefined && (typeof d.token !== 'string' || !/^[a-f0-9]{64}$/.test(d.token))) return json({error:'invalid_token'},400);
    try {
      if (path === '/v1/leave') {
        if (!d.token) return json({error:'token_required'},400);
        await env.DB.prepare('DELETE FROM presence_sessions WHERE session_hash = ?').bind(await hash(d.token)).run();
        return json({ok:true});
      }
      if (!Number.isSafeInteger(d.userId) || d.userId <= 0 || !Number.isSafeInteger(d.placeId) || d.placeId <= 0 ||
          typeof d.jobId !== 'string' || !/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/i.test(d.jobId)) return json({error:'invalid_identity'},400);
      const now = Math.floor(Date.now()/1000), ownToken = d.token || token();
      const ownHash = await hash(ownToken), job = d.jobId.toLowerCase();
      // A token owns only its session. UserId/JobId remain self-reported, not Roblox-authenticated.
      await env.DB.prepare(`INSERT INTO presence_sessions (session_hash,user_id,place_id,job_id,last_seen)
        VALUES (?,?,?,?,?) ON CONFLICT(session_hash) DO UPDATE SET
        user_id=excluded.user_id,place_id=excluded.place_id,job_id=excluded.job_id,last_seen=excluded.last_seen`)
        .bind(ownHash,d.userId,d.placeId,job,now).run();
      const {results} = await env.DB.prepare(`SELECT DISTINCT user_id FROM presence_sessions
        WHERE place_id=? AND job_id=? AND last_seen>? AND user_id<>? LIMIT 100`)
        .bind(d.placeId,job,now-TTL,d.userId).all();
      if (now >= nextCleanup) {
        nextCleanup = now + 60;
        // Expired rows are excluded immediately; physical cleanup runs on the next heartbeat.
        await env.DB.prepare('DELETE FROM presence_sessions WHERE last_seen <= ?').bind(now-TTL).run();
      }
      return json({ok:true,token:ownToken,peers:results.map(r=>r.user_id),ttl:TTL,pollAfter:20,identityVerified:false});
    } catch { return json({error:'service_unavailable'},503); }
  },
  async scheduled(_event, env) {
    await env.DB.prepare('DELETE FROM presence_sessions WHERE last_seen <= ?').bind(Math.floor(Date.now()/1000)-TTL).run();
  }
};
