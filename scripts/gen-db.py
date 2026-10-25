#!/usr/bin/env python3
"""gen-db.py <out.db> [users posts likes]: a deterministic test database with a small social-feed schema (users, posts,
likes, the indexes the tests' queries use), ANALYZEd so SQLite's planner picks the plans the tests expect. Defaults:
50,000 users, 200,000 posts, 800,000 likes (~70 MB). Likes are 80 % uniform and 20 % on the newest posts."""
import os, random, sqlite3, sys
out = sys.argv[1]
nu, np_, nl = (int(x) for x in sys.argv[2:5]) if len(sys.argv) >= 5 else (50000, 200000, 800000)
for suffix in ('', '-wal', '-shm'):
    if os.path.exists(out + suffix): os.remove(out + suffix)
db = sqlite3.connect(out)
db.executescript('''
PRAGMA journal_mode=WAL;
CREATE TABLE users (
  id          INTEGER PRIMARY KEY,
  username    TEXT NOT NULL UNIQUE,
  created_at  TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
);
CREATE TABLE posts (
  id          INTEGER PRIMARY KEY,
  user_id     INTEGER NOT NULL REFERENCES users(id),
  body        TEXT NOT NULL CHECK (length(body) BETWEEN 1 AND 500),
  created_at  TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
);
CREATE TABLE likes (
  user_id     INTEGER NOT NULL REFERENCES users(id),
  post_id     INTEGER NOT NULL REFERENCES posts(id),
  created_at  TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  PRIMARY KEY (user_id, post_id)
);
''')
rng = random.Random(20261025)
words = ('alpha beta gamma delta lorem ipsum dolor sit amet sqlite jit fast feed post like user query plan index '
         'tree page cell record value native code').split()
def ts(i, n):   # timestamps increase with the row number, 2025-01-01 .. 2026-01-01, ms resolution
    ms = 1735689600000 + int(i * (31536000000 / max(n, 1)))
    s, msr = divmod(ms, 1000)
    import time
    return time.strftime('%Y-%m-%dT%H:%M:%S', time.gmtime(s)) + '.%03dZ' % msr
db.executemany('INSERT INTO users(id, username, created_at) VALUES (?,?,?)',
               ((i, 'user%05d_%s' % (i, rng.choice(words)), ts(i, nu)) for i in range(1, nu + 1)))
db.executemany('INSERT INTO posts(id, user_id, body, created_at) VALUES (?,?,?,?)',
               ((i, rng.randint(1, nu), ' '.join(rng.choice(words) for _ in range(rng.randint(3, 40))), ts(i, np_))
                for i in range(1, np_ + 1)))
def likes():
    seen = set()
    while len(seen) < nl:
        u = rng.randint(1, nu)
        # 80 % uniform, 20 % on the newest posts (mean distance 2,000): ~4 likes per post, ~80 on the newest
        p = rng.randint(1, np_) if rng.random() < 0.8 else max(1, np_ - int(rng.expovariate(1 / 2000)))
        if (u, p) in seen: continue
        seen.add((u, p)); yield (u, p, ts(len(seen), nl))
db.executemany('INSERT INTO likes(user_id, post_id, created_at) VALUES (?,?,?)', likes())
db.executescript('''
CREATE INDEX posts_created_at_id_idx ON posts (created_at DESC, id DESC);
CREATE INDEX posts_user_id_idx       ON posts (user_id);
CREATE INDEX likes_post_id_idx       ON likes (post_id);
ANALYZE;
PRAGMA wal_checkpoint(TRUNCATE);
''')
db.commit(); db.close()
print(f'gen-db: {out}: {nu} users, {np_} posts, {nl} likes')
