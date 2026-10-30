-- MLflow tracking store (mlflow/mlflow @ d0b397f = v3.17.2, Apache-2.0). Every statement was captured from the real
-- mlflow 3.17.2 package (PyPI) running SqlAlchemyStore read and write paths against the synthetic database with a
-- SQLAlchemy before_cursor_execute listener: search_runs (UI default, metric/param/tag filters, order by metric),
-- get_run, get_metric_history, get_metric_history_bulk_interval, log_batch, search_traces with each filter family,
-- get_trace, query_trace_metrics (the trace analytics dashboard), find_completed_sessions,
-- calculate_trace_filter_correlation and delete_run. ? placeholders are numbered ?N in order; parameters are the ones
-- the app bound. @src is the app frame that executed the statement.
-- MLflow opens every SQLite connection with PRAGMA foreign_keys = ON, busy_timeout = 20000 and
-- case_sensitive_like = true (mlflow/store/db/utils.py:156-158); meta.json "pragmas" replays it, so LIKE here is case-sensitive as in the app
-- (so LIKE prefix filters can use an index the way they do in the app). MLflow also
-- registers a Python percentile(x, p) aggregate (mlflow/store/db/utils.py:491); the sqlite3 CLI's built-in percentile()
-- has the same signature.

-- @id mlflow.search_runs.default_page
-- @src mlflow/store/tracking/sqlalchemy_store.py:2368
-- @style SQLAlchemy 2.0 Core/ORM compiled by the sqlite dialect; ? positional, IN lists expanded per call; captured at the DBAPI cursor
-- @tags hotpath,cpu-evidence
-- @note Experiment page default listing (100 runs, start_time DESC): DISTINCT over runs with a CASE null-ordering key; runs has no experiment_id index, so the 15k-run table is scanned and sorted. Scaling complaint: https://github.com/mlflow/mlflow/issues/2730 (cannot retrieve beyond thousands of runs).
-- @param ?1 1
-- @param ?2 0
-- @param ?3 1
-- @param ?4 'active'
-- @param ?5 101
-- @param ?6 0
SELECT DISTINCT runs.run_uuid, runs.name, runs.source_type, runs.source_name, runs.entry_point_name, runs.user_id, runs.status, runs.start_time, runs.end_time, runs.deleted_time, runs.source_version, runs.lifecycle_stage, runs.artifact_uri, runs.experiment_id, CASE WHEN (runs.start_time IS NULL) THEN ?1 ELSE ?2 END AS clause_1, runs.start_time AS start_time__1
FROM runs
WHERE runs.experiment_id IN (?3) AND runs.lifecycle_stage IN (?4) ORDER BY clause_1, runs.start_time DESC, runs.run_uuid
 LIMIT ?5 OFFSET ?6;

-- @id mlflow.search_runs.page_latest_metrics
-- @src mlflow/store/tracking/sqlalchemy_store.py:2368
-- @style SQLAlchemy 2.0 Core/ORM compiled by the sqlite dialect; ? positional, IN lists expanded per call; captured at the DBAPI cursor
-- @tags hotpath,cpu-evidence
-- @note Per-page fetch of latest_metrics for the 101 runs on the page (IN list over index_latest_metrics_run_uuid). https://github.com/mlflow/mlflow/issues/2730
-- @param ?1 '6dda0b396473fa2fa3011425ba2900a7'
-- @param ?2 '4505be57ace302c19241cc2b973733c9'
-- @param ?3 '81c27c10807d6e705e8490d03e52b1f0'
-- @param ?4 '9a5122d0c8ea35b0c9e3b890c7d97330'
-- @param ?5 '8668b1f9ace0c16f0e603be543afc1e7'
-- @param ?6 '4fded7c34c5078350081e1a7fd7e90dd'
-- @param ?7 'd70de0899c84a15f96267d356ef4f157'
-- @param ?8 '5d946517f54fca01fda0f3eb20bdf509'
-- @param ?9 '686d7e8394bd3f756be109678705521d'
-- @param ?10 'a52a3c3c6857ab243823ce0c2e20d044'
-- @param ?11 'b2dfc9901156fcf03542e05051603470'
-- @param ?12 'bdb8e2fcb0c47264a382f5ccb7a79184'
-- @param ?13 '2bb0c0cac122d3c69f9e44c2dfe9d3f6'
-- @param ?14 '4a724b0d7c99bd7bc961d6e9ca5ae253'
-- @param ?15 '9ef758b9f54d88af79bf63a5cd368327'
-- @param ?16 '80fc2543dd2a06b5d7403127108c135d'
-- @param ?17 '76230bd73dbc914169001babaa44b649'
-- @param ?18 '9fbdaf8698a0f06a0103c34efafd21ba'
-- @param ?19 '188ea6c0486cc7406b5f27c08986c140'
-- @param ?20 '6300f1cdc50684bb34c0fea953e1a393'
-- @param ?21 'cb6e705059c3c430a0a20810dae6f5b0'
-- @param ?22 'b84c5646e10db7aa6c62eb0e8483e2fa'
-- @param ?23 '311d4d8090d98e80d6be4f80130d8280'
-- @param ?24 '443f678a098f9b060afd6c8269709536'
-- @param ?25 '998acc032596cdf5429f58e79a12d49d'
-- @param ?26 '7b8f988d0d734bfba0202669dd6864d3'
-- @param ?27 'd0dafd06297a7eead7c212ce0e0aa43a'
-- @param ?28 '49abf440d94655c0421d77409c9443c0'
-- @param ?29 '3ed2dad439d8e04cd3dd61c4364ce6ac'
-- @param ?30 '5cce0e4a51fc6246765c9442f2f75676'
-- @param ?31 '941e3f4d55e0133b0b7f4e2966ef2613'
-- @param ?32 'b21972c36e039535adfe80a7239995dd'
-- @param ?33 '0cef368705abea1175dab29bf578c599'
-- @param ?34 '623a9b0021b31d00ad7c9f00261b0500'
-- @param ?35 'b785ff793dba4fefe51e8b6556bd4467'
-- @param ?36 '576181948245a78c3f3c8984bfd3a7ec'
-- @param ?37 'acace60d9e4cda7b76de75e9f075e753'
-- @param ?38 '755cb50a9a692986e1bbbc027c7e17b6'
-- @param ?39 'caa81983b6705c75195da867ad20571d'
-- @param ?40 '257ddd474e18b151e139da5b7eff86d9'
-- @param ?41 '7ac941c06a1fe44018dbc6c0afa1c640'
-- @param ?42 '98c475368243663abb5af93e6c4c360a'
-- @param ?43 '6ff02854cab26eccaa9bb144495a692c'
-- @param ?44 '201150917e61f697aa19cf9d4bdbd84f'
-- @param ?45 'c53b8ccde6b9a1bbe23d9da979fca893'
-- @param ?46 '8deb5bcae2d5f0c64d1ae3c20604d8f6'
-- @param ?47 '3e0c8407968578914c99021b08864819'
-- @param ?48 '9357e880b28cab80843aee8039288780'
-- @param ?49 '06bc530492a1c79cb7764834948e787c'
-- @param ?50 '5c07b77daea8fa8bef183499c530b7e3'
-- @param ?51 '887ecf14131f360c15fad904d2e12a6c'
-- @param ?52 '389ff751c6cebdd71578f75dd562998f'
-- @param ?53 'ddca338d2f2668fb4d9cc569038369d3'
-- @param ?54 'a67a028a2b42b806b87a0b828f8b9a36'
-- @param ?55 '569b2ac7def23fd1b7f829db920d0959'
-- @param ?56 'abe68f40faf972c0ef9a1640c2af48c0'
-- @param ?57 '1f4af9c4db0e8edc22d56ff41e1539bc'
-- @param ?58 '74965e3df715c1cb5a775c594eb77923'
-- @param ?59 '4bc2115b3f84ca5d49b8145f2bc5ac45'
-- @param ?60 '512e9e110f3b851780d81f1d5ee95acf'
-- @param ?61 'a10d75d45b8bfd4c815a00c45c67ebac'
-- @param ?62 '19de6d0e0b57d422ebb56536eaf18b32'
-- @param ?63 '6f29d187275f07112357519b1b93ca99'
-- @param ?64 '8d2504fd3f82890bc5d68419d83e3a63'
-- @param ?65 '6450b81b87f1919db5173c1fb54c6d85'
-- @param ?66 '69bd44d157a84c57ec3746dde8701c0f'
-- @param ?67 'b99c1c94a3f8c48cecb92884e5eeacec'
-- @param ?68 'bf08a94a73af7f4623d9334219125b76'
-- @param ?69 '326d13ce53c49b6257148cf674784c72'
-- @param ?70 '37d9a084237b561c8e3497b4a79bfafc'
-- @param ?71 '87b878476fcbce518eb6795ba51a8bd9'
-- @param ?72 'a5b3abbd87ef504b3135abd961c4fba3'
-- @param ?73 '2d008718840de0a81ff4823841549de8'
-- @param ?74 '824beb91a015139757966e9d71f6dd4f'
-- @param ?75 '7cdf5edbd05e58dd207663df3ed32ec5'
-- @param ?76 'd797500abc1c46868f385b02a2991cb6'
-- @param ?77 '506847446be81d5cf993bf743122bc3c'
-- @param ?78 '4afbba8e9c3162a2c273b4b6fdff0db2'
-- @param ?79 'a0471f07b8389591fa15a11b2ea14d19'
-- @param ?80 '458f2dd8cc7aa7e88b53a9f8cadb5f28'
-- @param ?81 '9ada9251e881dad7c2f5965dfb7d9e8f'
-- @param ?82 '13ab898b984db1ad2d50facf8a073e15'
-- @param ?83 '68f6ee04b454e49c64f2e734baa97d7c'
-- @param ?84 '638a614ee49e29e22dd2dc768785cef2'
-- @param ?85 'b8d5c5c700a55cd16574c8dbb8280e59'
-- @param ?86 '4022a122fcc3ed2e54339f3a97b7b09e'
-- @param ?87 '5e1dd49814e76f28f6b2d1b854622068'
-- @param ?88 'b369391130eea2172e54be1d85045fcf'
-- @param ?89 '2c3a304be0ba78ed98b0228f138dff55'
-- @param ?90 '818594c4fcc1abdcd0520ef444303ebc'
-- @param ?91 '26cda3951103be33619017d1e06a50cb'
-- @param ?92 '7c19080e2d0af12299320436110c9032'
-- @param ?93 '9f80c83a14e52dd672d1417200daae86'
-- @param ?94 '76ac7b585d5436686211f978dde8e1a8'
-- @param ?95 'cbf7dfd1795b695799b3e5dd0e8b210f'
-- @param ?96 '44c8d70b2927402d040f4a4f9d14c095'
-- @param ?97 '9a143b84452e731c3bb136b4cdb6fffc'
-- @param ?98 '94a7aece7577b86204912bf69a935172'
-- @param ?99 '0d78a60825438f386eec9068291cf0f8'
-- @param ?100 '62c40a81414ac227a68e7ccd59bf305f'
-- @param ?101 '3f5c4a5559708573ccef3f9169f1120b'
SELECT tags.run_uuid, tags."key", tags.value
FROM tags
WHERE tags.run_uuid IN (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15, ?16, ?17, ?18, ?19, ?20, ?21, ?22, ?23, ?24, ?25, ?26, ?27, ?28, ?29, ?30, ?31, ?32, ?33, ?34, ?35, ?36, ?37, ?38, ?39, ?40, ?41, ?42, ?43, ?44, ?45, ?46, ?47, ?48, ?49, ?50, ?51, ?52, ?53, ?54, ?55, ?56, ?57, ?58, ?59, ?60, ?61, ?62, ?63, ?64, ?65, ?66, ?67, ?68, ?69, ?70, ?71, ?72, ?73, ?74, ?75, ?76, ?77, ?78, ?79, ?80, ?81, ?82, ?83, ?84, ?85, ?86, ?87, ?88, ?89, ?90, ?91, ?92, ?93, ?94, ?95, ?96, ?97, ?98, ?99, ?100, ?101);

-- @id mlflow.search_runs.page_dataset_inputs
-- @src mlflow/store/tracking/sqlalchemy_store.py:1206
-- @style SQLAlchemy 2.0 Core/ORM compiled by the sqlite dialect; ? positional, IN lists expanded per call; captured at the DBAPI cursor
-- @tags hotpath,cpu-evidence
-- @note Per-page dataset inputs: inputs JOIN datasets LEFT JOIN input_tags for 101 runs, ORDER BY run_uuid. input_tags has no index on input_uuid. https://github.com/mlflow/mlflow/issues/15231 (search_runs times out once an experiment reaches ~50k inputs)
-- @param ?1 'RUN'
-- @param ?2 '6dda0b396473fa2fa3011425ba2900a7'
-- @param ?3 '4505be57ace302c19241cc2b973733c9'
-- @param ?4 '81c27c10807d6e705e8490d03e52b1f0'
-- @param ?5 '9a5122d0c8ea35b0c9e3b890c7d97330'
-- @param ?6 '8668b1f9ace0c16f0e603be543afc1e7'
-- @param ?7 '4fded7c34c5078350081e1a7fd7e90dd'
-- @param ?8 'd70de0899c84a15f96267d356ef4f157'
-- @param ?9 '5d946517f54fca01fda0f3eb20bdf509'
-- @param ?10 '686d7e8394bd3f756be109678705521d'
-- @param ?11 'a52a3c3c6857ab243823ce0c2e20d044'
-- @param ?12 'b2dfc9901156fcf03542e05051603470'
-- @param ?13 'bdb8e2fcb0c47264a382f5ccb7a79184'
-- @param ?14 '2bb0c0cac122d3c69f9e44c2dfe9d3f6'
-- @param ?15 '4a724b0d7c99bd7bc961d6e9ca5ae253'
-- @param ?16 '9ef758b9f54d88af79bf63a5cd368327'
-- @param ?17 '80fc2543dd2a06b5d7403127108c135d'
-- @param ?18 '76230bd73dbc914169001babaa44b649'
-- @param ?19 '9fbdaf8698a0f06a0103c34efafd21ba'
-- @param ?20 '188ea6c0486cc7406b5f27c08986c140'
-- @param ?21 '6300f1cdc50684bb34c0fea953e1a393'
-- @param ?22 'cb6e705059c3c430a0a20810dae6f5b0'
-- @param ?23 'b84c5646e10db7aa6c62eb0e8483e2fa'
-- @param ?24 '311d4d8090d98e80d6be4f80130d8280'
-- @param ?25 '443f678a098f9b060afd6c8269709536'
-- @param ?26 '998acc032596cdf5429f58e79a12d49d'
-- @param ?27 '7b8f988d0d734bfba0202669dd6864d3'
-- @param ?28 'd0dafd06297a7eead7c212ce0e0aa43a'
-- @param ?29 '49abf440d94655c0421d77409c9443c0'
-- @param ?30 '3ed2dad439d8e04cd3dd61c4364ce6ac'
-- @param ?31 '5cce0e4a51fc6246765c9442f2f75676'
-- @param ?32 '941e3f4d55e0133b0b7f4e2966ef2613'
-- @param ?33 'b21972c36e039535adfe80a7239995dd'
-- @param ?34 '0cef368705abea1175dab29bf578c599'
-- @param ?35 '623a9b0021b31d00ad7c9f00261b0500'
-- @param ?36 'b785ff793dba4fefe51e8b6556bd4467'
-- @param ?37 '576181948245a78c3f3c8984bfd3a7ec'
-- @param ?38 'acace60d9e4cda7b76de75e9f075e753'
-- @param ?39 '755cb50a9a692986e1bbbc027c7e17b6'
-- @param ?40 'caa81983b6705c75195da867ad20571d'
-- @param ?41 '257ddd474e18b151e139da5b7eff86d9'
-- @param ?42 '7ac941c06a1fe44018dbc6c0afa1c640'
-- @param ?43 '98c475368243663abb5af93e6c4c360a'
-- @param ?44 '6ff02854cab26eccaa9bb144495a692c'
-- @param ?45 '201150917e61f697aa19cf9d4bdbd84f'
-- @param ?46 'c53b8ccde6b9a1bbe23d9da979fca893'
-- @param ?47 '8deb5bcae2d5f0c64d1ae3c20604d8f6'
-- @param ?48 '3e0c8407968578914c99021b08864819'
-- @param ?49 '9357e880b28cab80843aee8039288780'
-- @param ?50 '06bc530492a1c79cb7764834948e787c'
-- @param ?51 '5c07b77daea8fa8bef183499c530b7e3'
-- @param ?52 '887ecf14131f360c15fad904d2e12a6c'
-- @param ?53 '389ff751c6cebdd71578f75dd562998f'
-- @param ?54 'ddca338d2f2668fb4d9cc569038369d3'
-- @param ?55 'a67a028a2b42b806b87a0b828f8b9a36'
-- @param ?56 '569b2ac7def23fd1b7f829db920d0959'
-- @param ?57 'abe68f40faf972c0ef9a1640c2af48c0'
-- @param ?58 '1f4af9c4db0e8edc22d56ff41e1539bc'
-- @param ?59 '74965e3df715c1cb5a775c594eb77923'
-- @param ?60 '4bc2115b3f84ca5d49b8145f2bc5ac45'
-- @param ?61 '512e9e110f3b851780d81f1d5ee95acf'
-- @param ?62 'a10d75d45b8bfd4c815a00c45c67ebac'
-- @param ?63 '19de6d0e0b57d422ebb56536eaf18b32'
-- @param ?64 '6f29d187275f07112357519b1b93ca99'
-- @param ?65 '8d2504fd3f82890bc5d68419d83e3a63'
-- @param ?66 '6450b81b87f1919db5173c1fb54c6d85'
-- @param ?67 '69bd44d157a84c57ec3746dde8701c0f'
-- @param ?68 'b99c1c94a3f8c48cecb92884e5eeacec'
-- @param ?69 'bf08a94a73af7f4623d9334219125b76'
-- @param ?70 '326d13ce53c49b6257148cf674784c72'
-- @param ?71 '37d9a084237b561c8e3497b4a79bfafc'
-- @param ?72 '87b878476fcbce518eb6795ba51a8bd9'
-- @param ?73 'a5b3abbd87ef504b3135abd961c4fba3'
-- @param ?74 '2d008718840de0a81ff4823841549de8'
-- @param ?75 '824beb91a015139757966e9d71f6dd4f'
-- @param ?76 '7cdf5edbd05e58dd207663df3ed32ec5'
-- @param ?77 'd797500abc1c46868f385b02a2991cb6'
-- @param ?78 '506847446be81d5cf993bf743122bc3c'
-- @param ?79 '4afbba8e9c3162a2c273b4b6fdff0db2'
-- @param ?80 'a0471f07b8389591fa15a11b2ea14d19'
-- @param ?81 '458f2dd8cc7aa7e88b53a9f8cadb5f28'
-- @param ?82 '9ada9251e881dad7c2f5965dfb7d9e8f'
-- @param ?83 '13ab898b984db1ad2d50facf8a073e15'
-- @param ?84 '68f6ee04b454e49c64f2e734baa97d7c'
-- @param ?85 '638a614ee49e29e22dd2dc768785cef2'
-- @param ?86 'b8d5c5c700a55cd16574c8dbb8280e59'
-- @param ?87 '4022a122fcc3ed2e54339f3a97b7b09e'
-- @param ?88 '5e1dd49814e76f28f6b2d1b854622068'
-- @param ?89 'b369391130eea2172e54be1d85045fcf'
-- @param ?90 '2c3a304be0ba78ed98b0228f138dff55'
-- @param ?91 '818594c4fcc1abdcd0520ef444303ebc'
-- @param ?92 '26cda3951103be33619017d1e06a50cb'
-- @param ?93 '7c19080e2d0af12299320436110c9032'
-- @param ?94 '9f80c83a14e52dd672d1417200daae86'
-- @param ?95 '76ac7b585d5436686211f978dde8e1a8'
-- @param ?96 'cbf7dfd1795b695799b3e5dd0e8b210f'
-- @param ?97 '44c8d70b2927402d040f4a4f9d14c095'
-- @param ?98 '9a143b84452e731c3bb136b4cdb6fffc'
-- @param ?99 '94a7aece7577b86204912bf69a935172'
-- @param ?100 '0d78a60825438f386eec9068291cf0f8'
-- @param ?101 '62c40a81414ac227a68e7ccd59bf305f'
-- @param ?102 '3f5c4a5559708573ccef3f9169f1120b'
SELECT inputs.input_uuid AS inputs_input_uuid, inputs.destination_id AS run_uuid, datasets.dataset_uuid AS datasets_dataset_uuid, datasets.experiment_id AS datasets_experiment_id, datasets.name AS datasets_name, datasets.digest AS datasets_digest, datasets.dataset_source_type AS datasets_dataset_source_type, datasets.dataset_source AS datasets_dataset_source, datasets.dataset_schema AS datasets_dataset_schema, datasets.dataset_profile AS datasets_dataset_profile, input_tags.input_uuid AS input_tags_input_uuid, input_tags.name AS input_tags_name, input_tags.value AS input_tags_value
FROM inputs JOIN datasets ON inputs.source_id = datasets.dataset_uuid LEFT OUTER JOIN input_tags ON input_tags.input_uuid = inputs.input_uuid
WHERE inputs.destination_type = ?1 AND inputs.destination_id IN (?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15, ?16, ?17, ?18, ?19, ?20, ?21, ?22, ?23, ?24, ?25, ?26, ?27, ?28, ?29, ?30, ?31, ?32, ?33, ?34, ?35, ?36, ?37, ?38, ?39, ?40, ?41, ?42, ?43, ?44, ?45, ?46, ?47, ?48, ?49, ?50, ?51, ?52, ?53, ?54, ?55, ?56, ?57, ?58, ?59, ?60, ?61, ?62, ?63, ?64, ?65, ?66, ?67, ?68, ?69, ?70, ?71, ?72, ?73, ?74, ?75, ?76, ?77, ?78, ?79, ?80, ?81, ?82, ?83, ?84, ?85, ?86, ?87, ?88, ?89, ?90, ?91, ?92, ?93, ?94, ?95, ?96, ?97, ?98, ?99, ?100, ?101, ?102) ORDER BY run_uuid;

-- @id mlflow.search_runs.metric_and_param_filter
-- @src mlflow/store/tracking/sqlalchemy_store.py:2368
-- @style SQLAlchemy 2.0 Core/ORM compiled by the sqlite dialect; ? positional, IN lists expanded per call; captured at the DBAPI cursor
-- @tags hotpath,cpu-evidence
-- @note Filter `metrics.val_loss < 0.3 and params.model_type = 'lightgbm'` ordered by metrics.val_loss: runs JOIN filtered latest_metrics JOIN filtered params LEFT JOIN latest_metrics for the sort key, DISTINCT, CASE nan/null ordering. https://github.com/mlflow/mlflow/issues/2730
-- @param ?1 1
-- @param ?2 2
-- @param ?3 0
-- @param ?4 'val_loss'
-- @param ?5 0.3
-- @param ?6 'model_type'
-- @param ?7 'lightgbm'
-- @param ?8 'val_loss'
-- @param ?9 1
-- @param ?10 'active'
-- @param ?11 101
-- @param ?12 0
SELECT DISTINCT runs.run_uuid, runs.name, runs.source_type, runs.source_name, runs.entry_point_name, runs.user_id, runs.status, runs.start_time, runs.end_time, runs.deleted_time, runs.source_version, runs.lifecycle_stage, runs.artifact_uri, runs.experiment_id, CASE WHEN (anon_1.is_nan = 1) THEN ?1 WHEN (anon_1.value IS NULL) THEN ?2 ELSE ?3 END AS clause_1, anon_1.value
FROM runs JOIN (SELECT latest_metrics."key" AS "key", latest_metrics.value AS value, latest_metrics.timestamp AS timestamp, latest_metrics.step AS step, latest_metrics.is_nan AS is_nan, latest_metrics.run_uuid AS run_uuid
FROM latest_metrics
WHERE latest_metrics."key" = ?4 AND latest_metrics.value < ?5 AND latest_metrics.is_nan = 0) AS anon_2 ON runs.run_uuid = anon_2.run_uuid JOIN (SELECT params."key" AS "key", params.value AS value, params.run_uuid AS run_uuid
FROM params
WHERE params."key" = ?6 AND params.value = ?7) AS anon_3 ON runs.run_uuid = anon_3.run_uuid LEFT OUTER JOIN (SELECT latest_metrics."key" AS "key", latest_metrics.value AS value, latest_metrics.timestamp AS timestamp, latest_metrics.step AS step, latest_metrics.is_nan AS is_nan, latest_metrics.run_uuid AS run_uuid
FROM latest_metrics
WHERE latest_metrics."key" = ?8) AS anon_1 ON runs.run_uuid = anon_1.run_uuid
WHERE runs.experiment_id IN (?9) AND runs.lifecycle_stage IN (?10) ORDER BY clause_1, anon_1.value, runs.start_time DESC, runs.run_uuid
 LIMIT ?11 OFFSET ?12;

-- @id mlflow.search_runs.tag_like
-- @src mlflow/store/tracking/sqlalchemy_store.py:2368
-- @style SQLAlchemy 2.0 Core/ORM compiled by the sqlite dialect; ? positional, IN lists expanded per call; captured at the DBAPI cursor
-- @tags hotpath
-- @note Filter `tags.mlflow.runName LIKE 'sweep-1%'`: join on a filtered tags subquery; in the app case_sensitive_like is on.
-- @param ?1 'mlflow.runName'
-- @param ?2 'sweep-1%'
-- @param ?3 1
-- @param ?4 'active'
-- @param ?5 101
-- @param ?6 0
SELECT DISTINCT runs.run_uuid, runs.name, runs.source_type, runs.source_name, runs.entry_point_name, runs.user_id, runs.status, runs.start_time, runs.end_time, runs.deleted_time, runs.source_version, runs.lifecycle_stage, runs.artifact_uri, runs.experiment_id
FROM runs JOIN (SELECT tags."key" AS "key", tags.value AS value, tags.run_uuid AS run_uuid
FROM tags
WHERE tags."key" = ?1 AND tags.value LIKE ?2) AS anon_1 ON runs.run_uuid = anon_1.run_uuid
WHERE runs.experiment_id IN (?3) AND runs.lifecycle_stage IN (?4) ORDER BY runs.start_time DESC, runs.run_uuid
 LIMIT ?5 OFFSET ?6;

-- @id mlflow.search_runs.status_metric_order_by_param
-- @src mlflow/store/tracking/sqlalchemy_store.py:2368
-- @style SQLAlchemy 2.0 Core/ORM compiled by the sqlite dialect; ? positional, IN lists expanded per call; captured at the DBAPI cursor
-- @tags cpu-evidence
-- @note Filter `attributes.status = 'FINISHED' and metrics.accuracy > 0.8`, all lifecycle stages, ordered by params.lr DESC (string sort over a LEFT JOIN on params). https://github.com/mlflow/mlflow/issues/2730
-- @param ?1 1
-- @param ?2 0
-- @param ?3 'accuracy'
-- @param ?4 0.8
-- @param ?5 'lr'
-- @param ?6 1
-- @param ?7 'deleted'
-- @param ?8 'active'
-- @param ?9 'FINISHED'
-- @param ?10 51
-- @param ?11 0
SELECT DISTINCT runs.run_uuid, runs.name, runs.source_type, runs.source_name, runs.entry_point_name, runs.user_id, runs.status, runs.start_time, runs.end_time, runs.deleted_time, runs.source_version, runs.lifecycle_stage, runs.artifact_uri, runs.experiment_id, CASE WHEN (anon_1.value IS NULL) THEN ?1 ELSE ?2 END AS clause_1, anon_1.value
FROM runs JOIN (SELECT latest_metrics."key" AS "key", latest_metrics.value AS value, latest_metrics.timestamp AS timestamp, latest_metrics.step AS step, latest_metrics.is_nan AS is_nan, latest_metrics.run_uuid AS run_uuid
FROM latest_metrics
WHERE latest_metrics."key" = ?3 AND latest_metrics.value > ?4 AND latest_metrics.is_nan = 0) AS anon_2 ON runs.run_uuid = anon_2.run_uuid LEFT OUTER JOIN (SELECT params."key" AS "key", params.value AS value, params.run_uuid AS run_uuid
FROM params
WHERE params."key" = ?5) AS anon_1 ON runs.run_uuid = anon_1.run_uuid
WHERE runs.experiment_id IN (?6) AND runs.lifecycle_stage IN (?7, ?8) AND runs.status = ?9 ORDER BY clause_1, anon_1.value DESC, runs.start_time DESC, runs.run_uuid
 LIMIT ?10 OFFSET ?11;

-- @id mlflow.search_runs.two_experiments_order_by_metric
-- @src mlflow/store/tracking/sqlalchemy_store.py:2368
-- @style SQLAlchemy 2.0 Core/ORM compiled by the sqlite dialect; ? positional, IN lists expanded per call; captured at the DBAPI cursor
-- @tags cpu-evidence
-- @note Compare view across 2 experiments, max_results 1000: `metrics.loss > 0.6` ordered by metrics.loss then start_time; ~13k candidate runs sorted on two CASE keys. https://github.com/mlflow/mlflow/issues/2730
-- @param ?1 1
-- @param ?2 2
-- @param ?3 0
-- @param ?4 1
-- @param ?5 0
-- @param ?6 'loss'
-- @param ?7 0.6
-- @param ?8 'loss'
-- @param ?9 1
-- @param ?10 2
-- @param ?11 'active'
-- @param ?12 1001
-- @param ?13 0
SELECT DISTINCT runs.run_uuid, runs.name, runs.source_type, runs.source_name, runs.entry_point_name, runs.user_id, runs.status, runs.start_time, runs.end_time, runs.deleted_time, runs.source_version, runs.lifecycle_stage, runs.artifact_uri, runs.experiment_id, CASE WHEN (anon_1.is_nan = 1) THEN ?1 WHEN (anon_1.value IS NULL) THEN ?2 ELSE ?3 END AS clause_1, anon_1.value, CASE WHEN (runs.start_time IS NULL) THEN ?4 ELSE ?5 END AS clause_2, runs.start_time AS start_time__1
FROM runs JOIN (SELECT latest_metrics."key" AS "key", latest_metrics.value AS value, latest_metrics.timestamp AS timestamp, latest_metrics.step AS step, latest_metrics.is_nan AS is_nan, latest_metrics.run_uuid AS run_uuid
FROM latest_metrics
WHERE latest_metrics."key" = ?6 AND latest_metrics.value > ?7 AND latest_metrics.is_nan = 0) AS anon_2 ON runs.run_uuid = anon_2.run_uuid LEFT OUTER JOIN (SELECT latest_metrics."key" AS "key", latest_metrics.value AS value, latest_metrics.timestamp AS timestamp, latest_metrics.step AS step, latest_metrics.is_nan AS is_nan, latest_metrics.run_uuid AS run_uuid
FROM latest_metrics
WHERE latest_metrics."key" = ?8) AS anon_1 ON runs.run_uuid = anon_1.run_uuid
WHERE runs.experiment_id IN (?9, ?10) AND runs.lifecycle_stage IN (?11) ORDER BY clause_1, anon_1.value, clause_2, runs.start_time DESC, runs.run_uuid
 LIMIT ?12 OFFSET ?13;

-- @id mlflow.search_runs.param_tag_two_metrics
-- @src mlflow/store/tracking/sqlalchemy_store.py:2368
-- @style SQLAlchemy 2.0 Core/ORM compiled by the sqlite dialect; ? positional, IN lists expanded per call; captured at the DBAPI cursor
-- @tags cpu-evidence
-- @note Four filters (param, tag, two metric ranges) plus the order-by metric: five joins on key-filtered subqueries of params/tags/latest_metrics. https://github.com/mlflow/mlflow/issues/2730
-- @param ?1 1
-- @param ?2 2
-- @param ?3 0
-- @param ?4 'max_depth'
-- @param ?5 '5'
-- @param ?6 'stage'
-- @param ?7 'sweep'
-- @param ?8 'val_loss'
-- @param ?9 0.9
-- @param ?10 'loss'
-- @param ?11 0.5
-- @param ?12 'val_loss'
-- @param ?13 1
-- @param ?14 'active'
-- @param ?15 101
-- @param ?16 0
SELECT DISTINCT runs.run_uuid, runs.name, runs.source_type, runs.source_name, runs.entry_point_name, runs.user_id, runs.status, runs.start_time, runs.end_time, runs.deleted_time, runs.source_version, runs.lifecycle_stage, runs.artifact_uri, runs.experiment_id, CASE WHEN (anon_1.is_nan = 1) THEN ?1 WHEN (anon_1.value IS NULL) THEN ?2 ELSE ?3 END AS clause_1, anon_1.value
FROM runs JOIN (SELECT params."key" AS "key", params.value AS value, params.run_uuid AS run_uuid
FROM params
WHERE params."key" = ?4 AND params.value = ?5) AS anon_2 ON runs.run_uuid = anon_2.run_uuid JOIN (SELECT tags."key" AS "key", tags.value AS value, tags.run_uuid AS run_uuid
FROM tags
WHERE tags."key" = ?6 AND tags.value = ?7) AS anon_3 ON runs.run_uuid = anon_3.run_uuid JOIN (SELECT latest_metrics."key" AS "key", latest_metrics.value AS value, latest_metrics.timestamp AS timestamp, latest_metrics.step AS step, latest_metrics.is_nan AS is_nan, latest_metrics.run_uuid AS run_uuid
FROM latest_metrics
WHERE latest_metrics."key" = ?8 AND latest_metrics.value <= ?9 AND latest_metrics.is_nan = 0) AS anon_4 ON runs.run_uuid = anon_4.run_uuid JOIN (SELECT latest_metrics."key" AS "key", latest_metrics.value AS value, latest_metrics.timestamp AS timestamp, latest_metrics.step AS step, latest_metrics.is_nan AS is_nan, latest_metrics.run_uuid AS run_uuid
FROM latest_metrics
WHERE latest_metrics."key" = ?10 AND latest_metrics.value >= ?11 AND latest_metrics.is_nan = 0) AS anon_5 ON runs.run_uuid = anon_5.run_uuid LEFT OUTER JOIN (SELECT latest_metrics."key" AS "key", latest_metrics.value AS value, latest_metrics.timestamp AS timestamp, latest_metrics.step AS step, latest_metrics.is_nan AS is_nan, latest_metrics.run_uuid AS run_uuid
FROM latest_metrics
WHERE latest_metrics."key" = ?12) AS anon_1 ON runs.run_uuid = anon_1.run_uuid
WHERE runs.experiment_id IN (?13) AND runs.lifecycle_stage IN (?14) ORDER BY clause_1, anon_1.value, runs.start_time DESC, runs.run_uuid
 LIMIT ?15 OFFSET ?16;

-- @id mlflow.get_run.by_id
-- @src mlflow/store/tracking/sqlalchemy_store.py:1108
-- @style SQLAlchemy 2.0 Core/ORM compiled by the sqlite dialect; ? positional, IN lists expanded per call; captured at the DBAPI cursor
-- @tags hot-small
-- @note get_run: primary-key lookup of one run (followed by the same per-run child fetches).
-- @param ?1 '00189cf2a3dfb1de64e09cca03a42ace'
SELECT runs.run_uuid AS runs_run_uuid, runs.name AS runs_name, runs.source_type AS runs_source_type, runs.source_name AS runs_source_name, runs.entry_point_name AS runs_entry_point_name, runs.user_id AS runs_user_id, runs.status AS runs_status, runs.start_time AS runs_start_time, runs.end_time AS runs_end_time, runs.deleted_time AS runs_deleted_time, runs.source_version AS runs_source_version, runs.lifecycle_stage AS runs_lifecycle_stage, runs.artifact_uri AS runs_artifact_uri, runs.experiment_id AS runs_experiment_id
FROM runs
WHERE runs.run_uuid = ?1;

-- @id mlflow.metric_history.full
-- @src mlflow/store/tracking/sqlalchemy_store.py:1736
-- @style SQLAlchemy 2.0 Core/ORM compiled by the sqlite dialect; ? positional, IN lists expanded per call; captured at the DBAPI cursor
-- @tags hotpath,cpu-evidence
-- @note get_metric_history for a 5000-step training run: run_uuid + key over index_metrics_run_uuid_key_step, ordered by timestamp/step/value. https://github.com/mlflow/mlflow/pull/21727 (composite index added because history scans were slow)
-- @param ?1 '00189cf2a3dfb1de64e09cca03a42ace'
-- @param ?2 'loss'
-- @param ?3 -1
-- @param ?4 0
SELECT metrics."key" AS metrics_key, metrics.value AS metrics_value, metrics.timestamp AS metrics_timestamp, metrics.step AS metrics_step, metrics.is_nan AS metrics_is_nan, metrics.run_uuid AS metrics_run_uuid
FROM metrics
WHERE metrics.run_uuid = ?1 AND metrics."key" = ?2 ORDER BY metrics.timestamp, metrics.step, metrics.value
 LIMIT ?3 OFFSET ?4;

-- @id mlflow.metric_history.bulk_interval_ntile
-- @src mlflow/store/tracking/sqlalchemy_store.py:1947
-- @style SQLAlchemy 2.0 Core/ORM compiled by the sqlite dialect; ? positional, IN lists expanded per call; captured at the DBAPI cursor
-- @tags hotpath,analytics,cpu-evidence
-- @note Run charts: get_metric_history_bulk_interval downsamples in SQL: ntile(320) over the run's 5000 points, row_number() per bucket, keep rn = 1 (one statement per run). https://github.com/mlflow/mlflow/pull/20928 (100k-point metric took ~2.5 s per request before SQL downsampling)
-- @param ?1 320
-- @param ?2 '00189cf2a3dfb1de64e09cca03a42ace'
-- @param ?3 'loss'
-- @param ?4 1
SELECT anon_1.value AS anon_1_value, anon_1.timestamp AS anon_1_timestamp, anon_1.step AS anon_1_step, anon_1.is_nan AS anon_1_is_nan
FROM (SELECT anon_2.value AS value, anon_2.timestamp AS timestamp, anon_2.step AS step, anon_2.is_nan AS is_nan, row_number() OVER (PARTITION BY anon_2.bucket ORDER BY anon_2.step, anon_2.timestamp, anon_2.value, anon_2.is_nan) AS rn
FROM (SELECT metrics.value AS value, metrics.timestamp AS timestamp, metrics.step AS step, metrics.is_nan AS is_nan, ntile(?1) OVER (ORDER BY metrics.step, metrics.timestamp, metrics.value, metrics.is_nan) AS bucket
FROM metrics
WHERE metrics.run_uuid = ?2 AND metrics."key" = ?3) AS anon_2) AS anon_1
WHERE anon_1.rn = ?4 ORDER BY anon_1.step, anon_1.timestamp, anon_1.value, anon_1.is_nan;

-- @id mlflow.metric_history.bulk_interval_step0_system
-- @src mlflow/store/tracking/sqlalchemy_store.py:1947
-- @style SQLAlchemy 2.0 Core/ORM compiled by the sqlite dialect; ? positional, IN lists expanded per call; captured at the DBAPI cursor
-- @tags analytics,cpu-evidence
-- @note Same downsampling on a system-metrics series where all 6000 points share step 0, the case in https://github.com/mlflow/mlflow/pull/24173 (one step absorbs the whole history).
-- @param ?1 320
-- @param ?2 'e89cd5349aa234eceba530a4e165c04c'
-- @param ?3 'system/gpu_0_utilization_percentage'
-- @param ?4 1
SELECT anon_1.value AS anon_1_value, anon_1.timestamp AS anon_1_timestamp, anon_1.step AS anon_1_step, anon_1.is_nan AS anon_1_is_nan
FROM (SELECT anon_2.value AS value, anon_2.timestamp AS timestamp, anon_2.step AS step, anon_2.is_nan AS is_nan, row_number() OVER (PARTITION BY anon_2.bucket ORDER BY anon_2.step, anon_2.timestamp, anon_2.value, anon_2.is_nan) AS rn
FROM (SELECT metrics.value AS value, metrics.timestamp AS timestamp, metrics.step AS step, metrics.is_nan AS is_nan, ntile(?1) OVER (ORDER BY metrics.step, metrics.timestamp, metrics.value, metrics.is_nan) AS bucket
FROM metrics
WHERE metrics.run_uuid = ?2 AND metrics."key" = ?3) AS anon_2) AS anon_1
WHERE anon_1.rn = ?4 ORDER BY anon_1.step, anon_1.timestamp, anon_1.value, anon_1.is_nan;

-- @id mlflow.metric_history.max_step
-- @src mlflow/store/tracking/sqlalchemy_store.py:1800
-- @style SQLAlchemy 2.0 Core/ORM compiled by the sqlite dialect; ? positional, IN lists expanded per call; captured at the DBAPI cursor
-- @tags hot-small
-- @note get_max_step_for_metric: max(step) for one run/key (index-only).
-- @param ?1 '00189cf2a3dfb1de64e09cca03a42ace'
-- @param ?2 'loss'
SELECT max(metrics.step) AS max_1
FROM metrics
WHERE metrics.run_uuid = ?1 AND metrics."key" = ?2;

-- @id mlflow.log_batch.insert_metric
-- @src mlflow/store/tracking/sqlalchemy_store.py:1635
-- @style SQLAlchemy 2.0 Core/ORM compiled by the sqlite dialect; ? positional, IN lists expanded per call; captured at the DBAPI cursor
-- @tags hot-small,cpu-evidence,batch
-- @note log_batch inserts metrics with executemany (54 rows here, one row shown); every batch is followed by latest_metrics reads and upserts. https://github.com/mlflow/mlflow/issues/3010 (1000 metrics via log_batch took ~9 s)
-- @param ?1 'layer_0/grad_norm'
-- @param ?2 0.3
-- @param ?3 1793000000000
-- @param ?4 900
-- @param ?5 0
-- @param ?6 '00189cf2a3dfb1de64e09cca03a42ace'
INSERT INTO metrics ("key", value, timestamp, step, is_nan, run_uuid) VALUES (?1, ?2, ?3, ?4, ?5, ?6);

-- @id mlflow.search_traces.default_page
-- @src mlflow/store/tracking/sqlalchemy_store.py:4311
-- @style SQLAlchemy 2.0 Core/ORM compiled by the sqlite dialect; ? positional, IN lists expanded per call; captured at the DBAPI cursor
-- @tags hotpath
-- @note Traces tab default: trace_info for the experiment ordered by timestamp_ms DESC, 100 per page (index_trace_info_experiment_id_timestamp_ms).
-- @param ?1 4
-- @param ?2 100
-- @param ?3 0
SELECT trace_info.request_id AS trace_info_request_id, trace_info.experiment_id AS trace_info_experiment_id, trace_info.timestamp_ms AS trace_info_timestamp_ms, trace_info.execution_time_ms AS trace_info_execution_time_ms, trace_info.status AS trace_info_status, trace_info.client_request_id AS trace_info_client_request_id, trace_info.request_preview AS trace_info_request_preview, trace_info.response_preview AS trace_info_response_preview, trace_info.db_payload_generation AS trace_info_db_payload_generation, trace_info.trace_name AS trace_info_trace_name, trace_info.session_id AS trace_info_session_id, trace_info.input_tokens AS trace_info_input_tokens, trace_info.output_tokens AS trace_info_output_tokens, trace_info.total_tokens AS trace_info_total_tokens, trace_info.cache_read_input_tokens AS trace_info_cache_read_input_tokens, trace_info.cache_creation_input_tokens AS trace_info_cache_creation_input_tokens, trace_info.cache_creation_input_tokens_above_1hr AS trace_info_cache_creation_input_tokens_above_1hr, trace_info.input_cost AS trace_info_input_cost, trace_info.output_cost AS trace_info_output_cost, trace_info.total_cost AS trace_info_total_cost, trace_info.timestamp_ms AS trace_info_timestamp_ms__1
FROM trace_info
WHERE trace_info.experiment_id IN (?1) ORDER BY trace_info.timestamp_ms DESC, trace_info.request_id
 LIMIT ?2 OFFSET ?3;

-- @id mlflow.search_traces.tag_and_latency
-- @src mlflow/store/tracking/sqlalchemy_store.py:4311
-- @style SQLAlchemy 2.0 Core/ORM compiled by the sqlite dialect; ? positional, IN lists expanded per call; captured at the DBAPI cursor
-- @tags hotpath
-- @note Filter `tags.env = 'prod' and trace.execution_time_ms > 1000`: correlated tag subquery plus a range on execution_time_ms, no index on it.
-- @param ?1 'env'
-- @param ?2 'prod'
-- @param ?3 1000
-- @param ?4 4
-- @param ?5 100
-- @param ?6 0
SELECT trace_info.request_id AS trace_info_request_id, trace_info.experiment_id AS trace_info_experiment_id, trace_info.timestamp_ms AS trace_info_timestamp_ms, trace_info.execution_time_ms AS trace_info_execution_time_ms, trace_info.status AS trace_info_status, trace_info.client_request_id AS trace_info_client_request_id, trace_info.request_preview AS trace_info_request_preview, trace_info.response_preview AS trace_info_response_preview, trace_info.db_payload_generation AS trace_info_db_payload_generation, trace_info.trace_name AS trace_info_trace_name, trace_info.session_id AS trace_info_session_id, trace_info.input_tokens AS trace_info_input_tokens, trace_info.output_tokens AS trace_info_output_tokens, trace_info.total_tokens AS trace_info_total_tokens, trace_info.cache_read_input_tokens AS trace_info_cache_read_input_tokens, trace_info.cache_creation_input_tokens AS trace_info_cache_creation_input_tokens, trace_info.cache_creation_input_tokens_above_1hr AS trace_info_cache_creation_input_tokens_above_1hr, trace_info.input_cost AS trace_info_input_cost, trace_info.output_cost AS trace_info_output_cost, trace_info.total_cost AS trace_info_total_cost
FROM trace_info JOIN (SELECT trace_tags."key" AS "key", trace_tags.value AS value, trace_tags.request_id AS request_id
FROM trace_tags
WHERE trace_tags."key" = ?1 AND trace_tags.value = ?2) AS anon_1 ON trace_info.request_id = anon_1.request_id
WHERE trace_info.execution_time_ms > ?3 AND trace_info.experiment_id IN (?4) ORDER BY trace_info.timestamp_ms DESC, trace_info.request_id
 LIMIT ?5 OFFSET ?6;

-- @id mlflow.search_traces.span_name
-- @src mlflow/store/tracking/sqlalchemy_store.py:4311
-- @style SQLAlchemy 2.0 Core/ORM compiled by the sqlite dialect; ? positional, IN lists expanded per call; captured at the DBAPI cursor
-- @tags hotpath
-- @note Filter `span.name = 'ChatOpenAI'`: trace_info joined to a DISTINCT span subquery over the 45k spans.
-- @param ?1 'ChatOpenAI'
-- @param ?2 4
-- @param ?3 100
-- @param ?4 0
SELECT trace_info.request_id AS trace_info_request_id, trace_info.experiment_id AS trace_info_experiment_id, trace_info.timestamp_ms AS trace_info_timestamp_ms, trace_info.execution_time_ms AS trace_info_execution_time_ms, trace_info.status AS trace_info_status, trace_info.client_request_id AS trace_info_client_request_id, trace_info.request_preview AS trace_info_request_preview, trace_info.response_preview AS trace_info_response_preview, trace_info.db_payload_generation AS trace_info_db_payload_generation, trace_info.trace_name AS trace_info_trace_name, trace_info.session_id AS trace_info_session_id, trace_info.input_tokens AS trace_info_input_tokens, trace_info.output_tokens AS trace_info_output_tokens, trace_info.total_tokens AS trace_info_total_tokens, trace_info.cache_read_input_tokens AS trace_info_cache_read_input_tokens, trace_info.cache_creation_input_tokens AS trace_info_cache_creation_input_tokens, trace_info.cache_creation_input_tokens_above_1hr AS trace_info_cache_creation_input_tokens_above_1hr, trace_info.input_cost AS trace_info_input_cost, trace_info.output_cost AS trace_info_output_cost, trace_info.total_cost AS trace_info_total_cost
FROM trace_info
WHERE (EXISTS (SELECT *
FROM spans
WHERE spans.trace_id = trace_info.request_id AND spans.experiment_id = trace_info.experiment_id AND spans.name = ?1)) AND trace_info.experiment_id IN (?2) ORDER BY trace_info.timestamp_ms DESC, trace_info.request_id
 LIMIT ?3 OFFSET ?4;

-- @id mlflow.search_traces.feedback_with_sessions
-- @src mlflow/store/tracking/sqlalchemy_store.py:4311
-- @style SQLAlchemy 2.0 Core/ORM compiled by the sqlite dialect; ? positional, IN lists expanded per call; captured at the DBAPI cursor
-- @tags hotpath
-- @note Filter `feedback.correctness = 'false'`: UNION of directly-assessed traces and every trace in a session that has a session-level assessment (assessment_metadata LIKE '%"mlflow.trace.session":%'), joined back to trace_info.
-- @param ?1 'feedback'
-- @param ?2 'correctness'
-- @param ?3 'false'
-- @param ?4 '"false"'
-- @param ?5 4
-- @param ?6 4
-- @param ?7 'feedback'
-- @param ?8 'correctness'
-- @param ?9 'false'
-- @param ?10 '"false"'
-- @param ?11 '"mlflow.trace.session":'
-- @param ?12 4
-- @param ?13 100
-- @param ?14 0
SELECT trace_info.request_id AS trace_info_request_id, trace_info.experiment_id AS trace_info_experiment_id, trace_info.timestamp_ms AS trace_info_timestamp_ms, trace_info.execution_time_ms AS trace_info_execution_time_ms, trace_info.status AS trace_info_status, trace_info.client_request_id AS trace_info_client_request_id, trace_info.request_preview AS trace_info_request_preview, trace_info.response_preview AS trace_info_response_preview, trace_info.db_payload_generation AS trace_info_db_payload_generation, trace_info.trace_name AS trace_info_trace_name, trace_info.session_id AS trace_info_session_id, trace_info.input_tokens AS trace_info_input_tokens, trace_info.output_tokens AS trace_info_output_tokens, trace_info.total_tokens AS trace_info_total_tokens, trace_info.cache_read_input_tokens AS trace_info_cache_read_input_tokens, trace_info.cache_creation_input_tokens AS trace_info_cache_creation_input_tokens, trace_info.cache_creation_input_tokens_above_1hr AS trace_info_cache_creation_input_tokens_above_1hr, trace_info.input_cost AS trace_info_input_cost, trace_info.output_cost AS trace_info_output_cost, trace_info.total_cost AS trace_info_total_cost
FROM trace_info JOIN (SELECT anon_2.request_id AS request_id
FROM (SELECT DISTINCT assessments.trace_id AS request_id
FROM assessments
WHERE assessments.assessment_type = ?1 AND assessments.name = ?2 AND assessments.valid = 1 AND (assessments.value = ?3 OR assessments.value = ?4) UNION SELECT trace_info.request_id AS trace_info_request_id
FROM trace_info
WHERE trace_info.experiment_id IN (?5) AND trace_info.session_id IN (SELECT trace_info.session_id
FROM trace_info JOIN assessments ON assessments.trace_id = trace_info.request_id
WHERE trace_info.experiment_id IN (?6) AND trace_info.session_id IS NOT NULL AND assessments.assessment_type = ?7 AND assessments.name = ?8 AND assessments.valid = 1 AND (assessments.value = ?9 OR assessments.value = ?10) AND assessments.assessment_metadata IS NOT NULL AND (assessments.assessment_metadata LIKE '%' || ?11 || '%'))) AS anon_2) AS anon_1 ON trace_info.request_id = anon_1.request_id
WHERE trace_info.experiment_id IN (?12) ORDER BY trace_info.timestamp_ms DESC, trace_info.request_id
 LIMIT ?13 OFFSET ?14;

-- @id mlflow.search_traces.text_ilike
-- @src mlflow/store/tracking/sqlalchemy_store.py:4311
-- @style SQLAlchemy 2.0 Core/ORM compiled by the sqlite dialect; ? positional, IN lists expanded per call; captured at the DBAPI cursor
-- @tags hotpath
-- @note Free-text search `trace.text ILIKE '%refund%'`: lower() LIKE over request/response previews and span content, a full scan.
-- @param ?1 '%refund%'
-- @param ?2 4
-- @param ?3 100
-- @param ?4 0
SELECT trace_info.request_id AS trace_info_request_id, trace_info.experiment_id AS trace_info_experiment_id, trace_info.timestamp_ms AS trace_info_timestamp_ms, trace_info.execution_time_ms AS trace_info_execution_time_ms, trace_info.status AS trace_info_status, trace_info.client_request_id AS trace_info_client_request_id, trace_info.request_preview AS trace_info_request_preview, trace_info.response_preview AS trace_info_response_preview, trace_info.db_payload_generation AS trace_info_db_payload_generation, trace_info.trace_name AS trace_info_trace_name, trace_info.session_id AS trace_info_session_id, trace_info.input_tokens AS trace_info_input_tokens, trace_info.output_tokens AS trace_info_output_tokens, trace_info.total_tokens AS trace_info_total_tokens, trace_info.cache_read_input_tokens AS trace_info_cache_read_input_tokens, trace_info.cache_creation_input_tokens AS trace_info_cache_creation_input_tokens, trace_info.cache_creation_input_tokens_above_1hr AS trace_info_cache_creation_input_tokens_above_1hr, trace_info.input_cost AS trace_info_input_cost, trace_info.output_cost AS trace_info_output_cost, trace_info.total_cost AS trace_info_total_cost
FROM trace_info
WHERE (EXISTS (SELECT *
FROM spans
WHERE spans.trace_id = trace_info.request_id AND spans.experiment_id = trace_info.experiment_id AND lower(spans.content) LIKE lower(?1))) AND trace_info.experiment_id IN (?2) ORDER BY trace_info.timestamp_ms DESC, trace_info.request_id
 LIMIT ?3 OFFSET ?4;

-- @id mlflow.get_trace.spans
-- @src mlflow/store/tracking/sqlalchemy_store.py:7559
-- @style SQLAlchemy 2.0 Core/ORM compiled by the sqlite dialect; ? positional, IN lists expanded per call; captured at the DBAPI cursor
-- @tags hotpath,cpu-evidence
-- @note get_trace loads every span of the trace eagerly: 5000 spans (JSON content) for a runaway agent trace. https://github.com/mlflow/mlflow/issues/24314 (32,843-span trace hangs the UI and times out the API)
-- @param ?1 'tr-78a9832f36605a39f052d725cc40b839'
SELECT spans.trace_id AS spans_trace_id, spans.content AS spans_content, spans.parent_span_id AS spans_parent_span_id, spans.start_time_unix_nano AS spans_start_time_unix_nano
FROM spans
WHERE spans.trace_id IN (?1);

-- @id mlflow.trace_metrics.count_by_hour_status
-- @src mlflow/store/tracking/utils/sql_trace_metrics_utils.py:938
-- @style SQLAlchemy 2.0 Core/ORM compiled by the sqlite dialect; ? positional, IN lists expanded per call; captured at the DBAPI cursor
-- @tags hotpath,analytics
-- @note Trace analytics dashboard: trace count per hour bucket (floor(ts / 3600000.0) * 3600000) and status over 7 days.
-- @param ?1 3600000
-- @param ?2 3600000
-- @param ?3 4
-- @param ?4 1792395200000
-- @param ?5 1793000000000
-- @param ?6 3600000
-- @param ?7 3600000
-- @param ?8 3600000
-- @param ?9 3600000
-- @param ?10 1000
-- @param ?11 0
SELECT floor(trace_info.timestamp_ms / (?1 + 0.0)) * ?2 AS time_bucket, trace_info.status AS trace_status, count(trace_info.request_id) AS "COUNT"
FROM trace_info
WHERE trace_info.experiment_id IN (?3) AND trace_info.timestamp_ms >= ?4 AND trace_info.timestamp_ms <= ?5 AND trace_info.request_id IS NOT NULL AND trace_info.status IS NOT NULL GROUP BY floor(trace_info.timestamp_ms / (?6 + 0.0)) * ?7, trace_info.status ORDER BY floor(trace_info.timestamp_ms / (?8 + 0.0)) * ?9, trace_info.status
 LIMIT ?10 OFFSET ?11;

-- @id mlflow.trace_metrics.latency_percentiles_daily
-- @src mlflow/store/tracking/utils/sql_trace_metrics_utils.py:938
-- @style SQLAlchemy 2.0 Core/ORM compiled by the sqlite dialect; ? positional, IN lists expanded per call; captured at the DBAPI cursor
-- @tags analytics
-- @note Latency P50/P90/P99 and AVG per day: three percentile() aggregates over execution_time_ms per bucket.
-- @param ?1 86400000
-- @param ?2 86400000
-- @param ?3 50
-- @param ?4 90
-- @param ?5 99
-- @param ?6 4
-- @param ?7 1792395200000
-- @param ?8 1793000000000
-- @param ?9 86400000
-- @param ?10 86400000
-- @param ?11 86400000
-- @param ?12 86400000
-- @param ?13 1000
-- @param ?14 0
SELECT floor(trace_info.timestamp_ms / (?1 + 0.0)) * ?2 AS time_bucket, percentile(trace_info.execution_time_ms, ?3) AS "P50", percentile(trace_info.execution_time_ms, ?4) AS "P90", percentile(trace_info.execution_time_ms, ?5) AS "P99", avg(trace_info.execution_time_ms) AS "AVG"
FROM trace_info
WHERE trace_info.experiment_id IN (?6) AND trace_info.timestamp_ms >= ?7 AND trace_info.timestamp_ms <= ?8 AND trace_info.execution_time_ms IS NOT NULL GROUP BY floor(trace_info.timestamp_ms / (?9 + 0.0)) * ?10 ORDER BY floor(trace_info.timestamp_ms / (?11 + 0.0)) * ?12
 LIMIT ?13 OFFSET ?14;

-- @id mlflow.trace_metrics.span_count_by_type
-- @src mlflow/store/tracking/utils/sql_trace_metrics_utils.py:938
-- @style SQLAlchemy 2.0 Core/ORM compiled by the sqlite dialect; ? positional, IN lists expanded per call; captured at the DBAPI cursor
-- @tags analytics
-- @note Span count by span type: trace_info JOIN spans for the window, GROUP BY type.
-- @param ?1 4
-- @param ?2 1792395200000
-- @param ?3 1793000000000
-- @param ?4 1000
-- @param ?5 0
SELECT spans.type AS span_type, count(spans.span_id) AS "COUNT"
FROM trace_info JOIN spans ON spans.trace_id = trace_info.request_id
WHERE trace_info.experiment_id IN (?1) AND trace_info.timestamp_ms >= ?2 AND trace_info.timestamp_ms <= ?3 AND spans.span_id IS NOT NULL AND spans.type IS NOT NULL GROUP BY spans.type ORDER BY spans.type
 LIMIT ?4 OFFSET ?5;

-- @id mlflow.trace_metrics.span_latency_p95_by_name
-- @src mlflow/store/tracking/utils/sql_trace_metrics_utils.py:938
-- @style SQLAlchemy 2.0 Core/ORM compiled by the sqlite dialect; ? positional, IN lists expanded per call; captured at the DBAPI cursor
-- @tags analytics
-- @note Span latency P95 and AVG per day and span name: percentile over the generated duration column after the trace_info join.
-- @param ?1 1000000
-- @param ?2 86400000
-- @param ?3 86400000
-- @param ?4 1000000
-- @param ?5 95
-- @param ?6 1000000
-- @param ?7 4
-- @param ?8 1792395200000
-- @param ?9 1793000000000
-- @param ?10 1000000
-- @param ?11 1000000
-- @param ?12 86400000
-- @param ?13 86400000
-- @param ?14 1000000
-- @param ?15 86400000
-- @param ?16 86400000
-- @param ?17 1000
-- @param ?18 0
SELECT floor((spans.start_time_unix_nano / (?1 + 0.0)) / (?2 + 0.0)) * ?3 AS time_bucket, spans.name AS span_name, percentile((spans.end_time_unix_nano - spans.start_time_unix_nano) / ?4, ?5) AS "P95", avg((spans.end_time_unix_nano - spans.start_time_unix_nano) / ?6) AS "AVG"
FROM trace_info JOIN spans ON spans.trace_id = trace_info.request_id
WHERE trace_info.experiment_id IN (?7) AND trace_info.timestamp_ms >= ?8 AND trace_info.timestamp_ms <= ?9 AND (spans.end_time_unix_nano - spans.start_time_unix_nano) / ?10 IS NOT NULL AND spans.name IS NOT NULL GROUP BY floor((spans.start_time_unix_nano / (?11 + 0.0)) / (?12 + 0.0)) * ?13, spans.name ORDER BY floor((spans.start_time_unix_nano / (?14 + 0.0)) / (?15 + 0.0)) * ?16, spans.name
 LIMIT ?17 OFFSET ?18;

-- @id mlflow.trace_metrics.cost_by_model_daily
-- @src mlflow/store/tracking/utils/sql_trace_metrics_utils.py:938
-- @style SQLAlchemy 2.0 Core/ORM compiled by the sqlite dialect; ? positional, IN lists expanded per call; captured at the DBAPI cursor
-- @tags analytics
-- @note Cost dashboard: SUM(total_cost) per day and model_name from spans (nanosecond start time bucketed via two float divisions).
-- @param ?1 1000000
-- @param ?2 86400000
-- @param ?3 86400000
-- @param ?4 4
-- @param ?5 1792395200000000000
-- @param ?6 1793000000001000000
-- @param ?7 1000000
-- @param ?8 86400000
-- @param ?9 86400000
-- @param ?10 1000000
-- @param ?11 86400000
-- @param ?12 86400000
-- @param ?13 1000
-- @param ?14 0
SELECT floor((spans.start_time_unix_nano / (?1 + 0.0)) / (?2 + 0.0)) * ?3 AS time_bucket, spans.model_name AS span_model_name, sum(spans.total_cost) AS "SUM"
FROM trace_info JOIN spans ON spans.trace_id = trace_info.request_id
WHERE trace_info.experiment_id IN (?4) AND spans.start_time_unix_nano >= ?5 AND spans.start_time_unix_nano < ?6 AND spans.total_cost IS NOT NULL AND spans.model_name IS NOT NULL GROUP BY floor((spans.start_time_unix_nano / (?7 + 0.0)) / (?8 + 0.0)) * ?9, spans.model_name ORDER BY floor((spans.start_time_unix_nano / (?10 + 0.0)) / (?11 + 0.0)) * ?12, spans.model_name
 LIMIT ?13 OFFSET ?14;

-- @id mlflow.trace_metrics.assessment_counts
-- @src mlflow/store/tracking/utils/sql_trace_metrics_utils.py:938
-- @style SQLAlchemy 2.0 Core/ORM compiled by the sqlite dialect; ? positional, IN lists expanded per call; captured at the DBAPI cursor
-- @tags analytics
-- @note Quality tab: assessment count by name and value for valid assessments in the window.
-- @param ?1 4
-- @param ?2 1792395200000
-- @param ?3 1793000000000
-- @param ?4 1000
-- @param ?5 0
SELECT assessments.name AS assessment_name, assessments.value AS assessment_value, count(assessments.assessment_id) AS "COUNT"
FROM assessments
WHERE assessments.experiment_id IN (?1) AND assessments.valid = 1 AND assessments.trace_timestamp_ms >= ?2 AND assessments.trace_timestamp_ms <= ?3 AND assessments.assessment_id IS NOT NULL AND assessments.name IS NOT NULL AND assessments.value IS NOT NULL GROUP BY assessments.name, assessments.value ORDER BY assessments.name, assessments.value
 LIMIT ?4 OFFSET ?5;

-- @id mlflow.trace_metrics.session_count_daily
-- @src mlflow/store/tracking/utils/sql_trace_metrics_utils.py:938
-- @style SQLAlchemy 2.0 Core/ORM compiled by the sqlite dialect; ? positional, IN lists expanded per call; captured at the DBAPI cursor
-- @tags analytics
-- @note Sessions per day: count(DISTINCT session_id) per bucket.
-- @param ?1 86400000
-- @param ?2 86400000
-- @param ?3 4
-- @param ?4 1792395200000
-- @param ?5 1793000000000
-- @param ?6 86400000
-- @param ?7 86400000
-- @param ?8 86400000
-- @param ?9 86400000
-- @param ?10 1000
-- @param ?11 0
SELECT floor(trace_info.timestamp_ms / (?1 + 0.0)) * ?2 AS time_bucket, count(DISTINCT trace_info.session_id) AS "COUNT"
FROM trace_info
WHERE trace_info.experiment_id IN (?3) AND trace_info.timestamp_ms >= ?4 AND trace_info.timestamp_ms <= ?5 AND trace_info.session_id IS NOT NULL GROUP BY floor(trace_info.timestamp_ms / (?6 + 0.0)) * ?7 ORDER BY floor(trace_info.timestamp_ms / (?8 + 0.0)) * ?9
 LIMIT ?10 OFFSET ?11;

-- @id mlflow.sessions.find_completed
-- @src mlflow/store/tracking/sqlalchemy_store.py:4405
-- @style SQLAlchemy 2.0 Core/ORM compiled by the sqlite dialect; ? positional, IN lists expanded per call; captured at the DBAPI cursor
-- @tags analytics
-- @note Online evaluation: sessions whose last trace fell in the window: DISTINCT session ids joined back to all of the experiment's traces, min/max per session, HAVING-style filter in an outer query.
-- @param ?1 4
-- @param ?2 1792395200000
-- @param ?3 4
-- @param ?4 1793000000000
-- @param ?5 100
-- @param ?6 0
SELECT anon_1.session_id AS anon_1_session_id, anon_1.first_trace_timestamp_ms AS anon_1_first_trace_timestamp_ms, anon_1.last_trace_timestamp_ms AS anon_1_last_trace_timestamp_ms
FROM (SELECT trace_info.session_id AS session_id, min(trace_info.timestamp_ms) AS first_trace_timestamp_ms, max(trace_info.timestamp_ms) AS last_trace_timestamp_ms
FROM trace_info JOIN (SELECT DISTINCT trace_info.session_id AS session_id
FROM trace_info
WHERE trace_info.experiment_id = ?1 AND trace_info.timestamp_ms >= ?2 AND trace_info.session_id IS NOT NULL) AS anon_2 ON trace_info.session_id = anon_2.session_id
WHERE trace_info.experiment_id = ?3 GROUP BY trace_info.session_id) AS anon_1
WHERE anon_1.last_trace_timestamp_ms <= ?4 ORDER BY anon_1.last_trace_timestamp_ms ASC, anon_1.session_id ASC
 LIMIT ?5 OFFSET ?6;

-- @id mlflow.traces.filter_correlation
-- @src mlflow/store/tracking/sqlalchemy_store.py:5665
-- @style SQLAlchemy 2.0 Core/ORM compiled by the sqlite dialect; ? positional, IN lists expanded per call; captured at the DBAPI cursor
-- @tags analytics
-- @note Issue explorer: count(*) / count(filter1) / count(filter2) / joint over trace_info LEFT JOIN two filter subqueries (status = ERROR; feedback.correctness = false with the session UNION).
-- @param ?1 4
-- @param ?2 'ERROR'
-- @param ?3 'feedback'
-- @param ?4 'correctness'
-- @param ?5 'false'
-- @param ?6 '"false"'
-- @param ?7 4
-- @param ?8 4
-- @param ?9 'feedback'
-- @param ?10 'correctness'
-- @param ?11 'false'
-- @param ?12 '"false"'
-- @param ?13 '"mlflow.trace.session":'
-- @param ?14 4
-- @param ?15 4
SELECT count(trace_info.request_id) AS total, count(anon_1.request_id) AS filter1, count(anon_2.request_id) AS filter2, count(CASE WHEN (anon_1.request_id IS NOT NULL AND anon_2.request_id IS NOT NULL) THEN trace_info.request_id END) AS joint
FROM trace_info LEFT OUTER JOIN (SELECT trace_info.request_id AS request_id
FROM trace_info
WHERE trace_info.experiment_id IN (?1) AND trace_info.status = ?2) AS anon_1 ON trace_info.request_id = anon_1.request_id LEFT OUTER JOIN (SELECT trace_info.request_id AS request_id
FROM trace_info JOIN (SELECT anon_4.request_id AS request_id
FROM (SELECT DISTINCT assessments.trace_id AS request_id
FROM assessments
WHERE assessments.assessment_type = ?3 AND assessments.name = ?4 AND assessments.valid = 1 AND (assessments.value = ?5 OR assessments.value = ?6) UNION SELECT trace_info.request_id AS trace_info_request_id
FROM trace_info
WHERE trace_info.experiment_id IN (?7) AND trace_info.session_id IN (SELECT trace_info.session_id
FROM trace_info JOIN assessments ON assessments.trace_id = trace_info.request_id
WHERE trace_info.experiment_id IN (?8) AND trace_info.session_id IS NOT NULL AND assessments.assessment_type = ?9 AND assessments.name = ?10 AND assessments.valid = 1 AND (assessments.value = ?11 OR assessments.value = ?12) AND assessments.assessment_metadata IS NOT NULL AND (assessments.assessment_metadata LIKE '%' || ?13 || '%'))) AS anon_4) AS anon_3 ON trace_info.request_id = anon_3.request_id
WHERE trace_info.experiment_id IN (?14)) AS anon_2 ON trace_info.request_id = anon_2.request_id
WHERE trace_info.experiment_id IN (?15);

-- @id mlflow.delete_run.assessments_like
-- @src mlflow/store/tracking/sqlalchemy_store.py:975
-- @style SQLAlchemy 2.0 Core/ORM compiled by the sqlite dialect; ? positional, IN lists expanded per call; captured at the DBAPI cursor
-- @note delete_run removes assessments that mention the run: DELETE ... WHERE assessment_metadata LIKE '%' || run_id || '%', a full scan of assessments.
-- @param ?1 'e96861a4460051fc67232e5479a175dc'
DELETE FROM assessments WHERE (assessments.assessment_metadata LIKE '%' || ?1 || '%');
