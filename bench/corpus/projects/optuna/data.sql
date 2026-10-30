-- Synthetic data for Optuna's RDBStorage. Deterministic (no random()): values come from multiplicative hashes of
-- the row number. Scale 1: 6 studies, 34k trials. Study 1 (LightGBM, minimize, MedianPruner) holds 20k trials with
-- 5-6 params each and 30 intermediate values per completed trial; study 2 (NSGA-II, 2 objectives) 8k trials with
-- 8 params; study 3 (XGBoost CV, maximize) 5.1k trials with 10 report steps; studies 4-6 are 300-trial leftovers.
-- Studies 1-3 ran concurrently, so their trial_ids interleave. The tail of each big study is RUNNING (with
-- heartbeats, a few stale) or WAITING (enqueued with fixed_params). _cfg.scale multiplies the trial count.
BEGIN;

INSERT INTO version_info VALUES (1, 12, '5.0.0');
INSERT INTO alembic_version VALUES ('v3.2.0.a');

INSERT INTO studies(study_id, study_name) VALUES
  (1, 'lgbm-higgs-tuning'), (2, 'nsga2-arch-search'), (3, 'xgb-cv-churn'),
  (4, 'no-name-6f0c2d1e-1b7e-4b8e-9a51-6fd1a2b0c001'), (5, 'rf-baseline'), (6, 'svm-smoke-test');
INSERT INTO study_directions(study_direction_id, direction, study_id, objective) VALUES
  (1, 'MINIMIZE', 1, 0), (2, 'MINIMIZE', 2, 0), (3, 'MAXIMIZE', 2, 1), (4, 'MAXIMIZE', 3, 0),
  (5, 'MINIMIZE', 4, 0), (6, 'MAXIMIZE', 5, 0), (7, 'MINIMIZE', 6, 0);
INSERT INTO study_user_attributes(study_id, "key", value_json) VALUES
  (1, 'dataset', '"higgs"'), (1, 'metric', '"binary_logloss"'), (1, 'git_sha', '"9c1e0f2"'),
  (2, 'search_space', '"mlp-v3"'), (3, 'dataset', '"churn-2026q3"'), (3, 'n_folds', '5');
INSERT INTO study_system_attributes(study_id, "key", value_json) VALUES
  (2, 'nsga2:population_size', '50'), (1, 'pruner', '"MedianPruner"');

-- Trial skeleton: the first 900 trials are the three small sequential studies, the rest interleave studies 1-3.
CREATE TEMP TABLE _t(trial_id INTEGER PRIMARY KEY, study_id INT, h INT, number INT, cnt INT);
WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 34000*(SELECT scale FROM _cfg)),
g AS (SELECT i, (i * 2654435761) % 4294967296 AS h FROM n)
INSERT INTO _t(trial_id, study_id, h)
SELECT i, CASE WHEN i <= 300 THEN 4 WHEN i <= 600 THEN 5 WHEN i <= 900 THEN 6
               WHEN (h / 16) % 331 < 200 THEN 1 WHEN (h / 16) % 331 < 280 THEN 2 ELSE 3 END, h FROM g;
UPDATE _t SET number = w.rn - 1, cnt = w.c
FROM (SELECT trial_id, row_number() OVER (PARTITION BY study_id ORDER BY trial_id) AS rn,
             count(*) OVER (PARTITION BY study_id) AS c FROM _t) AS w WHERE w.trial_id = _t.trial_id;

-- Wall clock: study 4-6 trials are a month old, the interleaved ones run one per ~25 s up to late October 2025.
INSERT INTO trials(trial_id, number, study_id, state, datetime_start, datetime_complete)
SELECT trial_id, number, study_id, st,
  CASE WHEN st = 'WAITING' THEN NULL ELSE printf('%s.%06d', datetime(t0, 'unixepoch'), (h / 7) % 1000000) END,
  CASE WHEN st IN ('WAITING', 'RUNNING') THEN NULL
       ELSE printf('%s.%06d', datetime(t0 + 20 + (h / 65536) % 600, 'unixepoch'), (h / 11) % 1000000) END
FROM (SELECT *,
        CASE WHEN number >= cnt - 2 AND study_id <= 3 THEN 'WAITING'
             WHEN number >= cnt - 10 AND study_id <= 3 THEN 'RUNNING'
             WHEN study_id = 2 THEN CASE WHEN (h / 1024) % 100 < 94 THEN 'COMPLETE' ELSE 'FAIL' END
             WHEN study_id IN (1, 3) THEN CASE WHEN (h / 1024) % 100 < 55 THEN 'COMPLETE'
                                               WHEN (h / 1024) % 100 < 95 THEN 'PRUNED' ELSE 'FAIL' END
             ELSE CASE WHEN (h / 1024) % 100 < 90 THEN 'COMPLETE' ELSE 'FAIL' END END AS st,
        CASE WHEN trial_id <= 900 THEN 1759200000 + trial_id * 90
             ELSE 1761800000 - (34000*(SELECT scale FROM _cfg) - trial_id) * 25 / (SELECT scale FROM _cfg) END AS t0
      FROM _t);

-- Params. The value columns hold Optuna's internal representation (categorical = index into choices).
CREATE TEMP TABLE _pdef(study_id INT, k INT, name TEXT, dist TEXT, lo REAL, hi REAL, isint INT, logscale INT);
INSERT INTO _pdef VALUES
 (1,0,'learning_rate','{"name": "FloatDistribution", "attributes": {"step": null, "low": 0.0001, "high": 0.3, "log": true}}',0.0001,0.3,0,1),
 (1,1,'num_leaves','{"name": "IntDistribution", "attributes": {"log": false, "step": 1, "low": 8, "high": 256}}',8,256,1,0),
 (1,2,'boosting','{"name": "CategoricalDistribution", "attributes": {"choices": ["gbdt", "dart", "goss"]}}',0,2,1,0),
 (1,3,'feature_fraction','{"name": "FloatDistribution", "attributes": {"step": null, "low": 0.4, "high": 1.0, "log": false}}',0.4,1.0,0,0),
 (1,4,'min_child_samples','{"name": "IntDistribution", "attributes": {"log": false, "step": 1, "low": 5, "high": 100}}',5,100,1,0),
 (1,5,'drop_rate','{"name": "FloatDistribution", "attributes": {"step": null, "low": 0.01, "high": 0.5, "log": false}}',0.01,0.5,0,0),
 (2,0,'n_layers','{"name": "IntDistribution", "attributes": {"log": false, "step": 1, "low": 1, "high": 6}}',1,6,1,0),
 (2,1,'units_l0','{"name": "IntDistribution", "attributes": {"log": true, "step": 1, "low": 16, "high": 1024}}',16,1024,1,1),
 (2,2,'units_l1','{"name": "IntDistribution", "attributes": {"log": true, "step": 1, "low": 16, "high": 1024}}',16,1024,1,1),
 (2,3,'dropout','{"name": "FloatDistribution", "attributes": {"step": 0.05, "low": 0.0, "high": 0.5, "log": false}}',0,0.5,0,0),
 (2,4,'optimizer','{"name": "CategoricalDistribution", "attributes": {"choices": ["adam", "adamw", "sgd", "rmsprop"]}}',0,3,1,0),
 (2,5,'lr','{"name": "FloatDistribution", "attributes": {"step": null, "low": 1e-05, "high": 0.1, "log": true}}',0.00001,0.1,0,1),
 (2,6,'batch_size','{"name": "CategoricalDistribution", "attributes": {"choices": [32, 64, 128, 256]}}',0,3,1,0),
 (2,7,'weight_decay','{"name": "FloatDistribution", "attributes": {"step": null, "low": 1e-06, "high": 0.01, "log": true}}',0.000001,0.01,0,1),
 (3,0,'max_depth','{"name": "IntDistribution", "attributes": {"log": false, "step": 1, "low": 2, "high": 12}}',2,12,1,0),
 (3,1,'eta','{"name": "FloatDistribution", "attributes": {"step": null, "low": 0.005, "high": 0.5, "log": true}}',0.005,0.5,0,1),
 (3,2,'subsample','{"name": "FloatDistribution", "attributes": {"step": null, "low": 0.5, "high": 1.0, "log": false}}',0.5,1.0,0,0),
 (3,3,'colsample_bytree','{"name": "FloatDistribution", "attributes": {"step": null, "low": 0.3, "high": 1.0, "log": false}}',0.3,1.0,0,0),
 (4,0,'x','{"name": "FloatDistribution", "attributes": {"step": null, "low": -10.0, "high": 10.0, "log": false}}',-10,10,0,0),
 (4,1,'y','{"name": "FloatDistribution", "attributes": {"step": null, "low": -10.0, "high": 10.0, "log": false}}',-10,10,0,0),
 (5,0,'n_estimators','{"name": "IntDistribution", "attributes": {"log": false, "step": 50, "low": 50, "high": 1000}}',50,1000,1,0),
 (5,1,'max_features','{"name": "CategoricalDistribution", "attributes": {"choices": ["sqrt", "log2", null]}}',0,2,1,0),
 (6,0,'C','{"name": "FloatDistribution", "attributes": {"step": null, "low": 0.001, "high": 1000.0, "log": true}}',0.001,1000,0,1),
 (6,1,'kernel','{"name": "CategoricalDistribution", "attributes": {"choices": ["linear", "rbf", "poly"]}}',0,2,1,0);

-- Every non-WAITING trial gets every param of its study (drop_rate only when boosting = dart, units_l1 only when
-- n_layers > 1). u in [0,1) is a separate hash per (trial, param).
CREATE TEMP VIEW _u AS
SELECT t.trial_id, t.study_id, p.k, p.name, p.dist, p.lo, p.hi, p.isint, p.logscale,
       (((t.trial_id * 31 + p.k) * 2654435761) % 4294967296) / 4294967296.0 AS u
FROM _t t JOIN trials tr ON tr.trial_id = t.trial_id AND tr.state <> 'WAITING' JOIN _pdef p ON p.study_id = t.study_id;
INSERT INTO trial_params(trial_id, param_name, param_value, distribution_json)
SELECT trial_id, name,
  CASE WHEN isint AND logscale THEN CAST(round(exp(ln(lo) + (ln(hi) - ln(lo)) * u)) AS REAL)
       WHEN isint THEN CAST(CAST(lo + (hi - lo + 1) * u AS INT) AS REAL)
       WHEN logscale THEN exp(ln(lo) + (ln(hi) - ln(lo)) * u)
       ELSE lo + (hi - lo) * u END,
  dist
FROM _u
WHERE NOT (study_id = 1 AND name = 'drop_rate'
           AND CAST(3 * ((((trial_id * 31 + 2) * 2654435761) % 4294967296) / 4294967296.0) AS INT) <> 1)
  AND NOT (study_id = 2 AND name = 'units_l1'
           AND CAST(6 * ((((trial_id * 31 + 0) * 2654435761) % 4294967296) / 4294967296.0) AS INT) = 0)
ORDER BY trial_id, k;

-- Objective values for finished trials. Study 1 (logloss) drifts down as TPE converges; a few FINITE ties, rare inf.
INSERT INTO trial_values(trial_id, objective, value, value_type)
SELECT t.trial_id, o.objective,
  CASE WHEN o.objective = 0 AND (t.h / 4096) % 997 = 0 THEN NULL
       WHEN t.study_id = 1 THEN 0.18 + 0.30 * (1.0 - t.number * 1.0 / t.cnt) * ((t.h / 64) % 1000) / 1000.0 + ((t.h / 8) % 50) / 10000.0
       WHEN t.study_id = 2 AND o.objective = 0 THEN 2.0 + ((t.h / 64) % 5000) / 100.0
       WHEN t.study_id = 2 THEN 0.6 + ((t.h / 4096) % 390) / 1000.0
       WHEN t.study_id = 3 THEN 0.70 + 0.2 * (t.number * 1.0 / t.cnt) * ((t.h / 64) % 1000) / 1000.0
       ELSE ((t.h / 64) % 100000) / 1000.0 END,
  CASE WHEN o.objective = 0 AND (t.h / 4096) % 997 = 0 THEN CASE WHEN t.study_id = 3 THEN 'INF_NEG' ELSE 'INF_POS' END
       ELSE 'FINITE' END
FROM _t t JOIN trials tr ON tr.trial_id = t.trial_id AND tr.state = 'COMPLETE'
JOIN study_directions o ON o.study_id = t.study_id
ORDER BY t.trial_id, o.objective;

-- Intermediate values: study 1 reports 30 boosting rounds per completed trial, pruned trials stop after 3-20;
-- study 3 reports 10 CV folds (pruned after 2-6). Failed and running trials have a few.
CREATE TEMP TABLE _steps(trial_id INT, nsteps INT, h INT, study_id INT);
INSERT INTO _steps
SELECT t.trial_id,
  CASE WHEN t.study_id = 1 THEN CASE tr.state WHEN 'COMPLETE' THEN 30 WHEN 'PRUNED' THEN 3 + (t.h / 512) % 18
                                              ELSE (t.h / 512) % 4 END
       WHEN t.study_id = 3 THEN CASE tr.state WHEN 'COMPLETE' THEN 10 WHEN 'PRUNED' THEN 2 + (t.h / 512) % 5
                                              ELSE (t.h / 512) % 3 END
       ELSE 0 END, t.h, t.study_id
FROM _t t JOIN trials tr USING (trial_id) WHERE tr.state <> 'WAITING';
WITH RECURSIVE s(k) AS (SELECT 0 UNION ALL SELECT k+1 FROM s WHERE k < 29)
INSERT INTO trial_intermediate_values(trial_id, step, intermediate_value, intermediate_value_type)
SELECT st.trial_id, s.k,
  CASE WHEN (st.h / 32768) % 2003 = 0 AND s.k = 0 THEN NULL
       WHEN st.study_id = 1 THEN 0.69 * exp(-0.06 * s.k) + 0.15 + ((st.h / 64) % 1000) / 5000.0
       ELSE 0.65 + ((st.h / 64 + s.k * 37) % 300) / 1000.0 END,
  CASE WHEN (st.h / 32768) % 2003 = 0 AND s.k = 0 THEN 'NAN' ELSE 'FINITE' END
FROM _steps st JOIN s ON s.k < st.nsteps
ORDER BY st.trial_id, s.k;

-- System attributes: TPE's relative params (multivariate) on studies 1 and 3, NSGA-II generation + parents on
-- study 2, fixed_params on enqueued trials, fail_reason on failed ones.
INSERT INTO trial_system_attributes(trial_id, "key", value_json)
SELECT t.trial_id, 'tpe:relative_params:0',
  json_quote('' || (SELECT json_group_object(param_name, CASE WHEN param_name = 'boosting' THEN json_extract('["gbdt","dart","goss"]', '$[' || CAST(param_value AS INT) || ']') ELSE param_value END)
              FROM trial_params p WHERE p.trial_id = t.trial_id AND p.param_name <> 'drop_rate'))
FROM _t t JOIN trials tr USING (trial_id) WHERE t.study_id IN (1, 3) AND t.number >= 10 AND tr.state <> 'WAITING'
UNION ALL
SELECT t.trial_id, 'nsga2:generation', CAST(t.number / 50 AS TEXT) FROM _t t WHERE t.study_id = 2
UNION ALL
SELECT t.trial_id, 'nsga2:parents', json_array(t.trial_id - 50 - (t.h / 64) % 50, t.trial_id - 50 - (t.h / 4096) % 50)
FROM _t t WHERE t.study_id = 2 AND t.number >= 50
UNION ALL
SELECT t.trial_id, 'fixed_params', '{"learning_rate": 0.05, "num_leaves": 31, "boosting": "gbdt"}'
FROM _t t JOIN trials tr USING (trial_id) WHERE tr.state = 'WAITING'
UNION ALL
SELECT t.trial_id, 'fail_reason', json_quote('Traceback (most recent call last): ValueError: Input contains NaN')
FROM _t t JOIN trials tr USING (trial_id) WHERE tr.state = 'FAIL'
ORDER BY 1;

-- User attributes: worker host on every started trial, CV fold scores on completed study-3 trials.
INSERT INTO trial_user_attributes(trial_id, "key", value_json)
SELECT t.trial_id, 'host', json_quote('gpu-node-' || ((t.h / 256) % 12)) FROM _t t JOIN trials tr USING (trial_id)
WHERE tr.state <> 'WAITING'
UNION ALL
SELECT t.trial_id, 'fold_scores', json_array(0.7 + (t.h % 97) / 1000.0, 0.71 + (t.h % 89) / 1000.0, 0.69 + (t.h % 83) / 1000.0,
                                              0.72 + (t.h % 79) / 1000.0, 0.7 + (t.h % 73) / 1000.0)
FROM _t t JOIN trials tr USING (trial_id) WHERE t.study_id = 3 AND tr.state = 'COMPLETE'
ORDER BY 1;

-- Heartbeats: every RUNNING trial; the first 3 per study stopped beating an hour ago (stale).
INSERT INTO trial_heartbeats(trial_id, heartbeat)
SELECT t.trial_id, datetime(1761800000 - CASE WHEN t.number < t.cnt - 7 THEN 3600 ELSE 20 END, 'unixepoch')
FROM _t t JOIN trials tr USING (trial_id) WHERE tr.state = 'RUNNING';

DROP VIEW _u;
COMMIT;
