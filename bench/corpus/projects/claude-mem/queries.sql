-- claude-mem (thedotmack/claude-mem @ 8e91e3a, Apache-2.0). bun:sqlite with `?` positional placeholders; most WHERE
-- clauses are assembled at runtime (buildFilterClause, projectScopeSql, newestIdsPerProjectKeySql), so each query
-- below is one representative instantiation (tagged dynamic). Placeholders are normalised to ?N in argument order.

-- @id claude-mem.search.observations_fts_relevance
-- @src src/services/sqlite/SessionSearch.ts:741-791
-- @style ? positional; filter clause from buildFilterClause (SessionSearch.ts:300) + projectScopeSql (project-read-keys.ts:18)
-- @tags hotpath,dynamic
-- @note The memory search tool's main path: FTS5 MATCH of AND-joined quoted tokens joined back to the content table, project scope matching project OR merged_into_project case-insensitively, bm25 rank order, paged.
-- @param ?1 '"retry" AND "limit"'
-- @param ?2 'claude-mem'
-- @param ?3 'claude-mem'
-- @param ?4 20
-- @param ?5 0
SELECT o.*, o.discovery_tokens
FROM observations o
JOIN observations_fts ON observations_fts.rowid = o.id
WHERE observations_fts MATCH ?1
AND (o.project COLLATE NOCASE IN (?2) OR o.merged_into_project COLLATE NOCASE IN (?3))
ORDER BY observations_fts.rank ASC
LIMIT ?4 OFFSET ?5;

-- @id claude-mem.search.observations_fts_filtered
-- @src src/services/sqlite/SessionSearch.ts:741-791
-- @style ? positional; buildFilterClause with project, platformSource, type[], dateRange and concepts filters (SessionSearch.ts:300-399), orderBy date_desc
-- @tags hotpath,dynamic
-- @note Every filter at once: a correlated scalar subquery for the session's platform source, type IN list, epoch range and a json_each EXISTS over a CASE-normalised concepts array, on top of the FTS MATCH.
-- @param ?1 '"session" AND "timeout"'
-- @param ?2 'claude-mem'
-- @param ?3 'claude-mem'
-- @param ?4 'claude'
-- @param ?5 'bugfix'
-- @param ?6 'discovery'
-- @param ?7 'decision'
-- @param ?8 1769904000000
-- @param ?9 1782863999999
-- @param ?10 'gotcha'
-- @param ?11 'problem-solution'
-- @param ?12 20
-- @param ?13 0
SELECT o.*, o.discovery_tokens
FROM observations o
JOIN observations_fts ON observations_fts.rowid = o.id
WHERE observations_fts MATCH ?1
AND (o.project COLLATE NOCASE IN (?2) OR o.merged_into_project COLLATE NOCASE IN (?3))
AND COALESCE(NULLIF((SELECT s2.platform_source FROM sdk_sessions s2 WHERE s2.memory_session_id = o.memory_session_id), ''), 'claude') = ?4
AND o.type IN (?5,?6,?7)
AND o.created_at_epoch >= ?8
AND o.created_at_epoch <= ?9
AND (EXISTS (SELECT 1 FROM json_each(CASE WHEN json_valid(o.concepts) THEN CASE
        WHEN json_type(o.concepts) = 'array' THEN o.concepts
        WHEN json_type(o.concepts) = 'text' THEN json_array(json_extract(o.concepts, '$'))
        ELSE json_array(o.concepts) END ELSE json_array(o.concepts) END) WHERE type = 'text' AND value = ?10)
  OR EXISTS (SELECT 1 FROM json_each(CASE WHEN json_valid(o.concepts) THEN CASE
        WHEN json_type(o.concepts) = 'array' THEN o.concepts
        WHEN json_type(o.concepts) = 'text' THEN json_array(json_extract(o.concepts, '$'))
        ELSE json_array(o.concepts) END ELSE json_array(o.concepts) END) WHERE type = 'text' AND value = ?11))
ORDER BY o.created_at_epoch DESC, o.id DESC
LIMIT ?12 OFFSET ?13;

-- @id claude-mem.search.observations_fts_any_term
-- @src src/services/sqlite/SessionSearch.ts:895-913
-- @style ? positional; the AND query's SQL re-run with an OR-joined MATCH built by buildFTSAnyTermQuery (SessionSearch.ts:506)
-- @tags hotpath,dynamic
-- @note Natural-language question widened to any term: an FTS5 OR query ranked by bm25 across every row holding any word, then project-scoped and top-N.
-- @param ?1 '"when" OR "did" OR "change" OR "retry" OR "limit" OR "hooks"'
-- @param ?2 'claude-mem'
-- @param ?3 'claude-mem'
-- @param ?4 20
-- @param ?5 0
SELECT o.*, o.discovery_tokens
FROM observations o
JOIN observations_fts ON observations_fts.rowid = o.id
WHERE observations_fts MATCH ?1
AND (o.project COLLATE NOCASE IN (?2) OR o.merged_into_project COLLATE NOCASE IN (?3))
ORDER BY observations_fts.rank ASC
LIMIT ?4 OFFSET ?5;

-- @id claude-mem.search.observations_substring
-- @src src/services/sqlite/SessionSearch.ts:686-709
-- @style ? positional; buildSubstringClause (SessionSearch.ts:443): one OR group of six LIKE ... ESCAPE per term, ANDed
-- @tags hotpath,dynamic
-- @note Fallback when FTS cannot match (CJK runs, partial words): two terms x six columns of LIKE '%..%' ESCAPE over the project's rows, newest first.
-- @param ?1 '%retry%'
-- @param ?2 '%retry%'
-- @param ?3 '%retry%'
-- @param ?4 '%retry%'
-- @param ?5 '%retry%'
-- @param ?6 '%retry%'
-- @param ?7 '%Searc%'
-- @param ?8 '%Searc%'
-- @param ?9 '%Searc%'
-- @param ?10 '%Searc%'
-- @param ?11 '%Searc%'
-- @param ?12 '%Searc%'
-- @param ?13 'claude-mem'
-- @param ?14 'claude-mem'
-- @param ?15 20
-- @param ?16 0
SELECT o.*, o.discovery_tokens
FROM observations o
WHERE ((o.title LIKE ?1 ESCAPE '\' OR o.subtitle LIKE ?2 ESCAPE '\' OR o.narrative LIKE ?3 ESCAPE '\' OR o.text LIKE ?4 ESCAPE '\' OR o.facts LIKE ?5 ESCAPE '\' OR o.concepts LIKE ?6 ESCAPE '\') AND (o.title LIKE ?7 ESCAPE '\' OR o.subtitle LIKE ?8 ESCAPE '\' OR o.narrative LIKE ?9 ESCAPE '\' OR o.text LIKE ?10 ESCAPE '\' OR o.facts LIKE ?11 ESCAPE '\' OR o.concepts LIKE ?12 ESCAPE '\'))
AND (o.project COLLATE NOCASE IN (?13) OR o.merged_into_project COLLATE NOCASE IN (?14))
ORDER BY o.created_at_epoch DESC
LIMIT ?15 OFFSET ?16;

-- @id claude-mem.search.sessions_fts
-- @src src/services/sqlite/SessionSearch.ts:812-866
-- @style ? positional; buildFilterClause on alias s (type filter removed), relevance order
-- @tags hotpath,dynamic
-- @note Session-summary search: FTS5 over six summary columns joined to session_summaries, project/merged scope, platform scalar subquery, bm25 top-N.
-- @param ?1 '"hook" AND "timeout"'
-- @param ?2 'claude-mem'
-- @param ?3 'claude-mem'
-- @param ?4 'claude'
-- @param ?5 10
-- @param ?6 0
SELECT s.*, s.discovery_tokens
FROM session_summaries s
JOIN session_summaries_fts ON session_summaries_fts.rowid = s.id
WHERE session_summaries_fts MATCH ?1
AND (s.project COLLATE NOCASE IN (?2) OR s.merged_into_project COLLATE NOCASE IN (?3)) AND COALESCE(NULLIF((SELECT s2.platform_source FROM sdk_sessions s2 WHERE s2.memory_session_id = s.memory_session_id), ''), 'claude') = ?4
ORDER BY session_summaries_fts.rank ASC
LIMIT ?5 OFFSET ?6;

-- @id claude-mem.search.find_by_concept
-- @src src/services/sqlite/SessionSearch.ts:915-933
-- @style ? positional; buildFilterClause with concepts + project, orderBy date_desc
-- @tags hotpath,dynamic
-- @note Concept browse: json_each over a CASE-normalised JSON column inside EXISTS, project OR merged scope, newest-first top-N; no FTS, so it walks the project's rows.
-- @param ?1 'claude-mem'
-- @param ?2 'claude-mem'
-- @param ?3 'gotcha'
-- @param ?4 50
-- @param ?5 0
SELECT o.*, o.discovery_tokens
FROM observations o
WHERE (o.project COLLATE NOCASE IN (?1) OR o.merged_into_project COLLATE NOCASE IN (?2)) AND (EXISTS (SELECT 1 FROM json_each(CASE WHEN json_valid(o.concepts) THEN CASE
        WHEN json_type(o.concepts) = 'array' THEN o.concepts
        WHEN json_type(o.concepts) = 'text' THEN json_array(json_extract(o.concepts, '$'))
        ELSE json_array(o.concepts) END ELSE json_array(o.concepts) END) WHERE type = 'text' AND value = ?3))
ORDER BY o.created_at_epoch DESC, o.id DESC
LIMIT ?4 OFFSET ?5;

-- @id claude-mem.search.find_by_file_observations
-- @src src/services/sqlite/SessionSearch.ts:1014-1055
-- @style ? positional; jsonArrayLikeClause (SessionSearch.ts:590) over files_read/files_modified, one pattern (file, not folder)
-- @tags hotpath,dynamic
-- @note File history: two json_each EXISTS probes with LIKE ... ESCAPE over JSON path arrays, guarded by json_valid/json_type CASE, newest first.
-- @param ?1 'claude-mem'
-- @param ?2 'claude-mem'
-- @param ?3 '%src/services/SessionSearch.ts%'
-- @param ?4 '%src/services/SessionSearch.ts%'
-- @param ?5 20
-- @param ?6 0
SELECT o.*, o.discovery_tokens
FROM observations o
WHERE (o.project COLLATE NOCASE IN (?1) OR o.merged_into_project COLLATE NOCASE IN (?2)) AND (EXISTS (SELECT 1 FROM json_each(CASE WHEN json_valid(o.files_read) THEN CASE WHEN json_type(o.files_read) = 'array' THEN o.files_read ELSE '[]' END ELSE '[]' END) WHERE type = 'text' AND value LIKE ?3 ESCAPE '\') OR EXISTS (SELECT 1 FROM json_each(CASE WHEN json_valid(o.files_modified) THEN CASE WHEN json_type(o.files_modified) = 'array' THEN o.files_modified ELSE '[]' END ELSE '[]' END) WHERE type = 'text' AND value LIKE ?4 ESCAPE '\'))
ORDER BY o.created_at_epoch DESC, o.id DESC
LIMIT ?5 OFFSET ?6;

-- @id claude-mem.search.find_by_folder_sessions
-- @src src/services/sqlite/SessionSearch.ts:1057-1112
-- @style ? positional; folder mode: filePathPatterns (SessionSearch.ts:563) expands an absolute folder into 8 LIKE patterns, bound once per column; no SQL LIMIT (paged in JS)
-- @tags dynamic
-- @note Folder lookup on summaries: eight ORed LIKE patterns (absolute, backslashed and every trailing-suffix form) inside two json_each EXISTS, over a date-bounded project slice.
-- @param ?1 'claude-mem'
-- @param ?2 'claude-mem'
-- @param ?3 1772323200000
-- @param ?4 1774915199999
-- @param ?5 '%/Users/dev/code/project/src/services%'
-- @param ?6 '%\\Users\\dev\\code\\project\\src\\services%'
-- @param ?7 'Users/dev/code/project/src/services/%'
-- @param ?8 'dev/code/project/src/services/%'
-- @param ?9 'code/project/src/services/%'
-- @param ?10 'project/src/services/%'
-- @param ?11 'src/services/%'
-- @param ?12 'services/%'
-- @param ?13 '%/Users/dev/code/project/src/services%'
-- @param ?14 '%\\Users\\dev\\code\\project\\src\\services%'
-- @param ?15 'Users/dev/code/project/src/services/%'
-- @param ?16 'dev/code/project/src/services/%'
-- @param ?17 'code/project/src/services/%'
-- @param ?18 'project/src/services/%'
-- @param ?19 'src/services/%'
-- @param ?20 'services/%'
SELECT s.*, s.discovery_tokens
FROM session_summaries s
WHERE (s.project COLLATE NOCASE IN (?1) OR s.merged_into_project COLLATE NOCASE IN (?2)) AND s.created_at_epoch >= ?3 AND s.created_at_epoch <= ?4 AND (EXISTS (SELECT 1 FROM json_each(CASE WHEN json_valid(s.files_read) THEN CASE WHEN json_type(s.files_read) = 'array' THEN s.files_read ELSE '[]' END ELSE '[]' END) WHERE type = 'text' AND value LIKE ?5 ESCAPE '\' OR type = 'text' AND value LIKE ?6 ESCAPE '\' OR type = 'text' AND value LIKE ?7 ESCAPE '\' OR type = 'text' AND value LIKE ?8 ESCAPE '\' OR type = 'text' AND value LIKE ?9 ESCAPE '\' OR type = 'text' AND value LIKE ?10 ESCAPE '\' OR type = 'text' AND value LIKE ?11 ESCAPE '\' OR type = 'text' AND value LIKE ?12 ESCAPE '\') OR EXISTS (SELECT 1 FROM json_each(CASE WHEN json_valid(s.files_edited) THEN CASE WHEN json_type(s.files_edited) = 'array' THEN s.files_edited ELSE '[]' END ELSE '[]' END) WHERE type = 'text' AND value LIKE ?13 ESCAPE '\' OR type = 'text' AND value LIKE ?14 ESCAPE '\' OR type = 'text' AND value LIKE ?15 ESCAPE '\' OR type = 'text' AND value LIKE ?16 ESCAPE '\' OR type = 'text' AND value LIKE ?17 ESCAPE '\' OR type = 'text' AND value LIKE ?18 ESCAPE '\' OR type = 'text' AND value LIKE ?19 ESCAPE '\' OR type = 'text' AND value LIKE ?20 ESCAPE '\'))
ORDER BY s.created_at_epoch DESC;

-- @id claude-mem.search.find_by_type
-- @src src/services/sqlite/SessionSearch.ts:1116-1137
-- @style ? positional; buildFilterClause with type[] + project + dateRange start, orderBy date_desc
-- @tags hotpath,dynamic
-- @note Type browse ("show me recent decisions"): type IN list plus project OR merged scope, ordered top-N; the planner picks between the type index and the NOCASE recency indexes.
-- @param ?1 'claude-mem'
-- @param ?2 'claude-mem'
-- @param ?3 'decision'
-- @param ?4 'bugfix'
-- @param ?5 1772323200000
-- @param ?6 50
-- @param ?7 0
SELECT o.*, o.discovery_tokens
FROM observations o
WHERE (o.project COLLATE NOCASE IN (?1) OR o.merged_into_project COLLATE NOCASE IN (?2)) AND o.type IN (?3,?4) AND o.created_at_epoch >= ?5
ORDER BY o.created_at_epoch DESC
LIMIT ?6 OFFSET ?7;

-- @id claude-mem.search.user_prompts_like
-- @src src/services/sqlite/SessionSearch.ts:1140-1222
-- @style ? positional; baseConditions (project, platform) + LIKE ... ESCAPE on prompt_text
-- @tags hotpath,dynamic
-- @note Prompt search is always substring: join to sdk_sessions for project/platform, COALESCE(NULLIF()) platform default, LIKE '%..%' ESCAPE, newest first.
-- @param ?1 'claude-mem'
-- @param ?2 'claude'
-- @param ?3 '%fix the session timeout%'
-- @param ?4 20
-- @param ?5 0
SELECT
  up.*,
  s.project,
  s.memory_session_id,
  COALESCE(NULLIF(s.platform_source, ''), 'claude') as platform_source
FROM user_prompts up
JOIN sdk_sessions s ON up.session_db_id = s.id
WHERE s.project COLLATE NOCASE IN (?1) AND COALESCE(NULLIF(s.platform_source, ''), 'claude') = ?2 AND up.prompt_text LIKE ?3 ESCAPE '\'
ORDER BY up.created_at_epoch DESC, up.id DESC
LIMIT ?4 OFFSET ?5;

-- @id claude-mem.context.observations_newest_per_key
-- @src src/services/context/ObservationCompiler.ts:111-207
-- @style ? positional; newestIdsPerProjectKeySql (ObservationCompiler.ts:60) unions one top-N per (column, project key); default mode types/concepts, mainAgentOnly, platform 'claude', 50 observations
-- @tags hotpath,dynamic
-- @note SessionStart context injection: a UNION of per-key top-N subqueries (each a LEFT JOIN with an IN list and a json_each EXISTS), re-sorted and limited, then joined back for the full rows.
-- @param ?1 'claude-mem'
-- @param ?2 'claude'
-- @param ?3 'claude'
-- @param ?4 'discovery'
-- @param ?5 'bugfix'
-- @param ?6 'feature'
-- @param ?7 'refactor'
-- @param ?8 'change'
-- @param ?9 'decision'
-- @param ?10 'how-it-works'
-- @param ?11 'gotcha'
-- @param ?12 'pattern'
-- @param ?13 'problem-solution'
-- @param ?14 'trade-off'
-- @param ?15 'why-it-exists'
-- @param ?16 'what-changed'
-- @param ?17 50
-- @param ?18 'claude-mem'
-- @param ?19 'claude'
-- @param ?20 'claude'
-- @param ?21 'discovery'
-- @param ?22 'bugfix'
-- @param ?23 'feature'
-- @param ?24 'refactor'
-- @param ?25 'change'
-- @param ?26 'decision'
-- @param ?27 'how-it-works'
-- @param ?28 'gotcha'
-- @param ?29 'pattern'
-- @param ?30 'problem-solution'
-- @param ?31 'trade-off'
-- @param ?32 'why-it-exists'
-- @param ?33 'what-changed'
-- @param ?34 50
-- @param ?35 50
SELECT
  o.id,
  o.memory_session_id,
  s.content_session_id,
  COALESCE(s.platform_source, 'claude') as platform_source,
  o.type,
  o.title,
  o.subtitle,
  o.narrative,
  o.facts,
  o.concepts,
  o.files_read,
  o.files_modified,
  o.discovery_tokens,
  o.created_at,
  o.created_at_epoch,
  o.project
FROM (
  SELECT id FROM (SELECT * FROM (
    SELECT o.id, o.created_at_epoch
    FROM observations o
    LEFT JOIN sdk_sessions s ON o.memory_session_id = s.memory_session_id
    WHERE o.project COLLATE NOCASE = ?1 AND (?2 IS NULL OR s.platform_source = ?3)
      AND (COALESCE(o.agent_id, '') = '' OR COALESCE(o.agent_type, '') = '')
      AND ( (
        type IN (?4,?5,?6,?7,?8,?9)
        AND EXISTS (
          SELECT 1 FROM json_each(CASE WHEN json_valid(o.concepts) THEN o.concepts ELSE '[]' END)
          WHERE value IN (?10,?11,?12,?13,?14,?15,?16)
        )
      ))
    ORDER BY o.created_at_epoch DESC
    LIMIT ?17) UNION SELECT * FROM (
    SELECT o.id, o.created_at_epoch
    FROM observations o
    LEFT JOIN sdk_sessions s ON o.memory_session_id = s.memory_session_id
    WHERE o.merged_into_project COLLATE NOCASE = ?18 AND (?19 IS NULL OR s.platform_source = ?20)
      AND (COALESCE(o.agent_id, '') = '' OR COALESCE(o.agent_type, '') = '')
      AND ( (
        type IN (?21,?22,?23,?24,?25,?26)
        AND EXISTS (
          SELECT 1 FROM json_each(CASE WHEN json_valid(o.concepts) THEN o.concepts ELSE '[]' END)
          WHERE value IN (?27,?28,?29,?30,?31,?32,?33)
        )
      ))
    ORDER BY o.created_at_epoch DESC
    LIMIT ?34))
  ORDER BY created_at_epoch DESC
  LIMIT ?35) w
JOIN observations o ON o.id = w.id
LEFT JOIN sdk_sessions s ON o.memory_session_id = s.memory_session_id
ORDER BY o.created_at_epoch DESC;

-- @id claude-mem.context.summaries_newest_per_key
-- @src src/services/context/ObservationCompiler.ts:228-279
-- @style ? positional; newestIdsPerProjectKeySql over two project keys (4 UNION arms), sessionCount 10 + SUMMARY_LOOKAHEAD 1
-- @tags hotpath,dynamic
-- @note SessionStart's recent-summaries block: four per-key top-N arms (project and merged_into_project x two keys) unioned, re-limited, joined back with the session's platform.
-- @param ?1 'claude-mem'
-- @param ?2 'claude'
-- @param ?3 'claude'
-- @param ?4 11
-- @param ?5 'claude-mem-wt-fts'
-- @param ?6 'claude'
-- @param ?7 'claude'
-- @param ?8 11
-- @param ?9 'claude-mem'
-- @param ?10 'claude'
-- @param ?11 'claude'
-- @param ?12 11
-- @param ?13 'claude-mem-wt-fts'
-- @param ?14 'claude'
-- @param ?15 'claude'
-- @param ?16 11
-- @param ?17 11
SELECT
  ss.id,
  ss.memory_session_id,
  COALESCE(s.platform_source, 'claude') as platform_source,
  ss.request,
  ss.investigated,
  ss.learned,
  ss.completed,
  ss.next_steps,
  ss.notes,
  ss.created_at,
  ss.created_at_epoch,
  ss.project
FROM (
  SELECT id FROM (SELECT * FROM (
    SELECT ss.id, ss.created_at_epoch
    FROM session_summaries ss
    LEFT JOIN sdk_sessions s ON ss.memory_session_id = s.memory_session_id
    WHERE ss.project COLLATE NOCASE = ?1 AND (?2 IS NULL OR s.platform_source = ?3)
    ORDER BY ss.created_at_epoch DESC
    LIMIT ?4) UNION SELECT * FROM (
    SELECT ss.id, ss.created_at_epoch
    FROM session_summaries ss
    LEFT JOIN sdk_sessions s ON ss.memory_session_id = s.memory_session_id
    WHERE ss.project COLLATE NOCASE = ?5 AND (?6 IS NULL OR s.platform_source = ?7)
    ORDER BY ss.created_at_epoch DESC
    LIMIT ?8) UNION SELECT * FROM (
    SELECT ss.id, ss.created_at_epoch
    FROM session_summaries ss
    LEFT JOIN sdk_sessions s ON ss.memory_session_id = s.memory_session_id
    WHERE ss.merged_into_project COLLATE NOCASE = ?9 AND (?10 IS NULL OR s.platform_source = ?11)
    ORDER BY ss.created_at_epoch DESC
    LIMIT ?12) UNION SELECT * FROM (
    SELECT ss.id, ss.created_at_epoch
    FROM session_summaries ss
    LEFT JOIN sdk_sessions s ON ss.memory_session_id = s.memory_session_id
    WHERE ss.merged_into_project COLLATE NOCASE = ?13 AND (?14 IS NULL OR s.platform_source = ?15)
    ORDER BY ss.created_at_epoch DESC
    LIMIT ?16))
  ORDER BY created_at_epoch DESC
  LIMIT ?17) w
JOIN session_summaries ss ON ss.id = w.id
LEFT JOIN sdk_sessions s ON ss.memory_session_id = s.memory_session_id
ORDER BY ss.created_at_epoch DESC;

-- @id claude-mem.context.count_observations_by_projects
-- @src src/services/context/ObservationCompiler.ts:209-226
-- @style ? positional; IN lists sized to the project keys
-- @tags hotpath,dynamic
-- @note Context header count: COUNT(*) over a LEFT JOIN with a two-index OR (project / merged_into_project NOCASE IN) and an optional-parameter platform predicate.
-- @param ?1 'claude-mem'
-- @param ?2 'claude-mem-wt-fts'
-- @param ?3 'claude-mem'
-- @param ?4 'claude-mem-wt-fts'
-- @param ?5 'claude'
-- @param ?6 'claude'
SELECT COUNT(*) as count
FROM observations o
LEFT JOIN sdk_sessions s ON o.memory_session_id = s.memory_session_id
WHERE (o.project COLLATE NOCASE IN (?1,?2)
   OR o.merged_into_project COLLATE NOCASE IN (?3,?4))
  AND (?5 IS NULL OR s.platform_source = ?6);

-- @id claude-mem.context.project_read_keys
-- @src src/services/sqlite/project-read-keys.ts:51-88
-- @style ? positional; six lookups joined with UNION, the last one binding the requested keys four times
-- @tags hotpath,dynamic
-- @note Every SessionStart render: a six-arm UNION whose last arm compares four correlated COUNT(*) subqueries per merge candidate (whole-merge detection), all on NOCASE covering indexes.
-- @param ?1 'claude-mem'
-- @param ?2 'claude-mem'
-- @param ?3 'claude-mem'
-- @param ?4 'claude-mem'
-- @param ?5 'claude-mem'
-- @param ?6 'claude-mem'
-- @param ?7 'claude-mem'
-- @param ?8 'claude-mem'
-- @param ?9 'claude-mem'
SELECT project AS key FROM sdk_sessions WHERE project COLLATE NOCASE IN (?1) UNION SELECT project FROM observations WHERE project COLLATE NOCASE IN (?2) UNION SELECT merged_into_project FROM observations WHERE merged_into_project COLLATE NOCASE IN (?3) UNION SELECT project FROM session_summaries WHERE project COLLATE NOCASE IN (?4) UNION SELECT merged_into_project FROM session_summaries WHERE merged_into_project COLLATE NOCASE IN (?5) UNION SELECT candidates.key FROM (
        SELECT project AS key FROM observations WHERE merged_into_project COLLATE NOCASE IN (?6)
        UNION
        SELECT project AS key FROM session_summaries WHERE merged_into_project COLLATE NOCASE IN (?7)
      ) candidates
      WHERE (
        (SELECT COUNT(*) FROM observations WHERE project COLLATE NOCASE = candidates.key)
        + (SELECT COUNT(*) FROM session_summaries WHERE project COLLATE NOCASE = candidates.key)
      ) = (
        (SELECT COUNT(*) FROM observations
          WHERE project COLLATE NOCASE = candidates.key AND merged_into_project COLLATE NOCASE IN (?8))
        + (SELECT COUNT(*) FROM session_summaries
          WHERE project COLLATE NOCASE = candidates.key AND merged_into_project COLLATE NOCASE IN (?9))
      );

-- @id claude-mem.store.recent_sessions_with_status
-- @src src/services/sqlite/SessionStore.ts:3089-3119
-- @style ? positional; optional platform clause appended
-- @tags hotpath,dynamic
-- @note Context footer: LEFT JOIN to summaries, GROUP BY session with a CASE over the joined column, top-N inner query re-sorted ascending by the outer query.
-- @param ?1 'claude-mem'
-- @param ?2 'claude'
-- @param ?3 3
SELECT * FROM (
  SELECT
    s.memory_session_id,
    s.status,
    s.started_at,
    s.started_at_epoch,
    s.user_prompt,
    CASE WHEN sum.memory_session_id IS NOT NULL THEN 1 ELSE 0 END as has_summary
  FROM sdk_sessions s
  LEFT JOIN session_summaries sum ON s.memory_session_id = sum.memory_session_id
  WHERE s.project COLLATE NOCASE = ?1 AND s.memory_session_id IS NOT NULL
  AND COALESCE(NULLIF(s.platform_source, ''), 'claude') = ?2
  GROUP BY s.memory_session_id
  ORDER BY s.started_at_epoch DESC
  LIMIT ?3
)
ORDER BY started_at_epoch ASC;

-- @id claude-mem.store.session_catalog
-- @src src/services/sqlite/SessionStore.ts:3018-3056
-- @style ? positional; optional project/platform filters appended, LIMIT limit+1 for hasMore
-- @tags hotpath,dynamic
-- @note Viewer Sessions page: three correlated COUNT(*) subqueries summed per session row (observations, summaries, prompts), filtered and paged newest-first.
-- @param ?1 'observer-sessions'
-- @param ?2 'claude'
-- @param ?3 51
-- @param ?4 0
SELECT
  s.content_session_id,
  s.project,
  COALESCE(s.platform_source, 'claude') as platform_source,
  s.custom_title,
  s.started_at_epoch,
  (
    (SELECT COUNT(*) FROM observations o WHERE o.memory_session_id = s.memory_session_id)
    + (SELECT COUNT(*) FROM session_summaries ss WHERE ss.memory_session_id = s.memory_session_id)
    + (SELECT COUNT(*) FROM user_prompts up WHERE up.session_db_id = s.id)
  ) as item_count
FROM sdk_sessions s
WHERE s.project IS NOT NULL AND s.project != ''
  AND s.project != ?1
 AND COALESCE(s.platform_source, 'claude') = ?2 ORDER BY s.started_at_epoch DESC, s.id DESC LIMIT ?3 OFFSET ?4;

-- @id claude-mem.store.project_catalog
-- @src src/services/sqlite/SessionStore.ts:2962-2977
-- @style ? positional
-- @tags hotpath
-- @note Viewer project picker: GROUP BY an expression (COALESCE platform) and project, MAX epoch, ordered by the aggregate.
-- @param ?1 'observer-sessions'
SELECT
  COALESCE(platform_source, 'claude') as platform_source,
  project,
  MAX(started_at_epoch) as latest_epoch
FROM sdk_sessions
WHERE project IS NOT NULL AND project != ''
  AND project != ?1
GROUP BY COALESCE(platform_source, 'claude'), project
ORDER BY latest_epoch DESC;

-- @id claude-mem.store.all_projects
-- @src src/services/sqlite/SessionStore.ts:2941-2960
-- @style ? positional; platform clause appended when given
-- @tags dynamic
-- @note DISTINCT project list with an expression filter on platform, sorted.
-- @param ?1 'observer-sessions'
-- @param ?2 'claude'
-- @param ?3 'claude'
SELECT DISTINCT project
FROM sdk_sessions
WHERE project IS NOT NULL AND project != ''
  AND project != ?1
 AND COALESCE(platform_source, ?2) = ?3 ORDER BY project ASC;

-- @id claude-mem.store.timeline_boundary_before
-- @src src/services/sqlite/SessionStore.ts:4433-4451
-- @style ? positional; observationScope from buildScope (project+merged, platform)
-- @tags hotpath,dynamic
-- @note Timeline anchor probe: row-value comparison (created_at_epoch, id) <= (?, ?) with project OR merged scope and a LEFT JOIN platform filter, top-N descending.
-- @param ?1 1772629740000
-- @param ?2 30010
-- @param ?3 'claude-mem'
-- @param ?4 'claude-mem'
-- @param ?5 'claude'
-- @param ?6 11
SELECT o.id, o.created_at_epoch
FROM observations o
LEFT JOIN sdk_sessions src ON src.memory_session_id = o.memory_session_id
WHERE (o.created_at_epoch, o.id) <= (?1, ?2) AND (o.project COLLATE NOCASE IN (?3) OR o.merged_into_project COLLATE NOCASE IN (?4)) AND COALESCE(NULLIF(src.platform_source, ''), 'claude') = ?5
ORDER BY o.created_at_epoch DESC
LIMIT ?6;

-- @id claude-mem.store.timeline_observations
-- @src src/services/sqlite/SessionStore.ts:4516-4540
-- @style ? positional; observationScope appended
-- @tags hotpath,dynamic
-- @note Timeline body: epoch range scan with OR project scope and platform filter through a LEFT JOIN, ordered by (epoch, id).
-- @param ?1 1772283600000
-- @param ?2 1773003600000
-- @param ?3 'claude-mem'
-- @param ?4 'claude-mem'
-- @param ?5 'claude'
SELECT o.*
FROM observations o
LEFT JOIN sdk_sessions src ON src.memory_session_id = o.memory_session_id
WHERE o.created_at_epoch >= ?1 AND o.created_at_epoch <= ?2 AND (o.project COLLATE NOCASE IN (?3) OR o.merged_into_project COLLATE NOCASE IN (?4)) AND COALESCE(NULLIF(src.platform_source, ''), 'claude') = ?5
ORDER BY o.created_at_epoch ASC, o.id ASC;

-- @id claude-mem.store.timeline_summaries
-- @src src/services/sqlite/SessionStore.ts:4524-4541
-- @style ? positional; summaryScope appended
-- @tags hotpath,dynamic
-- @note Timeline summaries over the same window.
-- @param ?1 1772283600000
-- @param ?2 1773003600000
-- @param ?3 'claude-mem'
-- @param ?4 'claude-mem'
-- @param ?5 'claude'
SELECT ss.*
FROM session_summaries ss
LEFT JOIN sdk_sessions src ON src.memory_session_id = ss.memory_session_id
WHERE ss.created_at_epoch >= ?1 AND ss.created_at_epoch <= ?2 AND (ss.project COLLATE NOCASE IN (?3) OR ss.merged_into_project COLLATE NOCASE IN (?4)) AND COALESCE(NULLIF(src.platform_source, ''), 'claude') = ?5
ORDER BY ss.created_at_epoch ASC, ss.id ASC;

-- @id claude-mem.store.timeline_prompts
-- @src src/services/sqlite/SessionStore.ts:4532-4542
-- @style ? positional; promptScope appended (project only, no merged)
-- @tags hotpath,dynamic
-- @note Timeline prompts: inner join to sessions, epoch range on the prompt, project and COALESCE(NULLIF()) platform on the session.
-- @param ?1 1772283600000
-- @param ?2 1773003600000
-- @param ?3 'claude-mem'
-- @param ?4 'claude'
SELECT up.*, s.project, s.memory_session_id, COALESCE(NULLIF(s.platform_source, ''), 'claude') as platform_source
FROM user_prompts up
JOIN sdk_sessions s ON up.session_db_id = s.id
WHERE up.created_at_epoch >= ?1 AND up.created_at_epoch <= ?2 AND s.project COLLATE NOCASE IN (?3) AND COALESCE(NULLIF(s.platform_source, ''), 'claude') = ?4
ORDER BY up.created_at_epoch ASC, up.id ASC;

-- @id claude-mem.store.observations_by_ids
-- @src src/services/sqlite/SessionStore.ts:3228-3322
-- @style ? positional; id IN list from the search index plus project/platform/type filters, date_desc with LIMIT
-- @tags hotpath,dynamic
-- @note Hydrating search hits (Chroma ids): 20-element IN list on the rowid, OR project scope, platform via LEFT JOIN, type IN, top-N.
-- @param ?1 101
-- @param ?2 2021
-- @param ?3 4005
-- @param ?4 6011
-- @param ?5 8020
-- @param ?6 10007
-- @param ?7 12013
-- @param ?8 14002
-- @param ?9 16019
-- @param ?10 18004
-- @param ?11 20010
-- @param ?12 22016
-- @param ?13 24003
-- @param ?14 26008
-- @param ?15 28015
-- @param ?16 30001
-- @param ?17 32012
-- @param ?18 34018
-- @param ?19 36006
-- @param ?20 38009
-- @param ?21 'claude-mem'
-- @param ?22 'claude-mem'
-- @param ?23 'claude'
-- @param ?24 'bugfix'
-- @param ?25 'feature'
-- @param ?26 'discovery'
-- @param ?27 'change'
-- @param ?28 10
SELECT o.*
FROM observations o
LEFT JOIN sdk_sessions s ON s.memory_session_id = o.memory_session_id
WHERE o.id IN (?1,?2,?3,?4,?5,?6,?7,?8,?9,?10,?11,?12,?13,?14,?15,?16,?17,?18,?19,?20) AND (o.project COLLATE NOCASE IN (?21) OR o.merged_into_project COLLATE NOCASE IN (?22)) AND COALESCE(NULLIF(s.platform_source, ''), 'claude') = ?23 AND o.type IN (?24,?25,?26,?27)
ORDER BY o.created_at_epoch DESC, o.id DESC
LIMIT ?28;

-- @id claude-mem.observations.by_file_path
-- @src src/services/sqlite/observations/get.ts:8-71
-- @style ? positional; candidate path forms (forward/backslashed) in an IN list, project scope and platform clause appended
-- @tags hotpath,dynamic
-- @note PreToolUse:Read file context: seek observation_files by path IN (...), join observations and sessions, DISTINCT o.*, newest first.
-- @param ?1 'src/services/SessionStore.ts'
-- @param ?2 'src\services\SessionStore.ts'
-- @param ?3 'claude-mem'
-- @param ?4 'claude-mem'
-- @param ?5 'claude'
-- @param ?6 15
SELECT DISTINCT o.*
FROM observation_files f
JOIN observations o ON o.id = f.observation_id
LEFT JOIN sdk_sessions s ON s.memory_session_id = o.memory_session_id
WHERE f.path IN (?1,?2)
AND (o.project COLLATE NOCASE IN (?3) OR o.merged_into_project COLLATE NOCASE IN (?4))
AND COALESCE(NULLIF(s.platform_source, ''), 'claude') = ?5
ORDER BY o.created_at_epoch DESC
LIMIT ?6;

-- @id claude-mem.tool_uses.count_by_tool
-- @src src/services/sqlite/tool-uses.ts:442-479
-- @style ? positional; conditions appended per filter
-- @tags hotpath,dynamic
-- @note Receipt headline: COUNT(DISTINCT tool_use_id) GROUP BY tool_name over a project + date window, ordered by the aggregate.
-- @param ?1 'claude-mem'
-- @param ?2 1769904000000
-- @param ?3 1782863999999
SELECT tool_name, COUNT(DISTINCT tool_use_id) AS uses
FROM tool_uses
WHERE project COLLATE NOCASE = ?1 AND created_at_epoch >= ?2 AND created_at_epoch <= ?3
GROUP BY tool_name
ORDER BY uses DESC, tool_name ASC;

-- @id claude-mem.tool_uses.query_list
-- @src src/services/sqlite/tool-uses.ts:379-439
-- @style ? positional for filters; LIMIT/OFFSET are inlined integers in the app
-- @tags hotpath,dynamic
-- @note Tool-use listing: tool_name IN list, platform COALESCE(NULLIF()) expression, project NOCASE, newest first with inlined LIMIT/OFFSET.
-- @param ?1 'claude-mem'
-- @param ?2 'Edit'
-- @param ?3 'Write'
-- @param ?4 'claude'
SELECT * FROM tool_uses
WHERE project COLLATE NOCASE = ?1 AND tool_name IN (?2,?3) AND COALESCE(NULLIF(platform_source, ''), 'claude') = ?4
ORDER BY created_at_epoch DESC, id DESC
LIMIT 50 OFFSET 0;

-- @id claude-mem.store.insert_observation
-- @src src/services/sqlite/SessionStore.ts:4110-4117
-- @style ? positional, prepared once per batch, run per observation
-- @tags hot-small
-- @note Observation write: 22-column INSERT ... ON CONFLICT(memory_session_id, content_hash) DO NOTHING RETURNING id; fires the FTS5 sync trigger.
-- @param ?1 'mem-2000'
-- @param ?2 'claude-mem'
-- @param ?3 'bugfix'
-- @param ?4 'Fixed retry limit in SessionStore'
-- @param ?5 'The retry limit path now backs off'
-- @param ?6 '["SessionStore owns the retry limit"]'
-- @param ?7 'While investigating the retry limit, found that SessionStore retried forever.'
-- @param ?8 '["gotcha","problem-solution"]'
-- @param ?9 '["src/services/SessionStore.ts"]'
-- @param ?10 '["src/services/SessionStore.ts"]'
-- @param ?11 5
-- @param ?12 812
-- @param ?13 NULL
-- @param ?14 NULL
-- @param ?15 'a1b2c3d4e5f60718'
-- @param ?16 '2026-05-07T08:00:00.000Z'
-- @param ?17 1778140800000
-- @param ?18 'claude-haiku-4-5'
-- @param ?19 NULL
-- @param ?20 'claude-mem|fixed retry limit in sessionstore'
-- @param ?21 '["2026-05-07"]'
-- @param ?22 '2026-05-07'
INSERT INTO observations
(memory_session_id, project, type, title, subtitle, facts, narrative, concepts,
 files_read, files_modified, prompt_number, discovery_tokens, agent_type, agent_id, content_hash, created_at, created_at_epoch,
 generated_by_model, metadata, title_norm_key, reinforcement_dates, last_reinforced)
VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15, ?16, ?17, ?18, ?19, ?20, ?21, ?22)
ON CONFLICT(memory_session_id, content_hash) DO NOTHING
RETURNING id;

-- @id claude-mem.store.insert_summary
-- @src src/services/sqlite/SessionStore.ts:4216-4221
-- @style ? positional
-- @tags hot-small
-- @note Summary write at the end of a turn; fires the summaries FTS5 trigger.
-- @param ?1 'mem-2000'
-- @param ?2 'claude-mem'
-- @param ?3 'Investigate the retry limit'
-- @param ?4 'Read SessionStore.ts'
-- @param ?5 'Retries were unbounded'
-- @param ?6 'Bounded the retries'
-- @param ?7 'Verify on Windows'
-- @param ?8 '["src/services/SessionStore.ts"]'
-- @param ?9 '["src/services/SessionStore.ts"]'
-- @param ?10 NULL
-- @param ?11 5
-- @param ?12 2400
-- @param ?13 '2026-05-07T08:00:00.000Z'
-- @param ?14 1778140800000
INSERT INTO session_summaries
(memory_session_id, project, request, investigated, learned, completed,
 next_steps, files_read, files_edited, notes, prompt_number, discovery_tokens, created_at, created_at_epoch)
VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14);

-- @id claude-mem.store.insert_user_prompt
-- @src src/services/sqlite/SessionStore.ts:3724-3730
-- @style ? positional
-- @tags hot-small
-- @note Every UserPromptSubmit hook: one-row insert into user_prompts with the unique partial index on (session_db_id, native_prompt_id).
-- @param ?1 2000
-- @param ?2 'cs-sess-2000'
-- @param ?3 6
-- @param ?4 'please fix the retry limit in SessionStore'
-- @param ?5 '2026-05-07T08:00:00.000Z'
-- @param ?6 1778140800000
-- @param ?7 'native-6'
-- @param ?8 'ab12'
INSERT INTO user_prompts
(session_db_id, content_session_id, prompt_number, prompt_text, created_at, created_at_epoch, native_prompt_id, native_prompt_hash)
VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8);

-- @id claude-mem.tool_uses.upsert
-- @src src/services/sqlite/tool-uses.ts:205-230
-- @style ? positional
-- @tags hot-small
-- @note Every PostToolUse hook: INSERT ... ON CONFLICT DO UPDATE with CASE/COALESCE(excluded.*) merge rules, RETURNING id. Parameters hit an existing row (replay path).
-- @param ?1 'toolu_0004538453d7'
-- @param ?2 (SELECT content_session_id FROM tool_uses WHERE id = 1)
-- @param ?3 'mem-1'
-- @param ?4 1
-- @param ?5 'claude-mem'
-- @param ?6 'claude'
-- @param ?7 'Read'
-- @param ?8 '{"file_path":"/Users/dev/code/project/src/services/SessionStore.ts"}'
-- @param ?9 '{"ok":true,"bytes":1200}'
-- @param ?10 '/Users/dev/code/project-0'
-- @param ?11 1
-- @param ?12 NULL
-- @param ?13 NULL
-- @param ?14 NULL
-- @param ?15 NULL
-- @param ?16 '00000000deadbeef'
-- @param ?17 '2026-01-01T01:00:00.000Z'
-- @param ?18 1767229200000
INSERT INTO tool_uses (
  tool_use_id, content_session_id, memory_session_id, session_db_id, project,
  platform_source, tool_name, tool_input, tool_response, cwd, prompt_number,
  agent_type, agent_id, or_generation_id, or_session_id, content_hash,
  created_at, created_at_epoch
)
VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15, ?16, ?17, ?18)
ON CONFLICT(content_session_id, tool_use_id) DO UPDATE SET
  memory_session_id = CASE WHEN tool_uses.observation_id IS NULL
    THEN COALESCE(excluded.memory_session_id, tool_uses.memory_session_id)
    ELSE tool_uses.memory_session_id END,
  session_db_id     = COALESCE(excluded.session_db_id, tool_uses.session_db_id),
  project           = CASE WHEN excluded.project != '' THEN excluded.project ELSE tool_uses.project END,
  platform_source   = excluded.platform_source,
  tool_input        = COALESCE(excluded.tool_input, tool_uses.tool_input),
  tool_response     = COALESCE(excluded.tool_response, tool_uses.tool_response),
  cwd               = COALESCE(excluded.cwd, tool_uses.cwd),
  prompt_number     = COALESCE(excluded.prompt_number, tool_uses.prompt_number),
  agent_type        = COALESCE(excluded.agent_type, tool_uses.agent_type),
  agent_id          = COALESCE(excluded.agent_id, tool_uses.agent_id),
  or_generation_id  = COALESCE(excluded.or_generation_id, tool_uses.or_generation_id),
  or_session_id     = COALESCE(excluded.or_session_id, tool_uses.or_session_id),
  content_hash      = excluded.content_hash
RETURNING id;

-- @id claude-mem.store.observation_by_id
-- @src src/services/sqlite/SessionStore.ts:3147-3156
-- @style ? positional
-- @tags hot-small
-- @note get_observations / viewer detail: rowid point lookup returning the full row.
-- @param ?1 31234
SELECT *
FROM observations
WHERE id = ?1;

-- @id claude-mem.dedup.tier0_canonical
-- @src src/services/sqlite/dedup-store.ts:67-77
-- @style ? positional
-- @tags hot-small
-- @note Per-observation dedup probe: seek on (project, title_norm_key), oldest first, LIMIT 1.
-- @param ?1 'claude-mem'
-- @param ?2 'claude-mem|fixed retry limit in sessionstore'
SELECT id, occurrence_count, created_at_epoch FROM observations WHERE project = ?1 AND title_norm_key = ?2 ORDER BY created_at_epoch ASC, id ASC LIMIT 1;
