-- Arize Phoenix (Arize-ai/phoenix @ 6359d63 = arize-phoenix v21.0.0, Elastic License 2.0). Every statement was
-- captured from the real Phoenix server (arize-phoenix 21.0.0 from PyPI, `phoenix serve` on a SQLite file holding the
-- synthetic data) with a SQLAlchemy before_cursor_execute listener, while posting the UI's own GraphQL operations
-- (query texts extracted from the bundled frontend): projects page, project header stats, spans / traces / sessions
-- tables with filters and sorts, the metrics dashboard time series, annotation summaries, trace details, datasets,
-- the experiments table and experiment compare. ? placeholders are numbered ?N in order; parameters are the ones the
-- app bound. The window is the UI's "last 7 days" ending 2026-10-30. @src is the resolver / dataloader that builds the
-- statement (repo paths under src/).
-- Phoenix opens SQLite through sqlean.py with the sqlean text/stats/time/crypto extensions; the stock CLI lacks
-- time_parse/time_sub/time_trunc/time_fmt_datetime/text_contains/text_casefold, so those calls are rewritten to core
-- SQL (see each @modified). percentile(x, p) is sqlean's stats function; the CLI's built-in percentile() matches it.

-- @id phoenix.projects.min_start_max_end
-- @src src/phoenix/server/api/dataloaders/min_start_or_max_end_times.py:42
-- @style SQLAlchemy 2.0 async (aiosqlite over sqlean) compiled by the sqlite dialect; ? positional, IN lists expanded; captured at the DBAPI cursor
-- @tags hotpath,analytics
-- @note Projects page: min/max trace start per project (GROUP BY over traces for every listed project).
-- @param ?1 1
-- @param ?2 2
-- @param ?3 3
-- @param ?4 4
SELECT traces.project_rowid, min(traces.start_time) AS min_start, max(traces.start_time) AS max_end
FROM traces
WHERE traces.project_rowid IN (?1, ?2, ?3, ?4) GROUP BY traces.project_rowid;

-- @id phoenix.project.latency_p50
-- @src src/phoenix/server/api/dataloaders/latency_ms_quantile.py:94
-- @style SQLAlchemy 2.0 async (aiosqlite over sqlean) compiled by the sqlite dialect; ? positional, IN lists expanded; captured at the DBAPI cursor
-- @tags hotpath,analytics,cpu-evidence
-- @note Project card / header latency P50: percentile() over (end - start) of every trace in the 7-day window. Header stats time out on big projects: https://github.com/Arize-ai/phoenix/issues/11243
-- @modified Rewrote Phoenix's sqlean functions to core SQL: time_sub(time_parse(a), time_parse(b)) (sqlean time ext, exact ns) -> unixepoch seconds diff * 1e6 + microsecond substr diff, * 1000.
-- @param ?1 1000000.0
-- @param ?2 50.0
-- @param ?3 '2026-10-23 00:00:00.000000'
-- @param ?4 '2026-10-30 00:00:00.000000'
-- @param ?5 2
SELECT traces.project_rowid, percentile((((unixepoch(traces.end_time) - unixepoch(traces.start_time)) * 1000000 + (CAST(substr(traces.end_time, 21, 6) AS INTEGER) - CAST(substr(traces.start_time, 21, 6) AS INTEGER))) * 1000) / ?1, ?2) AS percentile_1
FROM traces
WHERE traces.start_time >= ?3 AND traces.start_time < ?4 AND traces.project_rowid IN (?5) GROUP BY traces.project_rowid;

-- @id phoenix.project.cost_summary
-- @src src/phoenix/server/api/dataloaders/span_cost_summary_by_project.py:66
-- @style SQLAlchemy 2.0 async (aiosqlite over sqlean) compiled by the sqlite dialect; ? positional, IN lists expanded; captured at the DBAPI cursor
-- @tags hotpath,analytics,cpu-evidence
-- @note Project header costSummary: sum of span_costs joined to traces in the window. https://github.com/Arize-ai/phoenix/issues/11243 (ProjectPageHeaderQuery costSummary fails on projects with >10k spans)
-- @param ?1 0
-- @param ?2 0
-- @param ?3 0
-- @param ?4 0
-- @param ?5 0
-- @param ?6 0
-- @param ?7 2
-- @param ?8 '2026-10-23 00:00:00.000000'
-- @param ?9 '2026-10-30 00:00:00.000000'
SELECT traces.project_rowid, coalesce(sum(span_costs.prompt_cost), ?1) AS prompt_cost, coalesce(sum(span_costs.completion_cost), ?2) AS completion_cost, coalesce(sum(span_costs.total_cost), ?3) AS total_cost, coalesce(sum(span_costs.prompt_tokens), ?4) AS prompt_tokens, coalesce(sum(span_costs.completion_tokens), ?5) AS completion_tokens, coalesce(sum(span_costs.total_tokens), ?6) AS total_tokens
FROM traces JOIN span_costs ON traces.id = span_costs.trace_rowid
WHERE traces.project_rowid IN (?7) AND traces.start_time >= ?8 AND traces.start_time < ?9 GROUP BY traces.project_rowid;

-- @id phoenix.spans.root_page
-- @src src/phoenix/server/api/types/Project.py:615
-- @style SQLAlchemy 2.0 async (aiosqlite over sqlean) compiled by the sqlite dialect; ? positional, IN lists expanded; captured at the DBAPI cursor
-- @tags hotpath,cpu-evidence
-- @note Spans table, root spans only (default view): spans JOIN traces for the project and window, ORDER BY start_time DESC NULLS LAST, id DESC, LIMIT 31. Slow UI under trace volume: https://github.com/Arize-ai/phoenix/issues/10699
-- @param ?1 2
-- @param ?2 '2026-10-23 00:00:00.000000'
-- @param ?3 '2026-10-30 00:00:00.000000'
-- @param ?4 31
-- @param ?5 0
SELECT spans.id, spans.start_time AS "startTime_span_sort_column"
FROM spans JOIN traces ON traces.id = spans.trace_rowid
WHERE traces.project_rowid = ?1 AND spans.start_time >= ?2 AND spans.start_time < ?3 ORDER BY "startTime_span_sort_column" DESC NULLS LAST, spans.id DESC
 LIMIT ?4 OFFSET ?5;

-- @id phoenix.spans.filter_llm_latency
-- @src src/phoenix/server/api/types/Project.py:615
-- @style SQLAlchemy 2.0 async (aiosqlite over sqlean) compiled by the sqlite dialect; ? positional, IN lists expanded; captured at the DBAPI cursor
-- @tags hotpath,dynamic
-- @note Filter DSL `span_kind == 'LLM' and latency_ms > 2000`: latency computed per row from the timestamp strings, no index.
-- @modified Rewrote Phoenix's sqlean functions to core SQL: time_sub(time_parse(a), time_parse(b)) (sqlean time ext, exact ns) -> unixepoch seconds diff * 1e6 + microsecond substr diff, * 1000.
-- @param ?1 2
-- @param ?2 '2026-10-23 00:00:00.000000'
-- @param ?3 '2026-10-30 00:00:00.000000'
-- @param ?4 'LLM'
-- @param ?5 1000000.0
-- @param ?6 2000
-- @param ?7 31
-- @param ?8 0
SELECT spans.id, spans.start_time AS "startTime_span_sort_column"
FROM spans JOIN traces ON traces.id = spans.trace_rowid
WHERE traces.project_rowid = ?1 AND spans.start_time >= ?2 AND spans.start_time < ?3 AND spans.span_kind = ?4 AND (((unixepoch(spans.end_time) - unixepoch(spans.start_time)) * 1000000 + (CAST(substr(spans.end_time, 21, 6) AS INTEGER) - CAST(substr(spans.start_time, 21, 6) AS INTEGER))) * 1000) / ?5 > ?6 ORDER BY "startTime_span_sort_column" DESC NULLS LAST, spans.id DESC
 LIMIT ?7 OFFSET ?8;

-- @id phoenix.spans.filter_input_contains
-- @src src/phoenix/server/api/types/Project.py:615
-- @style SQLAlchemy 2.0 async (aiosqlite over sqlean) compiled by the sqlite dialect; ? positional, IN lists expanded; captured at the DBAPI cursor
-- @tags hotpath,dynamic
-- @note Filter DSL `'#4242' in input.value`: case-folded substring test on JSON_EXTRACT of every span's attributes in the window.
-- @modified Rewrote Phoenix's sqlean functions to core SQL: text_contains(text_casefold(a), text_casefold(b)) (sqlean text ext) -> (instr(lower(a), lower(b)) > 0).
-- @param ?1 2
-- @param ?2 '2026-10-23 00:00:00.000000'
-- @param ?3 '2026-10-30 00:00:00.000000'
-- @param ?4 '$."input"."value"'
-- @param ?5 '#4242'
-- @param ?6 31
-- @param ?7 0
SELECT spans.id, spans.start_time AS "startTime_span_sort_column"
FROM spans JOIN traces ON traces.id = spans.trace_rowid
WHERE traces.project_rowid = ?1 AND spans.start_time >= ?2 AND spans.start_time < ?3 AND (instr(lower(CAST(JSON_EXTRACT(spans.attributes, ?4) AS VARCHAR)), lower(?5)) > 0) = 1 ORDER BY "startTime_span_sort_column" DESC NULLS LAST, spans.id DESC
 LIMIT ?6 OFFSET ?7;

-- @id phoenix.spans.filter_annotation_label
-- @src src/phoenix/server/api/types/Project.py:615
-- @style SQLAlchemy 2.0 async (aiosqlite over sqlean) compiled by the sqlite dialect; ? positional, IN lists expanded; captured at the DBAPI cursor
-- @tags hotpath,dynamic
-- @note Filter DSL `annotations['correctness'].label == 'incorrect'`: correlated EXISTS over a seed row LEFT JOIN span_annotations per candidate span.
-- @param ?1 2
-- @param ?2 '2026-10-23 00:00:00.000000'
-- @param ?3 '2026-10-30 00:00:00.000000'
-- @param ?4 1
-- @param ?5 1
-- @param ?6 'correctness'
-- @param ?7 'incorrect'
-- @param ?8 31
-- @param ?9 0
SELECT spans.id, spans.start_time AS "startTime_span_sort_column"
FROM spans JOIN traces ON traces.id = spans.trace_rowid
WHERE traces.project_rowid = ?1 AND spans.start_time >= ?2 AND spans.start_time < ?3 AND (EXISTS (SELECT ?4 AS anon_1
FROM (SELECT ?5 AS seed) AS anon_2 LEFT OUTER JOIN span_annotations AS span_annotation_0 ON span_annotation_0.span_rowid = spans.id AND span_annotation_0.name = ?6
WHERE span_annotation_0.label = ?7)) ORDER BY "startTime_span_sort_column" DESC NULLS LAST, spans.id DESC
 LIMIT ?8 OFFSET ?9;

-- @id phoenix.spans.sort_total_tokens
-- @src src/phoenix/server/api/types/Project.py:615
-- @style SQLAlchemy 2.0 async (aiosqlite over sqlean) compiled by the sqlite dialect; ? positional, IN lists expanded; captured at the DBAPI cursor
-- @tags hotpath
-- @note Root spans sorted by cumulative token count (prompt + completion, the expression ix_cumulative_llm_token_count_total indexes).
-- @param ?1 2
-- @param ?2 '2026-10-23 00:00:00.000000'
-- @param ?3 '2026-10-30 00:00:00.000000'
-- @param ?4 31
-- @param ?5 0
SELECT spans.id, spans.cumulative_llm_token_count_prompt + spans.cumulative_llm_token_count_completion AS "cumulativeTokenCountTotal_span_sort_column"
FROM spans JOIN traces ON traces.id = spans.trace_rowid
WHERE traces.project_rowid = ?1 AND spans.start_time >= ?2 AND spans.start_time < ?3 ORDER BY "cumulativeTokenCountTotal_span_sort_column" DESC NULLS LAST, spans.id DESC
 LIMIT ?4 OFFSET ?5;

-- @id phoenix.spans.row_fields_batch
-- @src src/phoenix/server/api/dataloaders/table_fields.py:20
-- @style SQLAlchemy 2.0 async (aiosqlite over sqlean) compiled by the sqlite dialect; ? positional, IN lists expanded; captured at the DBAPI cursor
-- @tags hotpath
-- @note Batch load of the visible rows' columns: JSON_QUOTE(JSON_EXTRACT(attributes, path)) for metadata, user id, input/output values by id IN (...).
-- @modified Rewrote Phoenix's sqlean functions to core SQL: time_sub(time_parse(a), time_parse(b)) (sqlean time ext, exact ns) -> unixepoch seconds diff * 1e6 + microsecond substr diff, * 1000.
-- @param ?1 '$."metadata"'
-- @param ?2 '$."user"."id"'
-- @param ?3 1000000.0
-- @param ?4 '$."input"."mime_type"'
-- @param ?5 '$."input"."value"'
-- @param ?6 '$."input"."value"'
-- @param ?7 1
-- @param ?8 101
-- @param ?9 '$."output"."mime_type"'
-- @param ?10 '$."output"."value"'
-- @param ?11 '$."output"."value"'
-- @param ?12 1
-- @param ?13 101
-- @param ?14 'RERANKER'
-- @param ?15 '$."reranker"."output_documents"'
-- @param ?16 0
-- @param ?17 '$."retrieval"."documents"'
-- @param ?18 0
-- @param ?19 42126
-- @param ?20 42127
-- @param ?21 42128
-- @param ?22 42129
-- @param ?23 42130
-- @param ?24 91416
-- @param ?25 91417
-- @param ?26 91418
-- @param ?27 91419
-- @param ?28 91420
-- @param ?29 38946
-- @param ?30 38947
-- @param ?31 38948
-- @param ?32 38949
-- @param ?33 38950
-- @param ?34 42696
-- @param ?35 42697
-- @param ?36 42698
-- @param ?37 42699
-- @param ?38 42700
-- @param ?39 90846
-- @param ?40 90847
-- @param ?41 90848
-- @param ?42 90849
-- @param ?43 90850
-- @param ?44 87666
-- @param ?45 87667
-- @param ?46 87668
-- @param ?47 87669
-- @param ?48 87670
SELECT spans.id, spans.span_kind, spans.name, JSON_QUOTE(JSON_EXTRACT(spans.attributes, ?1)) AS metadata_, JSON_QUOTE(JSON_EXTRACT(spans.attributes, ?2)) AS user_id, spans.status_code, spans.status_message, spans.start_time, (((unixepoch(spans.end_time) - unixepoch(spans.start_time)) * 1000000 + (CAST(substr(spans.end_time, 21, 6) AS INTEGER) - CAST(substr(spans.start_time, 21, 6) AS INTEGER))) * 1000) / ?3 AS latency_ms_1, spans.cumulative_llm_token_count_prompt + spans.cumulative_llm_token_count_completion AS cumulative_llm_token_count_total, spans.span_id, spans.trace_rowid, JSON_QUOTE(JSON_EXTRACT(spans.attributes, ?4)) AS input_mime_type, CASE WHEN (JSON_QUOTE(JSON_EXTRACT(spans.attributes, ?5)) IS NOT NULL) THEN substr(CAST(JSON_EXTRACT(spans.attributes, ?6) AS VARCHAR), ?7, ?8) END AS input_value_first_101_chars, JSON_QUOTE(JSON_EXTRACT(spans.attributes, ?9)) AS output_mime_type, CASE WHEN (JSON_QUOTE(JSON_EXTRACT(spans.attributes, ?10)) IS NOT NULL) THEN substr(CAST(JSON_EXTRACT(spans.attributes, ?11) AS VARCHAR), ?12, ?13) END AS output_value_first_101_chars, CASE WHEN (upper(spans.span_kind) = ?14) THEN coalesce(json_array_length(JSON_QUOTE(JSON_EXTRACT(spans.attributes, ?15))), ?16) ELSE coalesce(json_array_length(JSON_QUOTE(JSON_EXTRACT(spans.attributes, ?17))), ?18) END AS num_documents_1
FROM spans
WHERE spans.id IN (?19, ?20, ?21, ?22, ?23, ?24, ?25, ?26, ?27, ?28, ?29, ?30, ?31, ?32, ?33, ?34, ?35, ?36, ?37, ?38, ?39, ?40, ?41, ?42, ?43, ?44, ?45, ?46, ?47, ?48);

-- @id phoenix.traces.descendants_cte
-- @src src/phoenix/server/api/dataloaders/span_descendants.py:56
-- @style SQLAlchemy 2.0 async (aiosqlite over sqlean) compiled by the sqlite dialect; ? positional, IN lists expanded; captured at the DBAPI cursor
-- @tags hotpath
-- @note Traces table: WITH RECURSIVE descendants for 30 root spans at once (VALUES list of (root_rowid, max_depth)), joined on parent_id, depth-limited, sorted.
-- @param ?1 1
-- @param ?2 90846
-- @param ?3 3
-- @param ?4 42126
-- @param ?5 3
-- @param ?6 91416
-- @param ?7 3
-- @param ?8 87666
-- @param ?9 3
-- @param ?10 42696
-- @param ?11 3
-- @param ?12 38946
-- @param ?13 3
-- @param ?14 35196
-- @param ?15 3
-- @param ?16 109356
-- @param ?17 3
-- @param ?18 66546
-- @param ?19 3
-- @param ?20 62796
-- @param ?21 3
-- @param ?22 14076
-- @param ?23 3
-- @param ?24 84486
-- @param ?25 3
-- @param ?26 88236
-- @param ?27 3
-- @param ?28 10326
-- @param ?29 3
-- @param ?30 56886
-- @param ?31 3
-- @param ?32 60636
-- @param ?33 3
-- @param ?34 32016
-- @param ?35 3
-- @param ?36 35766
-- @param ?37 3
-- @param ?38 64386
-- @param ?39 3
-- @param ?40 108336
-- @param ?41 3
-- @param ?42 59616
-- @param ?43 3
-- @param ?44 8166
-- @param ?45 3
-- @param ?46 55866
-- @param ?47 3
-- @param ?48 10896
-- @param ?49 3
-- @param ?50 11916
-- @param ?51 3
-- @param ?52 7146
-- @param ?53 3
-- @param ?54 77556
-- @param ?55 3
-- @param ?56 81306
-- @param ?57 3
-- @param ?58 106176
-- @param ?59 3
-- @param ?60 108906
-- @param ?61 3
-- @param ?62 1
-- @param ?63 1
WITH RECURSIVE descendants(id, span_id, start_time, root_rowid, max_depth, depth) AS
(SELECT spans.id AS id, spans.span_id AS span_id, spans.start_time AS start_time, roots.root_rowid AS root_rowid, roots.max_depth AS max_depth, ?1 AS depth
FROM (SELECT spans.span_id AS span_id, "values".root_rowid AS root_rowid, "values".max_depth AS max_depth
FROM (SELECT ?2 AS root_rowid, ?3 AS max_depth UNION ALL VALUES (?4, ?5), (?6, ?7), (?8, ?9), (?10, ?11), (?12, ?13), (?14, ?15), (?16, ?17), (?18, ?19), (?20, ?21), (?22, ?23), (?24, ?25), (?26, ?27), (?28, ?29), (?30, ?31), (?32, ?33), (?34, ?35), (?36, ?37), (?38, ?39), (?40, ?41), (?42, ?43), (?44, ?45), (?46, ?47), (?48, ?49), (?50, ?51), (?52, ?53), (?54, ?55), (?56, ?57), (?58, ?59), (?60, ?61)) AS "values" JOIN spans ON spans.id = "values".root_rowid) AS roots JOIN spans ON spans.parent_id = roots.span_id UNION ALL SELECT spans.id AS id, spans.span_id AS span_id, spans.start_time AS start_time, parents.root_rowid AS root_rowid, parents.max_depth AS max_depth, parents.depth + ?62 AS depth
FROM descendants AS parents JOIN spans ON spans.parent_id = parents.span_id
WHERE parents.max_depth IS NULL OR parents.depth + ?63 <= parents.max_depth)
 SELECT descendants.id, descendants.root_rowid, descendants.max_depth
FROM descendants ORDER BY descendants.root_rowid, descendants.max_depth, descendants.depth, descendants.start_time, descendants.id;

-- @id phoenix.sessions.page
-- @src src/phoenix/server/api/types/Project.py:712
-- @style SQLAlchemy 2.0 async (aiosqlite over sqlean) compiled by the sqlite dialect; ? positional, IN lists expanded; captured at the DBAPI cursor
-- @tags hotpath
-- @note Sessions table default page: project_sessions overlapping the window, start_time DESC.
-- @param ?1 2
-- @param ?2 '2026-10-23 00:00:00.000000'
-- @param ?3 '2026-10-30 00:00:00.000000'
-- @param ?4 31
-- @param ?5 0
SELECT project_sessions.session_id, project_sessions.project_id, project_sessions.start_time, project_sessions.end_time, project_sessions.id, project_sessions.start_time AS "startTime_project_session_sort_column"
FROM project_sessions
WHERE project_sessions.project_id = ?1 AND project_sessions.end_time >= ?2 AND project_sessions.start_time < ?3 ORDER BY "startTime_project_session_sort_column" DESC NULLS LAST, project_sessions.id DESC
 LIMIT ?4 OFFSET ?5;

-- @id phoenix.sessions.sort_by_tokens
-- @src src/phoenix/server/api/types/Project.py:712
-- @style SQLAlchemy 2.0 async (aiosqlite over sqlean) compiled by the sqlite dialect; ? positional, IN lists expanded; captured at the DBAPI cursor
-- @tags hotpath,analytics
-- @note Sessions sorted by total tokens: per-session SUM over LLM spans JOIN traces JOIN project_sessions, LEFT JOINed back and sorted (the slowest sessions view).
-- @param ?1 0
-- @param ?2 0
-- @param ?3 0
-- @param ?4 0
-- @param ?5 'LLM'
-- @param ?6 2
-- @param ?7 '2026-10-23 00:00:00.000000'
-- @param ?8 '2026-10-30 00:00:00.000000'
-- @param ?9 2
-- @param ?10 '2026-10-23 00:00:00.000000'
-- @param ?11 '2026-10-30 00:00:00.000000'
-- @param ?12 31
-- @param ?13 0
SELECT project_sessions.session_id, project_sessions.project_id, project_sessions.start_time, project_sessions.end_time, project_sessions.id, coalesce(anon_1.total, ?1) AS "tokenCountTotal_project_session_sort_column"
FROM project_sessions LEFT OUTER JOIN (SELECT traces.project_session_rowid AS project_session_rowid, sum(coalesce(coalesce(spans.llm_token_count_prompt, ?2) + coalesce(spans.llm_token_count_completion, ?3), ?4)) AS total
FROM spans JOIN traces ON traces.id = spans.trace_rowid JOIN project_sessions AS session_scope ON session_scope.id = traces.project_session_rowid
WHERE spans.span_kind = ?5 AND traces.project_rowid IN (?6) AND session_scope.end_time >= ?7 AND session_scope.start_time < ?8 GROUP BY traces.project_session_rowid) AS anon_1 ON project_sessions.id = anon_1.project_session_rowid
WHERE project_sessions.project_id = ?9 AND project_sessions.end_time >= ?10 AND project_sessions.start_time < ?11 ORDER BY "tokenCountTotal_project_session_sort_column" DESC NULLS LAST, project_sessions.id DESC
 LIMIT ?12 OFFSET ?13;

-- @id phoenix.metrics.trace_count_errors_hourly
-- @src src/phoenix/server/api/types/Project.py:1700
-- @style SQLAlchemy 2.0 async (aiosqlite over sqlean) compiled by the sqlite dialect; ? positional, IN lists expanded; captured at the DBAPI cursor
-- @tags analytics
-- @note Dashboard trace count per hour with error count: traces LEFT JOIN (root spans GROUP BY trace HAVING max(cumulative_error_count) > 0), hour bucket.
-- @modified Rewrote Phoenix's sqlean functions to core SQL: time_fmt_datetime(time_trunc(time_parse(x), unit)) (sqlean) -> strftime(CASE unit ... END, x) (minute/hour/day units).
-- @param ?1 'hour'
-- @param ?2 0
-- @param ?3 2
-- @param ?4 '2026-10-23 00:00:00.000000'
-- @param ?5 '2026-10-30 00:00:00.000000'
-- @param ?6 0
-- @param ?7 2
-- @param ?8 '2026-10-23 00:00:00.000000'
-- @param ?9 '2026-10-30 00:00:00.000000'
-- @param ?10 'hour'
-- @param ?11 'hour'
SELECT strftime(CASE ?1 WHEN 'minute' THEN '%Y-%m-%d %H:%M:00' WHEN 'hour' THEN '%Y-%m-%d %H:00:00' ELSE '%Y-%m-%d 00:00:00' END, traces.start_time) AS time_fmt_datetime_1, count(traces.id) AS total_count, coalesce(count(anon_1.trace_rowid), ?2) AS error_count
FROM traces LEFT OUTER JOIN (SELECT spans.trace_rowid AS trace_rowid
FROM spans JOIN traces ON spans.trace_rowid = traces.id
WHERE spans.parent_id IS NULL AND traces.project_rowid = ?3 AND traces.start_time >= ?4 AND traces.start_time < ?5 GROUP BY spans.trace_rowid
HAVING max(spans.cumulative_error_count) > ?6) AS anon_1 ON anon_1.trace_rowid = traces.id
WHERE traces.project_rowid = ?7 AND traces.start_time >= ?8 AND traces.start_time < ?9 GROUP BY strftime(CASE ?10 WHEN 'minute' THEN '%Y-%m-%d %H:%M:00' WHEN 'hour' THEN '%Y-%m-%d %H:00:00' ELSE '%Y-%m-%d 00:00:00' END, traces.start_time) ORDER BY strftime(CASE ?11 WHEN 'minute' THEN '%Y-%m-%d %H:%M:00' WHEN 'hour' THEN '%Y-%m-%d %H:00:00' ELSE '%Y-%m-%d 00:00:00' END, traces.start_time);

-- @id phoenix.metrics.latency_percentiles_hourly
-- @src src/phoenix/server/api/types/Project.py:1863
-- @style SQLAlchemy 2.0 async (aiosqlite over sqlean) compiled by the sqlite dialect; ? positional, IN lists expanded; captured at the DBAPI cursor
-- @tags analytics,cpu-evidence
-- @note Dashboard latency P50/P75/P90/P95/P99 per hour: five percentile() aggregates over trace durations. https://github.com/Arize-ai/phoenix/issues/11243
-- @modified Rewrote Phoenix's sqlean functions to core SQL: time_fmt_datetime(time_trunc(time_parse(x), unit)) (sqlean) -> strftime(CASE unit ... END, x) (minute/hour/day units); time_sub(time_parse(a), time_parse(b)) (sqlean time ext, exact ns) -> unixepoch seconds diff * 1e6 + microsecond substr diff, * 1000.
-- @param ?1 'hour'
-- @param ?2 1000000.0
-- @param ?3 50
-- @param ?4 1000000.0
-- @param ?5 75
-- @param ?6 1000000.0
-- @param ?7 90
-- @param ?8 1000000.0
-- @param ?9 95
-- @param ?10 1000000.0
-- @param ?11 99
-- @param ?12 1000000.0
-- @param ?13 99.9
-- @param ?14 1000000.0
-- @param ?15 2
-- @param ?16 '2026-10-23 00:00:00.000000'
-- @param ?17 '2026-10-30 00:00:00.000000'
-- @param ?18 'hour'
-- @param ?19 'hour'
SELECT strftime(CASE ?1 WHEN 'minute' THEN '%Y-%m-%d %H:%M:00' WHEN 'hour' THEN '%Y-%m-%d %H:00:00' ELSE '%Y-%m-%d 00:00:00' END, traces.start_time) AS time_fmt_datetime_1, percentile((((unixepoch(traces.end_time) - unixepoch(traces.start_time)) * 1000000 + (CAST(substr(traces.end_time, 21, 6) AS INTEGER) - CAST(substr(traces.start_time, 21, 6) AS INTEGER))) * 1000) / ?2, ?3) AS p50, percentile((((unixepoch(traces.end_time) - unixepoch(traces.start_time)) * 1000000 + (CAST(substr(traces.end_time, 21, 6) AS INTEGER) - CAST(substr(traces.start_time, 21, 6) AS INTEGER))) * 1000) / ?4, ?5) AS p75, percentile((((unixepoch(traces.end_time) - unixepoch(traces.start_time)) * 1000000 + (CAST(substr(traces.end_time, 21, 6) AS INTEGER) - CAST(substr(traces.start_time, 21, 6) AS INTEGER))) * 1000) / ?6, ?7) AS p90, percentile((((unixepoch(traces.end_time) - unixepoch(traces.start_time)) * 1000000 + (CAST(substr(traces.end_time, 21, 6) AS INTEGER) - CAST(substr(traces.start_time, 21, 6) AS INTEGER))) * 1000) / ?8, ?9) AS p95, percentile((((unixepoch(traces.end_time) - unixepoch(traces.start_time)) * 1000000 + (CAST(substr(traces.end_time, 21, 6) AS INTEGER) - CAST(substr(traces.start_time, 21, 6) AS INTEGER))) * 1000) / ?10, ?11) AS p99, percentile((((unixepoch(traces.end_time) - unixepoch(traces.start_time)) * 1000000 + (CAST(substr(traces.end_time, 21, 6) AS INTEGER) - CAST(substr(traces.start_time, 21, 6) AS INTEGER))) * 1000) / ?12, ?13) AS p999, max((((unixepoch(traces.end_time) - unixepoch(traces.start_time)) * 1000000 + (CAST(substr(traces.end_time, 21, 6) AS INTEGER) - CAST(substr(traces.start_time, 21, 6) AS INTEGER))) * 1000) / ?14) AS max
FROM traces
WHERE traces.project_rowid = ?15 AND traces.start_time >= ?16 AND traces.start_time < ?17 GROUP BY strftime(CASE ?18 WHEN 'minute' THEN '%Y-%m-%d %H:%M:00' WHEN 'hour' THEN '%Y-%m-%d %H:00:00' ELSE '%Y-%m-%d 00:00:00' END, traces.start_time) ORDER BY strftime(CASE ?19 WHEN 'minute' THEN '%Y-%m-%d %H:%M:00' WHEN 'hour' THEN '%Y-%m-%d %H:00:00' ELSE '%Y-%m-%d 00:00:00' END, traces.start_time);

-- @id phoenix.metrics.cost_hourly
-- @src src/phoenix/server/api/types/Project.py:2110
-- @style SQLAlchemy 2.0 async (aiosqlite over sqlean) compiled by the sqlite dialect; ? positional, IN lists expanded; captured at the DBAPI cursor
-- @tags analytics
-- @note Dashboard cost per hour: span_costs JOIN traces, SUM total/prompt/completion cost per bucket.
-- @modified Rewrote Phoenix's sqlean functions to core SQL: time_fmt_datetime(time_trunc(time_parse(x), unit)) (sqlean) -> strftime(CASE unit ... END, x) (minute/hour/day units).
-- @param ?1 'hour'
-- @param ?2 2
-- @param ?3 '2026-10-23 00:00:00.000000'
-- @param ?4 '2026-10-30 00:00:00.000000'
-- @param ?5 'hour'
-- @param ?6 'hour'
SELECT strftime(CASE ?1 WHEN 'minute' THEN '%Y-%m-%d %H:%M:00' WHEN 'hour' THEN '%Y-%m-%d %H:00:00' ELSE '%Y-%m-%d 00:00:00' END, traces.start_time) AS time_fmt_datetime_1, sum(span_costs.total_cost) AS sum_1, sum(span_costs.prompt_cost) AS sum_2, sum(span_costs.completion_cost) AS sum_3
FROM traces JOIN span_costs ON span_costs.trace_rowid = traces.id
WHERE traces.project_rowid = ?2 AND traces.start_time >= ?3 AND traces.start_time < ?4 GROUP BY strftime(CASE ?5 WHEN 'minute' THEN '%Y-%m-%d %H:%M:00' WHEN 'hour' THEN '%Y-%m-%d %H:00:00' ELSE '%Y-%m-%d 00:00:00' END, traces.start_time) ORDER BY strftime(CASE ?6 WHEN 'minute' THEN '%Y-%m-%d %H:%M:00' WHEN 'hour' THEN '%Y-%m-%d %H:00:00' ELSE '%Y-%m-%d 00:00:00' END, traces.start_time);

-- @id phoenix.metrics.span_count_by_status_hourly
-- @src src/phoenix/server/api/types/Project.py:1614
-- @style SQLAlchemy 2.0 async (aiosqlite over sqlean) compiled by the sqlite dialect; ? positional, IN lists expanded; captured at the DBAPI cursor
-- @tags analytics
-- @note Dashboard span count per hour split by status (SUM(CASE ...)) over every span of the project in the window.
-- @modified Rewrote Phoenix's sqlean functions to core SQL: time_fmt_datetime(time_trunc(time_parse(x), unit)) (sqlean) -> strftime(CASE unit ... END, x) (minute/hour/day units).
-- @param ?1 'hour'
-- @param ?2 'OK'
-- @param ?3 1
-- @param ?4 0
-- @param ?5 'ERROR'
-- @param ?6 1
-- @param ?7 0
-- @param ?8 'UNSET'
-- @param ?9 1
-- @param ?10 0
-- @param ?11 2
-- @param ?12 '2026-10-23 00:00:00.000000'
-- @param ?13 '2026-10-30 00:00:00.000000'
-- @param ?14 'hour'
-- @param ?15 'hour'
SELECT strftime(CASE ?1 WHEN 'minute' THEN '%Y-%m-%d %H:%M:00' WHEN 'hour' THEN '%Y-%m-%d %H:00:00' ELSE '%Y-%m-%d 00:00:00' END, spans.start_time) AS time_fmt_datetime_1, count(spans.id) AS total_count, sum(CASE WHEN (spans.status_code = ?2) THEN ?3 ELSE ?4 END) AS ok_count, sum(CASE WHEN (spans.status_code = ?5) THEN ?6 ELSE ?7 END) AS error_count, sum(CASE WHEN (spans.status_code = ?8) THEN ?9 ELSE ?10 END) AS unset_count
FROM spans JOIN traces ON traces.id = spans.trace_rowid
WHERE traces.project_rowid = ?11 AND spans.start_time >= ?12 AND spans.start_time < ?13 GROUP BY strftime(CASE ?14 WHEN 'minute' THEN '%Y-%m-%d %H:%M:00' WHEN 'hour' THEN '%Y-%m-%d %H:00:00' ELSE '%Y-%m-%d 00:00:00' END, spans.start_time) ORDER BY strftime(CASE ?15 WHEN 'minute' THEN '%Y-%m-%d %H:%M:00' WHEN 'hour' THEN '%Y-%m-%d %H:00:00' ELSE '%Y-%m-%d 00:00:00' END, spans.start_time);

-- @id phoenix.metrics.top_models_by_cost
-- @src src/phoenix/server/api/types/Project.py:2447
-- @style SQLAlchemy 2.0 async (aiosqlite over sqlean) compiled by the sqlite dialect; ? positional, IN lists expanded; captured at the DBAPI cursor
-- @tags analytics
-- @note Top models by cost: span_cost_details JOIN span_costs JOIN traces, grouped by model and token type.
-- @param ?1 0
-- @param ?2 0
-- @param ?3 97
-- @param ?4 91
-- @param ?5 19
-- @param ?6 2
-- @param ?7 '2026-10-23 00:00:00.000000'
-- @param ?8 '2026-10-30 00:00:00.000000'
SELECT span_costs.model_id, span_cost_details.token_type, span_cost_details.is_prompt, coalesce(sum(span_cost_details.cost), ?1) AS cost, coalesce(sum(span_cost_details.tokens), ?2) AS tokens
FROM span_cost_details JOIN span_costs ON span_cost_details.span_cost_id = span_costs.id JOIN traces ON span_costs.trace_rowid = traces.id
WHERE span_costs.model_id IN (?3, ?4, ?5) AND traces.project_rowid = ?6 AND span_costs.span_start_time >= ?7 AND span_costs.span_start_time < ?8 GROUP BY span_costs.model_id, span_cost_details.token_type, span_cost_details.is_prompt;

-- @id phoenix.annotations.span_summary
-- @src src/phoenix/server/api/annotation_metrics.py:131
-- @style SQLAlchemy 2.0 async (aiosqlite over sqlean) compiled by the sqlite dialect; ? positional, IN lists expanded; captured at the DBAPI cursor
-- @tags analytics
-- @note Span annotation summary card (correctness): label fractions and mean score per name over annotated spans in the window, nested aggregate subqueries.
-- @param ?1 0
-- @param ?2 0
-- @param ?3 1.0
-- @param ?4 0
-- @param ?5 1.0
-- @param ?6 2
-- @param ?7 'correctness'
-- @param ?8 '2026-10-23 00:00:00.000000'
-- @param ?9 '2026-10-30 00:00:00.000000'
-- @param ?10 2
-- @param ?11 'correctness'
-- @param ?12 '2026-10-23 00:00:00.000000'
-- @param ?13 '2026-10-30 00:00:00.000000'
-- @param ?14 2
-- @param ?15 'correctness'
-- @param ?16 '2026-10-23 00:00:00.000000'
-- @param ?17 '2026-10-30 00:00:00.000000'
-- @param ?18 0
-- @param ?19 1.0
-- @param ?20 0
-- @param ?21 1.0
-- @param ?22 2
-- @param ?23 'correctness'
-- @param ?24 '2026-10-23 00:00:00.000000'
-- @param ?25 '2026-10-30 00:00:00.000000'
-- @param ?26 2
-- @param ?27 'correctness'
-- @param ?28 '2026-10-23 00:00:00.000000'
-- @param ?29 '2026-10-30 00:00:00.000000'
SELECT anon_1.name, anon_1.label, CASE WHEN (anon_2.entity_count > ?1) THEN (anon_1.avg_label_fraction_present * anon_1.entities_with_label) / (anon_2.entity_count + 0.0) END AS avg_label_fraction, anon_3.overall_avg_score AS avg_score, anon_1.total_label_count AS label_count, anon_1.total_score_count AS score_count, anon_1.total_score_sum AS score_sum, anon_1.entities_with_label AS record_count
FROM (SELECT anon_4.name AS name, anon_4.label AS label, count(DISTINCT anon_4.entity_id) AS entities_with_label, sum(anon_4.label_count) AS total_label_count, sum(anon_4.score_count) AS total_score_count, sum(anon_4.score_sum) AS total_score_sum, avg(anon_4.label_fraction) AS avg_label_fraction_present
FROM (SELECT anon_5.entity_id AS entity_id, anon_5.name AS name, anon_5.label AS label, anon_5.record_count AS record_count, anon_5.label_count AS label_count, anon_5.score_count AS score_count, anon_5.score_sum AS score_sum, CASE WHEN (anon_6.total_label_count > ?2) THEN (anon_5.label_count * ?3) / (anon_6.total_label_count + 0.0) END AS label_fraction, CASE WHEN (anon_6.total_score_count > ?4) THEN (anon_6.entity_score_sum * ?5) / (anon_6.total_score_count + 0.0) END AS entity_avg_score
FROM (SELECT spans.id AS entity_id, span_annotations.name AS name, span_annotations.label AS label, count(*) AS record_count, count(span_annotations.label) AS label_count, count(span_annotations.score) AS score_count, sum(span_annotations.score) AS score_sum
FROM span_annotations JOIN spans ON spans.id = span_annotations.span_rowid JOIN traces ON traces.id = spans.trace_rowid
WHERE traces.project_rowid = ?6 AND (span_annotations.score IS NOT NULL OR span_annotations.label IS NOT NULL) AND span_annotations.name IN (?7) AND spans.start_time >= ?8 AND spans.start_time < ?9 GROUP BY spans.id, span_annotations.name, span_annotations.label) AS anon_5 JOIN (SELECT anon_5.entity_id AS entity_id, anon_5.name AS name, sum(anon_5.label_count) AS total_label_count, sum(anon_5.score_count) AS total_score_count, sum(anon_5.score_sum) AS entity_score_sum
FROM (SELECT spans.id AS entity_id, span_annotations.name AS name, span_annotations.label AS label, count(*) AS record_count, count(span_annotations.label) AS label_count, count(span_annotations.score) AS score_count, sum(span_annotations.score) AS score_sum
FROM span_annotations JOIN spans ON spans.id = span_annotations.span_rowid JOIN traces ON traces.id = spans.trace_rowid
WHERE traces.project_rowid = ?10 AND (span_annotations.score IS NOT NULL OR span_annotations.label IS NOT NULL) AND span_annotations.name IN (?11) AND spans.start_time >= ?12 AND spans.start_time < ?13 GROUP BY spans.id, span_annotations.name, span_annotations.label) AS anon_5 GROUP BY anon_5.entity_id, anon_5.name) AS anon_6 ON anon_5.entity_id = anon_6.entity_id AND anon_5.name = anon_6.name) AS anon_4 GROUP BY anon_4.name, anon_4.label) AS anon_1 JOIN (SELECT span_annotations.name AS name, count(DISTINCT spans.id) AS entity_count
FROM span_annotations JOIN spans ON spans.id = span_annotations.span_rowid JOIN traces ON traces.id = spans.trace_rowid
WHERE traces.project_rowid = ?14 AND (span_annotations.score IS NOT NULL OR span_annotations.label IS NOT NULL) AND span_annotations.name IN (?15) AND spans.start_time >= ?16 AND spans.start_time < ?17 GROUP BY span_annotations.name) AS anon_2 ON anon_1.name = anon_2.name JOIN (SELECT anon_7.name AS name, avg(anon_7.entity_avg_score) AS overall_avg_score
FROM (SELECT DISTINCT anon_4.entity_id AS entity_id, anon_4.name AS name, anon_4.entity_avg_score AS entity_avg_score
FROM (SELECT anon_5.entity_id AS entity_id, anon_5.name AS name, anon_5.label AS label, anon_5.record_count AS record_count, anon_5.label_count AS label_count, anon_5.score_count AS score_count, anon_5.score_sum AS score_sum, CASE WHEN (anon_6.total_label_count > ?18) THEN (anon_5.label_count * ?19) / (anon_6.total_label_count + 0.0) END AS label_fraction, CASE WHEN (anon_6.total_score_count > ?20) THEN (anon_6.entity_score_sum * ?21) / (anon_6.total_score_count + 0.0) END AS entity_avg_score
FROM (SELECT spans.id AS entity_id, span_annotations.name AS name, span_annotations.label AS label, count(*) AS record_count, count(span_annotations.label) AS label_count, count(span_annotations.score) AS score_count, sum(span_annotations.score) AS score_sum
FROM span_annotations JOIN spans ON spans.id = span_annotations.span_rowid JOIN traces ON traces.id = spans.trace_rowid
WHERE traces.project_rowid = ?22 AND (span_annotations.score IS NOT NULL OR span_annotations.label IS NOT NULL) AND span_annotations.name IN (?23) AND spans.start_time >= ?24 AND spans.start_time < ?25 GROUP BY spans.id, span_annotations.name, span_annotations.label) AS anon_5 JOIN (SELECT anon_5.entity_id AS entity_id, anon_5.name AS name, sum(anon_5.label_count) AS total_label_count, sum(anon_5.score_count) AS total_score_count, sum(anon_5.score_sum) AS entity_score_sum
FROM (SELECT spans.id AS entity_id, span_annotations.name AS name, span_annotations.label AS label, count(*) AS record_count, count(span_annotations.label) AS label_count, count(span_annotations.score) AS score_count, sum(span_annotations.score) AS score_sum
FROM span_annotations JOIN spans ON spans.id = span_annotations.span_rowid JOIN traces ON traces.id = spans.trace_rowid
WHERE traces.project_rowid = ?26 AND (span_annotations.score IS NOT NULL OR span_annotations.label IS NOT NULL) AND span_annotations.name IN (?27) AND spans.start_time >= ?28 AND spans.start_time < ?29 GROUP BY spans.id, span_annotations.name, span_annotations.label) AS anon_5 GROUP BY anon_5.entity_id, anon_5.name) AS anon_6 ON anon_5.entity_id = anon_6.entity_id AND anon_5.name = anon_6.name) AS anon_4) AS anon_7 GROUP BY anon_7.name) AS anon_3 ON anon_1.name = anon_3.name ORDER BY anon_1.name, anon_1.label;

-- @id phoenix.metrics.span_annotation_score_hourly
-- @src src/phoenix/server/api/types/Project.py:2193
-- @style SQLAlchemy 2.0 async (aiosqlite over sqlean) compiled by the sqlite dialect; ? positional, IN lists expanded; captured at the DBAPI cursor
-- @tags analytics
-- @note Annotation score time series: AVG(score) per hour and annotation name, span_annotations JOIN spans JOIN traces.
-- @modified Rewrote Phoenix's sqlean functions to core SQL: time_fmt_datetime(time_trunc(time_parse(x), unit)) (sqlean) -> strftime(CASE unit ... END, x) (minute/hour/day units).
-- @param ?1 'hour'
-- @param ?2 2
-- @param ?3 '2026-10-23 00:00:00.000000'
-- @param ?4 '2026-10-30 00:00:00.000000'
-- @param ?5 'hour'
-- @param ?6 'hour'
SELECT strftime(CASE ?1 WHEN 'minute' THEN '%Y-%m-%d %H:%M:00' WHEN 'hour' THEN '%Y-%m-%d %H:00:00' ELSE '%Y-%m-%d 00:00:00' END, traces.start_time) AS time_fmt_datetime_1, span_annotations.name, avg(span_annotations.score) AS average_score
FROM span_annotations JOIN spans ON span_annotations.span_rowid = spans.id JOIN traces ON spans.trace_rowid = traces.id
WHERE traces.project_rowid = ?2 AND traces.start_time >= ?3 AND traces.start_time < ?4 GROUP BY strftime(CASE ?5 WHEN 'minute' THEN '%Y-%m-%d %H:%M:00' WHEN 'hour' THEN '%Y-%m-%d %H:00:00' ELSE '%Y-%m-%d 00:00:00' END, traces.start_time), span_annotations.name ORDER BY strftime(CASE ?6 WHEN 'minute' THEN '%Y-%m-%d %H:%M:00' WHEN 'hour' THEN '%Y-%m-%d %H:00:00' ELSE '%Y-%m-%d 00:00:00' END, traces.start_time);

-- @id phoenix.annotations.document_eval_summary
-- @src src/phoenix/server/api/types/Project.py:1212
-- @style SQLAlchemy 2.0 async (aiosqlite over sqlean) compiled by the sqlite dialect; ? positional, IN lists expanded; captured at the DBAPI cursor
-- @tags analytics
-- @note Retrieval relevance summary (rag-eval project): per-document scores with json_array_length of the retrieval documents; NDCG/precision computed in Python.
-- @param ?1 'RERANKER'
-- @param ?2 '$."reranker"."output_documents"'
-- @param ?3 0
-- @param ?4 '$."retrieval"."documents"'
-- @param ?5 0
-- @param ?6 3
-- @param ?7 'relevance'
-- @param ?8 'LLM'
-- @param ?9 '2026-10-23 00:00:00.000000'
-- @param ?10 '2026-10-30 00:00:00.000000'
SELECT document_annotations.name, spans.id, CASE WHEN (upper(spans.span_kind) = ?1) THEN coalesce(json_array_length(JSON_QUOTE(JSON_EXTRACT(spans.attributes, ?2))), ?3) ELSE coalesce(json_array_length(JSON_QUOTE(JSON_EXTRACT(spans.attributes, ?4))), ?5) END AS num_docs, document_annotations.score, document_annotations.document_position
FROM spans JOIN traces ON traces.id = spans.trace_rowid JOIN document_annotations ON spans.id = document_annotations.span_rowid
WHERE traces.project_rowid = ?6 AND document_annotations.name IN (?7) AND document_annotations.annotator_kind = ?8 AND document_annotations.score IS NOT NULL AND spans.start_time >= ?9 AND spans.start_time < ?10 ORDER BY document_annotations.name, spans.id;

-- @id phoenix.trace.spans_tree
-- @src src/phoenix/server/api/types/Trace.py:284
-- @style SQLAlchemy 2.0 async (aiosqlite over sqlean) compiled by the sqlite dialect; ? positional, IN lists expanded; captured at the DBAPI cursor
-- @tags hotpath
-- @note Trace details: every span of the trace with latency, for the tree view.
-- @modified Rewrote Phoenix's sqlean functions to core SQL: time_sub(time_parse(a), time_parse(b)) (sqlean time ext, exact ns) -> unixepoch seconds diff * 1e6 + microsecond substr diff, * 1000.
-- @param ?1 1000000.0
-- @param ?2 0
-- @param ?3 0
-- @param ?4 0
-- @param ?5 90848
-- @param ?6 90849
-- @param ?7 90850
-- @param ?8 90846
-- @param ?9 90847
SELECT spans.id, spans.span_id, spans.name, spans.span_kind, spans.status_code, spans.start_time, spans.end_time, spans.parent_id, (((unixepoch(spans.end_time) - unixepoch(spans.start_time)) * 1000000 + (CAST(substr(spans.end_time, 21, 6) AS INTEGER) - CAST(substr(spans.start_time, 21, 6) AS INTEGER))) * 1000) / ?1 AS latency_ms_1, coalesce(coalesce(spans.llm_token_count_prompt, ?2) + coalesce(spans.llm_token_count_completion, ?3), ?4) AS coalesce_1
FROM spans
WHERE spans.id IN (?5, ?6, ?7, ?8, ?9);

-- @id phoenix.datasets.example_revisions
-- @src src/phoenix/server/api/dataloaders/dataset_example_revisions.py:81
-- @style SQLAlchemy 2.0 async (aiosqlite over sqlean) compiled by the sqlite dialect; ? positional, IN lists expanded; captured at the DBAPI cursor
-- @tags hotpath
-- @note Examples table: latest revision per example at a version (max revision id per example via a VALUES list of (example, version) keys, validity CASE).
-- @param ?1 1
-- @param ?2 0
-- @param ?3 1
-- @param ?4 NULL
-- @param ?5 2
-- @param ?6 NULL
-- @param ?7 3
-- @param ?8 NULL
-- @param ?9 4
-- @param ?10 NULL
-- @param ?11 5
-- @param ?12 NULL
-- @param ?13 6
-- @param ?14 NULL
-- @param ?15 7
-- @param ?16 NULL
-- @param ?17 8
-- @param ?18 NULL
-- @param ?19 9
-- @param ?20 NULL
-- @param ?21 10
-- @param ?22 NULL
-- @param ?23 11
-- @param ?24 NULL
-- @param ?25 12
-- @param ?26 NULL
-- @param ?27 13
-- @param ?28 NULL
-- @param ?29 14
-- @param ?30 NULL
-- @param ?31 15
-- @param ?32 NULL
-- @param ?33 16
-- @param ?34 NULL
-- @param ?35 17
-- @param ?36 NULL
-- @param ?37 18
-- @param ?38 NULL
-- @param ?39 19
-- @param ?40 NULL
-- @param ?41 20
-- @param ?42 NULL
-- @param ?43 21
-- @param ?44 NULL
-- @param ?45 22
-- @param ?46 NULL
-- @param ?47 23
-- @param ?48 NULL
-- @param ?49 24
-- @param ?50 NULL
-- @param ?51 25
-- @param ?52 NULL
-- @param ?53 26
-- @param ?54 NULL
-- @param ?55 27
-- @param ?56 NULL
-- @param ?57 28
-- @param ?58 NULL
-- @param ?59 29
-- @param ?60 NULL
-- @param ?61 30
-- @param ?62 NULL
-- @param ?63 31
-- @param ?64 NULL
-- @param ?65 32
-- @param ?66 NULL
-- @param ?67 33
-- @param ?68 NULL
-- @param ?69 34
-- @param ?70 NULL
-- @param ?71 35
-- @param ?72 NULL
-- @param ?73 36
-- @param ?74 NULL
-- @param ?75 37
-- @param ?76 NULL
-- @param ?77 38
-- @param ?78 NULL
-- @param ?79 39
-- @param ?80 NULL
-- @param ?81 40
-- @param ?82 NULL
-- @param ?83 41
-- @param ?84 NULL
-- @param ?85 42
-- @param ?86 NULL
-- @param ?87 43
-- @param ?88 NULL
-- @param ?89 44
-- @param ?90 NULL
-- @param ?91 45
-- @param ?92 NULL
-- @param ?93 46
-- @param ?94 NULL
-- @param ?95 47
-- @param ?96 NULL
-- @param ?97 48
-- @param ?98 NULL
-- @param ?99 49
-- @param ?100 NULL
-- @param ?101 50
-- @param ?102 NULL
-- @param ?103 51
-- @param ?104 NULL
-- @param ?105 52
-- @param ?106 NULL
-- @param ?107 53
-- @param ?108 NULL
-- @param ?109 54
-- @param ?110 NULL
-- @param ?111 55
-- @param ?112 NULL
-- @param ?113 56
-- @param ?114 NULL
-- @param ?115 57
-- @param ?116 NULL
-- @param ?117 58
-- @param ?118 NULL
-- @param ?119 59
-- @param ?120 NULL
-- @param ?121 60
-- @param ?122 NULL
-- @param ?123 61
-- @param ?124 NULL
-- @param ?125 62
-- @param ?126 NULL
-- @param ?127 63
-- @param ?128 NULL
-- @param ?129 64
-- @param ?130 NULL
-- @param ?131 65
-- @param ?132 NULL
-- @param ?133 66
-- @param ?134 NULL
-- @param ?135 67
-- @param ?136 NULL
-- @param ?137 68
-- @param ?138 NULL
-- @param ?139 69
-- @param ?140 NULL
-- @param ?141 70
-- @param ?142 NULL
-- @param ?143 71
-- @param ?144 NULL
-- @param ?145 72
-- @param ?146 NULL
-- @param ?147 73
-- @param ?148 NULL
-- @param ?149 74
-- @param ?150 NULL
-- @param ?151 75
-- @param ?152 NULL
-- @param ?153 76
-- @param ?154 NULL
-- @param ?155 77
-- @param ?156 NULL
-- @param ?157 78
-- @param ?158 NULL
-- @param ?159 79
-- @param ?160 NULL
-- @param ?161 80
-- @param ?162 NULL
-- @param ?163 81
-- @param ?164 NULL
-- @param ?165 82
-- @param ?166 NULL
-- @param ?167 83
-- @param ?168 NULL
-- @param ?169 84
-- @param ?170 NULL
-- @param ?171 85
-- @param ?172 NULL
-- @param ?173 86
-- @param ?174 NULL
-- @param ?175 87
-- @param ?176 NULL
-- @param ?177 88
-- @param ?178 NULL
-- @param ?179 89
-- @param ?180 NULL
-- @param ?181 90
-- @param ?182 NULL
-- @param ?183 91
-- @param ?184 NULL
-- @param ?185 92
-- @param ?186 NULL
-- @param ?187 93
-- @param ?188 NULL
-- @param ?189 94
-- @param ?190 NULL
-- @param ?191 95
-- @param ?192 NULL
-- @param ?193 96
-- @param ?194 NULL
-- @param ?195 97
-- @param ?196 NULL
-- @param ?197 98
-- @param ?198 NULL
-- @param ?199 99
-- @param ?200 NULL
-- @param ?201 100
-- @param ?202 NULL
SELECT anon_1.example_id, anon_1.version_id, CASE WHEN (anon_1.version_id IS NULL OR dataset_versions.id IS NOT NULL) THEN ?1 ELSE ?2 END AS is_valid_version, dataset_example_revisions.dataset_example_id, dataset_example_revisions.dataset_version_id, dataset_example_revisions.input, dataset_example_revisions.output, dataset_example_revisions.metadata, dataset_example_revisions.content_hash, dataset_example_revisions.revision_kind, dataset_example_revisions.created_at, dataset_example_revisions.id
FROM (SELECT anon_2.example_id AS example_id, anon_2.version_id AS version_id, max(dataset_example_revisions.id) AS revision_id
FROM (SELECT ?3 AS example_id, ?4 AS version_id UNION SELECT ?5 AS example_id, ?6 AS version_id UNION SELECT ?7 AS example_id, ?8 AS version_id UNION SELECT ?9 AS example_id, ?10 AS version_id UNION SELECT ?11 AS example_id, ?12 AS version_id UNION SELECT ?13 AS example_id, ?14 AS version_id UNION SELECT ?15 AS example_id, ?16 AS version_id UNION SELECT ?17 AS example_id, ?18 AS version_id UNION SELECT ?19 AS example_id, ?20 AS version_id UNION SELECT ?21 AS example_id, ?22 AS version_id UNION SELECT ?23 AS example_id, ?24 AS version_id UNION SELECT ?25 AS example_id, ?26 AS version_id UNION SELECT ?27 AS example_id, ?28 AS version_id UNION SELECT ?29 AS example_id, ?30 AS version_id UNION SELECT ?31 AS example_id, ?32 AS version_id UNION SELECT ?33 AS example_id, ?34 AS version_id UNION SELECT ?35 AS example_id, ?36 AS version_id UNION SELECT ?37 AS example_id, ?38 AS version_id UNION SELECT ?39 AS example_id, ?40 AS version_id UNION SELECT ?41 AS example_id, ?42 AS version_id UNION SELECT ?43 AS example_id, ?44 AS version_id UNION SELECT ?45 AS example_id, ?46 AS version_id UNION SELECT ?47 AS example_id, ?48 AS version_id UNION SELECT ?49 AS example_id, ?50 AS version_id UNION SELECT ?51 AS example_id, ?52 AS version_id UNION SELECT ?53 AS example_id, ?54 AS version_id UNION SELECT ?55 AS example_id, ?56 AS version_id UNION SELECT ?57 AS example_id, ?58 AS version_id UNION SELECT ?59 AS example_id, ?60 AS version_id UNION SELECT ?61 AS example_id, ?62 AS version_id UNION SELECT ?63 AS example_id, ?64 AS version_id UNION SELECT ?65 AS example_id, ?66 AS version_id UNION SELECT ?67 AS example_id, ?68 AS version_id UNION SELECT ?69 AS example_id, ?70 AS version_id UNION SELECT ?71 AS example_id, ?72 AS version_id UNION SELECT ?73 AS example_id, ?74 AS version_id UNION SELECT ?75 AS example_id, ?76 AS version_id UNION SELECT ?77 AS example_id, ?78 AS version_id UNION SELECT ?79 AS example_id, ?80 AS version_id UNION SELECT ?81 AS example_id, ?82 AS version_id UNION SELECT ?83 AS example_id, ?84 AS version_id UNION SELECT ?85 AS example_id, ?86 AS version_id UNION SELECT ?87 AS example_id, ?88 AS version_id UNION SELECT ?89 AS example_id, ?90 AS version_id UNION SELECT ?91 AS example_id, ?92 AS version_id UNION SELECT ?93 AS example_id, ?94 AS version_id UNION SELECT ?95 AS example_id, ?96 AS version_id UNION SELECT ?97 AS example_id, ?98 AS version_id UNION SELECT ?99 AS example_id, ?100 AS version_id UNION SELECT ?101 AS example_id, ?102 AS version_id UNION SELECT ?103 AS example_id, ?104 AS version_id UNION SELECT ?105 AS example_id, ?106 AS version_id UNION SELECT ?107 AS example_id, ?108 AS version_id UNION SELECT ?109 AS example_id, ?110 AS version_id UNION SELECT ?111 AS example_id, ?112 AS version_id UNION SELECT ?113 AS example_id, ?114 AS version_id UNION SELECT ?115 AS example_id, ?116 AS version_id UNION SELECT ?117 AS example_id, ?118 AS version_id UNION SELECT ?119 AS example_id, ?120 AS version_id UNION SELECT ?121 AS example_id, ?122 AS version_id UNION SELECT ?123 AS example_id, ?124 AS version_id UNION SELECT ?125 AS example_id, ?126 AS version_id UNION SELECT ?127 AS example_id, ?128 AS version_id UNION SELECT ?129 AS example_id, ?130 AS version_id UNION SELECT ?131 AS example_id, ?132 AS version_id UNION SELECT ?133 AS example_id, ?134 AS version_id UNION SELECT ?135 AS example_id, ?136 AS version_id UNION SELECT ?137 AS example_id, ?138 AS version_id UNION SELECT ?139 AS example_id, ?140 AS version_id UNION SELECT ?141 AS example_id, ?142 AS version_id UNION SELECT ?143 AS example_id, ?144 AS version_id UNION SELECT ?145 AS example_id, ?146 AS version_id UNION SELECT ?147 AS example_id, ?148 AS version_id UNION SELECT ?149 AS example_id, ?150 AS version_id UNION SELECT ?151 AS example_id, ?152 AS version_id UNION SELECT ?153 AS example_id, ?154 AS version_id UNION SELECT ?155 AS example_id, ?156 AS version_id UNION SELECT ?157 AS example_id, ?158 AS version_id UNION SELECT ?159 AS example_id, ?160 AS version_id UNION SELECT ?161 AS example_id, ?162 AS version_id UNION SELECT ?163 AS example_id, ?164 AS version_id UNION SELECT ?165 AS example_id, ?166 AS version_id UNION SELECT ?167 AS example_id, ?168 AS version_id UNION SELECT ?169 AS example_id, ?170 AS version_id UNION SELECT ?171 AS example_id, ?172 AS version_id UNION SELECT ?173 AS example_id, ?174 AS version_id UNION SELECT ?175 AS example_id, ?176 AS version_id UNION SELECT ?177 AS example_id, ?178 AS version_id UNION SELECT ?179 AS example_id, ?180 AS version_id UNION SELECT ?181 AS example_id, ?182 AS version_id UNION SELECT ?183 AS example_id, ?184 AS version_id UNION SELECT ?185 AS example_id, ?186 AS version_id UNION SELECT ?187 AS example_id, ?188 AS version_id UNION SELECT ?189 AS example_id, ?190 AS version_id UNION SELECT ?191 AS example_id, ?192 AS version_id UNION SELECT ?193 AS example_id, ?194 AS version_id UNION SELECT ?195 AS example_id, ?196 AS version_id UNION SELECT ?197 AS example_id, ?198 AS version_id UNION SELECT ?199 AS example_id, ?200 AS version_id UNION SELECT ?201 AS example_id, ?202 AS version_id) AS anon_2 JOIN dataset_example_revisions ON anon_2.example_id = dataset_example_revisions.dataset_example_id
WHERE anon_2.version_id IS NULL OR dataset_example_revisions.dataset_version_id <= anon_2.version_id GROUP BY anon_2.example_id, anon_2.version_id) AS anon_1 JOIN dataset_example_revisions ON anon_1.revision_id = dataset_example_revisions.id LEFT OUTER JOIN dataset_versions ON anon_1.version_id = dataset_versions.id;

-- @id phoenix.experiments.error_rates
-- @src src/phoenix/server/api/dataloaders/experiment_error_rates.py:26
-- @style SQLAlchemy 2.0 async (aiosqlite over sqlean) compiled by the sqlite dialect; ? positional, IN lists expanded; captured at the DBAPI cursor
-- @tags analytics,cpu-evidence
-- @note Experiments table: average error rate per experiment over all its runs (nested GROUP BY), for every experiment on the dataset. Experiments page times out on large datasets: https://github.com/Arize-ai/phoenix/issues/16891
-- @param ?1 20
-- @param ?2 19
-- @param ?3 18
-- @param ?4 17
-- @param ?5 16
-- @param ?6 15
-- @param ?7 14
-- @param ?8 13
-- @param ?9 12
-- @param ?10 11
-- @param ?11 10
-- @param ?12 9
-- @param ?13 8
-- @param ?14 7
-- @param ?15 6
-- @param ?16 5
-- @param ?17 4
-- @param ?18 3
-- @param ?19 2
-- @param ?20 1
SELECT average_repetition_error_rates.experiment_id, avg(average_repetition_error_rates.average_repetition_error_rate) AS average_run_error_rates
FROM (SELECT experiment_runs.experiment_id AS experiment_id, count(experiment_runs.error) / (count(experiment_runs.id) + 0.0) AS average_repetition_error_rate
FROM experiment_runs
WHERE experiment_runs.experiment_id IN (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15, ?16, ?17, ?18, ?19, ?20) GROUP BY experiment_runs.dataset_example_id, experiment_runs.experiment_id) AS average_repetition_error_rates GROUP BY average_repetition_error_rates.experiment_id;

-- @id phoenix.experiments.avg_latency
-- @src src/phoenix/server/api/dataloaders/average_experiment_run_latency.py:16
-- @style SQLAlchemy 2.0 async (aiosqlite over sqlean) compiled by the sqlite dialect; ? positional, IN lists expanded; captured at the DBAPI cursor
-- @tags analytics,cpu-evidence
-- @note Experiments table: average run latency per experiment (avg over repetitions then over examples). https://github.com/Arize-ai/phoenix/issues/16891
-- @modified Rewrote Phoenix's sqlean functions to core SQL: time_sub(time_parse(a), time_parse(b)) (sqlean time ext, exact ns) -> unixepoch seconds diff * 1e6 + microsecond substr diff, * 1000.
-- @param ?1 1000000.0
-- @param ?2 20
-- @param ?3 19
-- @param ?4 18
-- @param ?5 17
-- @param ?6 16
-- @param ?7 15
-- @param ?8 14
-- @param ?9 13
-- @param ?10 12
-- @param ?11 11
-- @param ?12 10
-- @param ?13 9
-- @param ?14 8
-- @param ?15 7
-- @param ?16 6
-- @param ?17 5
-- @param ?18 4
-- @param ?19 3
-- @param ?20 2
-- @param ?21 1
SELECT anon_1.experiment_id, avg(anon_1.average_repetition_latency_ms) AS average_run_latency_ms
FROM (SELECT experiment_runs.experiment_id AS experiment_id, avg((((unixepoch(experiment_runs.end_time) - unixepoch(experiment_runs.start_time)) * 1000000 + (CAST(substr(experiment_runs.end_time, 21, 6) AS INTEGER) - CAST(substr(experiment_runs.start_time, 21, 6) AS INTEGER))) * 1000) / ?1) AS average_repetition_latency_ms
FROM experiment_runs
WHERE experiment_runs.experiment_id IN (?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15, ?16, ?17, ?18, ?19, ?20, ?21) GROUP BY experiment_runs.dataset_example_id, experiment_runs.experiment_id) AS anon_1 GROUP BY anon_1.experiment_id;

-- @id phoenix.experiments.annotation_summaries
-- @src src/phoenix/server/api/dataloaders/experiment_annotation_summaries.py:67
-- @style SQLAlchemy 2.0 async (aiosqlite over sqlean) compiled by the sqlite dialect; ? positional, IN lists expanded; captured at the DBAPI cursor
-- @tags analytics,cpu-evidence
-- @note Experiments table: mean/min/max score per experiment and evaluator, from repetition means per example. https://github.com/Arize-ai/phoenix/issues/16891
-- @param ?1 20
-- @param ?2 19
-- @param ?3 18
-- @param ?4 17
-- @param ?5 16
-- @param ?6 15
-- @param ?7 14
-- @param ?8 13
-- @param ?9 12
-- @param ?10 11
-- @param ?11 10
-- @param ?12 9
-- @param ?13 8
-- @param ?14 7
-- @param ?15 6
-- @param ?16 5
-- @param ?17 4
-- @param ?18 3
-- @param ?19 2
-- @param ?20 1
-- @param ?21 20
-- @param ?22 19
-- @param ?23 18
-- @param ?24 17
-- @param ?25 16
-- @param ?26 15
-- @param ?27 14
-- @param ?28 13
-- @param ?29 12
-- @param ?30 11
-- @param ?31 10
-- @param ?32 9
-- @param ?33 8
-- @param ?34 7
-- @param ?35 6
-- @param ?36 5
-- @param ?37 4
-- @param ?38 3
-- @param ?39 2
-- @param ?40 1
SELECT repetition_mean_scores.experiment_id AS experiment_id, repetition_mean_scores.annotation_name AS annotation_name, repetition_mean_scores.mean_score AS mean_score, anon_1.min_score AS min_score, anon_1.max_score AS max_score, anon_1.count AS count_, anon_1.error_count AS error_count, anon_1.score_count AS score_count, anon_1.label_count AS label_count
FROM (SELECT repetition_mean_scores_by_example.experiment_id AS experiment_id, repetition_mean_scores_by_example.annotation_name AS annotation_name, avg(repetition_mean_scores_by_example.mean_repetition_score) AS mean_score
FROM (SELECT experiment_runs.experiment_id AS experiment_id, experiment_run_annotations.name AS annotation_name, avg(experiment_run_annotations.score) AS mean_repetition_score
FROM experiment_run_annotations JOIN experiment_runs ON experiment_run_annotations.experiment_run_id = experiment_runs.id
WHERE experiment_runs.experiment_id IN (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15, ?16, ?17, ?18, ?19, ?20) GROUP BY experiment_runs.experiment_id, experiment_runs.dataset_example_id, experiment_run_annotations.name) AS repetition_mean_scores_by_example GROUP BY repetition_mean_scores_by_example.experiment_id, repetition_mean_scores_by_example.annotation_name) AS repetition_mean_scores JOIN (SELECT experiment_runs.experiment_id AS experiment_id, experiment_run_annotations.name AS annotation_name, min(experiment_run_annotations.score) AS min_score, max(experiment_run_annotations.score) AS max_score, count(*) AS count, count(experiment_run_annotations.error) AS error_count, count(experiment_run_annotations.score) AS score_count, count(experiment_run_annotations.label) AS label_count
FROM experiment_run_annotations JOIN experiment_runs ON experiment_run_annotations.experiment_run_id = experiment_runs.id
WHERE experiment_runs.experiment_id IN (?21, ?22, ?23, ?24, ?25, ?26, ?27, ?28, ?29, ?30, ?31, ?32, ?33, ?34, ?35, ?36, ?37, ?38, ?39, ?40) GROUP BY experiment_runs.experiment_id, experiment_run_annotations.name) AS anon_1 ON anon_1.experiment_id = repetition_mean_scores.experiment_id AND anon_1.annotation_name = repetition_mean_scores.annotation_name ORDER BY repetition_mean_scores.annotation_name;

-- @id phoenix.compare.runs_for_examples
-- @src src/phoenix/server/api/queries.py:682
-- @style SQLAlchemy 2.0 async (aiosqlite over sqlean) compiled by the sqlite dialect; ? positional, IN lists expanded; captured at the DBAPI cursor
-- @tags hotpath,cpu-evidence
-- @note compareExperiments: runs of the base + 2 compare experiments for the 50 examples on the page, LEFT JOIN traces on the text trace_id. https://github.com/Arize-ai/phoenix/issues/16891
-- @param ?1 1
-- @param ?2 2
-- @param ?3 3
-- @param ?4 4
-- @param ?5 5
-- @param ?6 6
-- @param ?7 7
-- @param ?8 8
-- @param ?9 9
-- @param ?10 10
-- @param ?11 11
-- @param ?12 12
-- @param ?13 13
-- @param ?14 14
-- @param ?15 15
-- @param ?16 16
-- @param ?17 17
-- @param ?18 18
-- @param ?19 19
-- @param ?20 20
-- @param ?21 21
-- @param ?22 22
-- @param ?23 23
-- @param ?24 24
-- @param ?25 25
-- @param ?26 26
-- @param ?27 27
-- @param ?28 28
-- @param ?29 29
-- @param ?30 30
-- @param ?31 31
-- @param ?32 32
-- @param ?33 33
-- @param ?34 34
-- @param ?35 35
-- @param ?36 36
-- @param ?37 37
-- @param ?38 38
-- @param ?39 39
-- @param ?40 40
-- @param ?41 41
-- @param ?42 42
-- @param ?43 43
-- @param ?44 44
-- @param ?45 45
-- @param ?46 46
-- @param ?47 47
-- @param ?48 48
-- @param ?49 49
-- @param ?50 50
-- @param ?51 20
-- @param ?52 19
-- @param ?53 18
SELECT experiment_runs.experiment_id, experiment_runs.dataset_example_id, experiment_runs.repetition_number, experiment_runs.trace_id, experiment_runs.output, experiment_runs.start_time, experiment_runs.end_time, experiment_runs.prompt_token_count, experiment_runs.completion_token_count, experiment_runs.error, experiment_runs.id, traces_1.trace_id AS trace_id_1, traces_1.id AS id_1
FROM experiment_runs LEFT OUTER JOIN traces AS traces_1 ON experiment_runs.trace_id = traces_1.trace_id
WHERE experiment_runs.dataset_example_id IN (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15, ?16, ?17, ?18, ?19, ?20, ?21, ?22, ?23, ?24, ?25, ?26, ?27, ?28, ?29, ?30, ?31, ?32, ?33, ?34, ?35, ?36, ?37, ?38, ?39, ?40, ?41, ?42, ?43, ?44, ?45, ?46, ?47, ?48, ?49, ?50) AND experiment_runs.experiment_id IN (?51, ?52, ?53) ORDER BY experiment_runs.repetition_number ASC;

-- @id phoenix.compare.metrics
-- @src src/phoenix/server/api/queries.py:826
-- @style SQLAlchemy 2.0 async (aiosqlite over sqlean) compiled by the sqlite dialect; ? positional, IN lists expanded; captured at the DBAPI cursor
-- @tags analytics,cpu-evidence
-- @note Compare metrics header: per-run latency/tokens/cost (experiment_runs LEFT JOIN traces LEFT JOIN span_costs) computed twice, min per example, base vs compare counted with 21 SUM(CASE) columns, unpaginated. https://github.com/Arize-ai/phoenix/issues/16891
-- @modified Rewrote Phoenix's sqlean functions to core SQL: time_sub(time_parse(a), time_parse(b)) (sqlean time ext, exact ns) -> unixepoch seconds diff * 1e6 + microsecond substr diff, * 1000.
-- @param ?1 1
-- @param ?2 0
-- @param ?3 0
-- @param ?4 1
-- @param ?5 0
-- @param ?6 0
-- @param ?7 1
-- @param ?8 0
-- @param ?9 0
-- @param ?10 1
-- @param ?11 0
-- @param ?12 0
-- @param ?13 1
-- @param ?14 0
-- @param ?15 0
-- @param ?16 1
-- @param ?17 0
-- @param ?18 0
-- @param ?19 1
-- @param ?20 0
-- @param ?21 0
-- @param ?22 1
-- @param ?23 0
-- @param ?24 0
-- @param ?25 1
-- @param ?26 0
-- @param ?27 0
-- @param ?28 1
-- @param ?29 0
-- @param ?30 0
-- @param ?31 1
-- @param ?32 0
-- @param ?33 0
-- @param ?34 1
-- @param ?35 0
-- @param ?36 0
-- @param ?37 1
-- @param ?38 0
-- @param ?39 0
-- @param ?40 1
-- @param ?41 0
-- @param ?42 0
-- @param ?43 1
-- @param ?44 0
-- @param ?45 0
-- @param ?46 1
-- @param ?47 0
-- @param ?48 0
-- @param ?49 1
-- @param ?50 0
-- @param ?51 0
-- @param ?52 1
-- @param ?53 0
-- @param ?54 0
-- @param ?55 1
-- @param ?56 0
-- @param ?57 0
-- @param ?58 1
-- @param ?59 0
-- @param ?60 0
-- @param ?61 1
-- @param ?62 0
-- @param ?63 0
-- @param ?64 1000000.0
-- @param ?65 20
-- @param ?66 19
-- @param ?67 18
-- @param ?68 20
-- @param ?69 1000000.0
-- @param ?70 20
-- @param ?71 19
-- @param ?72 18
-- @param ?73 19
-- @param ?74 18
SELECT count(*) AS num_base_experiment_runs, coalesce(sum(CASE WHEN (comp_exp_run_mins.min_latency_ms > base_experiment_runs.min_latency_ms) THEN ?1 ELSE ?2 END), ?3) AS num_latency_improved, coalesce(sum(CASE WHEN (comp_exp_run_mins.min_latency_ms < base_experiment_runs.min_latency_ms) THEN ?4 ELSE ?5 END), ?6) AS num_latency_regressed, coalesce(sum(CASE WHEN (comp_exp_run_mins.min_latency_ms = base_experiment_runs.min_latency_ms) THEN ?7 ELSE ?8 END), ?9) AS num_latency_is_equal, coalesce(sum(CASE WHEN (comp_exp_run_mins.min_total_tokens > base_experiment_runs.min_total_tokens) THEN ?10 ELSE ?11 END), ?12) AS num_total_token_count_improved, coalesce(sum(CASE WHEN (comp_exp_run_mins.min_total_tokens < base_experiment_runs.min_total_tokens) THEN ?13 ELSE ?14 END), ?15) AS num_total_token_count_regressed, coalesce(sum(CASE WHEN (comp_exp_run_mins.min_total_tokens = base_experiment_runs.min_total_tokens) THEN ?16 ELSE ?17 END), ?18) AS num_total_token_count_is_equal, coalesce(sum(CASE WHEN (comp_exp_run_mins.min_prompt_tokens > base_experiment_runs.min_prompt_tokens) THEN ?19 ELSE ?20 END), ?21) AS num_prompt_token_count_improved, coalesce(sum(CASE WHEN (comp_exp_run_mins.min_prompt_tokens < base_experiment_runs.min_prompt_tokens) THEN ?22 ELSE ?23 END), ?24) AS num_prompt_token_count_regressed, coalesce(sum(CASE WHEN (comp_exp_run_mins.min_prompt_tokens = base_experiment_runs.min_prompt_tokens) THEN ?25 ELSE ?26 END), ?27) AS num_prompt_token_count_is_equal, coalesce(sum(CASE WHEN (comp_exp_run_mins.min_completion_tokens > base_experiment_runs.min_completion_tokens) THEN ?28 ELSE ?29 END), ?30) AS num_completion_token_count_improved, coalesce(sum(CASE WHEN (comp_exp_run_mins.min_completion_tokens < base_experiment_runs.min_completion_tokens) THEN ?31 ELSE ?32 END), ?33) AS num_completion_token_count_regressed, coalesce(sum(CASE WHEN (comp_exp_run_mins.min_completion_tokens = base_experiment_runs.min_completion_tokens) THEN ?34 ELSE ?35 END), ?36) AS num_completion_token_count_is_equal, coalesce(sum(CASE WHEN (comp_exp_run_mins.min_total_cost > base_experiment_runs.min_total_cost) THEN ?37 ELSE ?38 END), ?39) AS num_total_cost_improved, coalesce(sum(CASE WHEN (comp_exp_run_mins.min_total_cost < base_experiment_runs.min_total_cost) THEN ?40 ELSE ?41 END), ?42) AS num_total_cost_regressed, coalesce(sum(CASE WHEN (comp_exp_run_mins.min_total_cost = base_experiment_runs.min_total_cost) THEN ?43 ELSE ?44 END), ?45) AS num_total_cost_is_equal, coalesce(sum(CASE WHEN (comp_exp_run_mins.min_prompt_cost > base_experiment_runs.min_prompt_cost) THEN ?46 ELSE ?47 END), ?48) AS num_prompt_cost_improved, coalesce(sum(CASE WHEN (comp_exp_run_mins.min_prompt_cost < base_experiment_runs.min_prompt_cost) THEN ?49 ELSE ?50 END), ?51) AS num_prompt_cost_regressed, coalesce(sum(CASE WHEN (comp_exp_run_mins.min_prompt_cost = base_experiment_runs.min_prompt_cost) THEN ?52 ELSE ?53 END), ?54) AS num_prompt_cost_is_equal, coalesce(sum(CASE WHEN (comp_exp_run_mins.min_completion_cost > base_experiment_runs.min_completion_cost) THEN ?55 ELSE ?56 END), ?57) AS num_completion_cost_improved, coalesce(sum(CASE WHEN (comp_exp_run_mins.min_completion_cost < base_experiment_runs.min_completion_cost) THEN ?58 ELSE ?59 END), ?60) AS num_completion_cost_regressed, coalesce(sum(CASE WHEN (comp_exp_run_mins.min_completion_cost = base_experiment_runs.min_completion_cost) THEN ?61 ELSE ?62 END), ?63) AS num_completion_cost_is_equal
FROM (SELECT run_metrics.dataset_example_id AS dataset_example_id, min(run_metrics.latency_ms) AS min_latency_ms, min(run_metrics.total_tokens) AS min_total_tokens, min(run_metrics.prompt_tokens) AS min_prompt_tokens, min(run_metrics.completion_tokens) AS min_completion_tokens, min(run_metrics.total_cost) AS min_total_cost, min(run_metrics.prompt_cost) AS min_prompt_cost, min(run_metrics.completion_cost) AS min_completion_cost
FROM (SELECT experiment_runs.id AS run_id, experiment_runs.experiment_id AS experiment_id, experiment_runs.dataset_example_id AS dataset_example_id, (((unixepoch(experiment_runs.end_time) - unixepoch(experiment_runs.start_time)) * 1000000 + (CAST(substr(experiment_runs.end_time, 21, 6) AS INTEGER) - CAST(substr(experiment_runs.start_time, 21, 6) AS INTEGER))) * 1000) / ?64 AS latency_ms, sum(span_costs.total_tokens) AS total_tokens, sum(span_costs.prompt_tokens) AS prompt_tokens, sum(span_costs.completion_tokens) AS completion_tokens, sum(span_costs.total_cost) AS total_cost, sum(span_costs.prompt_cost) AS prompt_cost, sum(span_costs.completion_cost) AS completion_cost
FROM experiment_runs LEFT OUTER JOIN traces ON experiment_runs.trace_id = traces.trace_id LEFT OUTER JOIN span_costs ON traces.id = span_costs.trace_rowid
WHERE experiment_runs.experiment_id IN (?65, ?66, ?67) GROUP BY experiment_runs.id) AS run_metrics
WHERE run_metrics.experiment_id = ?68 GROUP BY run_metrics.dataset_example_id) AS base_experiment_runs LEFT OUTER JOIN (SELECT run_metrics.dataset_example_id AS dataset_example_id, min(run_metrics.latency_ms) AS min_latency_ms, min(run_metrics.total_tokens) AS min_total_tokens, min(run_metrics.prompt_tokens) AS min_prompt_tokens, min(run_metrics.completion_tokens) AS min_completion_tokens, min(run_metrics.total_cost) AS min_total_cost, min(run_metrics.prompt_cost) AS min_prompt_cost, min(run_metrics.completion_cost) AS min_completion_cost
FROM (SELECT experiment_runs.id AS run_id, experiment_runs.experiment_id AS experiment_id, experiment_runs.dataset_example_id AS dataset_example_id, (((unixepoch(experiment_runs.end_time) - unixepoch(experiment_runs.start_time)) * 1000000 + (CAST(substr(experiment_runs.end_time, 21, 6) AS INTEGER) - CAST(substr(experiment_runs.start_time, 21, 6) AS INTEGER))) * 1000) / ?69 AS latency_ms, sum(span_costs.total_tokens) AS total_tokens, sum(span_costs.prompt_tokens) AS prompt_tokens, sum(span_costs.completion_tokens) AS completion_tokens, sum(span_costs.total_cost) AS total_cost, sum(span_costs.prompt_cost) AS prompt_cost, sum(span_costs.completion_cost) AS completion_cost
FROM experiment_runs LEFT OUTER JOIN traces ON experiment_runs.trace_id = traces.trace_id LEFT OUTER JOIN span_costs ON traces.id = span_costs.trace_rowid
WHERE experiment_runs.experiment_id IN (?70, ?71, ?72) GROUP BY experiment_runs.id) AS run_metrics
WHERE run_metrics.experiment_id IN (?73, ?74) GROUP BY run_metrics.dataset_example_id) AS comp_exp_run_mins ON base_experiment_runs.dataset_example_id = comp_exp_run_mins.dataset_example_id;

-- @id phoenix.datasets.experiment_count
-- @src src/phoenix/server/api/types/Dataset.py:375
-- @style SQLAlchemy 2.0 async (aiosqlite over sqlean) compiled by the sqlite dialect; ? positional, IN lists expanded; captured at the DBAPI cursor
-- @tags hot-small
-- @note Datasets table: experiment count per dataset (no index on is_ephemeral; dataset_id index).
-- @param ?1 1
SELECT count(experiments.id) AS count_1
FROM experiments
WHERE experiments.dataset_id = ?1 AND experiments.is_ephemeral IS 0;

-- @id phoenix.traces.by_trace_ids
-- @src src/phoenix/server/api/dataloaders/trace_by_trace_ids.py:20
-- @style SQLAlchemy 2.0 async (aiosqlite over sqlean) compiled by the sqlite dialect; ? positional, IN lists expanded; captured at the DBAPI cursor
-- @tags hot-small
-- @note Experiment run rows link to their traces by the 32-hex trace_id (unique index).
-- @param ?1 '6f7d1c2db71b186beb5f0139aeb55c9d'
-- @param ?2 '9839a0da0e3f215236233046b3e3d05e'
-- @param ?3 'c0f6258765632a3980e75f53b912441f'
-- @param ?4 '0db495de3d06e2e2ae11af76c50bc44e'
-- @param ?5 '36711a8b942aebc9f8d5de83ca3a380f'
-- @param ?6 '5f2d9f38eb4ef4b0439a0d90cf68abd0'
-- @param ?7 'abec0f8fc2f2ad5970c45db3db622bff'
-- @param ?8 'd4a8943c1a16b640bb888cc0e0909fc0'
-- @param ?9 'fd6518e9713abf27064cbbcde5bf1381'
-- @param ?10 '4a23894048de77d033770bf0f1b893b0'
-- @param ?11 '72e00deda00280b77e3b3afdf6e70771'
-- @param ?12 '9b9c929af726899ec8ff6a0afc157b32'
-- @param ?13 'e85b02f1ceca4247f629ba2d080efb61'
-- @param ?14 '1117879e25ee4b2e40ede93a0d3d6f22'
-- @param ?15 '39d40c4b7d1254158bb21847126be2e3'
-- @param ?16 '86927ca254b60cbeb8dc686a1e656312'
-- @param ?17 'af4f014fabda15a503a097772393d6d3'
-- @param ?18 'd80b85fc02fe1e8c4e64c68428c24a94'
-- @param ?19 '24c9f653daa1d7357b8f16a734bbcac3'
-- @param ?20 '4d867b0031c5e01cc65345b439ea3e84'
-- @param ?21 '7642ffad88e9e903111774c13f18b245'
-- @param ?22 'c3017004608da1ac3e41c4e44b123274'
-- @param ?23 'ebbdf4b1b7b1aa938905f3f15040a635'
-- @param ?24 '147a795e0ed5b37ad3ca22fe556f19f6'
-- @param ?25 '6138e9b5e6796c2300f4732161689a25'
-- @param ?26 '89f56e623d9d750a4bb8a22e66970de6'
-- @param ?27 'b2b1f30f94c17df1967cd13b6bc581a7'
-- @param ?28 'ff7063666c65369ac3a7215e77bf01d6'
-- @param ?29 '282ce813c3893f810e6b506b7ced7597'
-- @param ?30 '50e96cc01aad4868592f7f78821be958'
-- @param ?31 '9da7dd17f25101118659cf9b8e156987'
-- @param ?32 'c66461c4497509f8d11dfea89343dd48'
-- @param ?33 'ef20e671a09912df1be22db598725109'
-- @param ?34 '3bdf56c8783ccb88490c7dd8a46bd138'
-- @param ?35 '649bdb75cf60d46f93d0ace5a99a44f9'
-- @param ?36 '8d5860222684dd56de94dbf2aec8b8ba'
-- @param ?37 'da16d079fe2895ff0bbf2c15bac238e9'
-- @param ?38 '02d35526554c9ee656835b22bff0acaa'
-- @param ?39 '2b8fd9d3ac70a7cda1478a2fc51f206b'
-- @param ?40 '784e4a2a84146076ce71da52d118a09a'
-- @param ?41 'a10aced7db38695d1936095fd647145b'
-- @param ?42 'c9c75384325c724463fa386cdb75881c'
-- @param ?43 '1685c3db0a002aed9124888fe76f084b'
-- @param ?44 '3f424888612433d4dbe8b79cec9d7c0c'
-- @param ?45 '67fecd35b8483cbb26ace6a9f1cbefcd'
-- @param ?46 'b4bd3d8c8febf56453d736ccfdc56ffc'
-- @param ?47 'dd79c239e70ffe4b9e9b65d902f3e3bd'
-- @param ?48 '063646e63e340732e95f94e60822577e'
-- @param ?49 '52f4b73d15d7bfdb1689e509141bd7ad'
-- @param ?50 '7bb13bea6cfbc8c2614e1416194a4b6e'
-- @param ?51 'a46dc097c41fd1a9ac1243231e78bf2f'
-- @param ?52 'f12c30ee9bc38a52d93c93462a723f5e'
-- @param ?53 '19e8b59bf2e793392400c2532fa0b31f'
-- @param ?54 '42a53a484a0b9c206ec4f16034cf26e0'
-- @param ?55 '8f63aa9f21af54c99bef418340c8a70f'
-- @param ?56 'b8202f4c78d35db0e6b3709045f71ad0'
-- @param ?57 'e0dcb3f9cff7669731779f9d4b258e91'
-- @param ?58 '2d9b2450a79b1f405ea1efc0571f0ec0'
-- @param ?59 '5657a8fdfebf2827a9661ecd5c4d8281'
-- @param ?60 '7f142daa55e3310ef42a4dda617bf642'
-- @param ?61 'cbd29e012d86e9b721549dfd6d757671'
-- @param ?62 'f48f22ae84aaf29e6c18cd0a72a3ea32'
-- @param ?63 '1d4ba75bdbcefb85b6dcfc1777d25df3'
-- @param ?64 '6a0a17b2b372b42ee4074c3a83cbde22'
-- @param ?65 '92c69c5f0a96bd152ecb7b4788fa51e3'
-- @param ?66 'bb83210c61bac5fc798faa548e28c5a4'
-- @param ?67 '08419163395e7ea5a6b9fa779a2245d3'
-- @param ?68 '30fe16109082878cf17e29849f50b994'
-- @param ?69 '59ba9abde7a690733c425891a47f2d55'
-- @param ?70 'a6790b14bf4a491c696ca8b4b078ad84'
-- @param ?71 'cf358fc1166e5203b430d7c1b5a72145'
-- @param ?72 'f7f2146e6d925aeafef506cebad59506'
-- @param ?73 '44b084c5453613932c1f56f1c6cf1535'
-- @param ?74 '6d6d09729c5a1c7a76e385fecbfd88f6'
-- @param ?75 '96298e1ff37e2561c1a7b50bd12bfcb7'
-- @param ?76 'e2e7fe76cb21de0aeed2052edd257ce6'
-- @param ?77 '0ba483232245e6f13996343be253f0a7'
-- @param ?78 '346107d07969efd8845a6348e7826468'
-- @param ?79 '811f7827510da881b184b36bf37be497'
-- @param ?80 'a9dbfcd4a831b168fc48e278f8aa5858'
-- @param ?81 'd2988181ff55ba4f470d1185fdd8cc19'
-- @param ?82 '1f56f1d8d6f972f8743761a809d24c48'
-- @param ?83 '481376852e1d7bdfbefb90b50f00c009'
-- @param ?84 '70cffb32854184c609bfbfc2142f33ca'
-- @param ?85 'bd8e6b895ce53d6f36ea0fe52028b3f9'
-- @param ?86 'e64af036b409465681ae3ef2255727ba'
-- @param ?87 '0f0774e30b2d4f3dcc726dff2a859b7b'
-- @param ?88 '5bc5e53ae2d107e6f99cbe22367f1baa'
-- @param ?89 '848269e739f510cd4460ed2f3bad8f6b'
-- @param ?90 'ad3eee94911919b48f251c3c40dc032c'
-- @param ?91 'f9fd5eeb68bcd25dbc4f6c5f4cd5835b'
-- @param ?92 '22b9e398bfe0db4407139b6c5203f71c'
-- @param ?93 '4b7668451704e42b51d7ca7957326add'
-- @param ?94 '9834d89ceea89cd47f021a9c632beb0c'
-- @param ?95 'c0f15d4945cca5bbc9c649a9685a5ecd'
-- @param ?96 'e9ade1f69cf0aea2148a78b66d88d28e'
-- @param ?97 '366c524d7494674b41b4c8d9798252bd'
-- @param ?98 '5f28d6facbb870328c78f7e67eb0c67e'
-- @param ?99 '87e55ba722dc7919d73d26f383df3a3f'
-- @param ?100 'd4a3cbfefa8031c2046777168fd8ba6e'
-- @param ?101 'fd6050ab51a43aa94f2ba62395072e2f'
-- @param ?102 '261cd558a8c8439099efd5309a35a1f0'
-- @param ?103 '72db45af806bfc39c71a2553a62f221f'
-- @param ?104 '9b97ca5cd790052011de5460ab5d95e0'
-- @param ?105 'c4544f092eb40e075ca2836db08c09a1'
-- @param ?106 '1112bf600657c6b089ccd390bc8589d0'
-- @param ?107 '39cf440d5d7bcf97d491029dc1b3fd91'
-- @param ?108 '628bc8bab49fd87e1f5531aac6e27152'
-- @param ?109 'af4a39118c4391274c7f81cdd2dbf181'
-- @param ?110 'd806bdbee3679a0e9743b0dad80a6542'
-- @param ?111 '00c3426b3a8ba2f5e207dfe7dd38d903'
-- @param ?112 '4d81b2c2122f5b9e0f32300ae9325932'
-- @param ?113 '763e376f6953648559f65f17ee60ccf3'
-- @param ?114 '9efabc1cc0776d6ca4ba8e24f38f40b4'
-- @param ?115 'ebb92c73981b2615d1e4de47ff88c0e3'
-- @param ?116 '1475b120ef3f2efc1ca90d5404b734a4'
-- @param ?117 '3d3235cd466337e3676d3c6109e5a865'
-- @param ?118 '89f0a6241e06f08c94978c8415df2894'
-- @param ?119 'b2ad2ad1752af973df5bbb911b0d9c55'
-- @param ?120 'db69af7ecc4f025a2a1fea9e203c1016'
-- @param ?121 '28281fd5a3f2bb03574a3ac12c359045'
-- @param ?122 '50e4a482fb16c3eaa20e69ce31640406'
-- @param ?123 '79a1292f523accd1ecd298db369277c7'
-- @param ?124 'c65f998629de857a19fce8fe428bf7f6'
-- @param ?125 'ef1c1e3381028e6164c1180b47ba6bb7'
-- @param ?126 '17d8a2e0d8269748af8547184ce8df78'
-- @param ?127 '64971337afca4ff1dcaf973b58e25fa7'
-- @param ?128 '8d5397e406ee58d82773c6485e10d368'
-- @param ?129 'b6101c915e1261bf7237f555633f4729'
-- @param ?130 '02ce8ce835b61a689f6245786f38c758'
-- @param ?131 '2b8b11958cda234fea26748574673b19'
-- @param ?132 '54479642e3fe2c3634eaa3927995aeda'
-- @param ?133 'a1060699bba1e4df6214f3b5858f2f09'
-- @param ?134 'c9c28b4612c5edc6acd922c28abda2ca'
-- @param ?135 'f27f0ff369e9f6adf79d51cf8fec168b'
-- @param ?136 '3f3d804a418daf5624c7a1f29be596ba'
-- @param ?137 '67fa04f798b1b83d6f8bd0ffa1140a7b'
-- @param ?138 '90b689a4efd5c124ba50000ca6427e3c'
-- @param ?139 'dd74f9fbc77979cde77a502fb23bfe6b'
-- @param ?140 '06317ea81e9d82b4323e7f3cb76a722c'
-- @param ?141 '2eee035575c18b9b7d02ae49bc98e5ed'
-- @param ?142 '7bac73ac4d654444aa2cfe6cc892661c'
-- @param ?143 'a468f859a4894d2bf4f12d79cdc0d9dd'
-- @param ?144 'cd257d06fbad56123fb55c86d2ef4d9e'
-- @param ?145 '19e3ed5dd3510ebb6cdfaca9dee8cdcd'
-- @param ?146 '42a0720a2a7517a2b7a3dbb6e417418e'
-- @param ?147 '6b5cf6b78199208902680ac3e945b54f'
-- @param ?148 'b81b670e593cd9322f925ae6f53f357e'
-- @param ?149 'e0d7ebbbb060e2197a5689f3fa6da93f'
-- @param ?150 '099470680784eb00c51ab900ff9c1d00'
SELECT traces.project_rowid, traces.trace_id, traces.project_session_rowid, traces.start_time, traces.end_time, traces.id
FROM traces
WHERE traces.trace_id IN (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15, ?16, ?17, ?18, ?19, ?20, ?21, ?22, ?23, ?24, ?25, ?26, ?27, ?28, ?29, ?30, ?31, ?32, ?33, ?34, ?35, ?36, ?37, ?38, ?39, ?40, ?41, ?42, ?43, ?44, ?45, ?46, ?47, ?48, ?49, ?50, ?51, ?52, ?53, ?54, ?55, ?56, ?57, ?58, ?59, ?60, ?61, ?62, ?63, ?64, ?65, ?66, ?67, ?68, ?69, ?70, ?71, ?72, ?73, ?74, ?75, ?76, ?77, ?78, ?79, ?80, ?81, ?82, ?83, ?84, ?85, ?86, ?87, ?88, ?89, ?90, ?91, ?92, ?93, ?94, ?95, ?96, ?97, ?98, ?99, ?100, ?101, ?102, ?103, ?104, ?105, ?106, ?107, ?108, ?109, ?110, ?111, ?112, ?113, ?114, ?115, ?116, ?117, ?118, ?119, ?120, ?121, ?122, ?123, ?124, ?125, ?126, ?127, ?128, ?129, ?130, ?131, ?132, ?133, ?134, ?135, ?136, ?137, ?138, ?139, ?140, ?141, ?142, ?143, ?144, ?145, ?146, ?147, ?148, ?149, ?150);

-- @id phoenix.trace.num_spans
-- @src src/phoenix/server/api/dataloaders/num_spans_per_trace.py:16
-- @style SQLAlchemy 2.0 async (aiosqlite over sqlean) compiled by the sqlite dialect; ? positional, IN lists expanded; captured at the DBAPI cursor
-- @tags hot-small
-- @note Span count for one trace (trace details header).
-- @param ?1 18170
SELECT traces.id, count(*) AS count_1
FROM traces JOIN spans ON traces.id = spans.trace_rowid
WHERE traces.id IN (?1) GROUP BY traces.id;
