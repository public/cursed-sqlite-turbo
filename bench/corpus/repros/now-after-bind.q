@@Q v0 0 0 read
SELECT id, strftime('%Y-%m-%d %H:%M:%f', 'now'), date('now'), julianday('now') FROM e WHERE id <= 1;
@@Q pre 1 0 read
@@P ?1 'success'
SELECT id FROM e WHERE status = ?1 ORDER BY id DESC LIMIT 2;
@@Q v1 0 0 read
SELECT id, strftime('%Y-%m-%d %H:%M:%f', 'now'), date('now'), julianday('now') FROM e WHERE id <= 1;
