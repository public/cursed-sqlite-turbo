-- n8n-io/n8n @ 02cb18e19c8626adbc2d50122a71e7cb230dd856 (Sustainable Use License)
-- Final-state SQLite DDL for the tables the queries use, reconstructed from the TypeORM entities in
-- packages/@n8n/db/src/entities/*.ts (columns, @Index decorators) and the migrations under
-- packages/@n8n/db/src/migrations/{sqlite,common} (column types, defaults, insights tables:
-- common/1741167584277-RenameAnalyticsToInsights.ts, 1759399811000-ChangeValueTypesForInsights.ts,
-- 1784000000004-AddInsightsRawTimestampIdIndex.ts). Index names follow the migrations where one exists.
-- Only the CREATE statements the queries need; the original files are fetched by tools/fetch.sh.

CREATE TABLE "project" (
  "id" varchar(36) PRIMARY KEY NOT NULL,
  "name" varchar(255) NOT NULL,
  "type" varchar(36) NOT NULL,
  "createdAt" datetime(3) NOT NULL DEFAULT (STRFTIME('%Y-%m-%d %H:%M:%f', 'NOW')),
  "updatedAt" datetime(3) NOT NULL DEFAULT (STRFTIME('%Y-%m-%d %H:%M:%f', 'NOW')),
  "icon" text,
  "description" varchar(512),
  "creatorId" varchar,
  "customTelemetryTags" text NOT NULL DEFAULT '[]'
);

CREATE TABLE "project_relation" (
  "projectId" varchar(36) NOT NULL,
  "userId" varchar NOT NULL,
  "role" varchar NOT NULL,
  "createdAt" datetime(3) NOT NULL DEFAULT (STRFTIME('%Y-%m-%d %H:%M:%f', 'NOW')),
  "updatedAt" datetime(3) NOT NULL DEFAULT (STRFTIME('%Y-%m-%d %H:%M:%f', 'NOW')),
  PRIMARY KEY ("projectId", "userId"),
  FOREIGN KEY ("projectId") REFERENCES "project" ("id") ON DELETE CASCADE
);
CREATE INDEX "IDX_5f0643f6717905a05164090dde" ON "project_relation" ("userId");
CREATE INDEX "IDX_61448d56d61802b5dfde5cdb00" ON "project_relation" ("projectId");
CREATE INDEX "IDX_project_relation_role" ON "project_relation" ("role");

CREATE TABLE "folder" (
  "id" varchar(36) PRIMARY KEY NOT NULL,
  "name" varchar(128) NOT NULL,
  "parentFolderId" varchar(36),
  "projectId" varchar(36) NOT NULL,
  "createdAt" datetime(3) NOT NULL DEFAULT (STRFTIME('%Y-%m-%d %H:%M:%f', 'NOW')),
  "updatedAt" datetime(3) NOT NULL DEFAULT (STRFTIME('%Y-%m-%d %H:%M:%f', 'NOW')),
  FOREIGN KEY ("projectId") REFERENCES "project" ("id") ON DELETE CASCADE,
  FOREIGN KEY ("parentFolderId") REFERENCES "folder" ("id") ON DELETE CASCADE
);
CREATE UNIQUE INDEX "IDX_14f68deffaf858465715995508" ON "folder" ("projectId", "id");

CREATE TABLE "workflow_entity" (
  "id" varchar(36) PRIMARY KEY NOT NULL,
  "name" varchar(128) NOT NULL,
  "active" boolean NOT NULL,
  "nodes" text NOT NULL,
  "connections" text NOT NULL,
  "createdAt" datetime(3) NOT NULL DEFAULT (STRFTIME('%Y-%m-%d %H:%M:%f', 'NOW')),
  "updatedAt" datetime(3) NOT NULL DEFAULT (STRFTIME('%Y-%m-%d %H:%M:%f', 'NOW')),
  "settings" text,
  "staticData" text,
  "pinData" text,
  "versionId" char(36),
  "triggerCount" integer NOT NULL DEFAULT 0,
  "meta" text,
  "parentFolderId" varchar(36) DEFAULT NULL,
  "isArchived" boolean NOT NULL DEFAULT (FALSE),
  "versionCounter" integer NOT NULL DEFAULT 1,
  "description" text,
  "activeVersionId" varchar(36),
  "nodeGroups" text NOT NULL DEFAULT '[]',
  FOREIGN KEY ("parentFolderId") REFERENCES "folder" ("id") ON DELETE CASCADE
);
CREATE UNIQUE INDEX "IDX_943d8f922be094eb507cb9a7f9" ON "workflow_entity" ("name");

CREATE TABLE "shared_workflow" (
  "workflowId" varchar(36) NOT NULL,
  "projectId" varchar(36) NOT NULL,
  "role" text NOT NULL,
  "createdAt" datetime(3) NOT NULL DEFAULT (STRFTIME('%Y-%m-%d %H:%M:%f', 'NOW')),
  "updatedAt" datetime(3) NOT NULL DEFAULT (STRFTIME('%Y-%m-%d %H:%M:%f', 'NOW')),
  PRIMARY KEY ("workflowId", "projectId"),
  FOREIGN KEY ("workflowId") REFERENCES "workflow_entity" ("id") ON DELETE CASCADE,
  FOREIGN KEY ("projectId") REFERENCES "project" ("id") ON DELETE CASCADE
);
CREATE INDEX "idx_shared_workflow_workflow_id" ON "shared_workflow" ("workflowId");
CREATE INDEX "IDX_shared_workflow_projectId" ON "shared_workflow" ("projectId");

CREATE TABLE "tag_entity" (
  "id" varchar(36) PRIMARY KEY NOT NULL,
  "name" varchar(24) NOT NULL,
  "createdAt" datetime(3) NOT NULL DEFAULT (STRFTIME('%Y-%m-%d %H:%M:%f', 'NOW')),
  "updatedAt" datetime(3) NOT NULL DEFAULT (STRFTIME('%Y-%m-%d %H:%M:%f', 'NOW'))
);
CREATE UNIQUE INDEX "IDX_8f949d7a3a984759044054e89b" ON "tag_entity" ("name");

CREATE TABLE "workflows_tags" (
  "workflowId" varchar(36) NOT NULL,
  "tagId" varchar(36) NOT NULL,
  PRIMARY KEY ("workflowId", "tagId"),
  FOREIGN KEY ("workflowId") REFERENCES "workflow_entity" ("id") ON DELETE CASCADE,
  FOREIGN KEY ("tagId") REFERENCES "tag_entity" ("id") ON DELETE CASCADE
);
CREATE INDEX "idx_workflows_tags_workflow_id" ON "workflows_tags" ("workflowId");
CREATE INDEX "idx_workflows_tags_tag_id" ON "workflows_tags" ("tagId");

CREATE TABLE "execution_entity" (
  "id" integer PRIMARY KEY AUTOINCREMENT NOT NULL,
  "workflowId" varchar(36) NOT NULL,
  "finished" boolean NOT NULL,
  "mode" varchar NOT NULL,
  "retryOf" varchar,
  "retrySuccessId" varchar,
  "startedAt" datetime,
  "stoppedAt" datetime,
  "waitTill" datetime,
  "status" varchar NOT NULL,
  "deletedAt" datetime(3),
  "createdAt" datetime(3) NOT NULL DEFAULT (STRFTIME('%Y-%m-%d %H:%M:%f', 'NOW')),
  "storedAt" varchar(2) NOT NULL DEFAULT 'db' CHECK ("storedAt" IN ('db', 'fs', 's3', 'az')),
  "tracingContext" text,
  "deduplicationKey" varchar(255),
  "jsonSizeBytes" bigint NOT NULL DEFAULT 0,
  "workflowVersionId" varchar(36),
  "binaryDataSizeBytes" bigint NOT NULL DEFAULT 0,
  "usedPrivateCredentials" boolean NOT NULL DEFAULT FALSE,
  FOREIGN KEY ("workflowId") REFERENCES "workflow_entity" ("id") ON DELETE CASCADE
);
CREATE INDEX "IDX_81fc04c8a17de15835713505e4" ON "execution_entity" ("workflowId", "id");
CREATE INDEX "IDX_b94b45ce2c73ce46c54f20b5f9" ON "execution_entity" ("waitTill", "id");
CREATE INDEX "IDX_1688846335d274033e15c846a4" ON "execution_entity" ("finished", "id");
CREATE INDEX "IDX_78d62b89dc1433192b86dce18a" ON "execution_entity" ("workflowId", "finished", "id");
CREATE INDEX "IDX_06da892aaf92a48e7d3e400003" ON "execution_entity" ("workflowId", "waitTill", "id");
CREATE INDEX "IDX_execution_entity_workflowId_status_id" ON "execution_entity" ("workflowId", "status", "id") WHERE "deletedAt" IS NULL;
CREATE UNIQUE INDEX "IDX_execution_entity_deduplicationKey" ON "execution_entity" ("deduplicationKey") WHERE "deduplicationKey" IS NOT NULL;
CREATE INDEX "IDX_cefb067df2402f6aed0638a6c1" ON "execution_entity" ("stoppedAt");

CREATE TABLE "execution_data" (
  "executionId" int PRIMARY KEY NOT NULL,
  "workflowData" text NOT NULL,
  "data" text NOT NULL,
  "workflowVersionId" varchar(36),
  FOREIGN KEY ("executionId") REFERENCES "execution_entity" ("id") ON DELETE CASCADE
);

CREATE TABLE "execution_metadata" (
  "id" integer PRIMARY KEY AUTOINCREMENT NOT NULL,
  "executionId" integer NOT NULL,
  "key" varchar(255) NOT NULL,
  "value" text NOT NULL,
  FOREIGN KEY ("executionId") REFERENCES "execution_entity" ("id") ON DELETE CASCADE
);
CREATE UNIQUE INDEX "IDX_cec8eea3bf49551482ccb4933e" ON "execution_metadata" ("executionId", "key");

CREATE TABLE "annotation_tag_entity" (
  "id" varchar(16) PRIMARY KEY NOT NULL,
  "name" varchar(24) NOT NULL,
  "createdAt" datetime(3) NOT NULL DEFAULT (STRFTIME('%Y-%m-%d %H:%M:%f', 'NOW')),
  "updatedAt" datetime(3) NOT NULL DEFAULT (STRFTIME('%Y-%m-%d %H:%M:%f', 'NOW'))
);
CREATE UNIQUE INDEX "IDX_ae51b54c4bb430cf92f48b623f" ON "annotation_tag_entity" ("name");

CREATE TABLE "execution_annotations" (
  "id" integer PRIMARY KEY AUTOINCREMENT NOT NULL,
  "executionId" integer NOT NULL,
  "vote" varchar(6),
  "note" text,
  "createdAt" datetime(3) NOT NULL DEFAULT (STRFTIME('%Y-%m-%d %H:%M:%f', 'NOW')),
  "updatedAt" datetime(3) NOT NULL DEFAULT (STRFTIME('%Y-%m-%d %H:%M:%f', 'NOW')),
  FOREIGN KEY ("executionId") REFERENCES "execution_entity" ("id") ON DELETE CASCADE
);
CREATE UNIQUE INDEX "IDX_97f863fa83c4786f1956508496" ON "execution_annotations" ("executionId");

CREATE TABLE "execution_annotation_tags" (
  "annotationId" integer NOT NULL,
  "tagId" varchar(24) NOT NULL,
  PRIMARY KEY ("annotationId", "tagId"),
  FOREIGN KEY ("annotationId") REFERENCES "execution_annotations" ("id") ON DELETE CASCADE,
  FOREIGN KEY ("tagId") REFERENCES "annotation_tag_entity" ("id") ON DELETE CASCADE
);
CREATE INDEX "IDX_c1519757391996eb06064f0e7c" ON "execution_annotation_tags" ("annotationId");
CREATE INDEX "IDX_a3697779b366e131b2bbdae297" ON "execution_annotation_tags" ("tagId");

CREATE TABLE "webhook_entity" (
  "workflowId" varchar(36) NOT NULL,
  "webhookPath" varchar NOT NULL,
  "method" varchar NOT NULL,
  "node" varchar NOT NULL,
  "webhookId" varchar,
  "pathLength" integer,
  PRIMARY KEY ("webhookPath", "method")
);
CREATE INDEX "idx_webhook_entity_webhook_path_method" ON "webhook_entity" ("webhookId", "method", "pathLength");

CREATE TABLE "insights_metadata" (
  "metaId" integer PRIMARY KEY AUTOINCREMENT NOT NULL,
  "workflowId" varchar(16),
  "projectId" varchar(36),
  "workflowName" varchar(128) NOT NULL,
  "projectName" varchar(255) NOT NULL,
  FOREIGN KEY ("workflowId") REFERENCES "workflow_entity" ("id") ON DELETE SET NULL,
  FOREIGN KEY ("projectId") REFERENCES "project" ("id") ON DELETE SET NULL
);
CREATE UNIQUE INDEX "IDX_1d8ab99d5861c9388d2dc1cf73" ON "insights_metadata" ("workflowId");

CREATE TABLE "insights_raw" (
  "id" integer PRIMARY KEY AUTOINCREMENT NOT NULL,
  "metaId" integer NOT NULL,
  "type" integer NOT NULL,
  "value" bigint NOT NULL,
  "timestamp" datetime(0) NOT NULL DEFAULT (CURRENT_TIMESTAMP),
  FOREIGN KEY ("metaId") REFERENCES "insights_metadata" ("metaId") ON DELETE CASCADE
);
CREATE INDEX "IDX_insights_raw_timestamp_id" ON "insights_raw" ("timestamp", "id");

CREATE TABLE "insights_by_period" (
  "id" integer PRIMARY KEY AUTOINCREMENT NOT NULL,
  "metaId" integer NOT NULL,
  "type" integer NOT NULL,
  "value" bigint NOT NULL,
  "periodUnit" integer NOT NULL,
  "periodStart" datetime(0) DEFAULT (CURRENT_TIMESTAMP),
  FOREIGN KEY ("metaId") REFERENCES "insights_metadata" ("metaId") ON DELETE CASCADE
);
CREATE UNIQUE INDEX "IDX_60b6a84299eeb3f671dfec7693" ON "insights_by_period" ("periodStart", "type", "periodUnit", "metaId");
