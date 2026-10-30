-- Uptime Kuma (louislam/uptime-kuma @ 6da8aa1, MIT). redbean-node over knex with `?` placeholders (normalised to ?N).
-- R.getAll/getRow/getCell/exec pass the SQL through knex.raw; R.find/findOne/findAll/count wrap a WHERE fragment as
-- knex renders it (`select * from \`t\` where <fragment>`, `.first()` adds `limit ?`, getCell/count append ` limit ?`);
-- those reconstructions are tagged dynamic. Paths are repo-relative.

-- @id uptime_kuma.client.heartbeat_list
-- @src server/client.js:47-55
-- @style ? positional, R.getAll
-- @tags hotpath
-- @note Dashboard heartbeat bar per monitor: newest 100 by time on the (monitor_id, time) index.
-- @param ?1 42
SELECT * FROM heartbeat
WHERE monitor_id = ?1
ORDER BY time DESC
LIMIT 100;

-- @id uptime_kuma.client.latest_heartbeat_per_monitor
-- @src server/client.js:75-95
-- @style ? positional, IN list of monitor ids (chunked)
-- @tags hotpath,dynamic
-- @note Latest beat for every monitor on the dashboard: grouped MAX(id) derived table joined back by primary key.
-- @param ?1 11
-- @param ?2 12
-- @param ?3 13
-- @param ?4 21
-- @param ?5 42
-- @param ?6 57
-- @param ?7 64
-- @param ?8 88
SELECT h.id, h.monitor_id, h.status, h.msg, h.time, h.ping, h.important, h.duration, h.down_count, h.retries
FROM heartbeat h
JOIN (
    SELECT monitor_id, MAX(id) AS max_id
    FROM heartbeat
    WHERE monitor_id IN (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)
    GROUP BY monitor_id
) latest ON h.id = latest.max_id;

-- @id uptime_kuma.client.heartbeat_list_compact
-- @src server/client.js:106-119
-- @style ? positional, R.getAll
-- @tags hotpath
-- @note Compact variant of the heartbeat bar (explicit columns).
-- @param ?1 43
SELECT id, monitor_id, status, msg, time, ping, important, duration, down_count, retries
FROM heartbeat
WHERE monitor_id = ?1
ORDER BY time DESC
LIMIT 100;

-- @id uptime_kuma.client.important_heartbeat_list
-- @src server/client.js:132-141
-- @style ? positional, R.find -> knex.table("heartbeat").whereRaw(fragment)
-- @tags hotpath,dynamic
-- @note Important events (status flips) for a monitor via the partial index on (monitor_id, time) WHERE important = 1.
-- @param ?1 42
select * from `heartbeat` where monitor_id = ?1 AND important = 1 ORDER BY time DESC LIMIT 500;

-- @id uptime_kuma.server.important_heartbeat_paged_all
-- @src server/server.js:1124-1135
-- @style ? positional, R.find -> knex whereRaw
-- @tags hotpath,dynamic
-- @note Global event log page: all monitors' important beats, newest first, LIMIT/OFFSET.
-- @param ?1 25
-- @param ?2 50
select * from `heartbeat` where important = 1 ORDER BY time DESC LIMIT ?1 OFFSET ?2;

-- @id uptime_kuma.server.important_heartbeat_count
-- @src server/server.js:1100-1108
-- @style ? positional, R.count -> getCell("SELECT COUNT(*) FROM ?? WHERE ...") with the auto ` limit ?`
-- @tags hotpath,dynamic
-- @note Event count for the pager, on the partial index.
-- @param ?1 42
-- @param ?2 1
SELECT COUNT(*) FROM `heartbeat` WHERE monitor_id = ?1 AND important = 1 limit ?2;

-- @id uptime_kuma.monitor.previous_beat
-- @src server/model/monitor.js:509
-- @style ? positional, R.findOne -> knex whereRaw(...).first()
-- @tags hot-small,hotpath,dynamic
-- @note Runs before every single check: newest beat of the monitor, top-1.
-- @param ?1 42
-- @param ?2 1
select * from `heartbeat` where monitor_id = ?1 ORDER BY time DESC limit ?2;

-- @id uptime_kuma.monitor.insert_heartbeat
-- @src server/model/monitor.js:517-1088
-- @style ? positional, R.store(bean) -> knex insert with the bean's columns sorted
-- @tags hot-small,hotpath,dynamic
-- @note One insert per check across every monitor (four heartbeat indexes, two of them partial).
-- @param ?1 0
-- @param ?2 60
-- @param ?3 NULL
-- @param ?4 0
-- @param ?5 42
-- @param ?6 '200 - OK'
-- @param ?7 87
-- @param ?8 NULL
-- @param ?9 0
-- @param ?10 1
-- @param ?11 '2025-11-02 01:00:42.123'
insert into `heartbeat` (`down_count`, `duration`, `end_time`, `important`, `monitor_id`, `msg`, `ping`, `response`, `retries`, `status`, `time`)
values (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11);

-- @id uptime_kuma.monitor.last_down_heartbeat
-- @src server/model/monitor.js:1535-1538
-- @style ? positional, R.getRow
-- @tags hot-small,hotpath
-- @note Last important DOWN beat for a monitor (partial index).
-- @param ?1 42
-- @param ?2 0
SELECT time FROM heartbeat WHERE monitor_id = ?1 AND status = ?2 AND important = 1 ORDER BY time DESC LIMIT 1;

-- @id uptime_kuma.monitor.list_all
-- @src server/uptime-kuma-server.js:284-301
-- @style R.findAll -> knex whereRaw(" 1=1 " + orderBy)
-- @tags hotpath,dynamic
-- @note Monitor list sent to every dashboard socket: ~90-column rows ordered by weight then name.
select * from `monitor` where  1=1 ORDER BY weight DESC, name;

-- @id uptime_kuma.monitor.preload_tags
-- @src server/model/monitor.js:1852-1863
-- @style ? positional, IN list over all listed monitors
-- @tags hotpath,dynamic
-- @note Tags for the monitor list: monitor_tag JOIN tag with an IN list.
-- @param ?1 11
-- @param ?2 12
-- @param ?3 15
-- @param ?4 18
-- @param ?5 21
-- @param ?6 30
-- @param ?7 42
-- @param ?8 99
SELECT monitor_tag.monitor_id, monitor_tag.tag_id, monitor_tag.value, tag.name, tag.color
FROM monitor_tag
JOIN tag ON monitor_tag.tag_id = tag.id
WHERE monitor_tag.monitor_id IN (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8);

-- @id uptime_kuma.monitor.tags_for_monitor
-- @src server/model/monitor.js:277-280
-- @style ? positional, R.getAll
-- @tags hotpath
-- @note Tags of one monitor joined to tag, sorted by tag name.
-- @param ?1 42
SELECT mt.*, tag.name, tag.color FROM monitor_tag mt JOIN tag ON mt.tag_id = tag.id WHERE mt.monitor_id = ?1 ORDER BY tag.name;

-- @id uptime_kuma.monitor.notification_list
-- @src server/model/monitor.js:1575-1578
-- @style ? positional, R.getAll
-- @tags hotpath
-- @note Notifications to send for a monitor on a status change: comma join.
-- @param ?1 42
SELECT notification.* FROM notification, monitor_notification WHERE monitor_id = ?1 AND monitor_notification.notification_id = notification.id;

-- @id uptime_kuma.monitor.get_parent
-- @src server/model/monitor.js:2025-2035
-- @style ? positional, R.getRow
-- @tags dynamic
-- @note Parent of a monitor through a self LEFT JOIN.
-- @param ?1 43
SELECT parent.* FROM monitor parent
LEFT JOIN monitor child
    ON child.parent = parent.id
WHERE child.id = ?1;

-- @id uptime_kuma.uptime.load_history
-- @src server/uptime-calculator.js:186-191
-- @style ? positional, table name spliced in (stat_minutely here)
-- @tags hotpath,dynamic
-- @note UptimeCalculator warm-up: a day of minutely buckets for one monitor in timestamp order.
-- @param ?1 42
-- @param ?2 1762041600
SELECT timestamp, up, down, ping, ping_min, ping_max, extras
FROM stat_minutely WHERE monitor_id = ?1 AND timestamp > ?2 ORDER BY timestamp;

-- @id uptime_kuma.uptime.find_stat_bucket
-- @src server/uptime-calculator.js:390-395
-- @style ? positional, R.findOne -> knex whereRaw(...).first()
-- @tags hot-small,hotpath,dynamic
-- @note Point lookup of the current hourly bucket on the (monitor_id, timestamp) unique index.
-- @param ?1 42
-- @param ?2 1761958800
-- @param ?3 1
select * from `stat_hourly` where monitor_id = ?1 AND timestamp = ?2 limit ?3;

-- @id uptime_kuma.uptime.upsert_stat
-- @src server/uptime-calculator.js:427-448
-- @style ? positional, knex insert(...).onConflict(["monitor_id", "timestamp"]).merge(cols); insert columns sorted by knex
-- @tags hot-small,hotpath,dynamic
-- @note Per-beat aggregate upsert into stat_minutely (and hourly/daily): ON CONFLICT DO UPDATE SET col = excluded.col.
-- @param ?1 0
-- @param ?2 42
-- @param ?3 98.5
-- @param ?4 210
-- @param ?5 20
-- @param ?6 1762045140
-- @param ?7 2
insert into `stat_minutely` (`down`, `monitor_id`, `ping`, `ping_max`, `ping_min`, `timestamp`, `up`) values (?1, ?2, ?3, ?4, ?5, ?6, ?7)
on conflict (`monitor_id`, `timestamp`) do update set `up` = excluded.`up`, `down` = excluded.`down`, `ping` = excluded.`ping`, `ping_min` = excluded.`ping_min`, `ping_max` = excluded.`ping_max`;

-- @id uptime_kuma.uptime.delete_old_minutely
-- @src server/uptime-calculator.js:346-356
-- @style ? positional, R.exec
-- @tags hotpath
-- @note Rolling-window trim of a monitor's minutely buckets.
-- @param ?1 42
-- @param ?2 1762002000
DELETE FROM stat_minutely WHERE monitor_id = ?1 AND timestamp < ?2;

-- @id uptime_kuma.stats.sum_by_monitor
-- @src server/monitor-stats.ts:55-70
-- @style ? positional, table spliced in (stat_hourly here), IN list of monitor ids
-- @tags hotpath,dynamic
-- @note Dashboard uptime/avg ping for many monitors: SUM(up), SUM(down), SUM(ping * up) grouped by monitor.
-- @param ?1 1759500000
-- @param ?2 11
-- @param ?3 12
-- @param ?4 13
-- @param ?5 21
-- @param ?6 42
-- @param ?7 57
-- @param ?8 64
-- @param ?9 88
SELECT monitor_id,
        SUM(up) AS up,
        SUM(down) AS down,
        SUM(ping * up) AS ping_sum
 FROM stat_hourly
 WHERE timestamp >= ?1 AND monitor_id IN (?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9)
 GROUP BY monitor_id;

-- @id uptime_kuma.stats.uptime_30d_1y
-- @src server/monitor-stats.ts:105-117
-- @style ? positional, IN list of monitor ids
-- @tags hotpath,dynamic
-- @note 30-day and 1-year uptime in one pass over stat_daily: CASE-conditional SUMs grouped by monitor.
-- @param ?1 1759363200
-- @param ?2 1759363200
-- @param ?3 1730419200
-- @param ?4 11
-- @param ?5 12
-- @param ?6 13
-- @param ?7 21
-- @param ?8 42
-- @param ?9 57
-- @param ?10 64
-- @param ?11 88
SELECT monitor_id,
        SUM(CASE WHEN timestamp >= ?1 THEN up ELSE 0 END) AS up30,
        SUM(CASE WHEN timestamp >= ?2 THEN down ELSE 0 END) AS down30,
        SUM(up) AS up1y,
        SUM(down) AS down1y
 FROM stat_daily
 WHERE timestamp >= ?3 AND monitor_id IN (?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11)
 GROUP BY monitor_id;

-- @id uptime_kuma.status_page.find_by_slug
-- @src server/routers/status-page-router.js:46
-- @style ? positional, R.findOne -> knex whereRaw(...).first()
-- @tags hot-small,hotpath,dynamic
-- @note Status page lookup on every public page view.
-- @param ?1 'status'
-- @param ?2 1
select * from `status_page` where  slug = ?1  limit ?2;

-- @id uptime_kuma.status_page.public_monitor_ids
-- @src server/routers/status-page-router.js:75-84
-- @style ? positional, R.getCol
-- @tags hotpath
-- @note Public status page heartbeat endpoint: monitors in the page's public groups via a comma join on `group`.
-- @param ?1 1
SELECT monitor_group.monitor_id FROM monitor_group, `group`
WHERE monitor_group.group_id = `group`.id
AND public = 1
AND `group`.status_page_id = ?1;

-- @id uptime_kuma.status_page.group_monitor_list
-- @src server/model/group.js:33-45
-- @style ? positional, R.getAll
-- @tags hotpath
-- @note Monitors of a status-page group, ordered by the link weight, with link columns appended to monitor.*.
-- @param ?1 3
SELECT monitor.*, monitor_group.send_url, monitor_group.custom_url FROM monitor, monitor_group
WHERE monitor.id = monitor_group.monitor_id
AND group_id = ?1
ORDER BY monitor_group.weight;

-- @id uptime_kuma.status_page.incident_history
-- @src server/model/status_page.js:519-531
-- @style ? positional, R.find -> knex whereRaw (cursor branch)
-- @tags hotpath,dynamic
-- @note Incident history page with a created_date cursor, newest first, top-N.
-- @param ?1 1
-- @param ?2 '2026-06-01 00:00:00'
-- @param ?3 10
select * from `incident` where  status_page_id = ?1 AND created_date < ?2 ORDER BY created_date DESC LIMIT ?3 ;
