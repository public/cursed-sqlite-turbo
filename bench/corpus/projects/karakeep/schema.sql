-- Karakeep (karakeep-app/karakeep @ 2bb411f9, AGPL-3.0): only the CREATE statements the queries need.
-- Produced by applying every drizzle migration (packages/db/drizzle/0000-0095*.sql) to an empty database and
-- dumping the resulting tables with .schema, so ALTER TABLE ADD COLUMN history is folded in. Indexes are the app's own.
-- Source files: packages/db/schema.ts and packages/db/drizzle/*.sql (fetched by tools/fetch.sh, not vendored).

CREATE TABLE `user` (
	`id` text PRIMARY KEY NOT NULL,
	`name` text NOT NULL,
	`email` text NOT NULL,
	`emailVerified` integer,
	`image` text,
	`role` text DEFAULT 'user', `bookmarkQuota` integer, `storageQuota` integer, `browserCrawlingEnabled` integer, `bookmarkClickAction` text DEFAULT 'open_original_link' NOT NULL, `archiveDisplayBehaviour` text DEFAULT 'show' NOT NULL, `timezone` text DEFAULT 'UTC', `backupsEnabled` integer DEFAULT false NOT NULL, `backupsFrequency` text DEFAULT 'weekly' NOT NULL, `backupsRetentionDays` integer DEFAULT 30 NOT NULL, `readerFontSize` integer, `readerLineHeight` real, `readerFontFamily` text, `autoTaggingEnabled` integer, `autoSummarizationEnabled` integer, `inferredTagLang` text, `tagStyle` text DEFAULT 'titlecase-spaces', `curatedTagIds` text, `manualTierName` text, `createdAt` integer, `updatedAt` integer);
CREATE UNIQUE INDEX `user_email_unique` ON `user` (`email`);

CREATE TABLE `bookmarks` (
	`id` text PRIMARY KEY NOT NULL,
	`createdAt` integer NOT NULL,
	`archived` integer DEFAULT false NOT NULL,
	`favourited` integer DEFAULT false NOT NULL,
	`userId` text NOT NULL, `taggingStatus` text DEFAULT 'pending', `note` text, `title` text, `type` text NOT NULL DEFAULT "text", `summary` text, `modifiedAt` integer, `summarizationStatus` text DEFAULT 'pending', `source` text, `embeddingStatus` text DEFAULT 'pending', `lastSavedAt` integer NOT NULL DEFAULT 0,
	FOREIGN KEY (`userId`) REFERENCES `user`(`id`) ON UPDATE no action ON DELETE cascade
);
CREATE INDEX `bookmarks_userId_lastSavedAt_id_idx` ON `bookmarks` (`userId`,`lastSavedAt`,`id`);
CREATE INDEX `bookmarks_userId_archived_lastSavedAt_id_idx` ON `bookmarks` (`userId`,`archived`,`lastSavedAt`,`id`);
CREATE INDEX `bookmarks_userId_favourited_lastSavedAt_id_idx` ON `bookmarks` (`userId`,`favourited`,`lastSavedAt`,`id`);
CREATE INDEX `bookmarks_lastSavedAt_idx` ON `bookmarks` (`lastSavedAt`);

CREATE TABLE `bookmarkLinks` (
	`id` text PRIMARY KEY NOT NULL,
	`url` text NOT NULL,
	`title` text,
	`description` text,
	`imageUrl` text,
	`favicon` text,
	`crawledAt` integer, `htmlContent` text, `crawlStatus` text DEFAULT 'pending', `crawlStatusCode` integer DEFAULT 200, `author` text, `publisher` text, `datePublished` integer, `dateModified` integer, `contentAssetId` text, `probeMetadataAt` integer, `readerViewStatus` text, `readerViewScore` integer, `readerViewReasons` text, `readerViewClassifierVersion` integer,
	FOREIGN KEY (`id`) REFERENCES `bookmarks`(`id`) ON UPDATE no action ON DELETE cascade
);
CREATE INDEX `bookmarkLinks_url_idx` ON `bookmarkLinks` (`url`);

CREATE TABLE `bookmarkTexts` (
	`id` text PRIMARY KEY NOT NULL,
	`text` text, `sourceUrl` text,
	FOREIGN KEY (`id`) REFERENCES `bookmarks`(`id`) ON UPDATE no action ON DELETE cascade
);

CREATE TABLE "bookmarkAssets" (
	`id` text PRIMARY KEY NOT NULL,
	`assetType` text NOT NULL,
	`assetId` text NOT NULL, `content` text, `metadata` text, `fileName` text, `sourceUrl` text,
	FOREIGN KEY (`id`) REFERENCES `bookmarks`(`id`) ON UPDATE no action ON DELETE cascade
);

CREATE TABLE `bookmarkTags` (
	`id` text PRIMARY KEY NOT NULL,
	`name` text NOT NULL,
	`createdAt` integer NOT NULL,
	`userId` text NOT NULL, `normalizedName` text GENERATED ALWAYS AS (lower(replace(replace(replace("name", ' ', ''), '-', ''), '_', ''))) VIRTUAL,
	FOREIGN KEY (`userId`) REFERENCES `user`(`id`) ON UPDATE no action ON DELETE cascade
);
CREATE UNIQUE INDEX `bookmarkTags_userId_name_unique` ON `bookmarkTags` (`userId`,`name`);
CREATE INDEX `bookmarkTags_name_idx` ON `bookmarkTags` (`name`);
CREATE UNIQUE INDEX `bookmarkTags_userId_id_idx` ON `bookmarkTags` (`userId`,`id`);
CREATE INDEX `bookmarkTags_normalizedName_idx` ON `bookmarkTags` (`normalizedName`);

CREATE TABLE `tagsOnBookmarks` (
	`bookmarkId` text NOT NULL,
	`tagId` text NOT NULL,
	`attachedAt` text,
	`attachedBy` text,
	PRIMARY KEY(`bookmarkId`, `tagId`),
	FOREIGN KEY (`bookmarkId`) REFERENCES `bookmarks`(`id`) ON UPDATE no action ON DELETE cascade,
	FOREIGN KEY (`tagId`) REFERENCES `bookmarkTags`(`id`) ON UPDATE no action ON DELETE cascade
);
CREATE INDEX `tagsOnBookmarks_tagId_bookmarkId_idx` ON `tagsOnBookmarks` (`tagId`,`bookmarkId`);

CREATE TABLE `bookmarkLists` (
	`id` text PRIMARY KEY NOT NULL,
	`name` text NOT NULL,
	`icon` text NOT NULL,
	`createdAt` integer NOT NULL,
	`userId` text NOT NULL, `parentId` text REFERENCES bookmarkLists(id) ON DELETE SET NULL, `type` text NOT NULL DEFAULT "manual", `query` text, `description` text, `rssToken` text, `public` integer DEFAULT false NOT NULL,
	FOREIGN KEY (`userId`) REFERENCES `user`(`id`) ON UPDATE no action ON DELETE cascade
);
CREATE INDEX `bookmarkLists_userId_idx` ON `bookmarkLists` (`userId`);
CREATE UNIQUE INDEX `bookmarkLists_userId_id_idx` ON `bookmarkLists` (`userId`,`id`);

CREATE TABLE `listCollaborators` (
	`id` text PRIMARY KEY NOT NULL,
	`listId` text NOT NULL,
	`userId` text NOT NULL,
	`role` text NOT NULL,
	`createdAt` integer NOT NULL,
	`addedBy` text,
	FOREIGN KEY (`listId`) REFERENCES `bookmarkLists`(`id`) ON UPDATE no action ON DELETE cascade,
	FOREIGN KEY (`userId`) REFERENCES `user`(`id`) ON UPDATE no action ON DELETE cascade,
	FOREIGN KEY (`addedBy`) REFERENCES `user`(`id`) ON UPDATE no action ON DELETE set null
);
CREATE INDEX `listCollaborators_listId_idx` ON `listCollaborators` (`listId`);
CREATE INDEX `listCollaborators_userId_idx` ON `listCollaborators` (`userId`);
CREATE UNIQUE INDEX `listCollaborators_listId_userId_unique` ON `listCollaborators` (`listId`,`userId`);

CREATE TABLE `bookmarksInLists` (
	`bookmarkId` text NOT NULL,
	`listId` text NOT NULL,
	`addedAt` integer, `listMembershipId` text REFERENCES listCollaborators(id) ON UPDATE no action ON DELETE cascade,
	PRIMARY KEY(`bookmarkId`, `listId`),
	FOREIGN KEY (`bookmarkId`) REFERENCES `bookmarks`(`id`) ON UPDATE no action ON DELETE cascade,
	FOREIGN KEY (`listId`) REFERENCES `bookmarkLists`(`id`) ON UPDATE no action ON DELETE cascade
);
CREATE INDEX `bookmarksInLists_listId_bookmarkId_idx` ON `bookmarksInLists` (`listId`,`bookmarkId`);

CREATE TABLE `highlights` (
	`id` text PRIMARY KEY NOT NULL,
	`bookmarkId` text NOT NULL,
	`userId` text NOT NULL,
	`startOffset` integer NOT NULL,
	`endOffset` integer NOT NULL,
	`color` text DEFAULT 'yellow' NOT NULL,
	`note` text,
	`createdAt` integer NOT NULL, `text` text,
	FOREIGN KEY (`bookmarkId`) REFERENCES `bookmarks`(`id`) ON UPDATE no action ON DELETE cascade,
	FOREIGN KEY (`userId`) REFERENCES `user`(`id`) ON UPDATE no action ON DELETE cascade
);
CREATE INDEX `highlights_bookmarkId_idx` ON `highlights` (`bookmarkId`);
CREATE INDEX `highlights_userId_idx` ON `highlights` (`userId`);

CREATE TABLE "assets" (
        `id` text PRIMARY KEY NOT NULL,
        `assetType` text NOT NULL,
        `bookmarkId` text,
		`userId` text NOT NULL, `size` integer DEFAULT 0 NOT NULL, `contentType` text, `fileName` text,
        FOREIGN KEY (`bookmarkId`) REFERENCES `bookmarks`(`id`) ON UPDATE no action ON DELETE cascade
        FOREIGN KEY (`userId`) REFERENCES `user`(`id`) ON UPDATE no action ON DELETE cascade
);
CREATE INDEX `assets_bookmarkId_idx` ON `assets` (`bookmarkId`);
CREATE INDEX `assets_assetType_idx` ON `assets` (`assetType`);
CREATE INDEX `assets_userId_idx` ON `assets` (`userId`);
