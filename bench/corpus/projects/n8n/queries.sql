-- n8n (n8n-io/n8n @ 02cb18e, Sustainable Use License). Almost all SQL is emitted by TypeORM query builders and
-- repository methods; each query below is the SQLite text TypeORM produces for one representative call, reconstructed
-- from the builder code (tagged dynamic, noted in @note). Named :params become ? on SQLite and are normalised to ?N in
-- text order. The acting user is a member (not instance owner) so access checks go through the sharing subquery.

-- @id n8n.executions.list_range
-- @src packages/@n8n/db/src/repositories/execution.repository.ts:1100-1117
-- @style TypeORM query builder (? positional on SQLite); SQL reconstructed from the builder calls (findManyByRangeQuery -> toQueryBuilderWithAnnotations -> toQueryBuilder, lines 1207-1392)
-- @tags hotpath,dynamic
-- @note Executions list for a member: correlated EXISTS over shared_workflow/project/project_relation for access, status IN, newest-id top-N in a derived table, then left-joined to annotation tags. reconstructed from ORM code: TypeORM SelectQueryBuilder emission for SQLite (quoted aliases, ( ... ) AND ( deletedAt IS NULL ) soft-delete guard).
-- @param ?1 'workflow:owner'
-- @param ?2 'workflow:editor'
-- @param ?3 '00000000-0000-4000-8000-000000000003'
-- @param ?4 'project:personalOwner'
-- @param ?5 'project:admin'
-- @param ?6 'project:editor'
-- @param ?7 'project:viewer'
-- @param ?8 'success'
-- @param ?9 'error'
-- @param ?10 'crashed'
SELECT e.*, "ate"."id" AS "annotation_tags_id", "ate"."name" AS "annotation_tags_name" FROM (SELECT "execution"."id" AS "id", "execution"."workflowId" AS "workflowId", "execution"."workflowVersionId" AS "workflowVersionId", "execution"."jsonSizeBytes" AS "jsonSizeBytes", "execution"."binaryDataSizeBytes" AS "binaryDataSizeBytes", "execution"."mode" AS "mode", "execution"."retryOf" AS "retryOf", "execution"."status" AS "status", "execution"."createdAt" AS "createdAt", "execution"."startedAt" AS "startedAt", "execution"."stoppedAt" AS "stoppedAt", "execution"."usedPrivateCredentials" AS "usedPrivateCredentials", "execution"."waitTill" AS "waitTill", "execution"."retrySuccessId" AS "retrySuccessId", "workflow"."name" AS "workflowName", "annotation"."id" AS "annotation_id", "annotation"."vote" AS "annotation_vote" FROM "execution_entity" "execution" INNER JOIN "workflow_entity" "workflow" ON "workflow"."id"="execution"."workflowId" LEFT JOIN "execution_annotations" "annotation" ON "annotation"."executionId"="execution"."id" WHERE ( EXISTS (SELECT "sw"."workflowId" FROM "shared_workflow" "sw" INNER JOIN "project" "p" ON "sw"."projectId" = "p"."id" INNER JOIN "project_relation" "pr" ON "pr"."projectId" = "p"."id" WHERE "sw"."role" IN (?1, ?2) AND "pr"."userId" = ?3 AND "pr"."role" IN (?4, ?5, ?6, ?7) AND "sw"."workflowId" = execution."workflowId") AND "execution"."status" IN (?8, ?9, ?10) ) AND ( "execution"."deletedAt" IS NULL ) ORDER BY "execution"."id" DESC LIMIT 20) "e" LEFT JOIN "execution_annotation_tags" "atm" ON "atm"."annotationId" = e.annotation_id LEFT JOIN "annotation_tag_entity" "ate" ON "ate"."id" = "atm"."tagId" ORDER BY e.id DESC;

-- @id n8n.executions.list_range_metadata_filter
-- @src packages/@n8n/db/src/repositories/execution.repository.ts:1265-1281
-- @style TypeORM query builder (? positional on SQLite); SQL reconstructed from the builder calls; metadata (non-exact) filter, mode filter, startedAt range, order.top = running
-- @tags hotpath,dynamic
-- @note Executions list filtered by custom data: inner join on execution_metadata with LOWER()=LOWER() and LOWER() LIKE LOWER(), startedAt BETWEEN-style range, running-first CASE ordering re-applied on the outer derived table. reconstructed from ORM code: TypeORM SelectQueryBuilder emission for SQLite (quoted aliases, ( ... ) AND ( deletedAt IS NULL ) soft-delete guard).
-- @param ?1 'customer'
-- @param ?2 '%acme%'
-- @param ?3 'workflow:owner'
-- @param ?4 'workflow:editor'
-- @param ?5 '00000000-0000-4000-8000-000000000003'
-- @param ?6 'project:personalOwner'
-- @param ?7 'project:admin'
-- @param ?8 'project:editor'
-- @param ?9 'project:viewer'
-- @param ?10 'trigger'
-- @param ?11 '2026-09-01 00:00:00.000'
-- @param ?12 '2026-10-28 00:00:00.000'
SELECT e.*, "ate"."id" AS "annotation_tags_id", "ate"."name" AS "annotation_tags_name" FROM (SELECT "execution"."id" AS "id", "execution"."workflowId" AS "workflowId", "execution"."workflowVersionId" AS "workflowVersionId", "execution"."jsonSizeBytes" AS "jsonSizeBytes", "execution"."binaryDataSizeBytes" AS "binaryDataSizeBytes", "execution"."mode" AS "mode", "execution"."retryOf" AS "retryOf", "execution"."status" AS "status", "execution"."createdAt" AS "createdAt", "execution"."startedAt" AS "startedAt", "execution"."stoppedAt" AS "stoppedAt", "execution"."usedPrivateCredentials" AS "usedPrivateCredentials", "execution"."waitTill" AS "waitTill", "execution"."retrySuccessId" AS "retrySuccessId", "workflow"."name" AS "workflowName", "annotation"."id" AS "annotation_id", "annotation"."vote" AS "annotation_vote" FROM "execution_entity" "execution" INNER JOIN "workflow_entity" "workflow" ON "workflow"."id"="execution"."workflowId" INNER JOIN "execution_metadata" "md" ON "md"."executionId" = "execution"."id" AND LOWER("md"."key") = LOWER(?1) AND LOWER("md"."value") LIKE LOWER(?2) LEFT JOIN "execution_annotations" "annotation" ON "annotation"."executionId"="execution"."id" WHERE ( EXISTS (SELECT "sw"."workflowId" FROM "shared_workflow" "sw" INNER JOIN "project" "p" ON "sw"."projectId" = "p"."id" INNER JOIN "project_relation" "pr" ON "pr"."projectId" = "p"."id" WHERE "sw"."role" IN (?3, ?4) AND "pr"."userId" = ?5 AND "pr"."role" IN (?6, ?7, ?8, ?9) AND "sw"."workflowId" = execution."workflowId") AND "execution"."mode" = ?10 AND ("execution"."startedAt" >= ?11 AND "execution"."startedAt" <= ?12) ) AND ( "execution"."deletedAt" IS NULL ) ORDER BY (CASE WHEN "execution"."status" = 'running' THEN 0 ELSE 1 END) ASC, "execution"."id" DESC LIMIT 20) "e" LEFT JOIN "execution_annotation_tags" "atm" ON "atm"."annotationId" = e.annotation_id LEFT JOIN "annotation_tag_entity" "ate" ON "ate"."id" = "atm"."tagId" ORDER BY (CASE WHEN e.status = 'running' THEN 0 ELSE 1 END) ASC, e.id DESC;

-- @id n8n.executions.list_range_annotation_project
-- @src packages/@n8n/db/src/repositories/execution.repository.ts:1292-1330
-- @style TypeORM query builder (? positional on SQLite); SQL reconstructed from the builder calls; annotationTags + vote + projectId + isArchived filters, order.startedAt DESC
-- @tags hotpath,dynamic
-- @note Project executions page filtered by annotation tag and vote: six joins (workflow twice, annotation, tag mapping, shared_workflow whose alias shadows the EXISTS subquery alias), COALESCE ordering top-N. reconstructed from ORM code: TypeORM SelectQueryBuilder emission for SQLite (quoted aliases, ( ... ) AND ( deletedAt IS NULL ) soft-delete guard).
-- @param ?1 'at00000000000001'
-- @param ?2 'workflow:owner'
-- @param ?3 'workflow:editor'
-- @param ?4 '00000000-0000-4000-8000-000000000003'
-- @param ?5 'project:personalOwner'
-- @param ?6 'project:admin'
-- @param ?7 'project:editor'
-- @param ?8 'project:viewer'
-- @param ?9 'up'
-- @param ?10 'p000000000000043'
-- @param ?11 0
SELECT e.*, "ate"."id" AS "annotation_tags_id", "ate"."name" AS "annotation_tags_name" FROM (SELECT "execution"."id" AS "id", "execution"."workflowId" AS "workflowId", "execution"."workflowVersionId" AS "workflowVersionId", "execution"."jsonSizeBytes" AS "jsonSizeBytes", "execution"."binaryDataSizeBytes" AS "binaryDataSizeBytes", "execution"."mode" AS "mode", "execution"."retryOf" AS "retryOf", "execution"."status" AS "status", "execution"."createdAt" AS "createdAt", "execution"."startedAt" AS "startedAt", "execution"."stoppedAt" AS "stoppedAt", "execution"."usedPrivateCredentials" AS "usedPrivateCredentials", "execution"."waitTill" AS "waitTill", "execution"."retrySuccessId" AS "retrySuccessId", "workflow"."name" AS "workflowName", "annotation"."id" AS "annotation_id", "annotation"."vote" AS "annotation_vote" FROM "execution_entity" "execution" INNER JOIN "workflow_entity" "workflow" ON "workflow"."id"="execution"."workflowId" INNER JOIN "execution_annotations" "annotation" ON "annotation"."executionId"="execution"."id" INNER JOIN "execution_annotation_tags" "atm_0" ON "atm_0"."annotationId" = "annotation"."id" AND "atm_0"."tagId" = ?1 INNER JOIN "workflow_entity" "w" ON "w"."id" = "execution"."workflowId" INNER JOIN "shared_workflow" "sw" ON "sw"."workflowId" = "w"."id" WHERE ( EXISTS (SELECT "sw"."workflowId" FROM "shared_workflow" "sw" INNER JOIN "project" "p" ON "sw"."projectId" = "p"."id" INNER JOIN "project_relation" "pr" ON "pr"."projectId" = "p"."id" WHERE "sw"."role" IN (?2, ?3) AND "pr"."userId" = ?4 AND "pr"."role" IN (?5, ?6, ?7, ?8) AND "sw"."workflowId" = execution."workflowId") AND "annotation"."vote" = ?9 AND "sw"."projectId" = ?10 AND "workflow"."isArchived" = ?11 ) AND ( "execution"."deletedAt" IS NULL ) ORDER BY COALESCE("execution"."startedAt", "execution"."createdAt") DESC, "execution"."id" DESC LIMIT 20) "e" LEFT JOIN "execution_annotation_tags" "atm" ON "atm"."annotationId" = e.annotation_id LEFT JOIN "annotation_tag_entity" "ate" ON "ate"."id" = "atm"."tagId" ORDER BY COALESCE("e"."startedAt", "e"."createdAt") DESC, e.id DESC;

-- @id n8n.executions.count
-- @src packages/@n8n/db/src/repositories/execution.repository.ts:1183-1185
-- @style TypeORM query builder (? positional on SQLite); SQL reconstructed from the builder calls (toQueryBuilder(...).getCount())
-- @tags hotpath,dynamic
-- @note Total for the executions list header: COUNT(DISTINCT id) over the access-checked join. reconstructed from ORM code: TypeORM SelectQueryBuilder emission for SQLite (quoted aliases, ( ... ) AND ( deletedAt IS NULL ) soft-delete guard).
-- @param ?1 'workflow:owner'
-- @param ?2 'workflow:editor'
-- @param ?3 '00000000-0000-4000-8000-000000000003'
-- @param ?4 'project:personalOwner'
-- @param ?5 'project:admin'
-- @param ?6 'project:editor'
-- @param ?7 'project:viewer'
-- @param ?8 'success'
-- @param ?9 'error'
-- @param ?10 'crashed'
SELECT COUNT(DISTINCT("execution"."id")) AS "cnt" FROM "execution_entity" "execution" INNER JOIN "workflow_entity" "workflow" ON "workflow"."id"="execution"."workflowId" WHERE ( EXISTS (SELECT "sw"."workflowId" FROM "shared_workflow" "sw" INNER JOIN "project" "p" ON "sw"."projectId" = "p"."id" INNER JOIN "project_relation" "pr" ON "pr"."projectId" = "p"."id" WHERE "sw"."role" IN (?1, ?2) AND "pr"."userId" = ?3 AND "pr"."role" IN (?4, ?5, ?6, ?7) AND "sw"."workflowId" = execution."workflowId") AND "execution"."status" IN (?8, ?9, ?10) ) AND ( "execution"."deletedAt" IS NULL );

-- @id n8n.executions.summarise_runs_for_projects
-- @src packages/@n8n/db/src/repositories/execution.repository.ts:831-931
-- @style TypeORM query builder (? positional on SQLite); SQL reconstructed from the builder calls; IN lists expanded from :...params
-- @tags hotpath,dynamic
-- @note Per-workflow run digest: GROUP BY workflow with COUNT(DISTINCT), COUNT(DISTINCT CASE ...), MAX(CASE ...) aggregates over a stoppedAt window joined through shared_workflow, ordered by MAX(stoppedAt), top-N. reconstructed from ORM code: TypeORM SelectQueryBuilder emission for SQLite (quoted aliases, ( ... ) AND ( deletedAt IS NULL ) soft-delete guard).
-- @param ?1 'error'
-- @param ?2 'crashed'
-- @param ?3 'error'
-- @param ?4 'crashed'
-- @param ?5 'evaluation'
-- @param ?6 '2026-10-21 00:00:00.000'
-- @param ?7 '2026-10-28 00:00:00.000'
-- @param ?8 'p000000000000041'
-- @param ?9 'p000000000000043'
-- @param ?10 'p000000000000045'
SELECT "execution"."workflowId" AS "workflowId", MAX("workflow"."name") AS "workflowName", COUNT(DISTINCT "execution"."id") AS "total", COUNT(DISTINCT CASE WHEN "execution"."status" IN (?1, ?2) THEN "execution"."id" END) AS "failed", MAX("execution"."stoppedAt") AS "lastStoppedAt", MAX(CASE WHEN "execution"."status" IN (?3, ?4) THEN "execution"."id" END) AS "lastFailedExecutionId" FROM "execution_entity" "execution" INNER JOIN "workflow_entity" "workflow" ON "workflow"."id" = "execution"."workflowId" INNER JOIN "shared_workflow" "sw" ON "sw"."workflowId" = "workflow"."id" WHERE ( "execution"."deletedAt" IS NULL AND "execution"."mode" != ?5 AND "execution"."stoppedAt" IS NOT NULL AND "execution"."stoppedAt" >= ?6 AND "execution"."stoppedAt" < ?7 AND "sw"."projectId" IN (?8, ?9, ?10) ) AND ( "execution"."deletedAt" IS NULL ) GROUP BY "execution"."workflowId" ORDER BY MAX("execution"."stoppedAt") DESC LIMIT 20;

-- @id n8n.executions.prune_soft_delete
-- @src packages/@n8n/db/src/repositories/execution.repository.ts:675-722
-- @style TypeORM UpdateQueryBuilder; Raw() cutoffs inlined by dbNowPlusMsLiteral (utils/dialect-time.ts:22), defaults pruneDataMaxAge 336 h, pruneDataMaxCount 10000
-- @tags dynamic
-- @note Pruning pass: UPDATE with NOT IN (annotated ids), a STRFTIME(now - 14 days) cutoff OR an id cutoff from a scalar subquery with ORDER BY id DESC LIMIT 1 OFFSET 10000. Reconstructed from ORM code (UpdateQueryBuilder emits unaliased column names).
-- @param ?1 'new'
-- @param ?2 'running'
-- @param ?3 'waiting'
UPDATE "execution_entity" SET "deletedAt" = STRFTIME('%Y-%m-%d %H:%M:%f', 'NOW') WHERE ("deletedAt" IS NULL AND "status" NOT IN (?1, ?2, ?3)) AND id NOT IN (SELECT "annotation"."executionId" FROM "execution_annotations" "annotation") AND (("stoppedAt" <= STRFTIME('%Y-%m-%d %H:%M:%f', 'NOW', '-1209600 seconds')) OR id <= (SELECT "execution"."id" AS "execution_id" FROM "execution_entity" "execution" WHERE ( "execution"."id" NOT IN (SELECT "annotation"."executionId" FROM "execution_annotations" "annotation") ) AND ( "execution"."deletedAt" IS NULL ) ORDER BY "execution"."id" DESC LIMIT 1 OFFSET 10000));

-- @id n8n.executions.find_soft_deleted
-- @src packages/@n8n/db/src/repositories/execution.repository.ts:724-750
-- @style TypeORM Repository.find (withDeleted, take 100); Raw() cutoff inlined
-- @tags dynamic
-- @note Hard-delete batch picker: soft-deleted rows past a STRFTIME(now - 1 h) buffer, newest id first, LIMIT 100. Reconstructed from ORM code (find() aliases columns as Entity_column).
SELECT "ExecutionEntity"."id" AS "ExecutionEntity_id", "ExecutionEntity"."workflowId" AS "ExecutionEntity_workflowId", "ExecutionEntity"."storedAt" AS "ExecutionEntity_storedAt" FROM "execution_entity" "ExecutionEntity" WHERE (("ExecutionEntity"."deletedAt" <= STRFTIME('%Y-%m-%d %H:%M:%f', 'NOW', '-3600 seconds'))) ORDER BY "ExecutionEntity"."id" DESC LIMIT 100;

-- @id n8n.executions.delete_by_ids
-- @src packages/@n8n/db/src/repositories/execution.repository.ts:752-754
-- @style TypeORM Repository.delete({ id: In(ids) })
-- @tags batch,dynamic
-- @note Hard delete of a pruning batch: DELETE ... WHERE id IN (20 ids). Reconstructed from ORM code.
-- @param ?1 50
-- @param ?2 100
-- @param ?3 150
-- @param ?4 200
-- @param ?5 250
-- @param ?6 300
-- @param ?7 350
-- @param ?8 400
-- @param ?9 450
-- @param ?10 500
-- @param ?11 550
-- @param ?12 600
-- @param ?13 650
-- @param ?14 700
-- @param ?15 750
-- @param ?16 800
-- @param ?17 850
-- @param ?18 900
-- @param ?19 950
-- @param ?20 1000
DELETE FROM "execution_entity" WHERE "id" IN (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15, ?16, ?17, ?18, ?19, ?20);

-- @id n8n.executions.waiting
-- @src packages/@n8n/db/src/repositories/execution.repository.ts:756-779
-- @style TypeORM Repository.find via findMultipleExecutions; waitTill bound as a UTC datetime string on SQLite
-- @tags hotpath,dynamic
-- @note Wait tracker poll (every minute): waitTill <= now + 70 s AND status = waiting, ordered by waitTill. Reconstructed from ORM code.
-- @param ?1 '2026-10-28 00:01:10.000'
-- @param ?2 'waiting'
SELECT "ExecutionEntity"."id" AS "ExecutionEntity_id", "ExecutionEntity"."waitTill" AS "ExecutionEntity_waitTill" FROM "execution_entity" "ExecutionEntity" WHERE (("ExecutionEntity"."waitTill" <= ?1) AND ("ExecutionEntity"."status" = ?2)) AND ( "ExecutionEntity"."deletedAt" IS NULL ) ORDER BY "ExecutionEntity"."waitTill" ASC;

-- @id n8n.executions.count_in_workflows
-- @src packages/@n8n/db/src/repositories/execution.repository.ts:797-810
-- @style TypeORM Repository.count with getFindManyInWorkflowsCondition (lines 943-980)
-- @tags dynamic
-- @note Public API execution count: id < cursor AND status AND workflowId IN list, counted distinct. Reconstructed from ORM code.
-- @param ?1 70000
-- @param ?2 'success'
-- @param ?3 'wf00000000000001'
-- @param ?4 'wf00000000000002'
-- @param ?5 'wf00000000000003'
-- @param ?6 'wf00000000000010'
SELECT COUNT(DISTINCT("ExecutionEntity"."id")) AS "cnt" FROM "execution_entity" "ExecutionEntity" WHERE (("ExecutionEntity"."id" < ?1) AND ("ExecutionEntity"."status" = ?2) AND ("ExecutionEntity"."workflowId" IN (?3, ?4, ?5, ?6))) AND ( "ExecutionEntity"."deletedAt" IS NULL );

-- @id n8n.executions.concurrent_count
-- @src packages/@n8n/db/src/repositories/execution.repository.ts:1458-1464
-- @style TypeORM Repository.count
-- @tags hot-small
-- @note Concurrency control check on every production run: count running webhook/trigger executions. Reconstructed from ORM code.
-- @param ?1 'running'
-- @param ?2 'webhook'
-- @param ?3 'trigger'
SELECT COUNT(1) AS "cnt" FROM "execution_entity" "ExecutionEntity" WHERE (("ExecutionEntity"."status" = ?1) AND ("ExecutionEntity"."mode" IN (?2, ?3))) AND ( "ExecutionEntity"."deletedAt" IS NULL );

-- @id n8n.executions.find_one_by_id
-- @src packages/@n8n/db/src/repositories/execution.repository.ts:536-554
-- @style TypeORM EntityManager.findOneBy (setRunning)
-- @tags hot-small
-- @note Start of every execution: primary-key lookup of the full row with the soft-delete guard. Reconstructed from ORM code.
-- @param ?1 79971
SELECT "ExecutionEntity"."id" AS "ExecutionEntity_id", "ExecutionEntity"."finished" AS "ExecutionEntity_finished", "ExecutionEntity"."mode" AS "ExecutionEntity_mode", "ExecutionEntity"."retryOf" AS "ExecutionEntity_retryOf", "ExecutionEntity"."retrySuccessId" AS "ExecutionEntity_retrySuccessId", "ExecutionEntity"."status" AS "ExecutionEntity_status", "ExecutionEntity"."createdAt" AS "ExecutionEntity_createdAt", "ExecutionEntity"."startedAt" AS "ExecutionEntity_startedAt", "ExecutionEntity"."stoppedAt" AS "ExecutionEntity_stoppedAt", "ExecutionEntity"."deletedAt" AS "ExecutionEntity_deletedAt", "ExecutionEntity"."workflowId" AS "ExecutionEntity_workflowId", "ExecutionEntity"."waitTill" AS "ExecutionEntity_waitTill", "ExecutionEntity"."storedAt" AS "ExecutionEntity_storedAt", "ExecutionEntity"."tracingContext" AS "ExecutionEntity_tracingContext", "ExecutionEntity"."deduplicationKey" AS "ExecutionEntity_deduplicationKey", "ExecutionEntity"."jsonSizeBytes" AS "ExecutionEntity_jsonSizeBytes", "ExecutionEntity"."binaryDataSizeBytes" AS "ExecutionEntity_binaryDataSizeBytes", "ExecutionEntity"."workflowVersionId" AS "ExecutionEntity_workflowVersionId", "ExecutionEntity"."usedPrivateCredentials" AS "ExecutionEntity_usedPrivateCredentials" FROM "execution_entity" "ExecutionEntity" WHERE (("ExecutionEntity"."id" = ?1)) AND ( "ExecutionEntity"."deletedAt" IS NULL ) LIMIT 1;

-- @id n8n.executions.set_running
-- @src packages/@n8n/db/src/repositories/execution.repository.ts:545-549
-- @style TypeORM EntityManager.update
-- @tags hot-small
-- @note Start of every execution: mark running. Reconstructed from ORM code.
-- @param ?1 'running'
-- @param ?2 '2026-10-28 00:00:01.000'
-- @param ?3 79971
UPDATE "execution_entity" SET "status" = ?1, "startedAt" = ?2, "waitTill" = NULL WHERE "id" = ?3;

-- @id n8n.executions.update_data
-- @src packages/@n8n/db/src/repositories/execution.repository.ts:592-615
-- @style TypeORM EntityManager.update (updateExistingExecution)
-- @tags hot-small
-- @note End of every execution: write the flatted run data blob by executionId. Reconstructed from ORM code.
-- @param ?1 '[{"version":1,"startData":"1","resultData":"2"},{},{"runData":"3","lastNodeExecuted":"4"},{"HTTP Request":"5"},"HTTP Request",[]]'
-- @param ?2 79971
UPDATE "execution_data" SET "data" = ?1 WHERE "executionId" = ?2;

-- @id n8n.workflows.list_count
-- @src packages/@n8n/db/src/repositories/workflow.repository.ts:1291-1372
-- @style TypeORM query builder (? positional on SQLite); SQL reconstructed from the builder calls (getManyAndCountWithSharingSubquery -> getManyAndCount count half); filter isArchived=false, query "daily report"
-- @tags hotpath,dynamic
-- @note Workflow overview count: COUNT(DISTINCT id) across left joins to folder, tags (via junction), shares and projects, with an IN (sharing subquery) and a two-word LOWER(name || description) LIKE search. reconstructed from ORM code: TypeORM SelectQueryBuilder emission for SQLite (quoted aliases, ( ... ) AND ( deletedAt IS NULL ) soft-delete guard).
-- @param ?1 'workflow:owner'
-- @param ?2 'workflow:editor'
-- @param ?3 '00000000-0000-4000-8000-000000000003'
-- @param ?4 'project:personalOwner'
-- @param ?5 'project:admin'
-- @param ?6 'project:editor'
-- @param ?7 'project:viewer'
-- @param ?8 0
-- @param ?9 '%daily%'
-- @param ?10 '%report%'
SELECT COUNT(DISTINCT("workflow"."id")) AS "cnt" FROM "workflow_entity" "workflow" LEFT JOIN "folder" "parentFolder" ON "parentFolder"."id"="workflow"."parentFolderId" LEFT JOIN "workflows_tags" "workflow_tags" ON "workflow_tags"."workflowId"="workflow"."id" LEFT JOIN "tag_entity" "tags" ON "tags"."id"="workflow_tags"."tagId" LEFT JOIN "shared_workflow" "shared" ON "shared"."workflowId"="workflow"."id" LEFT JOIN "project" "project" ON "project"."id"="shared"."projectId" WHERE "workflow"."id" IN (SELECT "sw"."workflowId" FROM "shared_workflow" "sw" INNER JOIN "project" "p" ON "sw"."projectId" = "p"."id" INNER JOIN "project_relation" "pr" ON "pr"."projectId" = "p"."id" WHERE "sw"."role" IN (?1, ?2) AND "pr"."userId" = ?3 AND "pr"."role" IN (?4, ?5, ?6, ?7)) AND "workflow"."isArchived" = ?8 AND (LOWER("workflow"."name" || ' ' || COALESCE("workflow"."description", '')) LIKE ?9 AND LOWER("workflow"."name" || ' ' || COALESCE("workflow"."description", '')) LIKE ?10);

-- @id n8n.workflows.list_page_ids
-- @src packages/@n8n/db/src/repositories/workflow.repository.ts:1291-1372
-- @style TypeORM query builder (? positional on SQLite); SQL reconstructed from the builder calls (getManyAndCount page half: TypeORM pages joined to-many results through a DISTINCT over the full select); sortBy updatedAt:desc, take 50
-- @tags hotpath,dynamic
-- @note Workflow overview page: TypeORM distinctAlias wrapper - SELECT DISTINCT over a 28-column, 5-join derived table, ordered by updatedAt then id, LIMIT 50. reconstructed from ORM code: TypeORM SelectQueryBuilder emission for SQLite (quoted aliases, ( ... ) AND ( deletedAt IS NULL ) soft-delete guard).
-- @param ?1 'workflow:owner'
-- @param ?2 'workflow:editor'
-- @param ?3 '00000000-0000-4000-8000-000000000003'
-- @param ?4 'project:personalOwner'
-- @param ?5 'project:admin'
-- @param ?6 'project:editor'
-- @param ?7 'project:viewer'
-- @param ?8 0
-- @param ?9 '%daily%'
-- @param ?10 '%report%'
SELECT DISTINCT "distinctAlias"."workflow_id" AS "ids_workflow_id", "distinctAlias"."workflow_updatedAt" FROM (SELECT "workflow"."id" AS "workflow_id", "workflow"."name" AS "workflow_name", "workflow"."active" AS "workflow_active", "workflow"."isArchived" AS "workflow_isArchived", "workflow"."createdAt" AS "workflow_createdAt", "workflow"."updatedAt" AS "workflow_updatedAt", "workflow"."versionId" AS "workflow_versionId", "workflow"."activeVersionId" AS "workflow_activeVersionId", "workflow"."settings" AS "workflow_settings", "workflow"."description" AS "workflow_description", "parentFolder"."id" AS "parentFolder_id", "parentFolder"."name" AS "parentFolder_name", "parentFolder"."parentFolderId" AS "parentFolder_parentFolderId", "tags"."id" AS "tags_id", "tags"."name" AS "tags_name", "tags"."createdAt" AS "tags_createdAt", "tags"."updatedAt" AS "tags_updatedAt", "shared"."role" AS "shared_role", "shared"."createdAt" AS "shared_createdAt", "shared"."updatedAt" AS "shared_updatedAt", "shared"."workflowId" AS "shared_workflowId", "shared"."projectId" AS "shared_projectId", "project"."id" AS "project_id", "project"."name" AS "project_name", "project"."type" AS "project_type", "project"."icon" AS "project_icon", "project"."createdAt" AS "project_createdAt", "project"."updatedAt" AS "project_updatedAt" FROM "workflow_entity" "workflow" LEFT JOIN "folder" "parentFolder" ON "parentFolder"."id"="workflow"."parentFolderId" LEFT JOIN "workflows_tags" "workflow_tags" ON "workflow_tags"."workflowId"="workflow"."id" LEFT JOIN "tag_entity" "tags" ON "tags"."id"="workflow_tags"."tagId" LEFT JOIN "shared_workflow" "shared" ON "shared"."workflowId"="workflow"."id" LEFT JOIN "project" "project" ON "project"."id"="shared"."projectId" WHERE "workflow"."id" IN (SELECT "sw"."workflowId" FROM "shared_workflow" "sw" INNER JOIN "project" "p" ON "sw"."projectId" = "p"."id" INNER JOIN "project_relation" "pr" ON "pr"."projectId" = "p"."id" WHERE "sw"."role" IN (?1, ?2) AND "pr"."userId" = ?3 AND "pr"."role" IN (?4, ?5, ?6, ?7)) AND "workflow"."isArchived" = ?8 AND (LOWER("workflow"."name" || ' ' || COALESCE("workflow"."description", '')) LIKE ?9 AND LOWER("workflow"."name" || ' ' || COALESCE("workflow"."description", '')) LIKE ?10)) "distinctAlias" ORDER BY "distinctAlias"."workflow_updatedAt" DESC, "workflow_id" ASC LIMIT 50;

-- @id n8n.workflows.recent_for_projects_count
-- @src packages/@n8n/db/src/repositories/workflow.repository.ts:126-161
-- @style TypeORM query builder (? positional on SQLite); SQL reconstructed from the builder calls; projectIds IN list, mcpVisibleOnly
-- @tags dynamic
-- @note Activity digest total: COUNT(DISTINCT) over workflow x shared_workflow with a JSON_EXTRACT settings predicate. reconstructed from ORM code: TypeORM SelectQueryBuilder emission for SQLite (quoted aliases, ( ... ) AND ( deletedAt IS NULL ) soft-delete guard).
-- @param ?1 0
-- @param ?2 'p000000000000041'
-- @param ?3 'p000000000000043'
-- @param ?4 'p000000000000045'
-- @param ?5 1
SELECT COUNT(DISTINCT "workflow"."id") AS "total" FROM "workflow_entity" "workflow" INNER JOIN "shared_workflow" "shared" ON "shared"."workflowId" = "workflow"."id" WHERE "workflow"."isArchived" = ?1 AND "shared"."projectId" IN (?2, ?3, ?4) AND JSON_EXTRACT("workflow"."settings", '$.availableInMCP') = ?5;

-- @id n8n.workflows.recent_for_projects_page
-- @src packages/@n8n/db/src/repositories/workflow.repository.ts:163-172
-- @style TypeORM query builder (? positional on SQLite); SQL reconstructed from the builder calls; projectIds IN list
-- @tags dynamic
-- @note Activity digest page: GROUP BY workflow with MAX(name), MAX(CASE ...) and ORDER BY MAX(updatedAt) top-N across shares. reconstructed from ORM code: TypeORM SelectQueryBuilder emission for SQLite (quoted aliases, ( ... ) AND ( deletedAt IS NULL ) soft-delete guard).
-- @param ?1 0
-- @param ?2 'p000000000000041'
-- @param ?3 'p000000000000043'
-- @param ?4 'p000000000000045'
SELECT "workflow"."id" AS "id", MAX("workflow"."name") AS "name", MAX(CASE WHEN "workflow"."activeVersionId" IS NOT NULL THEN 1 ELSE 0 END) AS "active" FROM "workflow_entity" "workflow" INNER JOIN "shared_workflow" "shared" ON "shared"."workflowId" = "workflow"."id" WHERE "workflow"."isArchived" = ?1 AND "shared"."projectId" IN (?2, ?3, ?4) GROUP BY "workflow"."id" ORDER BY MAX("workflow"."updatedAt") DESC LIMIT 10;

-- @id n8n.webhooks.find_static
-- @src packages/cli/src/webhooks/webhook.service.ts:102
-- @style TypeORM Repository.findOneBy({ webhookPath, method })
-- @tags hot-small
-- @note Every production webhook request: primary-key lookup by (path, method). Reconstructed from ORM code.
-- @param ?1 '9e3779b1-0001-4001-85f4-000000001eef'
-- @param ?2 'GET'
SELECT "WebhookEntity"."workflowId" AS "WebhookEntity_workflowId", "WebhookEntity"."webhookPath" AS "WebhookEntity_webhookPath", "WebhookEntity"."method" AS "WebhookEntity_method", "WebhookEntity"."node" AS "WebhookEntity_node", "WebhookEntity"."webhookId" AS "WebhookEntity_webhookId", "WebhookEntity"."pathLength" AS "WebhookEntity_pathLength" FROM "webhook_entity" "WebhookEntity" WHERE (("WebhookEntity"."webhookPath" = ?1) AND ("WebhookEntity"."method" = ?2)) LIMIT 1;

-- @id n8n.webhooks.find_dynamic
-- @src packages/cli/src/webhooks/webhook.service.ts:200-212
-- @style TypeORM Repository.findBy({ webhookId, method, pathLength })
-- @tags hotpath
-- @note Webhook requests with :params: lookup on the (webhookId, method, pathLength) index, segments matched in JS. Reconstructed from ORM code.
-- @param ?1 '17156075-0000-4000-8000-000000000005'
-- @param ?2 'GET'
-- @param ?3 2
SELECT "WebhookEntity"."workflowId" AS "WebhookEntity_workflowId", "WebhookEntity"."webhookPath" AS "WebhookEntity_webhookPath", "WebhookEntity"."method" AS "WebhookEntity_method", "WebhookEntity"."node" AS "WebhookEntity_node", "WebhookEntity"."webhookId" AS "WebhookEntity_webhookId", "WebhookEntity"."pathLength" AS "WebhookEntity_pathLength" FROM "webhook_entity" "WebhookEntity" WHERE (("WebhookEntity"."webhookId" = ?1) AND ("WebhookEntity"."method" = ?2) AND ("WebhookEntity"."pathLength" = ?3));

-- @id n8n.insights.summary
-- @src packages/modules/insights/backend/src/insights-by-period.repository.ts:371-430
-- @style TypeORM query builder (? positional on SQLite); SQL reconstructed from the builder calls; date-range literals inlined into the CTE by the app; projectId filter
-- @tags hotpath,dynamic
-- @note Insights banner: CTE of date literals cross-joined, CASE current/previous period bucketing, GROUP BY the CASE alias and type. reconstructed from ORM code (TypeORM SelectQueryBuilder with addCommonTableExpression; the date_ranges CTE text is getDateRangesSelectQuery, insights-by-period-query.helper.ts:79).
-- @param ?1 'p000000000000041'
WITH "date_ranges" AS (SELECT
			'2026-10-13 00:00:00.000' AS prev_start_date,
			'2026-10-20 00:00:00.000' AS start_date,
			'2026-10-27 00:00:00.000' AS end_date
	) SELECT 
						CASE
							WHEN "insights"."periodStart" >= date_ranges.start_date AND "insights"."periodStart" < date_ranges.end_date
							THEN 'current'
							ELSE 'previous'
						END
					 AS "period", "insights"."type" AS "type", SUM(value) AS "total_value" FROM "insights_by_period" "insights" INNER JOIN "date_ranges" "date_ranges" ON 1=1 INNER JOIN "insights_metadata" "metadata" ON "metadata"."metaId"="insights"."metaId" WHERE "insights"."periodStart" >= date_ranges.prev_start_date AND "insights"."periodStart" < date_ranges.end_date AND "metadata"."projectId" = ?1 GROUP BY period, "insights"."type";

-- @id n8n.insights.by_workflow
-- @src packages/modules/insights/backend/src/insights-by-period.repository.ts:445-520
-- @style TypeORM query builder (? positional on SQLite); SQL reconstructed from the builder calls; access filter for a non-admin (applyAccessFilter, line 138), sortBy total:desc, take 20
-- @tags hotpath,dynamic
-- @note Insights table: eight SUM(CASE ...) aggregates incl. guarded failure-rate and average-runtime ratios, grouped by four metadata columns, correlated EXISTS access check, ordered by an aggregate alias. reconstructed from ORM code (TypeORM SelectQueryBuilder with addCommonTableExpression; the date_ranges CTE text is getDateRangesSelectQuery, insights-by-period-query.helper.ts:79).
-- @param ?1 'workflow:owner'
-- @param ?2 'workflow:editor'
-- @param ?3 '00000000-0000-4000-8000-000000000003'
-- @param ?4 'project:personalOwner'
-- @param ?5 'project:admin'
-- @param ?6 'project:editor'
-- @param ?7 'project:viewer'
WITH "date_ranges" AS (SELECT
			'2026-05-02 00:00:00.000' AS prev_start_date,
			'2026-07-30 00:00:00.000' AS start_date,
			'2026-10-28 00:00:00.000' AS end_date
	) SELECT "metadata"."workflowId" AS "workflowId", "metadata"."workflowName" AS "workflowName", "metadata"."projectId" AS "projectId", "metadata"."projectName" AS "projectName", SUM(CASE WHEN "insights"."type" = 2 THEN value ELSE 0 END) AS "succeeded", SUM(CASE WHEN "insights"."type" = 3 THEN value ELSE 0 END) AS "failed", SUM(CASE WHEN "insights"."type" IN (2, 3) THEN value ELSE 0 END) AS "total", CASE
								WHEN SUM(CASE WHEN "insights"."type" IN (2, 3) THEN value ELSE 0 END) = 0 THEN 0
								ELSE 1.0 * SUM(CASE WHEN "insights"."type" = 3 THEN value ELSE 0 END) / SUM(CASE WHEN "insights"."type" IN (2, 3) THEN value ELSE 0 END)
							END AS "failureRate", SUM(CASE WHEN "insights"."type" = 1 THEN value ELSE 0 END) AS "runTime", SUM(CASE WHEN "insights"."type" = 0 THEN value ELSE 0 END) AS "timeSaved", CASE
								WHEN SUM(CASE WHEN "insights"."type" IN (2, 3) THEN value ELSE 0 END) = 0	THEN 0
								ELSE 1.0 * SUM(CASE WHEN "insights"."type" = 1 THEN value ELSE 0 END) / SUM(CASE WHEN "insights"."type" IN (2, 3) THEN value ELSE 0 END)
							END AS "averageRunTime" FROM "insights_by_period" "insights" INNER JOIN "insights_metadata" "metadata" ON "metadata"."metaId"="insights"."metaId" INNER JOIN "date_ranges" "date_ranges" ON 1=1 WHERE "insights"."periodStart" >= date_ranges.start_date AND "insights"."periodStart" < date_ranges.end_date AND EXISTS (SELECT "sw"."workflowId" FROM "shared_workflow" "sw" INNER JOIN "project" "p" ON "sw"."projectId" = "p"."id" INNER JOIN "project_relation" "pr" ON "pr"."projectId" = "p"."id" WHERE "sw"."role" IN (?1, ?2) AND "pr"."userId" = ?3 AND "pr"."role" IN (?4, ?5, ?6, ?7) AND "sw"."workflowId" = metadata."workflowId") GROUP BY "metadata"."workflowId", "metadata"."workflowName", "metadata"."projectId", "metadata"."projectName" ORDER BY "total" DESC LIMIT 20;

-- @id n8n.insights.by_workflow_count
-- @src packages/modules/insights/backend/src/insights-by-period.repository.ts:432-443
-- @style TypeORM query builder (? positional on SQLite); SQL reconstructed from the builder calls (countInsightsByWorkflowGroups wraps the grouped query, CTE included, in a derived table)
-- @tags hotpath,dynamic
-- @note Row count for the insights table: COUNT(*) over a derived table that itself carries the WITH clause and the full grouped aggregate. reconstructed from ORM code (TypeORM SelectQueryBuilder with addCommonTableExpression; the date_ranges CTE text is getDateRangesSelectQuery, insights-by-period-query.helper.ts:79).
-- @param ?1 'workflow:owner'
-- @param ?2 'workflow:editor'
-- @param ?3 '00000000-0000-4000-8000-000000000003'
-- @param ?4 'project:personalOwner'
-- @param ?5 'project:admin'
-- @param ?6 'project:editor'
-- @param ?7 'project:viewer'
SELECT COUNT(*) AS "count" FROM (WITH "date_ranges" AS (SELECT
			'2026-05-02 00:00:00.000' AS prev_start_date,
			'2026-07-30 00:00:00.000' AS start_date,
			'2026-10-28 00:00:00.000' AS end_date
	) SELECT "metadata"."workflowId" AS "workflowId", "metadata"."workflowName" AS "workflowName", "metadata"."projectId" AS "projectId", "metadata"."projectName" AS "projectName", SUM(CASE WHEN "insights"."type" = 2 THEN value ELSE 0 END) AS "succeeded", SUM(CASE WHEN "insights"."type" = 3 THEN value ELSE 0 END) AS "failed", SUM(CASE WHEN "insights"."type" IN (2, 3) THEN value ELSE 0 END) AS "total", CASE
								WHEN SUM(CASE WHEN "insights"."type" IN (2, 3) THEN value ELSE 0 END) = 0 THEN 0
								ELSE 1.0 * SUM(CASE WHEN "insights"."type" = 3 THEN value ELSE 0 END) / SUM(CASE WHEN "insights"."type" IN (2, 3) THEN value ELSE 0 END)
							END AS "failureRate", SUM(CASE WHEN "insights"."type" = 1 THEN value ELSE 0 END) AS "runTime", SUM(CASE WHEN "insights"."type" = 0 THEN value ELSE 0 END) AS "timeSaved", CASE
								WHEN SUM(CASE WHEN "insights"."type" IN (2, 3) THEN value ELSE 0 END) = 0	THEN 0
								ELSE 1.0 * SUM(CASE WHEN "insights"."type" = 1 THEN value ELSE 0 END) / SUM(CASE WHEN "insights"."type" IN (2, 3) THEN value ELSE 0 END)
							END AS "averageRunTime" FROM "insights_by_period" "insights" INNER JOIN "insights_metadata" "metadata" ON "metadata"."metaId"="insights"."metaId" INNER JOIN "date_ranges" "date_ranges" ON 1=1 WHERE "insights"."periodStart" >= date_ranges.start_date AND "insights"."periodStart" < date_ranges.end_date AND EXISTS (SELECT "sw"."workflowId" FROM "shared_workflow" "sw" INNER JOIN "project" "p" ON "sw"."projectId" = "p"."id" INNER JOIN "project_relation" "pr" ON "pr"."projectId" = "p"."id" WHERE "sw"."role" IN (?1, ?2) AND "pr"."userId" = ?3 AND "pr"."role" IN (?4, ?5, ?6, ?7) AND "sw"."workflowId" = metadata."workflowId") GROUP BY "metadata"."workflowId", "metadata"."workflowName", "metadata"."projectId", "metadata"."projectName") "workflow_groups";

-- @id n8n.insights.by_time_day_tz
-- @src packages/modules/insights/backend/src/insights-by-period.repository.ts:522-578
-- @style TypeORM query builder (? positional on SQLite); SQL reconstructed from the builder calls; periodUnit day for a Europe/Berlin caller (SQLite fallback: fixed +120 min offset, getPeriodStartExpr line 175)
-- @tags hotpath,dynamic
-- @note Insights chart: date maths (strftime of a datetime shifted by the caller offset) as SELECT, GROUP BY and ORDER BY expression, four SUM(CASE) series, project filter. reconstructed from ORM code (TypeORM SelectQueryBuilder with addCommonTableExpression; the date_ranges CTE text is getDateRangesSelectQuery, insights-by-period-query.helper.ts:79).
-- @param ?1 'p000000000000041'
WITH "date_ranges" AS (SELECT
			'2026-10-13 00:00:00.000' AS prev_start_date,
			'2026-10-20 00:00:00.000' AS start_date,
			'2026-10-27 00:00:00.000' AS end_date
	) SELECT strftime('%Y-%m-%d %H:%M:%f', datetime(strftime('%Y-%m-%d 00:00:00', periodStart, '120 minutes'), '-120 minutes')) as "periodStart", SUM(CASE WHEN "insights"."type" = 0 THEN value ELSE 0 END) AS "timeSaved", SUM(CASE WHEN "insights"."type" = 1 THEN value ELSE 0 END) AS "runTime", SUM(CASE WHEN "insights"."type" = 2 THEN value ELSE 0 END) AS "succeeded", SUM(CASE WHEN "insights"."type" = 3 THEN value ELSE 0 END) AS "failed" FROM "insights_by_period" "insights" INNER JOIN "date_ranges" "date_ranges" ON 1=1 INNER JOIN "insights_metadata" "metadata" ON "metadata"."metaId"="insights"."metaId" WHERE "periodStart" >= date_ranges.start_date AND "periodStart" < date_ranges.end_date AND "metadata"."projectId" = ?1 GROUP BY strftime('%Y-%m-%d %H:%M:%f', datetime(strftime('%Y-%m-%d 00:00:00', periodStart, '120 minutes'), '-120 minutes')) ORDER BY strftime('%Y-%m-%d %H:%M:%f', datetime(strftime('%Y-%m-%d 00:00:00', periodStart, '120 minutes'), '-120 minutes')) ASC;

-- @id n8n.insights.by_time_week
-- @src packages/modules/insights/backend/src/insights-by-period.repository.ts:522-578
-- @style TypeORM query builder (? positional on SQLite); SQL reconstructed from the builder calls; periodUnit week, no caller time zone, instance-wide (no project/access filter)
-- @tags hotpath,dynamic
-- @note Insights chart by week over 90 days: date(periodStart, '-6 days', 'weekday 1') bucketing in SELECT/GROUP BY/ORDER BY. reconstructed from ORM code (TypeORM SelectQueryBuilder with addCommonTableExpression; the date_ranges CTE text is getDateRangesSelectQuery, insights-by-period-query.helper.ts:79).
WITH "date_ranges" AS (SELECT
			'2026-05-02 00:00:00.000' AS prev_start_date,
			'2026-07-30 00:00:00.000' AS start_date,
			'2026-10-28 00:00:00.000' AS end_date
	) SELECT strftime('%Y-%m-%d 00:00:00.000', date(periodStart, '-6 days', 'weekday 1')) as "periodStart", SUM(CASE WHEN "insights"."type" = 0 THEN value ELSE 0 END) AS "timeSaved", SUM(CASE WHEN "insights"."type" = 1 THEN value ELSE 0 END) AS "runTime", SUM(CASE WHEN "insights"."type" = 2 THEN value ELSE 0 END) AS "succeeded", SUM(CASE WHEN "insights"."type" = 3 THEN value ELSE 0 END) AS "failed" FROM "insights_by_period" "insights" INNER JOIN "date_ranges" "date_ranges" ON 1=1 WHERE "periodStart" >= date_ranges.start_date AND "periodStart" < date_ranges.end_date GROUP BY strftime('%Y-%m-%d 00:00:00.000', date(periodStart, '-6 days', 'weekday 1')) ORDER BY strftime('%Y-%m-%d 00:00:00.000', date(periodStart, '-6 days', 'weekday 1')) ASC;

-- @id n8n.insights.daily_billable
-- @src packages/modules/insights/backend/src/insights-by-period.repository.ts:580-608
-- @style TypeORM query builder (? positional on SQLite); SQL reconstructed from the builder calls; UTC bucketing (offset 0)
-- @tags dynamic
-- @note Daily billable executions for licensing: day bucketing through strftime/datetime with a zero offset, type = 4 filter. reconstructed from ORM code (TypeORM SelectQueryBuilder with addCommonTableExpression; the date_ranges CTE text is getDateRangesSelectQuery, insights-by-period-query.helper.ts:79).
WITH "date_ranges" AS (SELECT
			'2026-05-02 00:00:00.000' AS prev_start_date,
			'2026-07-30 00:00:00.000' AS start_date,
			'2026-10-28 00:00:00.000' AS end_date
	) SELECT strftime('%Y-%m-%d %H:%M:%f', datetime(strftime('%Y-%m-%d 00:00:00', periodStart, '0 minutes'), '0 minutes')) as "periodStart", SUM(value) AS "billable" FROM "insights_by_period" "insights" INNER JOIN "date_ranges" "date_ranges" ON 1=1 WHERE "periodStart" >= date_ranges.start_date AND "periodStart" < date_ranges.end_date AND "insights"."type" = 4 GROUP BY strftime('%Y-%m-%d %H:%M:%f', datetime(strftime('%Y-%m-%d 00:00:00', periodStart, '0 minutes'), '0 minutes')) ORDER BY strftime('%Y-%m-%d %H:%M:%f', datetime(strftime('%Y-%m-%d 00:00:00', periodStart, '0 minutes'), '0 minutes')) ASC;

-- @id n8n.insights.compaction_batch_hour_to_day
-- @src packages/modules/insights/backend/src/insights-by-period.repository.ts:222-246
-- @style TypeORM SelectQueryBuilder; threshold inlined as date('now', '-90 days') (getPeriodFilterExpr)
-- @tags dynamic
-- @note Compaction batch picker: hourly rows older than date('now', '-90 days'), oldest first, LIMIT 500 (the CREATE TEMPORARY TABLE ... AS body). Reconstructed from ORM code.
SELECT "id", "metaId", "type", "periodStart", "value" FROM "insights_by_period" "InsightsByPeriod" WHERE "periodUnit" = 0 AND "periodStart" < date('now', '-90 days') ORDER BY "periodStart" ASC LIMIT 500;

-- @id n8n.insights.compaction_upsert_hour
-- @src packages/modules/insights/backend/src/insights-by-period.repository.ts:304-343
-- @style raw sql`` template around a TypeORM aggregation builder (getAggregationQuery, line 248); periodUnit hour
-- @tags batch,dynamic
-- @note Compaction write: INSERT ... SELECT with GROUP BY on a strftime() bucket, ON CONFLICT(4-column unique key) DO UPDATE SET value = value + excluded.value RETURNING *. rows_to_compact is the app's per-transaction temp table, materialised by data.sql.
INSERT INTO insights_by_period
					("metaId", "type", "periodUnit", "periodStart", value)
				SELECT "metaId", "type", 0 AS "periodUnit", strftime('%Y-%m-%d %H:00:00.000', periodStart) AS "periodStart", SUM("value") AS "value" FROM "rows_to_compact" "rtc" GROUP BY "metaId", "type", strftime('%Y-%m-%d %H:00:00.000', periodStart)
			
				ON CONFLICT("metaId", "type", "periodUnit", "periodStart")
				DO UPDATE SET value = insights_by_period.value + excluded.value
				RETURNING *;

-- @id n8n.insights.compaction_delete_raw
-- @src packages/modules/insights/backend/src/insights-by-period.repository.ts:322-326
-- @style raw sql`` template
-- @tags batch
-- @note Compaction cleanup: delete the compacted source rows by IN (SELECT id FROM rows_to_compact).
DELETE FROM insights_raw
				WHERE id IN (SELECT id FROM rows_to_compact);

-- @id n8n.insights.raw_insert_batch
-- @src packages/modules/insights/backend/src/insights-collection.service.ts:304
-- @style TypeORM Repository.insert(events[]) -> one multi-row INSERT
-- @tags batch
-- @note Buffered insights flush: multi-row VALUES insert of execution events. Reconstructed from ORM code.
-- @param ?1 31
-- @param ?2 2
-- @param ?3 1
-- @param ?4 '2026-10-28 00:00:01.000'
-- @param ?5 31
-- @param ?6 1
-- @param ?7 842
-- @param ?8 '2026-10-28 00:00:01.000'
-- @param ?9 31
-- @param ?10 0
-- @param ?11 5
-- @param ?12 '2026-10-28 00:00:01.000'
-- @param ?13 61
-- @param ?14 3
-- @param ?15 1
-- @param ?16 '2026-10-28 00:00:02.000'
-- @param ?17 61
-- @param ?18 1
-- @param ?19 120
-- @param ?20 '2026-10-28 00:00:02.000'
-- @param ?21 61
-- @param ?22 4
-- @param ?23 1
-- @param ?24 '2026-10-28 00:00:02.000'
INSERT INTO "insights_raw"("metaId", "type", "value", "timestamp") VALUES (?1, ?2, ?3, ?4), (?5, ?6, ?7, ?8), (?9, ?10, ?11, ?12), (?13, ?14, ?15, ?16), (?17, ?18, ?19, ?20), (?21, ?22, ?23, ?24);

-- @id n8n.insights.metadata_upsert
-- @src packages/modules/insights/backend/src/insights-metadata.repository.ts:12-16
-- @style TypeORM Repository.upsert(rows, ['workflowId'])
-- @tags hot-small
-- @note Before each flush: keep workflow/project names current, INSERT ... ON CONFLICT (workflowId) DO UPDATE SET from EXCLUDED. Reconstructed from ORM code.
-- @param ?1 'wf00000000000031'
-- @param ?2 'p000000000000041'
-- @param ?3 'Sync CRM contacts #31 (renamed)'
-- @param ?4 'Team 1'
INSERT INTO "insights_metadata"("metaId", "workflowId", "projectId", "workflowName", "projectName") VALUES (NULL, ?1, ?2, ?3, ?4) ON CONFLICT ( "workflowId" ) DO UPDATE SET "workflowId" = EXCLUDED."workflowId", "projectId" = EXCLUDED."projectId", "workflowName" = EXCLUDED."workflowName", "projectName" = EXCLUDED."projectName";

-- @id n8n.insights.prune_old
-- @src packages/modules/insights/backend/src/insights-by-period.repository.ts:623-630
-- @style TypeORM Repository.delete({ periodStart: LessThanOrEqual(threshold) })
-- @note Insights retention: range delete on periodStart. Reconstructed from ORM code.
-- @param ?1 '2025-10-28 00:00:00.000'
DELETE FROM "insights_by_period" WHERE "periodStart" <= ?1;
