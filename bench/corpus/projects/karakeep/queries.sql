-- Karakeep (karakeep-app/karakeep @ 2bb411f9, AGPL-3.0). Drizzle ORM on SQLite (better-sqlite3).
-- Every statement was compiled with drizzle's .toSQL() from the real query builders: schema.ts and lib/search.ts copied
-- verbatim from the pinned SHA, smart-list queries parsed with the app's own searchQueryParser.ts, the model code
-- (lists.ts, bookmarks.ts, tags.ts, users.ts, admin.ts, highlights.repo.ts) transcribed call for call into a scratch
-- package pinned to drizzle-orm 0.45.4 (the lockfile's version). Drizzle binds positionally (?); they are numbered ?N in
-- order. Timestamps are epoch seconds; the data is anchored at 1790000000 (now). The drizzle field bookmarks.createdAt
-- maps to the lastSavedAt column.

-- @id karakeep.lists.stats.manual_sizes
-- @src packages/trpc/models/lists.ts:348-379
-- @style drizzle query builder, .toSQL() for SQLite; ? positional (numbered here)
-- @tags analytics,hotpath,dynamic,cpu-evidence
-- @note lists.stats, manual part: one GROUP BY over bookmarksInLists for all 30 manual lists (IN list expanded). Runs on every sidebar render. https://github.com/karakeep-app/karakeep/issues/3088 Compiled with .toSQL() from the real drizzle builder (drizzle-orm 0.45.4, schema.ts + lib/search.ts copied from the pinned SHA, model code transcribed).
-- @param ?1 'l1'
-- @param ?2 'l2'
-- @param ?3 'l3'
-- @param ?4 'l4'
-- @param ?5 'l5'
-- @param ?6 'l6'
-- @param ?7 'l7'
-- @param ?8 'l8'
-- @param ?9 'l9'
-- @param ?10 'l10'
-- @param ?11 'l11'
-- @param ?12 'l12'
-- @param ?13 'l13'
-- @param ?14 'l14'
-- @param ?15 'l15'
-- @param ?16 'l16'
-- @param ?17 'l17'
-- @param ?18 'l18'
-- @param ?19 'l19'
-- @param ?20 'l20'
-- @param ?21 'l21'
-- @param ?22 'l22'
-- @param ?23 'l23'
-- @param ?24 'l24'
-- @param ?25 'l25'
-- @param ?26 'l26'
-- @param ?27 'l27'
-- @param ?28 'l28'
-- @param ?29 'l29'
-- @param ?30 'l30'
select "listId", count(*) from "bookmarksInLists" where "bookmarksInLists"."listId" in (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15, ?16, ?17, ?18, ?19, ?20, ?21, ?22, ?23, ?24, ?25, ?26, ?27, ?28, ?29, ?30) group by "bookmarksInLists"."listId";

-- @id karakeep.lists.stats.smart.single_tag
-- @src packages/trpc/models/lists.ts:1092-1103; lib/search.ts:68-83
-- @style drizzle query builder, .toSQL() for SQLite; ? positional (numbered here)
-- @tags analytics,hotpath,dynamic,cpu-evidence
-- @note lists.stats, smart list '#UI': SmartList.getSize count(*) with the tagName matcher as an IN (tagsOnBookmarks JOIN bookmarkTags) subquery, the form that replaced the slow correlated EXISTS. https://github.com/karakeep-app/karakeep/issues/3088 Compiled with .toSQL() from the real drizzle builder (drizzle-orm 0.45.4, schema.ts + lib/search.ts copied from the pinned SHA, model code transcribed).
-- @param ?1 'u1'
-- @param ?2 'u1'
-- @param ?3 'UI'
select count(*) from "bookmarks" where ("bookmarks"."userId" = ?1 and "bookmarks"."id" in (select "tagsOnBookmarks"."bookmarkId" from "tagsOnBookmarks" inner join "bookmarkTags" on "tagsOnBookmarks"."tagId" = "bookmarkTags"."id" where ("bookmarkTags"."userId" = ?2 and "bookmarkTags"."name" = ?3)));

-- @id karakeep.lists.stats.smart.tag_or_tag
-- @src packages/trpc/models/lists.ts:1092-1103; lib/search.ts:68-83,277-284
-- @style drizzle query builder, .toSQL() for SQLite; ? positional (numbered here)
-- @tags analytics,hotpath,dynamic,cpu-evidence
-- @note Smart list '#AI or #MachineLearning or #LLM': OR of three IN subqueries combined as a balanced tree (combineBalanced). https://github.com/karakeep-app/karakeep/issues/3088 Compiled with .toSQL() from the real drizzle builder (drizzle-orm 0.45.4, schema.ts + lib/search.ts copied from the pinned SHA, model code transcribed).
-- @param ?1 'u1'
-- @param ?2 'u1'
-- @param ?3 'AI'
-- @param ?4 'u1'
-- @param ?5 'MachineLearning'
-- @param ?6 'u1'
-- @param ?7 'LLM'
select count(*) from "bookmarks" where ("bookmarks"."userId" = ?1 and (("bookmarks"."id" in (select "tagsOnBookmarks"."bookmarkId" from "tagsOnBookmarks" inner join "bookmarkTags" on "tagsOnBookmarks"."tagId" = "bookmarkTags"."id" where ("bookmarkTags"."userId" = ?2 and "bookmarkTags"."name" = ?3)) or "bookmarks"."id" in (select "tagsOnBookmarks"."bookmarkId" from "tagsOnBookmarks" inner join "bookmarkTags" on "tagsOnBookmarks"."tagId" = "bookmarkTags"."id" where ("bookmarkTags"."userId" = ?4 and "bookmarkTags"."name" = ?5))) or "bookmarks"."id" in (select "tagsOnBookmarks"."bookmarkId" from "tagsOnBookmarks" inner join "bookmarkTags" on "tagsOnBookmarks"."tagId" = "bookmarkTags"."id" where ("bookmarkTags"."userId" = ?6 and "bookmarkTags"."name" = ?7))));

-- @id karakeep.lists.stats.smart.tag_and_not_tag
-- @src packages/trpc/models/lists.ts:1092-1103; lib/search.ts:68-83,269-276
-- @style drizzle query builder, .toSQL() for SQLite; ? positional (numbered here)
-- @tags analytics,hotpath,dynamic,cpu-evidence
-- @note Smart list '#Programming -#Archive': IN plus NOT IN over the tag join. https://github.com/karakeep-app/karakeep/issues/3088 Compiled with .toSQL() from the real drizzle builder (drizzle-orm 0.45.4, schema.ts + lib/search.ts copied from the pinned SHA, model code transcribed).
-- @param ?1 'u1'
-- @param ?2 'u1'
-- @param ?3 'Programming'
-- @param ?4 'u1'
-- @param ?5 'Archive'
select count(*) from "bookmarks" where ("bookmarks"."userId" = ?1 and ("bookmarks"."id" in (select "tagsOnBookmarks"."bookmarkId" from "tagsOnBookmarks" inner join "bookmarkTags" on "tagsOnBookmarks"."tagId" = "bookmarkTags"."id" where ("bookmarkTags"."userId" = ?2 and "bookmarkTags"."name" = ?3)) and "bookmarks"."id" not in (select "tagsOnBookmarks"."bookmarkId" from "tagsOnBookmarks" inner join "bookmarkTags" on "tagsOnBookmarks"."tagId" = "bookmarkTags"."id" where ("bookmarkTags"."userId" = ?4 and "bookmarkTags"."name" = ?5))));

-- @id karakeep.lists.stats.smart.fav_and_tag
-- @src packages/trpc/models/lists.ts:1092-1103; lib/search.ts:68-83,206-208
-- @style drizzle query builder, .toSQL() for SQLite; ? positional (numbered here)
-- @tags analytics,hotpath,dynamic,cpu-evidence
-- @note Smart list 'is:fav #Design': favourited = 1 AND IN tag subquery. https://github.com/karakeep-app/karakeep/issues/3088 Compiled with .toSQL() from the real drizzle builder (drizzle-orm 0.45.4, schema.ts + lib/search.ts copied from the pinned SHA, model code transcribed).
-- @param ?1 'u1'
-- @param ?2 1
-- @param ?3 'u1'
-- @param ?4 'Design'
select count(*) from "bookmarks" where ("bookmarks"."userId" = ?1 and ("bookmarks"."favourited" = ?2 and "bookmarks"."id" in (select "tagsOnBookmarks"."bookmarkId" from "tagsOnBookmarks" inner join "bookmarkTags" on "tagsOnBookmarks"."tagId" = "bookmarkTags"."id" where ("bookmarkTags"."userId" = ?3 and "bookmarkTags"."name" = ?4))));

-- @id karakeep.lists.stats.smart.recent_tag_not_archived
-- @src packages/trpc/models/lists.ts:1092-1103; lib/search.ts:68-83,151-153,232-235
-- @style drizzle query builder, .toSQL() for SQLite; ? positional (numbered here)
-- @tags analytics,hotpath,dynamic,cpu-evidence
-- @note Smart list 'age:<1y #News -is:archived': lastSavedAt >= now-1y (bound as a literal, now = 1790000000) AND tag IN AND archived = 0. https://github.com/karakeep-app/karakeep/issues/3088 Compiled with .toSQL() from the real drizzle builder (drizzle-orm 0.45.4, schema.ts + lib/search.ts copied from the pinned SHA, model code transcribed).
-- @param ?1 'u1'
-- @param ?2 1758464000
-- @param ?3 'u1'
-- @param ?4 'News'
-- @param ?5 0
select count(*) from "bookmarks" where ("bookmarks"."userId" = ?1 and (("bookmarks"."lastSavedAt" >= ?2 and "bookmarks"."id" in (select "tagsOnBookmarks"."bookmarkId" from "tagsOnBookmarks" inner join "bookmarkTags" on "tagsOnBookmarks"."tagId" = "bookmarkTags"."id" where ("bookmarkTags"."userId" = ?3 and "bookmarkTags"."name" = ?4))) and "bookmarks"."archived" = ?5));

-- @id karakeep.lists.stats.smart.url_or_title
-- @src packages/trpc/models/lists.ts:1092-1103; lib/search.ts:154-205
-- @style drizzle query builder, .toSQL() for SQLite; ? positional (numbered here)
-- @tags analytics,hotpath,dynamic
-- @note Smart list 'url:github.com or title:rust': two correlated EXISTS with LIKE '%..%' (links and assets) OR'd with a title LIKE and another correlated EXISTS; scans every bookmark of the user. Compiled with .toSQL() from the real drizzle builder (drizzle-orm 0.45.4, schema.ts + lib/search.ts copied from the pinned SHA, model code transcribed).
-- @param ?1 'u1'
-- @param ?2 '%github.com%'
-- @param ?3 '%github.com%'
-- @param ?4 '%rust%'
-- @param ?5 '%rust%'
select count(*) from "bookmarks" where ("bookmarks"."userId" = ?1 and ((exists (select "id", "url", "title", "description", "author", "publisher", "datePublished", "dateModified", "imageUrl", "favicon", "htmlContent", "contentAssetId", "readerViewStatus", "readerViewScore", "readerViewReasons", "readerViewClassifierVersion", "crawledAt", "crawlStatus", "crawlStatusCode", "probeMetadataAt" from "bookmarkLinks" where ("bookmarkLinks"."id" = "bookmarks"."id" and "bookmarkLinks"."url" like ?2)) or exists (select "id", "assetType", "assetId", "content", "metadata", "fileName", "sourceUrl" from "bookmarkAssets" where ("bookmarkAssets"."id" = "bookmarks"."id" and "bookmarkAssets"."sourceUrl" is not null and "bookmarkAssets"."sourceUrl" like ?3))) or ("bookmarks"."title" like ?4 or exists (select "id", "url", "title", "description", "author", "publisher", "datePublished", "dateModified", "imageUrl", "favicon", "htmlContent", "contentAssetId", "readerViewStatus", "readerViewScore", "readerViewReasons", "readerViewClassifierVersion", "crawledAt", "crawlStatus", "crawlStatusCode", "probeMetadataAt" from "bookmarkLinks" where ("bookmarkLinks"."id" = "bookmarks"."id" and "bookmarkLinks"."title" like ?5)))));

-- @id karakeep.lists.stats.smart.untagged
-- @src packages/trpc/models/lists.ts:1092-1103; lib/search.ts:84-92
-- @style drizzle query builder, .toSQL() for SQLite; ? positional (numbered here)
-- @tags analytics,hotpath,dynamic
-- @note Smart list '-is:tagged': NOT EXISTS over tagsOnBookmarks per bookmark. Compiled with .toSQL() from the real drizzle builder (drizzle-orm 0.45.4, schema.ts + lib/search.ts copied from the pinned SHA, model code transcribed).
-- @param ?1 'u1'
select count(*) from "bookmarks" where ("bookmarks"."userId" = ?1 and not exists (select "bookmarkId", "tagId", "attachedAt", "attachedBy" from "tagsOnBookmarks" where "tagsOnBookmarks"."bookmarkId" = "bookmarks"."id"));

-- @id karakeep.lists.stats.smart.has_highlights_in_list
-- @src packages/trpc/models/lists.ts:1092-1103; lib/search.ts:93-120,214-223
-- @style drizzle query builder, .toSQL() for SQLite; ? positional (numbered here)
-- @tags analytics,hotpath,dynamic
-- @note Smart list 'has:highlights list:Reading': highlights IN subquery AND the nested list's condition (ManualList.getBookmarksCondition, lists.ts:1152-1160). Compiled with .toSQL() from the real drizzle builder (drizzle-orm 0.45.4, schema.ts + lib/search.ts copied from the pinned SHA, model code transcribed).
-- @param ?1 'u1'
-- @param ?2 'u1'
-- @param ?3 'l3'
select count(*) from "bookmarks" where ("bookmarks"."userId" = ?1 and ("bookmarks"."id" in (select "bookmarkId" from "highlights" where "highlights"."userId" = ?2) and "bookmarks"."id" in (select "bookmarkId" from "bookmarksInLists" where "bookmarksInLists"."listId" = ?3)));

-- @id karakeep.lists.stats.smart.not_inlist_link_after
-- @src packages/trpc/models/lists.ts:1092-1103; lib/search.ts:121-129,224-227,236-239
-- @style drizzle query builder, .toSQL() for SQLite; ? positional (numbered here)
-- @tags analytics,hotpath,dynamic
-- @note Smart list '-is:inlist is:link after:2025-01-01': correlated NOT EXISTS over bookmarksInLists plus type and date filters. Compiled with .toSQL() from the real drizzle builder (drizzle-orm 0.45.4, schema.ts + lib/search.ts copied from the pinned SHA, model code transcribed).
-- @param ?1 'u1'
-- @param ?2 'link'
-- @param ?3 1735689600
select count(*) from "bookmarks" where ("bookmarks"."userId" = ?1 and ((not exists (select "bookmarkId", "listId", "addedAt", "listMembershipId" from "bookmarksInLists" where "bookmarksInLists"."bookmarkId" = "bookmarks"."id") and "bookmarks"."type" = ?2) and "bookmarks"."lastSavedAt" >= ?3));

-- @id karakeep.lists.stats.smart.single_tag_v0332
-- @src packages/trpc/lib/search.ts:68-83
-- @style drizzle query builder, .toSQL() for SQLite; ? positional (numbered here)
-- @tags analytics,dynamic,cpu-evidence
-- @note The slow form from the issue: v0.33.2 getIds tagName case, SELECT DISTINCT bookmarks.id with a correlated EXISTS (tagsOnBookmarks JOIN bookmarkTags) per bookmark. 16.3 s for lists.stats with 40 smart lists on a Pi. https://github.com/karakeep-app/karakeep/issues/3088
-- @modified Not the pinned code: compiled from search.ts:101-128 at tag v0.33.2 (98c0c789), which the pinned SHA replaced by the IN-subquery condition (single_tag). Kept as the issue's reproduction.
-- @param ?1 'u1'
-- @param ?2 'u1'
-- @param ?3 'UI'
select distinct "id" from "bookmarks" where ("bookmarks"."userId" = ?1 and exists (select "tagsOnBookmarks"."bookmarkId", "tagsOnBookmarks"."tagId", "tagsOnBookmarks"."attachedAt", "tagsOnBookmarks"."attachedBy", "bookmarkTags"."id", "bookmarkTags"."name", "bookmarkTags"."normalizedName", "bookmarkTags"."createdAt", "bookmarkTags"."userId" from "tagsOnBookmarks" inner join "bookmarkTags" on "tagsOnBookmarks"."tagId" = "bookmarkTags"."id" where ("tagsOnBookmarks"."bookmarkId" = "bookmarks"."id" and "bookmarkTags"."userId" = ?2 and "bookmarkTags"."name" = ?3)));

-- @id karakeep.lists.stats.smart.single_tag_pr3089
-- @src packages/trpc/lib/search.ts:68-83
-- @style drizzle query builder, .toSQL() for SQLite; ? positional (numbered here)
-- @tags analytics,dynamic,cpu-evidence
-- @note The fix from PR #3089: tag-first CROSS JOIN bookmarkTags -> tagsOnBookmarks -> bookmarks to pin SQLite's join order (16.3 s -> 2.3 s). https://github.com/karakeep-app/karakeep/issues/3088
-- @modified Not the pinned code: compiled from the builder added by PR #3089 (merge 21b0fa8a), later replaced by the IN-subquery condition at the pinned SHA.
-- @param ?1 'u1'
-- @param ?2 'UI'
-- @param ?3 'u1'
select distinct "bookmarks"."id" from "bookmarkTags" cross join "tagsOnBookmarks" cross join "bookmarks" where ("bookmarkTags"."userId" = ?1 and "bookmarkTags"."name" = ?2 and "tagsOnBookmarks"."tagId" = "bookmarkTags"."id" and "bookmarks"."id" = "tagsOnBookmarks"."bookmarkId" and "bookmarks"."userId" = ?3);

-- @id karakeep.bookmarks.get_bookmarks.home
-- @src packages/trpc/models/bookmarks.ts:429-610
-- @style drizzle query builder, .toSQL() for SQLite; ? positional (numbered here)
-- @tags hotpath,dynamic,hot-small,cpu-evidence
-- @note Home page (archived=false, 20 per page): CTE of 21 bookmarks by lastSavedAt, then 6 LEFT JOINs (tags, links, texts, assets) fanning out to every tag row. https://github.com/karakeep-app/karakeep/issues/1690 (slow web UI; reporter's DB was on a NAS share). Compiled with .toSQL() from the real drizzle builder (drizzle-orm 0.45.4, schema.ts + lib/search.ts copied from the pinned SHA, model code transcribed).
-- @param ?1 'u1'
-- @param ?2 0
-- @param ?3 21
with "bookmarksSq" as (select "id", "createdAt", "lastSavedAt", "modifiedAt", "title", "archived", "favourited", "userId", "taggingStatus", "summarizationStatus", "embeddingStatus", "summary", "note", "type", "source" from "bookmarks" where ("bookmarks"."userId" = ?1 and "bookmarks"."archived" = ?2) order by "bookmarks"."lastSavedAt" desc, "bookmarks"."id" desc limit ?3) select "bookmarksSq"."id", "bookmarksSq"."createdAt", "bookmarksSq"."lastSavedAt", "bookmarksSq"."modifiedAt", "bookmarksSq"."title", "bookmarksSq"."archived", "bookmarksSq"."favourited", "bookmarksSq"."userId", "bookmarksSq"."taggingStatus", "bookmarksSq"."summarizationStatus", "bookmarksSq"."embeddingStatus", "bookmarksSq"."summary", "bookmarksSq"."note", "bookmarksSq"."type", "bookmarksSq"."source", "tagsOnBookmarks"."bookmarkId", "tagsOnBookmarks"."tagId", "tagsOnBookmarks"."attachedAt", "tagsOnBookmarks"."attachedBy", "bookmarkTags"."id", "bookmarkTags"."name", "bookmarkTags"."normalizedName", "bookmarkTags"."createdAt", "bookmarkTags"."userId", "bookmarkLinks"."id", "bookmarkLinks"."url", "bookmarkLinks"."title", "bookmarkLinks"."description", "bookmarkLinks"."author", "bookmarkLinks"."publisher", "bookmarkLinks"."datePublished", "bookmarkLinks"."dateModified", "bookmarkLinks"."imageUrl", "bookmarkLinks"."favicon", "bookmarkLinks"."htmlContent", "bookmarkLinks"."contentAssetId", "bookmarkLinks"."readerViewStatus", "bookmarkLinks"."readerViewScore", "bookmarkLinks"."readerViewReasons", "bookmarkLinks"."readerViewClassifierVersion", "bookmarkLinks"."crawledAt", "bookmarkLinks"."crawlStatus", "bookmarkLinks"."crawlStatusCode", "bookmarkLinks"."probeMetadataAt", "bookmarkTexts"."id", "bookmarkTexts"."text", "bookmarkTexts"."sourceUrl", "bookmarkAssets"."id", "bookmarkAssets"."assetType", "bookmarkAssets"."assetId", "bookmarkAssets"."content", "bookmarkAssets"."metadata", "bookmarkAssets"."fileName", "bookmarkAssets"."sourceUrl", "assets"."id", "assets"."assetType", "assets"."size", "assets"."contentType", "assets"."fileName", "assets"."bookmarkId", "assets"."userId" from "bookmarksSq" left join "tagsOnBookmarks" on "bookmarksSq"."id" = "tagsOnBookmarks"."bookmarkId" left join "bookmarkTags" on "tagsOnBookmarks"."tagId" = "bookmarkTags"."id" left join "bookmarkLinks" on "bookmarkLinks"."id" = "bookmarksSq"."id" left join "bookmarkTexts" on "bookmarkTexts"."id" = "bookmarksSq"."id" left join "bookmarkAssets" on "bookmarkAssets"."id" = "bookmarksSq"."id" left join "assets" on "assets"."bookmarkId" = "bookmarksSq"."id" order by "bookmarksSq"."lastSavedAt" desc, "bookmarksSq"."id" desc;

-- @id karakeep.bookmarks.get_bookmarks.home_cursor
-- @src packages/trpc/models/bookmarks.ts:429-610
-- @style drizzle query builder, .toSQL() for SQLite; ? positional (numbered here)
-- @tags hotpath,dynamic
-- @note Infinite scroll page further down: cursor condition lastSavedAt < ? OR (= ? AND id <= ?) inside the CTE. Compiled with .toSQL() from the real drizzle builder (drizzle-orm 0.45.4, schema.ts + lib/search.ts copied from the pinned SHA, model code transcribed).
-- @param ?1 'u1'
-- @param ?2 0
-- @param ?3 1786500000
-- @param ?4 1786500000
-- @param ?5 'b20000'
-- @param ?6 21
with "bookmarksSq" as (select "id", "createdAt", "lastSavedAt", "modifiedAt", "title", "archived", "favourited", "userId", "taggingStatus", "summarizationStatus", "embeddingStatus", "summary", "note", "type", "source" from "bookmarks" where ("bookmarks"."userId" = ?1 and "bookmarks"."archived" = ?2 and ("bookmarks"."lastSavedAt" < ?3 or ("bookmarks"."lastSavedAt" = ?4 and "bookmarks"."id" <= ?5))) order by "bookmarks"."lastSavedAt" desc, "bookmarks"."id" desc limit ?6) select "bookmarksSq"."id", "bookmarksSq"."createdAt", "bookmarksSq"."lastSavedAt", "bookmarksSq"."modifiedAt", "bookmarksSq"."title", "bookmarksSq"."archived", "bookmarksSq"."favourited", "bookmarksSq"."userId", "bookmarksSq"."taggingStatus", "bookmarksSq"."summarizationStatus", "bookmarksSq"."embeddingStatus", "bookmarksSq"."summary", "bookmarksSq"."note", "bookmarksSq"."type", "bookmarksSq"."source", "tagsOnBookmarks"."bookmarkId", "tagsOnBookmarks"."tagId", "tagsOnBookmarks"."attachedAt", "tagsOnBookmarks"."attachedBy", "bookmarkTags"."id", "bookmarkTags"."name", "bookmarkTags"."normalizedName", "bookmarkTags"."createdAt", "bookmarkTags"."userId", "bookmarkLinks"."id", "bookmarkLinks"."url", "bookmarkLinks"."title", "bookmarkLinks"."description", "bookmarkLinks"."author", "bookmarkLinks"."publisher", "bookmarkLinks"."datePublished", "bookmarkLinks"."dateModified", "bookmarkLinks"."imageUrl", "bookmarkLinks"."favicon", "bookmarkLinks"."htmlContent", "bookmarkLinks"."contentAssetId", "bookmarkLinks"."readerViewStatus", "bookmarkLinks"."readerViewScore", "bookmarkLinks"."readerViewReasons", "bookmarkLinks"."readerViewClassifierVersion", "bookmarkLinks"."crawledAt", "bookmarkLinks"."crawlStatus", "bookmarkLinks"."crawlStatusCode", "bookmarkLinks"."probeMetadataAt", "bookmarkTexts"."id", "bookmarkTexts"."text", "bookmarkTexts"."sourceUrl", "bookmarkAssets"."id", "bookmarkAssets"."assetType", "bookmarkAssets"."assetId", "bookmarkAssets"."content", "bookmarkAssets"."metadata", "bookmarkAssets"."fileName", "bookmarkAssets"."sourceUrl", "assets"."id", "assets"."assetType", "assets"."size", "assets"."contentType", "assets"."fileName", "assets"."bookmarkId", "assets"."userId" from "bookmarksSq" left join "tagsOnBookmarks" on "bookmarksSq"."id" = "tagsOnBookmarks"."bookmarkId" left join "bookmarkTags" on "tagsOnBookmarks"."tagId" = "bookmarkTags"."id" left join "bookmarkLinks" on "bookmarkLinks"."id" = "bookmarksSq"."id" left join "bookmarkTexts" on "bookmarkTexts"."id" = "bookmarksSq"."id" left join "bookmarkAssets" on "bookmarkAssets"."id" = "bookmarksSq"."id" left join "assets" on "assets"."bookmarkId" = "bookmarksSq"."id" order by "bookmarksSq"."lastSavedAt" desc, "bookmarksSq"."id" desc;

-- @id karakeep.bookmarks.get_bookmarks.by_tag
-- @src packages/trpc/models/bookmarks.ts:540-557,598-610
-- @style drizzle query builder, .toSQL() for SQLite; ? positional (numbered here)
-- @tags hotpath,dynamic
-- @note Tag page for the 3rd most used tag: CTE driven from tagsOnBookmarks JOIN bookmarks, top 21 by lastSavedAt (sort over all of the tag's bookmarks), then the 6-way fan-out. Compiled with .toSQL() from the real drizzle builder (drizzle-orm 0.45.4, schema.ts + lib/search.ts copied from the pinned SHA, model code transcribed).
-- @param ?1 't3'
-- @param ?2 'u1'
-- @param ?3 21
with "bookmarksSq" as (select "bookmarks"."id", "bookmarks"."createdAt", "bookmarks"."lastSavedAt", "bookmarks"."modifiedAt", "bookmarks"."title", "bookmarks"."archived", "bookmarks"."favourited", "bookmarks"."userId", "bookmarks"."taggingStatus", "bookmarks"."summarizationStatus", "bookmarks"."embeddingStatus", "bookmarks"."summary", "bookmarks"."note", "bookmarks"."type", "bookmarks"."source" from "tagsOnBookmarks" inner join "bookmarks" on "bookmarks"."id" = "tagsOnBookmarks"."bookmarkId" where ("tagsOnBookmarks"."tagId" = ?1 and "bookmarks"."userId" = ?2) order by "bookmarks"."lastSavedAt" desc, "bookmarks"."id" desc limit ?3) select "bookmarksSq"."id", "bookmarksSq"."createdAt", "bookmarksSq"."lastSavedAt", "bookmarksSq"."modifiedAt", "bookmarksSq"."title", "bookmarksSq"."archived", "bookmarksSq"."favourited", "bookmarksSq"."userId", "bookmarksSq"."taggingStatus", "bookmarksSq"."summarizationStatus", "bookmarksSq"."embeddingStatus", "bookmarksSq"."summary", "bookmarksSq"."note", "bookmarksSq"."type", "bookmarksSq"."source", "tagsOnBookmarks"."bookmarkId", "tagsOnBookmarks"."tagId", "tagsOnBookmarks"."attachedAt", "tagsOnBookmarks"."attachedBy", "bookmarkTags"."id", "bookmarkTags"."name", "bookmarkTags"."normalizedName", "bookmarkTags"."createdAt", "bookmarkTags"."userId", "bookmarkLinks"."id", "bookmarkLinks"."url", "bookmarkLinks"."title", "bookmarkLinks"."description", "bookmarkLinks"."author", "bookmarkLinks"."publisher", "bookmarkLinks"."datePublished", "bookmarkLinks"."dateModified", "bookmarkLinks"."imageUrl", "bookmarkLinks"."favicon", "bookmarkLinks"."htmlContent", "bookmarkLinks"."contentAssetId", "bookmarkLinks"."readerViewStatus", "bookmarkLinks"."readerViewScore", "bookmarkLinks"."readerViewReasons", "bookmarkLinks"."readerViewClassifierVersion", "bookmarkLinks"."crawledAt", "bookmarkLinks"."crawlStatus", "bookmarkLinks"."crawlStatusCode", "bookmarkLinks"."probeMetadataAt", "bookmarkTexts"."id", "bookmarkTexts"."text", "bookmarkTexts"."sourceUrl", "bookmarkAssets"."id", "bookmarkAssets"."assetType", "bookmarkAssets"."assetId", "bookmarkAssets"."content", "bookmarkAssets"."metadata", "bookmarkAssets"."fileName", "bookmarkAssets"."sourceUrl", "assets"."id", "assets"."assetType", "assets"."size", "assets"."contentType", "assets"."fileName", "assets"."bookmarkId", "assets"."userId" from "bookmarksSq" left join "tagsOnBookmarks" on "bookmarksSq"."id" = "tagsOnBookmarks"."bookmarkId" left join "bookmarkTags" on "tagsOnBookmarks"."tagId" = "bookmarkTags"."id" left join "bookmarkLinks" on "bookmarkLinks"."id" = "bookmarksSq"."id" left join "bookmarkTexts" on "bookmarkTexts"."id" = "bookmarksSq"."id" left join "bookmarkAssets" on "bookmarkAssets"."id" = "bookmarksSq"."id" left join "assets" on "assets"."bookmarkId" = "bookmarksSq"."id" order by "bookmarksSq"."lastSavedAt" desc, "bookmarksSq"."id" desc;

-- @id karakeep.bookmarks.get_bookmarks.by_list
-- @src packages/trpc/models/bookmarks.ts:522-539,598-610
-- @style drizzle query builder, .toSQL() for SQLite; ? positional (numbered here)
-- @tags hotpath,dynamic
-- @note List page for the biggest manual list (Reading): CTE driven from bookmarksInLists, top 21, then the fan-out. Compiled with .toSQL() from the real drizzle builder (drizzle-orm 0.45.4, schema.ts + lib/search.ts copied from the pinned SHA, model code transcribed).
-- @param ?1 'l3'
-- @param ?2 21
with "bookmarksSq" as (select "bookmarks"."id", "bookmarks"."createdAt", "bookmarks"."lastSavedAt", "bookmarks"."modifiedAt", "bookmarks"."title", "bookmarks"."archived", "bookmarks"."favourited", "bookmarks"."userId", "bookmarks"."taggingStatus", "bookmarks"."summarizationStatus", "bookmarks"."embeddingStatus", "bookmarks"."summary", "bookmarks"."note", "bookmarks"."type", "bookmarks"."source" from "bookmarksInLists" inner join "bookmarks" on "bookmarks"."id" = "bookmarksInLists"."bookmarkId" where "bookmarksInLists"."listId" = ?1 order by "bookmarks"."lastSavedAt" desc, "bookmarks"."id" desc limit ?2) select "bookmarksSq"."id", "bookmarksSq"."createdAt", "bookmarksSq"."lastSavedAt", "bookmarksSq"."modifiedAt", "bookmarksSq"."title", "bookmarksSq"."archived", "bookmarksSq"."favourited", "bookmarksSq"."userId", "bookmarksSq"."taggingStatus", "bookmarksSq"."summarizationStatus", "bookmarksSq"."embeddingStatus", "bookmarksSq"."summary", "bookmarksSq"."note", "bookmarksSq"."type", "bookmarksSq"."source", "tagsOnBookmarks"."bookmarkId", "tagsOnBookmarks"."tagId", "tagsOnBookmarks"."attachedAt", "tagsOnBookmarks"."attachedBy", "bookmarkTags"."id", "bookmarkTags"."name", "bookmarkTags"."normalizedName", "bookmarkTags"."createdAt", "bookmarkTags"."userId", "bookmarkLinks"."id", "bookmarkLinks"."url", "bookmarkLinks"."title", "bookmarkLinks"."description", "bookmarkLinks"."author", "bookmarkLinks"."publisher", "bookmarkLinks"."datePublished", "bookmarkLinks"."dateModified", "bookmarkLinks"."imageUrl", "bookmarkLinks"."favicon", "bookmarkLinks"."htmlContent", "bookmarkLinks"."contentAssetId", "bookmarkLinks"."readerViewStatus", "bookmarkLinks"."readerViewScore", "bookmarkLinks"."readerViewReasons", "bookmarkLinks"."readerViewClassifierVersion", "bookmarkLinks"."crawledAt", "bookmarkLinks"."crawlStatus", "bookmarkLinks"."crawlStatusCode", "bookmarkLinks"."probeMetadataAt", "bookmarkTexts"."id", "bookmarkTexts"."text", "bookmarkTexts"."sourceUrl", "bookmarkAssets"."id", "bookmarkAssets"."assetType", "bookmarkAssets"."assetId", "bookmarkAssets"."content", "bookmarkAssets"."metadata", "bookmarkAssets"."fileName", "bookmarkAssets"."sourceUrl", "assets"."id", "assets"."assetType", "assets"."size", "assets"."contentType", "assets"."fileName", "assets"."bookmarkId", "assets"."userId" from "bookmarksSq" left join "tagsOnBookmarks" on "bookmarksSq"."id" = "tagsOnBookmarks"."bookmarkId" left join "bookmarkTags" on "tagsOnBookmarks"."tagId" = "bookmarkTags"."id" left join "bookmarkLinks" on "bookmarkLinks"."id" = "bookmarksSq"."id" left join "bookmarkTexts" on "bookmarkTexts"."id" = "bookmarksSq"."id" left join "bookmarkAssets" on "bookmarkAssets"."id" = "bookmarksSq"."id" left join "assets" on "assets"."bookmarkId" = "bookmarksSq"."id" order by "bookmarksSq"."lastSavedAt" desc, "bookmarksSq"."id" desc;

-- @id karakeep.bookmarks.get_bookmarks.smart_list
-- @src packages/trpc/models/bookmarks.ts:461-469,579-610
-- @style drizzle query builder, .toSQL() for SQLite; ? positional (numbered here)
-- @tags hotpath,dynamic,cpu-evidence
-- @note Smart list page '#Programming or #AI -is:archived': the smart-list condition (IN subqueries) inside the home-path CTE, top 21, then the fan-out. https://github.com/karakeep-app/karakeep/issues/3088 Compiled with .toSQL() from the real drizzle builder (drizzle-orm 0.45.4, schema.ts + lib/search.ts copied from the pinned SHA, model code transcribed).
-- @param ?1 'u1'
-- @param ?2 'u1'
-- @param ?3 'Programming'
-- @param ?4 'u1'
-- @param ?5 'AI'
-- @param ?6 0
-- @param ?7 21
with "bookmarksSq" as (select "id", "createdAt", "lastSavedAt", "modifiedAt", "title", "archived", "favourited", "userId", "taggingStatus", "summarizationStatus", "embeddingStatus", "summary", "note", "type", "source" from "bookmarks" where ("bookmarks"."userId" = ?1 and (("bookmarks"."id" in (select "tagsOnBookmarks"."bookmarkId" from "tagsOnBookmarks" inner join "bookmarkTags" on "tagsOnBookmarks"."tagId" = "bookmarkTags"."id" where ("bookmarkTags"."userId" = ?2 and "bookmarkTags"."name" = ?3)) or "bookmarks"."id" in (select "tagsOnBookmarks"."bookmarkId" from "tagsOnBookmarks" inner join "bookmarkTags" on "tagsOnBookmarks"."tagId" = "bookmarkTags"."id" where ("bookmarkTags"."userId" = ?4 and "bookmarkTags"."name" = ?5))) and "bookmarks"."archived" = ?6)) order by "bookmarks"."lastSavedAt" desc, "bookmarks"."id" desc limit ?7) select "bookmarksSq"."id", "bookmarksSq"."createdAt", "bookmarksSq"."lastSavedAt", "bookmarksSq"."modifiedAt", "bookmarksSq"."title", "bookmarksSq"."archived", "bookmarksSq"."favourited", "bookmarksSq"."userId", "bookmarksSq"."taggingStatus", "bookmarksSq"."summarizationStatus", "bookmarksSq"."embeddingStatus", "bookmarksSq"."summary", "bookmarksSq"."note", "bookmarksSq"."type", "bookmarksSq"."source", "tagsOnBookmarks"."bookmarkId", "tagsOnBookmarks"."tagId", "tagsOnBookmarks"."attachedAt", "tagsOnBookmarks"."attachedBy", "bookmarkTags"."id", "bookmarkTags"."name", "bookmarkTags"."normalizedName", "bookmarkTags"."createdAt", "bookmarkTags"."userId", "bookmarkLinks"."id", "bookmarkLinks"."url", "bookmarkLinks"."title", "bookmarkLinks"."description", "bookmarkLinks"."author", "bookmarkLinks"."publisher", "bookmarkLinks"."datePublished", "bookmarkLinks"."dateModified", "bookmarkLinks"."imageUrl", "bookmarkLinks"."favicon", "bookmarkLinks"."htmlContent", "bookmarkLinks"."contentAssetId", "bookmarkLinks"."readerViewStatus", "bookmarkLinks"."readerViewScore", "bookmarkLinks"."readerViewReasons", "bookmarkLinks"."readerViewClassifierVersion", "bookmarkLinks"."crawledAt", "bookmarkLinks"."crawlStatus", "bookmarkLinks"."crawlStatusCode", "bookmarkLinks"."probeMetadataAt", "bookmarkTexts"."id", "bookmarkTexts"."text", "bookmarkTexts"."sourceUrl", "bookmarkAssets"."id", "bookmarkAssets"."assetType", "bookmarkAssets"."assetId", "bookmarkAssets"."content", "bookmarkAssets"."metadata", "bookmarkAssets"."fileName", "bookmarkAssets"."sourceUrl", "assets"."id", "assets"."assetType", "assets"."size", "assets"."contentType", "assets"."fileName", "assets"."bookmarkId", "assets"."userId" from "bookmarksSq" left join "tagsOnBookmarks" on "bookmarksSq"."id" = "tagsOnBookmarks"."bookmarkId" left join "bookmarkTags" on "tagsOnBookmarks"."tagId" = "bookmarkTags"."id" left join "bookmarkLinks" on "bookmarkLinks"."id" = "bookmarksSq"."id" left join "bookmarkTexts" on "bookmarkTexts"."id" = "bookmarksSq"."id" left join "bookmarkAssets" on "bookmarkAssets"."id" = "bookmarksSq"."id" left join "assets" on "assets"."bookmarkId" = "bookmarksSq"."id" order by "bookmarksSq"."lastSavedAt" desc, "bookmarksSq"."id" desc;

-- @id karakeep.tags.list.by_usage
-- @src packages/trpc/models/tags.ts:84-152
-- @style drizzle query builder, .toSQL() for SQLite; ? positional (numbered here)
-- @tags analytics,hotpath,dynamic
-- @note Tags page: every tag of the user LEFT JOIN tagsOnBookmarks, GROUP BY with SUM(CASE attachedBy) counts, ORDER BY count desc, no limit (3.8k groups over ~270k links). Compiled with .toSQL() from the real drizzle builder (drizzle-orm 0.45.4, schema.ts + lib/search.ts copied from the pinned SHA, model code transcribed).
-- @param ?1 'u1'
select "bookmarkTags"."id", "bookmarkTags"."name", 
      SUM(CASE WHEN "tagsOnBookmarks"."attachedBy" = 'ai' THEN 1 ELSE 0 END)
     as "countAttachedByAi", 
      SUM(CASE WHEN "tagsOnBookmarks"."attachedBy" = 'human' THEN 1 ELSE 0 END)
     as "countAttachedByHuman", COUNT("tagsOnBookmarks"."tagId") as "count" from "bookmarkTags" left join "tagsOnBookmarks" on "bookmarkTags"."id" = "tagsOnBookmarks"."tagId" where "bookmarkTags"."userId" = ?1 group by "bookmarkTags"."id", "bookmarkTags"."name" order by count desc;

-- @id karakeep.tags.list.search_relevance
-- @src packages/trpc/models/tags.ts:84-152
-- @style drizzle query builder, .toSQL() for SQLite; ? positional (numbered here)
-- @tags analytics,hotpath,dynamic
-- @note Tag autocomplete 'pro': LIKE '%pro%' filter, grouped counts, ORDER BY a CASE relevance expression and length(name), LIMIT 51. Compiled with .toSQL() from the real drizzle builder (drizzle-orm 0.45.4, schema.ts + lib/search.ts copied from the pinned SHA, model code transcribed).
-- @param ?1 'u1'
-- @param ?2 '%pro%'
-- @param ?3 'pro'
-- @param ?4 'pro%'
-- @param ?5 51
select "bookmarkTags"."id", "bookmarkTags"."name", 
      SUM(CASE WHEN "tagsOnBookmarks"."attachedBy" = 'ai' THEN 1 ELSE 0 END)
     as "countAttachedByAi", 
      SUM(CASE WHEN "tagsOnBookmarks"."attachedBy" = 'human' THEN 1 ELSE 0 END)
     as "countAttachedByHuman", COUNT("tagsOnBookmarks"."tagId") as "count" from "bookmarkTags" left join "tagsOnBookmarks" on "bookmarkTags"."id" = "tagsOnBookmarks"."tagId" where ("bookmarkTags"."userId" = ?1 and "bookmarkTags"."name" like ?2) group by "bookmarkTags"."id", "bookmarkTags"."name" order by 
            CASE
              WHEN lower(?3) = lower("bookmarkTags"."name") THEN 2
              WHEN "bookmarkTags"."name" LIKE ?4 THEN 1
              ELSE 0
            END desc, length("bookmarkTags"."name") asc limit ?5;

-- @id karakeep.tags.list.unused
-- @src packages/trpc/models/tags.ts:84-152
-- @style drizzle query builder, .toSQL() for SQLite; ? positional (numbered here)
-- @tags analytics,dynamic
-- @note Tags page 'unused' filter: grouped counts with HAVING COUNT(tagId) = 0, by name, LIMIT 51 OFFSET 0. Compiled with .toSQL() from the real drizzle builder (drizzle-orm 0.45.4, schema.ts + lib/search.ts copied from the pinned SHA, model code transcribed).
-- @param ?1 'u1'
-- @param ?2 0
-- @param ?3 51
select "bookmarkTags"."id", "bookmarkTags"."name", 
      SUM(CASE WHEN "tagsOnBookmarks"."attachedBy" = 'ai' THEN 1 ELSE 0 END)
     as "countAttachedByAi", 
      SUM(CASE WHEN "tagsOnBookmarks"."attachedBy" = 'human' THEN 1 ELSE 0 END)
     as "countAttachedByHuman", COUNT("tagsOnBookmarks"."tagId") as "count" from "bookmarkTags" left join "tagsOnBookmarks" on "bookmarkTags"."id" = "tagsOnBookmarks"."tagId" where "bookmarkTags"."userId" = ?1 group by "bookmarkTags"."id", "bookmarkTags"."name" having COUNT("tagsOnBookmarks"."tagId") = ?2 order by "bookmarkTags"."name" asc limit ?3;

-- @id karakeep.tags.delete_unused
-- @src packages/trpc/models/tags.ts:184-199
-- @style drizzle query builder, .toSQL() for SQLite; ? positional (numbered here)
-- @tags dynamic
-- @note Delete unused tags: DELETE with a correlated NOT EXISTS per tag (300 rows go). Compiled with .toSQL() from the real drizzle builder (drizzle-orm 0.45.4, schema.ts + lib/search.ts copied from the pinned SHA, model code transcribed).
-- @param ?1 'u1'
delete from "bookmarkTags" where ("bookmarkTags"."userId" = ?1 and not exists (select "tagId" from "tagsOnBookmarks" where "tagsOnBookmarks"."tagId" = "bookmarkTags"."id"));

-- @id karakeep.users.bookmark_counts
-- @src packages/trpc/models/users.ts:388-400
-- @style drizzle query builder, .toSQL() for SQLite; ? positional (numbered here)
-- @tags analytics,hotpath,dynamic
-- @note Sidebar counts: count(*) plus two COALESCE(SUM(CASE ...)) over all of the user's bookmarks. Compiled with .toSQL() from the real drizzle builder (drizzle-orm 0.45.4, schema.ts + lib/search.ts copied from the pinned SHA, model code transcribed).
-- @param ?1 'u1'
select count(*), COALESCE(SUM(CASE WHEN "favourited" THEN 1 ELSE 0 END), 0), COALESCE(SUM(CASE WHEN "archived" THEN 1 ELSE 0 END), 0) from "bookmarks" where "bookmarks"."userId" = ?1;

-- @id karakeep.users.stats.top_domains
-- @src packages/trpc/models/users.ts:476-533
-- @style drizzle query builder, .toSQL() for SQLite; ? positional (numbered here)
-- @tags analytics,dynamic
-- @note Stats page top domains: GROUP BY a nested CASE/INSTR/SUBSTR host extraction over every link of the user, ORDER BY count LIMIT 10. Compiled with .toSQL() from the real drizzle builder (drizzle-orm 0.45.4, schema.ts + lib/search.ts copied from the pinned SHA, model code transcribed).
-- @param ?1 'u1'
-- @param ?2 10
select CASE
            WHEN "bookmarkLinks"."url" LIKE 'https://%' THEN
              CASE
                WHEN INSTR(SUBSTR("bookmarkLinks"."url", 9), '/') > 0 THEN
                  SUBSTR("bookmarkLinks"."url", 9, INSTR(SUBSTR("bookmarkLinks"."url", 9), '/') - 1)
                ELSE
                  SUBSTR("bookmarkLinks"."url", 9)
              END
            WHEN "bookmarkLinks"."url" LIKE 'http://%' THEN
              CASE
                WHEN INSTR(SUBSTR("bookmarkLinks"."url", 8), '/') > 0 THEN
                  SUBSTR("bookmarkLinks"."url", 8, INSTR(SUBSTR("bookmarkLinks"."url", 8), '/') - 1)
                ELSE
                  SUBSTR("bookmarkLinks"."url", 8)
              END
            ELSE
              CASE
                WHEN INSTR("bookmarkLinks"."url", '/') > 0 THEN
                  SUBSTR("bookmarkLinks"."url", 1, INSTR("bookmarkLinks"."url", '/') - 1)
                ELSE
                  "bookmarkLinks"."url"
              END
          END, count(*) from "bookmarkLinks" inner join "bookmarks" on "bookmarks"."id" = "bookmarkLinks"."id" where "bookmarks"."userId" = ?1 group by CASE
            WHEN "bookmarkLinks"."url" LIKE 'https://%' THEN
              CASE
                WHEN INSTR(SUBSTR("bookmarkLinks"."url", 9), '/') > 0 THEN
                  SUBSTR("bookmarkLinks"."url", 9, INSTR(SUBSTR("bookmarkLinks"."url", 9), '/') - 1)
                ELSE
                  SUBSTR("bookmarkLinks"."url", 9)
              END
            WHEN "bookmarkLinks"."url" LIKE 'http://%' THEN
              CASE
                WHEN INSTR(SUBSTR("bookmarkLinks"."url", 8), '/') > 0 THEN
                  SUBSTR("bookmarkLinks"."url", 8, INSTR(SUBSTR("bookmarkLinks"."url", 8), '/') - 1)
                ELSE
                  SUBSTR("bookmarkLinks"."url", 8)
              END
            ELSE
              CASE
                WHEN INSTR("bookmarkLinks"."url", '/') > 0 THEN
                  SUBSTR("bookmarkLinks"."url", 1, INSTR("bookmarkLinks"."url", '/') - 1)
                ELSE
                  "bookmarkLinks"."url"
              END
          END order by count(*) desc limit ?2;

-- @id karakeep.users.stats.assets_by_type
-- @src packages/trpc/models/users.ts:543-552
-- @style drizzle query builder, .toSQL() for SQLite; ? positional (numbered here)
-- @tags analytics,dynamic
-- @note Stats page asset breakdown: count and SUM(size) per assetType for the user. Compiled with .toSQL() from the real drizzle builder (drizzle-orm 0.45.4, schema.ts + lib/search.ts copied from the pinned SHA, model code transcribed).
-- @param ?1 'u1'
select "assetType", count(*), COALESCE(SUM("size"), 0) from "assets" where "assets"."userId" = ?1 group by "assets"."assetType";

-- @id karakeep.users.stats.timestamps
-- @src packages/trpc/models/users.ts:583-589
-- @style drizzle query builder, .toSQL() for SQLite; ? positional (numbered here)
-- @tags analytics,dynamic
-- @note Stats page activity heatmap: fetches every bookmark's lastSavedAt for the user (bucketed by hour/day in JS). Compiled with .toSQL() from the real drizzle builder (drizzle-orm 0.45.4, schema.ts + lib/search.ts copied from the pinned SHA, model code transcribed).
-- @param ?1 'u1'
select "lastSavedAt" from "bookmarks" where "bookmarks"."userId" = ?1;

-- @id karakeep.users.stats.tag_usage
-- @src packages/trpc/models/users.ts:591-603
-- @style drizzle query builder, .toSQL() for SQLite; ? positional (numbered here)
-- @tags analytics,dynamic
-- @note Stats page top tags: bookmarkTags JOIN tagsOnBookmarks GROUP BY name ORDER BY count desc LIMIT 10. Compiled with .toSQL() from the real drizzle builder (drizzle-orm 0.45.4, schema.ts + lib/search.ts copied from the pinned SHA, model code transcribed).
-- @param ?1 'u1'
-- @param ?2 10
select "bookmarkTags"."name", count(*) from "bookmarkTags" inner join "tagsOnBookmarks" on "tagsOnBookmarks"."tagId" = "bookmarkTags"."id" where "bookmarkTags"."userId" = ?1 group by "bookmarkTags"."name" order by count(*) desc limit ?2;

-- @id karakeep.admin.user_stats.bookmarks
-- @src packages/trpc/routers/admin.ts:484-495
-- @style drizzle query builder, .toSQL() for SQLite; ? positional (numbered here)
-- @tags analytics,dynamic
-- @note Admin user list: bookmark count per user over the whole bookmarks table. Compiled with .toSQL() from the real drizzle builder (drizzle-orm 0.45.4, schema.ts + lib/search.ts copied from the pinned SHA, model code transcribed).
select "userId", count(*) from "bookmarks" group by "bookmarks"."userId";

-- @id karakeep.highlights.search
-- @src packages/trpc/models/highlights.repo.ts:89-130
-- @style drizzle query builder, .toSQL() for SQLite; ? positional (numbered here)
-- @tags dynamic
-- @note Highlights search: LIKE '%design%' on text OR note, newest first, LIMIT 51 (relational findMany). Compiled with .toSQL() from the real drizzle builder (drizzle-orm 0.45.4, schema.ts + lib/search.ts copied from the pinned SHA, model code transcribed).
-- @param ?1 'u1'
-- @param ?2 '%design%'
-- @param ?3 '%design%'
-- @param ?4 51
select "id", "bookmarkId", "userId", "startOffset", "endOffset", "color", "text", "note", "createdAt" from "highlights" "highlights" where ("highlights"."userId" = ?1 and ("highlights"."text" like ?2 or "highlights"."note" like ?3)) order by "highlights"."createdAt" desc, "highlights"."id" desc limit ?4;

-- @id karakeep.lists.get_all_owned
-- @src packages/trpc/models/lists.ts:381-409
-- @style drizzle query builder, .toSQL() for SQLite; ? positional (numbered here)
-- @tags hotpath,dynamic,hot-small
-- @note Sidebar lists: relational findMany with a json_group_array subquery for one collaborator per list. Compiled with .toSQL() from the real drizzle builder (drizzle-orm 0.45.4, schema.ts + lib/search.ts copied from the pinned SHA, model code transcribed).
-- @param ?1 1
-- @param ?2 'u1'
select "id", "name", "description", "icon", "createdAt", "userId", "type", "query", "parentId", "public", (select coalesce(json_group_array(json_array("id")), json_array()) as "data" from (select * from "listCollaborators" "bookmarkLists_collaborators" where "bookmarkLists_collaborators"."listId" = "bookmarkLists"."id" limit ?1) "bookmarkLists_collaborators") as "collaborators" from "bookmarkLists" "bookmarkLists" where "bookmarkLists"."userId" = ?2;

-- @id karakeep.bookmarks.bare_from_id
-- @src packages/trpc/models/bookmarks.ts:116-136
-- @style drizzle query builder, .toSQL() for SQLite; ? positional (numbered here)
-- @tags hotpath,dynamic,hot-small
-- @note Point lookup by primary key before every bookmark mutation (findFirst, LIMIT 1). Compiled with .toSQL() from the real drizzle builder (drizzle-orm 0.45.4, schema.ts + lib/search.ts copied from the pinned SHA, model code transcribed).
-- @param ?1 'b123'
-- @param ?2 1
select "id", "createdAt", "lastSavedAt", "modifiedAt", "title", "archived", "favourited", "userId", "taggingStatus", "summarizationStatus", "embeddingStatus", "summary", "note", "type", "source" from "bookmarks" "bookmarks" where "bookmarks"."id" = ?1 limit ?2;
