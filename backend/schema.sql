CREATE TABLE IF NOT EXISTS presence_sessions (
  session_hash TEXT PRIMARY KEY,
  user_id INTEGER NOT NULL,
  place_id INTEGER NOT NULL,
  job_id TEXT NOT NULL,
  last_seen INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS presence_peers ON presence_sessions (place_id, job_id, last_seen, user_id);
CREATE INDEX IF NOT EXISTS presence_expiry ON presence_sessions (last_seen);
