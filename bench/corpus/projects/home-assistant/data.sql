-- Synthetic data for Home Assistant's recorder. Deterministic (no random()): values come from multiplicative hashes
-- of the row number. "Now" is 1790000000 (float epoch seconds, as the recorder stores them).
-- Scale 1: 400 entities (states_meta), 2660 attribute sets, 200k states over the 10-day purge window, 20 event types,
-- 2000 event_data rows, 30k events, 150 statistics with 45 days of hourly rows (162k) and 3 days of 5-minute rows
-- (130k). _cfg.scale multiplies states, events and the number of statistics.
BEGIN;

CREATE TEMP TABLE _dom(k INTEGER PRIMARY KEY, d TEXT);
INSERT INTO _dom VALUES (0,'climate'),(1,'light'),(2,'light'),(3,'switch'),(4,'binary_sensor'),(5,'binary_sensor'),
  (6,'person'),(7,'device_tracker'),(8,'automation'),(9,'input_boolean'),(10,'cover'),(11,'media_player'),
  (12,'counter'),(13,'sensor'),(14,'sensor'),(15,'sensor'),(16,'sensor'),(17,'sensor'),(18,'sensor'),(19,'sensor');

-- entity_id = <domain>.e<metadata_id>; domain = metadata_id % 20. Ids 381-400 never get states (purge candidates).
WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 400)
INSERT INTO states_meta(metadata_id, entity_id)
SELECT i, (SELECT d FROM _dom WHERE k = i % 20) || '.e' || i FROM n;

-- 7 attribute sets per entity: attributes_id (m*7-6 .. m*7). Half the sensors carry a unit_of_measurement.
WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 2660)
INSERT INTO state_attributes(attributes_id, hash, shared_attrs)
SELECT i, (i * 2654435761) % 4294967296,
  CASE
    WHEN dom = 'sensor' AND m % 2 = 1 THEN json_object('state_class','measurement','unit_of_measurement',
         CASE m % 3 WHEN 0 THEN '°C' WHEN 1 THEN 'W' ELSE '%' END, 'device_class',
         CASE m % 3 WHEN 0 THEN 'temperature' WHEN 1 THEN 'power' ELSE 'humidity' END, 'friendly_name', 'Sensor ' || m)
    WHEN dom = 'sensor' THEN json_object('friendly_name', 'Text sensor ' || m, 'icon', 'mdi:information-outline')
    WHEN dom = 'climate' THEN json_object('hvac_modes', json_array('off','heat','cool'), 'min_temp', 7, 'max_temp', 35,
         'current_temperature', 18 + (i % 7), 'temperature', 20 + (i % 3), 'friendly_name', 'Thermostat ' || m,
         'supported_features', 385)
    WHEN dom = 'light' THEN json_object('supported_color_modes', json_array('brightness','color_temp'), 'color_mode',
         'brightness', 'brightness', (i * 37) % 256, 'friendly_name', 'Light ' || m, 'supported_features', 40)
    WHEN dom = 'person' OR dom = 'device_tracker' THEN json_object('source_type','gps','latitude', 52.1 + (i % 10) / 100.0,
         'longitude', 4.3 + (i % 13) / 100.0, 'gps_accuracy', 10 + i % 40, 'friendly_name', 'Tracker ' || m)
    ELSE json_object('friendly_name', initcap_dom || ' ' || m, 'icon', 'mdi:' || dom)
  END
FROM (SELECT i, (i + 6) / 7 AS m, (SELECT d FROM _dom WHERE k = ((i + 6) / 7) % 20) AS dom,
             upper(substr((SELECT d FROM _dom WHERE k = ((i + 6) / 7) % 20), 1, 1)) ||
             substr((SELECT d FROM _dom WHERE k = ((i + 6) / 7) % 20), 2) AS initcap_dom FROM n);

-- states: 200k rows spread evenly over the last 10 days. Half the rows go to the 40 hottest entities.
-- old_state_id = previous state of the same entity; last_changed_ts NULL (= last_updated_ts) for ~75 %.
WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 200000*(SELECT scale FROM _cfg)),
g AS (SELECT i, h, m, (SELECT d FROM _dom WHERE k = m % 20) AS dom,
             1790000000.0 - 864000.0 + i * (864000.0 / (200000*(SELECT scale FROM _cfg))) + (h % 1000) / 1000.0 AS ts
      FROM (SELECT i, h, CASE WHEN (h / 2) % 2 = 0 THEN ((h / 4) % 40) + 1 ELSE ((h / 256) % 380) + 1 END AS m
            FROM (SELECT i, (i * 2654435761) % 4294967296 AS h FROM n)))
INSERT INTO states(state_id, state, last_changed_ts, last_reported_ts, last_updated_ts, old_state_id, attributes_id,
                   origin_idx, context_id_bin, context_user_id_bin, context_parent_id_bin, metadata_id)
SELECT i,
  CASE WHEN (h / 131072) % 50 = 0 THEN 'unavailable'
       WHEN dom = 'sensor' THEN printf('%.1f', 15 + ((h / 1024) % 200) / 10.0)
       WHEN dom = 'climate' THEN CASE (h / 2048) % 3 WHEN 0 THEN 'off' ELSE 'heat' END
       WHEN dom IN ('person', 'device_tracker') THEN CASE (h / 2048) % 3 WHEN 0 THEN 'not_home' ELSE 'home' END
       WHEN dom = 'cover' THEN CASE (h / 2048) % 2 WHEN 0 THEN 'open' ELSE 'closed' END
       WHEN dom = 'media_player' THEN CASE (h / 2048) % 3 WHEN 0 THEN 'playing' WHEN 1 THEN 'paused' ELSE 'idle' END
       WHEN dom = 'counter' THEN CAST((h / 2048) % 100 AS TEXT)
       ELSE CASE (h / 2048) % 2 WHEN 0 THEN 'on' ELSE 'off' END END,
  CASE WHEN (h / 16) % 4 = 0 THEN ts - (h % 600) ELSE NULL END,
  CASE WHEN (h / 8192) % 10 = 0 THEN ts + 30 ELSE NULL END,
  ts,
  lag(i) OVER (PARTITION BY m ORDER BY i),
  m * 7 - ((h / 65536) % 7),
  0,
  unhex(printf('%016X%016X', 0x0199000000000000,
               CASE WHEN (h / 32) % 5 = 0 THEN 1000000 + (i * 30000) / 200000 ELSE i END)),
  CASE WHEN (h / 512) % 10 = 0 THEN unhex(printf('%032X', 0xA0 + (h / 4096) % 3)) END,
  NULL,
  m
FROM g ORDER BY i;

WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 20)
INSERT INTO event_types(event_type_id, event_type)
SELECT i, CASE i WHEN 1 THEN 'logbook_entry' WHEN 2 THEN 'call_service' WHEN 3 THEN 'automation_triggered'
  WHEN 4 THEN 'script_started' WHEN 5 THEN 'homeassistant_start' WHEN 6 THEN 'homeassistant_stop'
  WHEN 7 THEN 'zha_event' WHEN 8 THEN 'mobile_app_notification_action' WHEN 9 THEN 'component_loaded'
  WHEN 10 THEN 'service_registered' WHEN 11 THEN 'core_config_updated' WHEN 12 THEN 'entity_registry_updated'
  WHEN 13 THEN 'device_registry_updated' WHEN 14 THEN 'area_registry_updated' WHEN 15 THEN 'tag_scanned'
  WHEN 16 THEN 'deconz_event' WHEN 17 THEN 'hue_event' WHEN 18 THEN 'shelly.click' WHEN 19 THEN 'esphome.button'
  ELSE 'timer.finished' END FROM n;

-- event_data: each row names an entity (k*7 % 380 + 1) and one of 50 devices.
WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 2000)
INSERT INTO event_data(data_id, hash, shared_data)
SELECT i, (i * 2246822519) % 4294967296,
  json_object('domain', dom, 'service', CASE i % 3 WHEN 0 THEN 'turn_on' WHEN 1 THEN 'turn_off' ELSE 'toggle' END,
              'entity_id', dom || '.e' || m, 'device_id', printf('dev%04d', i % 50),
              'service_data', json_object('brightness_pct', i % 100))
FROM (SELECT i, (i * 7) % 380 + 1 AS m, (SELECT d FROM _dom WHERE k = ((i * 7) % 380 + 1) % 20) AS dom FROM n);

-- events: 30k over 10 days, half of them logbook-relevant types (1-6). Context ids 1000000+j, shared with ~1/5 of
-- the states fired at the same moment; every third event carries a user id.
WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 30000*(SELECT scale FROM _cfg))
INSERT INTO events(event_id, origin_idx, time_fired_ts, data_id, context_id_bin, context_user_id_bin,
                   context_parent_id_bin, event_type_id)
SELECT i, 0, 1790000000.0 - 864000.0 + i * (864000.0 / (30000*(SELECT scale FROM _cfg))) + (h % 1000) / 1000.0,
  ((h / 65536) % 2000) + 1,
  unhex(printf('%016X%016X', 0x0199000000000000, 1000000 + i)),
  CASE WHEN i % 3 = 0 THEN unhex(printf('%032X', 0xA0 + (h / 4096) % 3)) END,
  CASE WHEN (h / 128) % 4 = 0 THEN unhex(printf('%016X%016X', 0x0199000000000000, 1000000 + i - 1)) END,
  CASE WHEN (h / 16) % 10 < 5 THEN ((h / 256) % 6) + 1 ELSE ((h / 4096) % 14) + 7 END
FROM (SELECT i, (i * 2654435761) % 4294967296 AS h FROM n);

-- statistics_meta: k % 3 = 0 are sum statistics (energy), k % 10 = 0 (not % 3) circular means, the rest arithmetic.
WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 150*(SELECT scale FROM _cfg))
INSERT INTO statistics_meta(id, statistic_id, source, unit_of_measurement, unit_class, has_mean, has_sum, name, mean_type)
SELECT i, 'sensor.stat_' || i, 'recorder',
  CASE WHEN i % 3 = 0 THEN 'kWh' WHEN i % 10 = 0 THEN '°' WHEN i % 2 = 0 THEN '°C' ELSE 'W' END,
  CASE WHEN i % 3 = 0 THEN 'energy' WHEN i % 10 = 0 THEN NULL WHEN i % 2 = 0 THEN 'temperature' ELSE 'power' END,
  i % 3 <> 0, i % 3 = 0, NULL,
  CASE WHEN i % 3 = 0 THEN 0 WHEN i % 10 = 0 THEN 2 ELSE 1 END
FROM n;

-- hourly statistics: 45 days ending at the last full hour (1789999200).
WITH RECURSIVE hr(j) AS (SELECT 0 UNION ALL SELECT j+1 FROM hr WHERE j < 45*24 - 1)
INSERT INTO statistics(created_ts, metadata_id, start_ts, mean, mean_weight, min, max, last_reset_ts, state, sum)
SELECT st + 3600 + 12.5, id, st,
  CASE WHEN mean_type = 0 THEN NULL ELSE v END,
  CASE WHEN mean_type = 2 THEN 0.5 + ((id * 31 + j) % 50) / 100.0 END,
  CASE WHEN mean_type = 0 THEN NULL ELSE v - 1.5 END,
  CASE WHEN mean_type = 0 THEN NULL ELSE v + 2.0 END,
  NULL,
  CASE WHEN mean_type = 0 THEN j * ((id % 7) + 1) * 0.5 END,
  CASE WHEN mean_type = 0 THEN j * ((id % 7) + 1) * 0.5 END
FROM (SELECT m.id, m.mean_type, t.j, t.st,
             CASE WHEN m.mean_type = 2 THEN (m.id * 37 + t.j * 11) % 360
                  ELSE 15 + ((m.id * 13 + t.j * 7) % 100) / 10.0 END AS v
      FROM statistics_meta m, (SELECT j, 1789999200.0 - 45*86400 + j * 3600.0 AS st FROM hr) t
      ORDER BY m.id, t.j);

-- 5-minute statistics: 3 days ending at 1789999200.
WITH RECURSIVE f(j) AS (SELECT 0 UNION ALL SELECT j+1 FROM f WHERE j < 3*288 - 1)
INSERT INTO statistics_short_term(created_ts, metadata_id, start_ts, mean, mean_weight, min, max, last_reset_ts, state, sum)
SELECT st + 300 + 2.5, id, st,
  CASE WHEN mean_type = 0 THEN NULL ELSE v END,
  CASE WHEN mean_type = 2 THEN 0.5 + ((id * 31 + j) % 50) / 100.0 END,
  CASE WHEN mean_type = 0 THEN NULL ELSE v - 0.4 END,
  CASE WHEN mean_type = 0 THEN NULL ELSE v + 0.6 END,
  NULL,
  CASE WHEN mean_type = 0 THEN 1000 + j * ((id % 7) + 1) * 0.05 END,
  CASE WHEN mean_type = 0 THEN 1000 + j * ((id % 7) + 1) * 0.05 END
FROM (SELECT m.id, m.mean_type, t.j, t.st,
             CASE WHEN m.mean_type = 2 THEN (m.id * 37 + t.j * 3) % 360
                  ELSE 15 + ((m.id * 13 + t.j * 3) % 100) / 10.0 END AS v
      FROM statistics_meta m, (SELECT j, 1789999200.0 - 3*86400 + j * 300.0 AS st FROM f) t
      ORDER BY m.id, t.j);

WITH RECURSIVE f(j) AS (SELECT 0 UNION ALL SELECT j+1 FROM f WHERE j < 3*288 - 1)
INSERT INTO statistics_runs(start) SELECT datetime(1789999200 - 3*86400 + j * 300, 'unixepoch') FROM f;

WITH RECURSIVE r(j) AS (SELECT 0 UNION ALL SELECT j+1 FROM r WHERE j < 29)
INSERT INTO recorder_runs(start, "end", closed_incorrect, created)
SELECT datetime(1790000000 - (30 - j) * 86400, 'unixepoch'),
       CASE WHEN j < 29 THEN datetime(1790000000 - (29 - j) * 86400 - 60, 'unixepoch') END, 0,
       datetime(1790000000 - (30 - j) * 86400, 'unixepoch') FROM r;

INSERT INTO schema_changes(schema_version, changed) VALUES (51, '2026-06-01 00:00:00');
INSERT INTO migration_changes(migration_id, version) VALUES ('event_context_id_as_binary', 2), ('state_context_id_as_binary', 2),
  ('event_type_id_migration', 2), ('entity_id_migration', 2), ('event_id_post_migration', 2), ('entity_id_post_migration', 1);

DROP TABLE _dom;
COMMIT;
