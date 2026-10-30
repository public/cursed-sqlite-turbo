-- Audiobookshelf (advplyr/audiobookshelf @ edb1f7e, GPL-3.0). Sequelize v6 on SQLite. Most hot-path SQL is
-- ORM-generated around raw `Sequelize.literal(...)` fragments (correlated count subqueries, json_each filters,
-- CAST sort keys); those queries are reconstructed from the findAll/findAndCountAll options and tagged dynamic.
-- Sequelize inlines replacements and where values as escaped literals; here the ids/values that vary per request
-- are normalised to named parameters (:libraryId, :userId, ...). Instance save/update/create use Sequelize's bind
-- parameters ($1, $2, ...), kept as is. Raw sequelize.query() strings are quoted verbatim apart from whitespace.

-- @id abs.library.books_title_page
-- @src server/utils/queries/libraryItemsBookFilters.js:399-626
-- @style Sequelize findAll (book + required libraryItem include), literal ORDER BY; values inlined by Sequelize
-- @tags hotpath,dynamic
-- @note Default library page: every book column plus the library item, joined on the hasOne scope (mediaType='book') and sorted by `libraryItem`.`title` COLLATE NOCASE (served by a NOCASE index). Reconstructed from ORM code.
-- @param :libraryId '11111111-0000-4000-8000-000000000001'
SELECT `book`.`id`, `book`.`title`, `book`.`titleIgnorePrefix`, `book`.`subtitle`, `book`.`publishedYear`, `book`.`publishedDate`, `book`.`publisher`, `book`.`description`, `book`.`isbn`, `book`.`asin`, `book`.`language`, `book`.`explicit`, `book`.`abridged`, `book`.`coverPath`, `book`.`duration`, `book`.`narrators`, `book`.`audioFiles`, `book`.`ebookFile`, `book`.`chapters`, `book`.`tags`, `book`.`genres`, `book`.`createdAt`, `book`.`updatedAt`, `libraryItem`.`id` AS `libraryItem.id`, `libraryItem`.`ino` AS `libraryItem.ino`, `libraryItem`.`path` AS `libraryItem.path`, `libraryItem`.`relPath` AS `libraryItem.relPath`, `libraryItem`.`mediaId` AS `libraryItem.mediaId`, `libraryItem`.`mediaType` AS `libraryItem.mediaType`, `libraryItem`.`isFile` AS `libraryItem.isFile`, `libraryItem`.`isMissing` AS `libraryItem.isMissing`, `libraryItem`.`isInvalid` AS `libraryItem.isInvalid`, `libraryItem`.`mtime` AS `libraryItem.mtime`, `libraryItem`.`ctime` AS `libraryItem.ctime`, `libraryItem`.`birthtime` AS `libraryItem.birthtime`, `libraryItem`.`size` AS `libraryItem.size`, `libraryItem`.`lastScan` AS `libraryItem.lastScan`, `libraryItem`.`lastScanVersion` AS `libraryItem.lastScanVersion`, `libraryItem`.`libraryFiles` AS `libraryItem.libraryFiles`, `libraryItem`.`extraData` AS `libraryItem.extraData`, `libraryItem`.`title` AS `libraryItem.title`, `libraryItem`.`titleIgnorePrefix` AS `libraryItem.titleIgnorePrefix`, `libraryItem`.`authorNamesFirstLast` AS `libraryItem.authorNamesFirstLast`, `libraryItem`.`authorNamesLastFirst` AS `libraryItem.authorNamesLastFirst`, `libraryItem`.`createdAt` AS `libraryItem.createdAt`, `libraryItem`.`updatedAt` AS `libraryItem.updatedAt`, `libraryItem`.`libraryId` AS `libraryItem.libraryId`, `libraryItem`.`libraryFolderId` AS `libraryItem.libraryFolderId`
FROM `books` AS `book`
INNER JOIN `libraryItems` AS `libraryItem` ON `book`.`id` = `libraryItem`.`mediaId` AND (`libraryItem`.`mediaType` = 'book' AND `libraryItem`.`libraryId` = :libraryId)
ORDER BY `libraryItem`.`title` COLLATE NOCASE ASC
LIMIT 0, 12;

-- @id abs.library.books_title_page_count
-- @src server/utils/queries/libraryItemsBookFilters.js:360-367
-- @style Sequelize model.count(findOptions) with distinct (count cache key miss)
-- @tags hotpath,dynamic
-- @note Total for the unfiltered library page: count(DISTINCT book.id) over the book/libraryItem join. Reconstructed from ORM code.
-- @param :libraryId '11111111-0000-4000-8000-000000000001'
SELECT count(DISTINCT(`book`.`id`)) AS `count`
FROM `books` AS `book`
INNER JOIN `libraryItems` AS `libraryItem` ON `book`.`id` = `libraryItem`.`mediaId` AND (`libraryItem`.`mediaType` = 'book' AND `libraryItem`.`libraryId` = :libraryId);

-- @id abs.library.series_for_page_books
-- @src server/utils/queries/libraryItemsBookFilters.js:416-425
-- @style Sequelize `separate: true` include: one follow-up query with the page's book ids inlined
-- @tags hotpath,dynamic
-- @note After every library page, the series (with sequence) of the page's books: IN-list over bookSeries.bookId joined to series, ordered by createdAt. Reconstructed from ORM code.
SELECT `bookSeries`.`id`, `bookSeries`.`seriesId`, `bookSeries`.`sequence`, `bookSeries`.`createdAt`, `bookSeries`.`bookId`,
       `series`.`id` AS `series.id`, `series`.`name` AS `series.name`, `series`.`nameIgnorePrefix` AS `series.nameIgnorePrefix`
FROM `bookSeries` AS `bookSeries`
LEFT OUTER JOIN `series` AS `series` ON `bookSeries`.`seriesId` = `series`.`id`
WHERE `bookSeries`.`bookId` IN ('b00cb00c-0000-4000-8000-000000000327', 'b00cb00c-0000-4000-8000-000000000651', 'b00cb00c-0000-4000-8000-000000000975',
  'b00cb00c-0000-4000-8000-000000001202', 'b00cb00c-0000-4000-8000-000000001552', 'b00cb00c-0000-4000-8000-000000001876',
  'b00cb00c-0000-4000-8000-000000002200', 'b00cb00c-0000-4000-8000-000000002524', 'b00cb00c-0000-4000-8000-000000002874',
  'b00cb00c-0000-4000-8000-000000003198', 'b00cb00c-0000-4000-8000-000000005648', 'b00cb00c-0000-4000-8000-000000005972')
ORDER BY `bookSeries`.`createdAt` ASC;

-- @id abs.library.books_genre_restricted_user
-- @src server/utils/queries/libraryItemsBookFilters.js:17-43,191-195,265-266,399-626
-- @style Sequelize findAll; json_each literals with replacements :filterValue and :userTagsSelected (array expanded)
-- @tags hotpath,dynamic
-- @note Library page filtered to genre "Fantasy" for a user without explicit-content access and a tag allow-list: two correlated json_each count subqueries plus explicit = 0, newest first. Reconstructed from ORM code.
-- @param :libraryId '11111111-0000-4000-8000-000000000001'
-- @param :filterValue 'Fantasy'
SELECT `book`.`id`, `book`.`title`, `book`.`titleIgnorePrefix`, `book`.`subtitle`, `book`.`publishedYear`, `book`.`publishedDate`, `book`.`publisher`, `book`.`description`, `book`.`isbn`, `book`.`asin`, `book`.`language`, `book`.`explicit`, `book`.`abridged`, `book`.`coverPath`, `book`.`duration`, `book`.`narrators`, `book`.`audioFiles`, `book`.`ebookFile`, `book`.`chapters`, `book`.`tags`, `book`.`genres`, `book`.`createdAt`, `book`.`updatedAt`, `libraryItem`.`id` AS `libraryItem.id`, `libraryItem`.`ino` AS `libraryItem.ino`, `libraryItem`.`path` AS `libraryItem.path`, `libraryItem`.`relPath` AS `libraryItem.relPath`, `libraryItem`.`mediaId` AS `libraryItem.mediaId`, `libraryItem`.`mediaType` AS `libraryItem.mediaType`, `libraryItem`.`isFile` AS `libraryItem.isFile`, `libraryItem`.`isMissing` AS `libraryItem.isMissing`, `libraryItem`.`isInvalid` AS `libraryItem.isInvalid`, `libraryItem`.`mtime` AS `libraryItem.mtime`, `libraryItem`.`ctime` AS `libraryItem.ctime`, `libraryItem`.`birthtime` AS `libraryItem.birthtime`, `libraryItem`.`size` AS `libraryItem.size`, `libraryItem`.`lastScan` AS `libraryItem.lastScan`, `libraryItem`.`lastScanVersion` AS `libraryItem.lastScanVersion`, `libraryItem`.`libraryFiles` AS `libraryItem.libraryFiles`, `libraryItem`.`extraData` AS `libraryItem.extraData`, `libraryItem`.`title` AS `libraryItem.title`, `libraryItem`.`titleIgnorePrefix` AS `libraryItem.titleIgnorePrefix`, `libraryItem`.`authorNamesFirstLast` AS `libraryItem.authorNamesFirstLast`, `libraryItem`.`authorNamesLastFirst` AS `libraryItem.authorNamesLastFirst`, `libraryItem`.`createdAt` AS `libraryItem.createdAt`, `libraryItem`.`updatedAt` AS `libraryItem.updatedAt`, `libraryItem`.`libraryId` AS `libraryItem.libraryId`, `libraryItem`.`libraryFolderId` AS `libraryItem.libraryFolderId`
FROM `books` AS `book`
INNER JOIN `libraryItems` AS `libraryItem` ON `book`.`id` = `libraryItem`.`mediaId` AND (`libraryItem`.`mediaType` = 'book' AND `libraryItem`.`libraryId` = :libraryId)
WHERE ((SELECT count(*) FROM json_each(genres) WHERE json_valid(genres) AND json_each.value = :filterValue) >= 1
  AND `book`.`explicit` = 0
  AND (SELECT count(*) FROM json_each(tags) WHERE json_valid(tags) AND json_each.value IN ('kids', 'favorite')) >= 1)
ORDER BY libraryItem.createdAt DESC
LIMIT 0, 12;

-- @id abs.library.books_finished_by_author_lf
-- @src server/utils/queries/libraryItemsBookFilters.js:127-128,277-279,517-530,399-626
-- @style Sequelize findAll with a non-required mediaProgress include filtered through '$mediaProgresses.isFinished$'
-- @tags hotpath,dynamic
-- @note Filter progress=finished sorted by "author last, first" then title: LEFT JOIN on the per-user progress with the association scope, WHERE on the joined row, two NOCASE sort keys. Reconstructed from ORM code.
-- @param :libraryId '11111111-0000-4000-8000-000000000001'
-- @param :userId 'eeeeeeee-0000-4000-8000-000000000002'
SELECT `book`.`id`, `book`.`title`, `book`.`titleIgnorePrefix`, `book`.`subtitle`, `book`.`publishedYear`, `book`.`publishedDate`, `book`.`publisher`, `book`.`description`, `book`.`isbn`, `book`.`asin`, `book`.`language`, `book`.`explicit`, `book`.`abridged`, `book`.`coverPath`, `book`.`duration`, `book`.`narrators`, `book`.`audioFiles`, `book`.`ebookFile`, `book`.`chapters`, `book`.`tags`, `book`.`genres`, `book`.`createdAt`, `book`.`updatedAt`, `libraryItem`.`id` AS `libraryItem.id`, `libraryItem`.`ino` AS `libraryItem.ino`, `libraryItem`.`path` AS `libraryItem.path`, `libraryItem`.`relPath` AS `libraryItem.relPath`, `libraryItem`.`mediaId` AS `libraryItem.mediaId`, `libraryItem`.`mediaType` AS `libraryItem.mediaType`, `libraryItem`.`isFile` AS `libraryItem.isFile`, `libraryItem`.`isMissing` AS `libraryItem.isMissing`, `libraryItem`.`isInvalid` AS `libraryItem.isInvalid`, `libraryItem`.`mtime` AS `libraryItem.mtime`, `libraryItem`.`ctime` AS `libraryItem.ctime`, `libraryItem`.`birthtime` AS `libraryItem.birthtime`, `libraryItem`.`size` AS `libraryItem.size`, `libraryItem`.`lastScan` AS `libraryItem.lastScan`, `libraryItem`.`lastScanVersion` AS `libraryItem.lastScanVersion`, `libraryItem`.`libraryFiles` AS `libraryItem.libraryFiles`, `libraryItem`.`extraData` AS `libraryItem.extraData`, `libraryItem`.`title` AS `libraryItem.title`, `libraryItem`.`titleIgnorePrefix` AS `libraryItem.titleIgnorePrefix`, `libraryItem`.`authorNamesFirstLast` AS `libraryItem.authorNamesFirstLast`, `libraryItem`.`authorNamesLastFirst` AS `libraryItem.authorNamesLastFirst`, `libraryItem`.`createdAt` AS `libraryItem.createdAt`, `libraryItem`.`updatedAt` AS `libraryItem.updatedAt`, `libraryItem`.`libraryId` AS `libraryItem.libraryId`, `libraryItem`.`libraryFolderId` AS `libraryItem.libraryFolderId`, `mediaProgresses`.`id` AS `mediaProgresses.id`, `mediaProgresses`.`isFinished` AS `mediaProgresses.isFinished`, `mediaProgresses`.`currentTime` AS `mediaProgresses.currentTime`, `mediaProgresses`.`ebookProgress` AS `mediaProgresses.ebookProgress`, `mediaProgresses`.`updatedAt` AS `mediaProgresses.updatedAt`, `mediaProgresses`.`createdAt` AS `mediaProgresses.createdAt`, `mediaProgresses`.`finishedAt` AS `mediaProgresses.finishedAt`
FROM `books` AS `book`
INNER JOIN `libraryItems` AS `libraryItem` ON `book`.`id` = `libraryItem`.`mediaId` AND (`libraryItem`.`mediaType` = 'book' AND `libraryItem`.`libraryId` = :libraryId)
LEFT OUTER JOIN `mediaProgresses` AS `mediaProgresses` ON `book`.`id` = `mediaProgresses`.`mediaItemId` AND (`mediaProgresses`.`mediaItemType` = 'book' AND `mediaProgresses`.`userId` = :userId)
WHERE (`mediaProgresses`.`isFinished` = 1)
ORDER BY `libraryItem`.`authorNamesLastFirst` COLLATE NOCASE ASC, `libraryItem`.`title` COLLATE NOCASE ASC
LIMIT 0, 12;

-- @id abs.home.continue_listening
-- @src server/utils/queries/libraryFilters.js:56-58; server/utils/queries/libraryItemsBookFilters.js:129-148,291-292,517-530
-- @style Sequelize findAndCountAll (rows query); progress include with hideFromContinueListening = false on the home page
-- @tags hotpath,dynamic
-- @note "Continue Listening" shelf: in-progress books (audio or ebook) for the user, sorted by progress updatedAt DESC NULLS LAST. Reconstructed from ORM code.
-- @param :libraryId '11111111-0000-4000-8000-000000000001'
-- @param :userId 'eeeeeeee-0000-4000-8000-000000000002'
SELECT `book`.`id`, `book`.`title`, `book`.`titleIgnorePrefix`, `book`.`subtitle`, `book`.`publishedYear`, `book`.`publishedDate`, `book`.`publisher`, `book`.`description`, `book`.`isbn`, `book`.`asin`, `book`.`language`, `book`.`explicit`, `book`.`abridged`, `book`.`coverPath`, `book`.`duration`, `book`.`narrators`, `book`.`audioFiles`, `book`.`ebookFile`, `book`.`chapters`, `book`.`tags`, `book`.`genres`, `book`.`createdAt`, `book`.`updatedAt`, `libraryItem`.`id` AS `libraryItem.id`, `libraryItem`.`ino` AS `libraryItem.ino`, `libraryItem`.`path` AS `libraryItem.path`, `libraryItem`.`relPath` AS `libraryItem.relPath`, `libraryItem`.`mediaId` AS `libraryItem.mediaId`, `libraryItem`.`mediaType` AS `libraryItem.mediaType`, `libraryItem`.`isFile` AS `libraryItem.isFile`, `libraryItem`.`isMissing` AS `libraryItem.isMissing`, `libraryItem`.`isInvalid` AS `libraryItem.isInvalid`, `libraryItem`.`mtime` AS `libraryItem.mtime`, `libraryItem`.`ctime` AS `libraryItem.ctime`, `libraryItem`.`birthtime` AS `libraryItem.birthtime`, `libraryItem`.`size` AS `libraryItem.size`, `libraryItem`.`lastScan` AS `libraryItem.lastScan`, `libraryItem`.`lastScanVersion` AS `libraryItem.lastScanVersion`, `libraryItem`.`libraryFiles` AS `libraryItem.libraryFiles`, `libraryItem`.`extraData` AS `libraryItem.extraData`, `libraryItem`.`title` AS `libraryItem.title`, `libraryItem`.`titleIgnorePrefix` AS `libraryItem.titleIgnorePrefix`, `libraryItem`.`authorNamesFirstLast` AS `libraryItem.authorNamesFirstLast`, `libraryItem`.`authorNamesLastFirst` AS `libraryItem.authorNamesLastFirst`, `libraryItem`.`createdAt` AS `libraryItem.createdAt`, `libraryItem`.`updatedAt` AS `libraryItem.updatedAt`, `libraryItem`.`libraryId` AS `libraryItem.libraryId`, `libraryItem`.`libraryFolderId` AS `libraryItem.libraryFolderId`, `mediaProgresses`.`id` AS `mediaProgresses.id`, `mediaProgresses`.`isFinished` AS `mediaProgresses.isFinished`, `mediaProgresses`.`currentTime` AS `mediaProgresses.currentTime`, `mediaProgresses`.`ebookProgress` AS `mediaProgresses.ebookProgress`, `mediaProgresses`.`updatedAt` AS `mediaProgresses.updatedAt`, `mediaProgresses`.`createdAt` AS `mediaProgresses.createdAt`, `mediaProgresses`.`finishedAt` AS `mediaProgresses.finishedAt`
FROM `books` AS `book`
INNER JOIN `libraryItems` AS `libraryItem` ON `book`.`id` = `libraryItem`.`mediaId` AND (`libraryItem`.`mediaType` = 'book' AND `libraryItem`.`libraryId` = :libraryId)
LEFT OUTER JOIN `mediaProgresses` AS `mediaProgresses` ON `book`.`id` = `mediaProgresses`.`mediaItemId` AND (`mediaProgresses`.`mediaItemType` = 'book' AND `mediaProgresses`.`userId` = :userId AND `mediaProgresses`.`hideFromContinueListening` = 0)
WHERE (((`mediaProgresses`.`currentTime` > 0 OR `mediaProgresses`.`ebookProgress` > 0) AND `mediaProgresses`.`isFinished` = 0))
ORDER BY mediaProgresses.updatedAt DESC NULLS LAST
LIMIT 0, 10;

-- @id abs.home.recently_added
-- @src server/utils/queries/libraryFilters.js:93-95; server/utils/queries/libraryItemsBookFilters.js:265-266,531-535
-- @style Sequelize findAndCountAll; createdAt >= now - 60 days computed in JS and inlined as a DATETIME string
-- @tags hotpath,dynamic
-- @note "Recently Added" shelf: library items created in the last 60 days, newest first (text DATETIME range on libraryItems.createdAt). Reconstructed from ORM code.
-- @param :libraryId '11111111-0000-4000-8000-000000000001'
-- @param :since '2026-08-29 00:00:00.000 +00:00'
SELECT `book`.`id`, `book`.`title`, `book`.`titleIgnorePrefix`, `book`.`subtitle`, `book`.`publishedYear`, `book`.`publishedDate`, `book`.`publisher`, `book`.`description`, `book`.`isbn`, `book`.`asin`, `book`.`language`, `book`.`explicit`, `book`.`abridged`, `book`.`coverPath`, `book`.`duration`, `book`.`narrators`, `book`.`audioFiles`, `book`.`ebookFile`, `book`.`chapters`, `book`.`tags`, `book`.`genres`, `book`.`createdAt`, `book`.`updatedAt`, `libraryItem`.`id` AS `libraryItem.id`, `libraryItem`.`ino` AS `libraryItem.ino`, `libraryItem`.`path` AS `libraryItem.path`, `libraryItem`.`relPath` AS `libraryItem.relPath`, `libraryItem`.`mediaId` AS `libraryItem.mediaId`, `libraryItem`.`mediaType` AS `libraryItem.mediaType`, `libraryItem`.`isFile` AS `libraryItem.isFile`, `libraryItem`.`isMissing` AS `libraryItem.isMissing`, `libraryItem`.`isInvalid` AS `libraryItem.isInvalid`, `libraryItem`.`mtime` AS `libraryItem.mtime`, `libraryItem`.`ctime` AS `libraryItem.ctime`, `libraryItem`.`birthtime` AS `libraryItem.birthtime`, `libraryItem`.`size` AS `libraryItem.size`, `libraryItem`.`lastScan` AS `libraryItem.lastScan`, `libraryItem`.`lastScanVersion` AS `libraryItem.lastScanVersion`, `libraryItem`.`libraryFiles` AS `libraryItem.libraryFiles`, `libraryItem`.`extraData` AS `libraryItem.extraData`, `libraryItem`.`title` AS `libraryItem.title`, `libraryItem`.`titleIgnorePrefix` AS `libraryItem.titleIgnorePrefix`, `libraryItem`.`authorNamesFirstLast` AS `libraryItem.authorNamesFirstLast`, `libraryItem`.`authorNamesLastFirst` AS `libraryItem.authorNamesLastFirst`, `libraryItem`.`createdAt` AS `libraryItem.createdAt`, `libraryItem`.`updatedAt` AS `libraryItem.updatedAt`, `libraryItem`.`libraryId` AS `libraryItem.libraryId`, `libraryItem`.`libraryFolderId` AS `libraryItem.libraryFolderId`
FROM `books` AS `book`
INNER JOIN `libraryItems` AS `libraryItem` ON `book`.`id` = `libraryItem`.`mediaId` AND (`libraryItem`.`mediaType` = 'book' AND `libraryItem`.`libraryId` = :libraryId AND `libraryItem`.`createdAt` >= :since)
ORDER BY libraryItem.createdAt DESC
LIMIT 0, 10;

-- @id abs.library.collapse_series_first_books
-- @src server/utils/queries/libraryItemsBookFilters.js:312-331,557-585
-- @style Sequelize seriesModel.findAll with a required belongsToMany(book) include and a literal numBooks attribute
-- @tags hotpath,dynamic
-- @note "Collapse series" pre-query: every series with its books and library items, a correlated numBooks count per row, ordered by CAST of the through-table sequence alias AS FLOAT NULLS LAST. Reconstructed from ORM code.
-- @param :libraryId '11111111-0000-4000-8000-000000000001'
SELECT `series`.`id`, `series`.`name`, (SELECT count(*) FROM bookSeries bs WHERE bs.seriesId = series.id) AS `numBooks`,
       `books`.`id` AS `books.id`, `books`.`title` AS `books.title`,
       `books->bookSeries`.`id` AS `books.bookSeries.id`, `books->bookSeries`.`seriesId` AS `books.bookSeries.seriesId`,
       `books->bookSeries`.`bookId` AS `books.bookSeries.bookId`, `books->bookSeries`.`sequence` AS `books.bookSeries.sequence`,
       `books->libraryItem`.`id` AS `books.libraryItem.id`, `books->libraryItem`.`mediaId` AS `books.libraryItem.mediaId`,
       `books->libraryItem`.`libraryId` AS `books.libraryItem.libraryId`, `books->libraryItem`.`title` AS `books.libraryItem.title`
FROM `series` AS `series`
INNER JOIN ( `bookSeries` AS `books->bookSeries` INNER JOIN `books` AS `books` ON `books`.`id` = `books->bookSeries`.`bookId`) ON `series`.`id` = `books->bookSeries`.`seriesId`
INNER JOIN `libraryItems` AS `books->libraryItem` ON `books`.`id` = `books->libraryItem`.`mediaId` AND (`books->libraryItem`.`mediaType` = 'book' AND `books->libraryItem`.`libraryId` = :libraryId)
ORDER BY CAST(`books.bookSeries.sequence` AS FLOAT) ASC NULLS LAST;

-- @id abs.series.books_in_series
-- @src server/utils/queries/libraryItemsBookFilters.js:493-507,1079-1081
-- @style Sequelize findAll with a required belongsToMany(series) include filtered by id; no LIMIT
-- @tags hotpath,dynamic
-- @note Series page: the series' books with library items, nested through-table join, ordered by CAST(`series.bookSeries.sequence` AS FLOAT) ASC NULLS LAST. Reconstructed from ORM code.
-- @param :libraryId '11111111-0000-4000-8000-000000000001'
-- @param :seriesId '5e5e5e5e-0000-4000-8000-000000000006'
SELECT `book`.`id`, `book`.`title`, `book`.`titleIgnorePrefix`, `book`.`subtitle`, `book`.`publishedYear`, `book`.`publishedDate`, `book`.`publisher`, `book`.`description`, `book`.`isbn`, `book`.`asin`, `book`.`language`, `book`.`explicit`, `book`.`abridged`, `book`.`coverPath`, `book`.`duration`, `book`.`narrators`, `book`.`audioFiles`, `book`.`ebookFile`, `book`.`chapters`, `book`.`tags`, `book`.`genres`, `book`.`createdAt`, `book`.`updatedAt`, `libraryItem`.`id` AS `libraryItem.id`, `libraryItem`.`ino` AS `libraryItem.ino`, `libraryItem`.`path` AS `libraryItem.path`, `libraryItem`.`relPath` AS `libraryItem.relPath`, `libraryItem`.`mediaId` AS `libraryItem.mediaId`, `libraryItem`.`mediaType` AS `libraryItem.mediaType`, `libraryItem`.`isFile` AS `libraryItem.isFile`, `libraryItem`.`isMissing` AS `libraryItem.isMissing`, `libraryItem`.`isInvalid` AS `libraryItem.isInvalid`, `libraryItem`.`mtime` AS `libraryItem.mtime`, `libraryItem`.`ctime` AS `libraryItem.ctime`, `libraryItem`.`birthtime` AS `libraryItem.birthtime`, `libraryItem`.`size` AS `libraryItem.size`, `libraryItem`.`lastScan` AS `libraryItem.lastScan`, `libraryItem`.`lastScanVersion` AS `libraryItem.lastScanVersion`, `libraryItem`.`libraryFiles` AS `libraryItem.libraryFiles`, `libraryItem`.`extraData` AS `libraryItem.extraData`, `libraryItem`.`title` AS `libraryItem.title`, `libraryItem`.`titleIgnorePrefix` AS `libraryItem.titleIgnorePrefix`, `libraryItem`.`authorNamesFirstLast` AS `libraryItem.authorNamesFirstLast`, `libraryItem`.`authorNamesLastFirst` AS `libraryItem.authorNamesLastFirst`, `libraryItem`.`createdAt` AS `libraryItem.createdAt`, `libraryItem`.`updatedAt` AS `libraryItem.updatedAt`, `libraryItem`.`libraryId` AS `libraryItem.libraryId`, `libraryItem`.`libraryFolderId` AS `libraryItem.libraryFolderId`, `series`.`id` AS `series.id`, `series`.`name` AS `series.name`, `series->bookSeries`.`sequence` AS `series.bookSeries.sequence`
FROM `books` AS `book`
INNER JOIN `libraryItems` AS `libraryItem` ON `book`.`id` = `libraryItem`.`mediaId` AND (`libraryItem`.`mediaType` = 'book' AND `libraryItem`.`libraryId` = :libraryId)
INNER JOIN ( `bookSeries` AS `series->bookSeries` INNER JOIN `series` AS `series` ON `series`.`id` = `series->bookSeries`.`seriesId`) ON `book`.`id` = `series->bookSeries`.`bookId` AND `series`.`id` = :seriesId
ORDER BY CAST(`series.bookSeries.sequence` AS FLOAT) ASC NULLS LAST;

-- @id abs.author.books_by_author
-- @src server/utils/queries/libraryFilters.js:426-427; server/utils/queries/libraryItemsBookFilters.js:482-492
-- @style Sequelize findAndCountAll with a required belongsToMany(author) include filtered by id
-- @tags hotpath,dynamic
-- @note Author page: the author's books newest first through the bookAuthors junction. Reconstructed from ORM code.
-- @param :libraryId '11111111-0000-4000-8000-000000000001'
-- @param :authorId 'a0a0a0a0-0000-4000-8000-000000000096'
SELECT `book`.`id`, `book`.`title`, `book`.`titleIgnorePrefix`, `book`.`subtitle`, `book`.`publishedYear`, `book`.`publishedDate`, `book`.`publisher`, `book`.`description`, `book`.`isbn`, `book`.`asin`, `book`.`language`, `book`.`explicit`, `book`.`abridged`, `book`.`coverPath`, `book`.`duration`, `book`.`narrators`, `book`.`audioFiles`, `book`.`ebookFile`, `book`.`chapters`, `book`.`tags`, `book`.`genres`, `book`.`createdAt`, `book`.`updatedAt`, `libraryItem`.`id` AS `libraryItem.id`, `libraryItem`.`ino` AS `libraryItem.ino`, `libraryItem`.`path` AS `libraryItem.path`, `libraryItem`.`relPath` AS `libraryItem.relPath`, `libraryItem`.`mediaId` AS `libraryItem.mediaId`, `libraryItem`.`mediaType` AS `libraryItem.mediaType`, `libraryItem`.`isFile` AS `libraryItem.isFile`, `libraryItem`.`isMissing` AS `libraryItem.isMissing`, `libraryItem`.`isInvalid` AS `libraryItem.isInvalid`, `libraryItem`.`mtime` AS `libraryItem.mtime`, `libraryItem`.`ctime` AS `libraryItem.ctime`, `libraryItem`.`birthtime` AS `libraryItem.birthtime`, `libraryItem`.`size` AS `libraryItem.size`, `libraryItem`.`lastScan` AS `libraryItem.lastScan`, `libraryItem`.`lastScanVersion` AS `libraryItem.lastScanVersion`, `libraryItem`.`libraryFiles` AS `libraryItem.libraryFiles`, `libraryItem`.`extraData` AS `libraryItem.extraData`, `libraryItem`.`title` AS `libraryItem.title`, `libraryItem`.`titleIgnorePrefix` AS `libraryItem.titleIgnorePrefix`, `libraryItem`.`authorNamesFirstLast` AS `libraryItem.authorNamesFirstLast`, `libraryItem`.`authorNamesLastFirst` AS `libraryItem.authorNamesLastFirst`, `libraryItem`.`createdAt` AS `libraryItem.createdAt`, `libraryItem`.`updatedAt` AS `libraryItem.updatedAt`, `libraryItem`.`libraryId` AS `libraryItem.libraryId`, `libraryItem`.`libraryFolderId` AS `libraryItem.libraryFolderId`, `authors`.`id` AS `authors.id`, `authors`.`name` AS `authors.name`
FROM `books` AS `book`
INNER JOIN `libraryItems` AS `libraryItem` ON `book`.`id` = `libraryItem`.`mediaId` AND (`libraryItem`.`mediaType` = 'book' AND `libraryItem`.`libraryId` = :libraryId)
INNER JOIN ( `bookAuthors` AS `authors->bookAuthor` INNER JOIN `authors` AS `authors` ON `authors`.`id` = `authors->bookAuthor`.`authorId`) ON `book`.`id` = `authors->bookAuthor`.`bookId` AND `authors`.`id` = :authorId
ORDER BY libraryItem.createdAt DESC
LIMIT 0, 12;

-- @id abs.library_item.book_expanded
-- @src server/models/LibraryItem.js:191-233
-- @style Sequelize libraryItem.getMedia() (findOne by primary key) with belongsToMany author and series includes
-- @tags hotpath,dynamic
-- @note Item page: one book with its authors and series through two nested junction LEFT JOINs, ordered by the junction rows' createdAt. Reconstructed from ORM code.
-- @param :bookId 'b00cb00c-0000-4000-8000-000000000008'
SELECT `book`.`id`, `book`.`title`, `book`.`titleIgnorePrefix`, `book`.`subtitle`, `book`.`publishedYear`, `book`.`publishedDate`, `book`.`publisher`, `book`.`description`, `book`.`isbn`, `book`.`asin`, `book`.`language`, `book`.`explicit`, `book`.`abridged`, `book`.`coverPath`, `book`.`duration`, `book`.`narrators`, `book`.`audioFiles`, `book`.`ebookFile`, `book`.`chapters`, `book`.`tags`, `book`.`genres`, `book`.`createdAt`, `book`.`updatedAt`, `authors`.`id` AS `authors.id`, `authors`.`name` AS `authors.name`, `authors`.`lastFirst` AS `authors.lastFirst`, `authors`.`asin` AS `authors.asin`, `authors`.`description` AS `authors.description`, `authors`.`imagePath` AS `authors.imagePath`, `authors`.`createdAt` AS `authors.createdAt`, `authors`.`updatedAt` AS `authors.updatedAt`, `authors`.`libraryId` AS `authors.libraryId`, `series`.`id` AS `series.id`, `series`.`name` AS `series.name`, `series`.`nameIgnorePrefix` AS `series.nameIgnorePrefix`, `series`.`description` AS `series.description`, `series`.`createdAt` AS `series.createdAt`, `series`.`updatedAt` AS `series.updatedAt`, `series`.`libraryId` AS `series.libraryId`,
       `series->bookSeries`.`id` AS `series.bookSeries.id`, `series->bookSeries`.`sequence` AS `series.bookSeries.sequence`
FROM `books` AS `book`
LEFT OUTER JOIN ( `bookAuthors` AS `authors->bookAuthor` INNER JOIN `authors` AS `authors` ON `authors`.`id` = `authors->bookAuthor`.`authorId`) ON `book`.`id` = `authors->bookAuthor`.`bookId`
LEFT OUTER JOIN ( `bookSeries` AS `series->bookSeries` INNER JOIN `series` AS `series` ON `series`.`id` = `series->bookSeries`.`seriesId`) ON `book`.`id` = `series->bookSeries`.`bookId`
WHERE `book`.`id` = :bookId
ORDER BY `authors->bookAuthor`.`createdAt` ASC, `series->bookSeries`.`createdAt` ASC;

-- @id abs.home.continue_series
-- @src server/utils/queries/libraryItemsBookFilters.js:704-796
-- @style Sequelize seriesModel.findAndCountAll (rows query); literal subqueries with replacement :userId; NOT IN from user.extraData
-- @tags hotpath,dynamic
-- @note "Continue Series" shelf: per series, a correlated max(updatedAt) sort key plus three correlated count subqueries (>=1 finished, >=1 unfinished via LEFT JOIN, 0 in progress), excluding the user's hidden series. Reconstructed from ORM code.
-- @param :libraryId '11111111-0000-4000-8000-000000000001'
-- @param :userId 'eeeeeeee-0000-4000-8000-000000000002'
SELECT `series`.`id`, `series`.`name`, `series`.`nameIgnorePrefix`, `series`.`description`, `series`.`createdAt`, `series`.`updatedAt`, `series`.`libraryId`,
       (SELECT max(mp.updatedAt) FROM bookSeries bs, mediaProgresses mp WHERE mp.mediaItemId = bs.bookId AND mp.userId = :userId AND bs.seriesId = series.id) AS `recent_progress`
FROM `series` AS `series`
WHERE (`series`.`id` NOT IN ('5e5e5e5e-0000-4000-8000-000000000074', '5e5e5e5e-0000-4000-8000-000000900002') AND `series`.`libraryId` = :libraryId)
  AND (SELECT count(*) FROM mediaProgresses mp, bookSeries bs WHERE bs.seriesId = series.id AND mp.mediaItemId = bs.bookId AND mp.userId = :userId AND mp.isFinished = 1) >= 1
  AND (SELECT count(*) FROM bookSeries bs LEFT OUTER JOIN mediaProgresses mp ON mp.mediaItemId = bs.bookId AND mp.userId = :userId WHERE bs.seriesId = series.id AND (mp.isFinished = 0 OR mp.isFinished IS NULL)) >= 1
  AND (SELECT count(*) FROM mediaProgresses mp, bookSeries bs WHERE mp.mediaItemId = bs.bookId AND mp.userId = :userId AND bs.seriesId = series.id AND mp.isFinished = 0 AND mp.currentTime > 0) = 0
ORDER BY recent_progress DESC
LIMIT 0, 10;

-- @id abs.home.discover_count
-- @src server/utils/queries/libraryItemsBookFilters.js:892-936
-- @style Sequelize bookModel.count({distinct, col: 'id'}); first-book-of-unstarted-series ids from the previous query inlined
-- @tags hotpath,dynamic
-- @note "Discover" shelf count: not-started books (NULL-or-0 checks on the LEFT JOINed progress) that are either in no series (correlated COUNT = 0) or the first book of an unstarted series (IN list). Reconstructed from ORM code.
-- @param :libraryId '11111111-0000-4000-8000-000000000001'
-- @param :userId 'eeeeeeee-0000-4000-8000-000000000002'
SELECT count(DISTINCT(`book`.`id`)) AS `count`
FROM `books` AS `book`
INNER JOIN `libraryItems` AS `libraryItem` ON `book`.`id` = `libraryItem`.`mediaId` AND (`libraryItem`.`mediaType` = 'book' AND `libraryItem`.`libraryId` = :libraryId)
LEFT OUTER JOIN `mediaProgresses` AS `mediaProgresses` ON `book`.`id` = `mediaProgresses`.`mediaItemId` AND (`mediaProgresses`.`mediaItemType` = 'book' AND `mediaProgresses`.`userId` = :userId)
WHERE ((`mediaProgresses`.`isFinished` IS NULL OR `mediaProgresses`.`isFinished` = 0)
  AND (`mediaProgresses`.`currentTime` IS NULL OR `mediaProgresses`.`currentTime` = 0)
  AND ((SELECT COUNT(*) FROM bookSeries bs where bs.bookId = book.id) = 0
       OR `book`.`id` IN ('b00cb00c-0000-4000-8000-000000003760', 'b00cb00c-0000-4000-8000-000000006045', 'b00cb00c-0000-4000-8000-000000008799',
                          'b00cb00c-0000-4000-8000-000000001575', 'b00cb00c-0000-4000-8000-000000000327', 'b00cb00c-0000-4000-8000-000000005956',
                          'b00cb00c-0000-4000-8000-000000011048', 'b00cb00c-0000-4000-8000-000000000101', 'b00cb00c-0000-4000-8000-000000003150',
                          'b00cb00c-0000-4000-8000-000000004777')));

-- @id abs.home.recent_series
-- @src server/utils/queries/libraryFilters.js:207-279
-- @style Sequelize seriesModel.findAndCountAll; literal count subqueries (hideSingleBookSeries setting, explicit-content restriction)
-- @tags hotpath,dynamic
-- @note "Recent Series" shelf for a user without explicit access in a library that hides single-book series: two correlated join-count subqueries on top of a createdAt range. Reconstructed from ORM code.
-- @param :libraryId '11111111-0000-4000-8000-000000000001'
-- @param :since '2026-08-29 00:00:00.000 +00:00'
SELECT `series`.`id`, `series`.`name`, `series`.`nameIgnorePrefix`, `series`.`description`, `series`.`createdAt`, `series`.`updatedAt`, `series`.`libraryId`
FROM `series` AS `series`
WHERE (`series`.`libraryId` = :libraryId AND `series`.`createdAt` >= :since)
  AND (SELECT count(*) FROM books b, bookSeries bs WHERE bs.seriesId = series.id AND bs.bookId = b.id) > 1
  AND (SELECT count(*) FROM books b, bookSeries bs WHERE bs.seriesId = series.id AND bs.bookId = b.id AND b.explicit = 0) > 0
ORDER BY `series`.`createdAt` DESC
LIMIT 0, 10;

-- @id abs.home.newest_authors
-- @src server/utils/queries/libraryFilters.js:334-358
-- @style Sequelize authorModel.findAndCountAll with limit and a required belongsToMany include: Sequelize's limited-subquery shape
-- @tags hotpath,dynamic
-- @note "Newest Authors" shelf: Sequelize wraps the limited author scan in a derived table with a correlated `(SELECT ... LIMIT 1) IS NOT NULL` existence probe, then re-joins the junction for the books. Reconstructed from ORM code.
-- @param :libraryId '11111111-0000-4000-8000-000000000001'
-- @param :since '2026-08-29 00:00:00.000 +00:00'
SELECT `author`.*, `books`.`id` AS `books.id`, `books`.`tags` AS `books.tags`, `books`.`explicit` AS `books.explicit`
FROM (SELECT `author`.`id`, `author`.`name`, `author`.`lastFirst`, `author`.`asin`, `author`.`description`, `author`.`imagePath`, `author`.`createdAt`, `author`.`updatedAt`, `author`.`libraryId`
      FROM `authors` AS `author`
      WHERE `author`.`libraryId` = :libraryId AND `author`.`createdAt` >= :since
        AND ( SELECT `bookAuthor`.`id` FROM `bookAuthors` AS `bookAuthor` INNER JOIN `books` AS `book` ON `bookAuthor`.`bookId` = `book`.`id` WHERE (`author`.`id` = `bookAuthor`.`authorId`) LIMIT 1 ) IS NOT NULL
      ORDER BY `author`.`createdAt` DESC
      LIMIT 10) AS `author`
INNER JOIN ( `bookAuthors` AS `books->bookAuthor` INNER JOIN `books` AS `books` ON `books`.`id` = `books->bookAuthor`.`bookId`) ON `author`.`id` = `books->bookAuthor`.`authorId`
ORDER BY `author`.`createdAt` DESC;

-- @id abs.series.list_by_num_books_genre
-- @src server/utils/queries/seriesFilters.js:29-184
-- @style Sequelize seriesModel.findAndCountAll; literal attribute + literal count filters with replacement :filterValue
-- @tags hotpath,dynamic
-- @note Series page filtered by genre, sorted by book count, single-book series hidden: correlated numBooks in the result set and a count subquery nesting a json_each count subquery. Reconstructed from ORM code.
-- @param :libraryId '11111111-0000-4000-8000-000000000001'
-- @param :filterValue 'Mystery'
SELECT `series`.`id`, `series`.`name`, `series`.`nameIgnorePrefix`, `series`.`description`, `series`.`createdAt`, `series`.`updatedAt`, `series`.`libraryId`,
       (SELECT count(*) FROM bookSeries bs WHERE bs.seriesId = series.id) AS `numBooks`
FROM `series` AS `series`
WHERE (`series`.`libraryId` = :libraryId)
  AND (SELECT count(*) FROM books b, bookSeries bs WHERE bs.seriesId = series.id AND bs.bookId = b.id) > 1
  AND (SELECT count(*) FROM books b, bookSeries bs WHERE bs.seriesId = series.id AND bs.bookId = b.id AND (SELECT count(*) FROM json_each(b.genres) WHERE json_valid(b.genres) AND json_each.value = :filterValue) > 0) > 0
ORDER BY `numBooks` DESC
LIMIT 0, 50;

-- @id abs.series.list_finished_by_duration
-- @src server/utils/queries/seriesFilters.js:29-184
-- @style Sequelize seriesModel.findAndCountAll; literal attribute + literal count filters with replacement :userId
-- @tags dynamic
-- @note Series filtered to "finished" for a user and sorted by total duration: correlated SUM(duration) in the result set, comma join mixed with a LEFT JOIN whose ON references the comma-joined table, compared = 0. Reconstructed from ORM code.
-- @param :libraryId '11111111-0000-4000-8000-000000000001'
-- @param :userId 'eeeeeeee-0000-4000-8000-000000000001'
SELECT `series`.`id`, `series`.`name`, `series`.`nameIgnorePrefix`, `series`.`description`, `series`.`createdAt`, `series`.`updatedAt`, `series`.`libraryId`,
       (SELECT SUM(b.duration) FROM books b, bookSeries bs WHERE bs.seriesId = series.id AND b.id = bs.bookId) AS `totalDuration`
FROM `series` AS `series`
WHERE (`series`.`libraryId` = :libraryId)
  AND (SELECT count(*) FROM books b, bookSeries bs WHERE bs.seriesId = series.id AND bs.bookId = b.id) > 1
  AND (SELECT count(*) FROM books b, bookSeries bs LEFT OUTER JOIN mediaProgresses mp ON mp.mediaItemId = b.id AND mp.userId = :userId WHERE bs.seriesId = series.id AND bs.bookId = b.id AND (mp.isFinished IS NULL OR mp.isFinished = 0)) = 0
ORDER BY `totalDuration` DESC
LIMIT 0, 50;

-- @id abs.search.books
-- @src server/utils/queries/libraryItemsBookFilters.js:1093-1149; server/Database.js:994-999
-- @style Sequelize findAll; TextSearchQuery.matchExpression literals (no unaccent extension) + Op.substring
-- @tags hotpath,dynamic
-- @note Global search box, books: four-way OR of LIKE '%q%' over title, subtitle, asin and isbn on the library's books. Reconstructed from ORM code.
-- @param :libraryId '11111111-0000-4000-8000-000000000001'
-- @param :q '%dragon%'
SELECT `book`.`id`, `book`.`title`, `book`.`titleIgnorePrefix`, `book`.`subtitle`, `book`.`publishedYear`, `book`.`publishedDate`, `book`.`publisher`, `book`.`description`, `book`.`isbn`, `book`.`asin`, `book`.`language`, `book`.`explicit`, `book`.`abridged`, `book`.`coverPath`, `book`.`duration`, `book`.`narrators`, `book`.`audioFiles`, `book`.`ebookFile`, `book`.`chapters`, `book`.`tags`, `book`.`genres`, `book`.`createdAt`, `book`.`updatedAt`, `libraryItem`.`id` AS `libraryItem.id`, `libraryItem`.`ino` AS `libraryItem.ino`, `libraryItem`.`path` AS `libraryItem.path`, `libraryItem`.`relPath` AS `libraryItem.relPath`, `libraryItem`.`mediaId` AS `libraryItem.mediaId`, `libraryItem`.`mediaType` AS `libraryItem.mediaType`, `libraryItem`.`isFile` AS `libraryItem.isFile`, `libraryItem`.`isMissing` AS `libraryItem.isMissing`, `libraryItem`.`isInvalid` AS `libraryItem.isInvalid`, `libraryItem`.`mtime` AS `libraryItem.mtime`, `libraryItem`.`ctime` AS `libraryItem.ctime`, `libraryItem`.`birthtime` AS `libraryItem.birthtime`, `libraryItem`.`size` AS `libraryItem.size`, `libraryItem`.`lastScan` AS `libraryItem.lastScan`, `libraryItem`.`lastScanVersion` AS `libraryItem.lastScanVersion`, `libraryItem`.`libraryFiles` AS `libraryItem.libraryFiles`, `libraryItem`.`extraData` AS `libraryItem.extraData`, `libraryItem`.`title` AS `libraryItem.title`, `libraryItem`.`titleIgnorePrefix` AS `libraryItem.titleIgnorePrefix`, `libraryItem`.`authorNamesFirstLast` AS `libraryItem.authorNamesFirstLast`, `libraryItem`.`authorNamesLastFirst` AS `libraryItem.authorNamesLastFirst`, `libraryItem`.`createdAt` AS `libraryItem.createdAt`, `libraryItem`.`updatedAt` AS `libraryItem.updatedAt`, `libraryItem`.`libraryId` AS `libraryItem.libraryId`, `libraryItem`.`libraryFolderId` AS `libraryItem.libraryFolderId`
FROM `books` AS `book`
INNER JOIN `libraryItems` AS `libraryItem` ON `book`.`id` = `libraryItem`.`mediaId` AND (`libraryItem`.`mediaType` = 'book' AND `libraryItem`.`libraryId` = :libraryId)
WHERE ((book.title LIKE :q OR book.subtitle LIKE :q OR `book`.`asin` LIKE :q OR `book`.`isbn` LIKE :q))
LIMIT 0, 12;

-- @id abs.search.narrators
-- @src server/utils/queries/libraryItemsBookFilters.js:1174-1185
-- @style raw sequelize.query with :replacements; match expression interpolated
-- @tags hotpath
-- @note Search narrators: comma join of books, libraryItems and json_each(b.narrators) with LIKE on the array values, GROUP BY value.
-- @param :libraryId '11111111-0000-4000-8000-000000000001'
-- @param :limit 12
-- @param :offset 0
SELECT value, count(*) AS numBooks FROM books b, libraryItems li, json_each(b.narrators) WHERE json_valid(b.narrators) AND json_each.value LIKE '%rosa%' AND b.id = li.mediaId AND li.libraryId = :libraryId GROUP BY value LIMIT :limit OFFSET :offset;

-- @id abs.search.authors
-- @src server/utils/queries/authorFilters.js:62-73
-- @style Sequelize authorModel.findAll; matchExpression literal + literal numBooks attribute
-- @tags hotpath,dynamic
-- @note Search authors: LIKE on name within the library, correlated count of the author's books in the result set. Reconstructed from ORM code.
-- @param :libraryId '11111111-0000-4000-8000-000000000001'
SELECT `author`.`id`, `author`.`name`, `author`.`lastFirst`, `author`.`asin`, `author`.`description`, `author`.`imagePath`, `author`.`createdAt`, `author`.`updatedAt`, `author`.`libraryId`, (SELECT count(*) FROM bookAuthors ba WHERE ba.authorId = author.id) AS `numBooks`
FROM `authors` AS `author`
WHERE (name LIKE '%tanaka%' AND `author`.`libraryId` = :libraryId)
LIMIT 0, 12;

-- @id abs.stats.authors_with_count
-- @src server/utils/queries/authorFilters.js:27-43
-- @style Sequelize bookAuthorModel.findAll with group and fn COUNT; ORDER BY literal alias
-- @tags dynamic
-- @note Library stats "top authors": join junction to authors filtered by library, GROUP BY authorId + author.id, ORDER BY the count alias, top 10. Reconstructed from ORM code.
-- @param :libraryId '11111111-0000-4000-8000-000000000001'
SELECT `bookAuthor`.`authorId`, COUNT(`authorId`) AS `count`, `author`.`id` AS `author.id`, `author`.`name` AS `author.name`
FROM `bookAuthors` AS `bookAuthor`
INNER JOIN `authors` AS `author` ON `bookAuthor`.`authorId` = `author`.`id` AND `author`.`libraryId` = :libraryId
GROUP BY `authorId`, `author`.`id`
ORDER BY count DESC
LIMIT 10;

-- @id abs.stats.genres_with_count
-- @src server/utils/queries/libraryItemsBookFilters.js:1290-1297
-- @style raw sequelize.query with :replacements
-- @note Library stats genres: json_each over every book's genres in the library, GROUP BY value ORDER BY count DESC.
-- @param :libraryId '11111111-0000-4000-8000-000000000001'
SELECT value, count(*) AS numItems FROM books b, libraryItems li, json_each(b.genres) WHERE json_valid(b.genres) AND b.id = li.mediaId AND li.libraryId = :libraryId GROUP BY value ORDER BY numItems DESC;

-- @id abs.podcast.recent_episodes
-- @src server/utils/queries/libraryItemsPodcastFilters.js:506-545
-- @style Sequelize podcastEpisodeModel.findAll, subQuery false; '$mediaProgresses.isFinished$' where on a LEFT JOIN
-- @tags hotpath,dynamic
-- @note Podcast library "latest episodes": episodes -> podcast -> library item (inner) with the user's progress LEFT JOINed under its association scope, unfinished only, newest publishedAt first. Reconstructed from ORM code.
-- @param :libraryId '11111111-0000-4000-8000-000000000002'
-- @param :userId 'eeeeeeee-0000-4000-8000-000000000001'
SELECT `podcastEpisode`.`id`, `podcastEpisode`.`index`, `podcastEpisode`.`season`, `podcastEpisode`.`episode`, `podcastEpisode`.`episodeType`, `podcastEpisode`.`title`, `podcastEpisode`.`subtitle`, `podcastEpisode`.`description`, `podcastEpisode`.`pubDate`, `podcastEpisode`.`enclosureURL`, `podcastEpisode`.`enclosureSize`, `podcastEpisode`.`enclosureType`, `podcastEpisode`.`publishedAt`, `podcastEpisode`.`audioFile`, `podcastEpisode`.`chapters`, `podcastEpisode`.`extraData`, `podcastEpisode`.`createdAt`, `podcastEpisode`.`updatedAt`, `podcastEpisode`.`podcastId`, `podcast`.`id` AS `podcast.id`, `podcast`.`title` AS `podcast.title`, `podcast`.`titleIgnorePrefix` AS `podcast.titleIgnorePrefix`, `podcast`.`author` AS `podcast.author`, `podcast`.`releaseDate` AS `podcast.releaseDate`, `podcast`.`feedURL` AS `podcast.feedURL`, `podcast`.`imageURL` AS `podcast.imageURL`, `podcast`.`description` AS `podcast.description`, `podcast`.`itunesPageURL` AS `podcast.itunesPageURL`, `podcast`.`itunesId` AS `podcast.itunesId`, `podcast`.`itunesArtistId` AS `podcast.itunesArtistId`, `podcast`.`language` AS `podcast.language`, `podcast`.`podcastType` AS `podcast.podcastType`, `podcast`.`explicit` AS `podcast.explicit`, `podcast`.`autoDownloadEpisodes` AS `podcast.autoDownloadEpisodes`, `podcast`.`autoDownloadSchedule` AS `podcast.autoDownloadSchedule`, `podcast`.`lastEpisodeCheck` AS `podcast.lastEpisodeCheck`, `podcast`.`maxEpisodesToKeep` AS `podcast.maxEpisodesToKeep`, `podcast`.`maxNewEpisodesToDownload` AS `podcast.maxNewEpisodesToDownload`, `podcast`.`coverPath` AS `podcast.coverPath`, `podcast`.`tags` AS `podcast.tags`, `podcast`.`genres` AS `podcast.genres`, `podcast`.`numEpisodes` AS `podcast.numEpisodes`, `podcast`.`createdAt` AS `podcast.createdAt`, `podcast`.`updatedAt` AS `podcast.updatedAt`, `podcast->libraryItem`.`id` AS `podcast.libraryItem.id`, `podcast->libraryItem`.`ino` AS `podcast.libraryItem.ino`, `podcast->libraryItem`.`path` AS `podcast.libraryItem.path`, `podcast->libraryItem`.`relPath` AS `podcast.libraryItem.relPath`, `podcast->libraryItem`.`mediaId` AS `podcast.libraryItem.mediaId`, `podcast->libraryItem`.`mediaType` AS `podcast.libraryItem.mediaType`, `podcast->libraryItem`.`isFile` AS `podcast.libraryItem.isFile`, `podcast->libraryItem`.`isMissing` AS `podcast.libraryItem.isMissing`, `podcast->libraryItem`.`isInvalid` AS `podcast.libraryItem.isInvalid`, `podcast->libraryItem`.`mtime` AS `podcast.libraryItem.mtime`, `podcast->libraryItem`.`ctime` AS `podcast.libraryItem.ctime`, `podcast->libraryItem`.`birthtime` AS `podcast.libraryItem.birthtime`, `podcast->libraryItem`.`size` AS `podcast.libraryItem.size`, `podcast->libraryItem`.`lastScan` AS `podcast.libraryItem.lastScan`, `podcast->libraryItem`.`lastScanVersion` AS `podcast.libraryItem.lastScanVersion`, `podcast->libraryItem`.`libraryFiles` AS `podcast.libraryItem.libraryFiles`, `podcast->libraryItem`.`extraData` AS `podcast.libraryItem.extraData`, `podcast->libraryItem`.`title` AS `podcast.libraryItem.title`, `podcast->libraryItem`.`titleIgnorePrefix` AS `podcast.libraryItem.titleIgnorePrefix`, `podcast->libraryItem`.`authorNamesFirstLast` AS `podcast.libraryItem.authorNamesFirstLast`, `podcast->libraryItem`.`authorNamesLastFirst` AS `podcast.libraryItem.authorNamesLastFirst`, `podcast->libraryItem`.`createdAt` AS `podcast.libraryItem.createdAt`, `podcast->libraryItem`.`updatedAt` AS `podcast.libraryItem.updatedAt`, `podcast->libraryItem`.`libraryId` AS `podcast.libraryItem.libraryId`, `podcast->libraryItem`.`libraryFolderId` AS `podcast.libraryItem.libraryFolderId`, `mediaProgresses`.`id` AS `mediaProgresses.id`, `mediaProgresses`.`mediaItemId` AS `mediaProgresses.mediaItemId`, `mediaProgresses`.`mediaItemType` AS `mediaProgresses.mediaItemType`, `mediaProgresses`.`duration` AS `mediaProgresses.duration`, `mediaProgresses`.`currentTime` AS `mediaProgresses.currentTime`, `mediaProgresses`.`isFinished` AS `mediaProgresses.isFinished`, `mediaProgresses`.`hideFromContinueListening` AS `mediaProgresses.hideFromContinueListening`, `mediaProgresses`.`ebookLocation` AS `mediaProgresses.ebookLocation`, `mediaProgresses`.`ebookProgress` AS `mediaProgresses.ebookProgress`, `mediaProgresses`.`finishedAt` AS `mediaProgresses.finishedAt`, `mediaProgresses`.`extraData` AS `mediaProgresses.extraData`, `mediaProgresses`.`createdAt` AS `mediaProgresses.createdAt`, `mediaProgresses`.`updatedAt` AS `mediaProgresses.updatedAt`, `mediaProgresses`.`userId` AS `mediaProgresses.userId`, `mediaProgresses`.`podcastId` AS `mediaProgresses.podcastId`
FROM `podcastEpisodes` AS `podcastEpisode`
INNER JOIN `podcasts` AS `podcast` ON `podcastEpisode`.`podcastId` = `podcast`.`id`
INNER JOIN `libraryItems` AS `podcast->libraryItem` ON `podcast`.`id` = `podcast->libraryItem`.`mediaId` AND (`podcast->libraryItem`.`mediaType` = 'podcast' AND `podcast->libraryItem`.`libraryId` = :libraryId)
LEFT OUTER JOIN `mediaProgresses` AS `mediaProgresses` ON `podcastEpisode`.`id` = `mediaProgresses`.`mediaItemId` AND (`mediaProgresses`.`mediaItemType` = 'podcastEpisode' AND `mediaProgresses`.`userId` = :userId)
WHERE (`mediaProgresses`.`isFinished` IS NULL OR `mediaProgresses`.`isFinished` = 0)
ORDER BY `podcastEpisode`.`publishedAt` DESC
LIMIT 0, 10;

-- @id abs.maint.hidden_series_cleanup
-- @src server/Server.js:538-541
-- @style raw sequelize.query, no parameters
-- @note Startup cleanup: json_each over each user's extraData->"seriesHideFromContinueListening" (double-quoted string label), anti-join to series, json_group_array of the dangling ids per user.
SELECT u.id, u.username, u.extraData, json_group_array(value) AS seriesIdsToRemove FROM users u, json_each(u.extraData->"seriesHideFromContinueListening") LEFT JOIN series se ON se.id = value WHERE se.id IS NULL GROUP BY u.id;

-- @id abs.series.by_name_and_library
-- @src server/models/Series.js:46-55
-- @style Sequelize findOne with where(fn('lower', col('name')))
-- @tags hot-small,dynamic
-- @note Scanner lookup per scanned book's series: lower(name) equality (not indexable by the NOCASE index) within a library, LIMIT 1. Reconstructed from ORM code.
-- @param :libraryId '11111111-0000-4000-8000-000000000001'
-- @param :name 'the distant garden saga 42'
SELECT `id`, `name`, `nameIgnorePrefix`, `description`, `createdAt`, `updatedAt`, `libraryId`
FROM `series` AS `series`
WHERE lower(`name`) = :name AND `series`.`libraryId` = :libraryId
LIMIT 1;

-- @id abs.library_item.by_pk
-- @src server/models/LibraryItem.js:191-194
-- @style Sequelize findByPk
-- @tags hot-small,hotpath,dynamic
-- @note Primary-key lookup of a library item (every item request, play start). Reconstructed from ORM code.
-- @param :id '1111aaaa-0000-4000-8000-000000000327'
SELECT `libraryItem`.`id`, `libraryItem`.`ino`, `libraryItem`.`path`, `libraryItem`.`relPath`, `libraryItem`.`mediaId`, `libraryItem`.`mediaType`, `libraryItem`.`isFile`, `libraryItem`.`isMissing`, `libraryItem`.`isInvalid`, `libraryItem`.`mtime`, `libraryItem`.`ctime`, `libraryItem`.`birthtime`, `libraryItem`.`size`, `libraryItem`.`lastScan`, `libraryItem`.`lastScanVersion`, `libraryItem`.`libraryFiles`, `libraryItem`.`extraData`, `libraryItem`.`title`, `libraryItem`.`titleIgnorePrefix`, `libraryItem`.`authorNamesFirstLast`, `libraryItem`.`authorNamesLastFirst`, `libraryItem`.`createdAt`, `libraryItem`.`updatedAt`, `libraryItem`.`libraryId`, `libraryItem`.`libraryFolderId`
FROM `libraryItems` AS `libraryItem`
WHERE `libraryItem`.`id` = :id;

-- @id abs.progress.lookup_item_for_update
-- @src server/models/User.js:765-777
-- @style Sequelize findByPk with nested non-required includes
-- @tags hot-small,hotpath,dynamic
-- @note Progress sync (PATCH /me/progress): item by id, LEFT JOIN its book, LEFT JOIN the user's progress row under the association scope. Reconstructed from ORM code.
-- @param :libraryItemId '1111aaaa-0000-4000-8000-000000000006'
-- @param :userId 'eeeeeeee-0000-4000-8000-000000000002'
SELECT `libraryItem`.`id`, `libraryItem`.`mediaId`, `libraryItem`.`mediaType`, `book`.`id` AS `book.id`, `book`.`title` AS `book.title`,
       `book->mediaProgresses`.`id` AS `book.mediaProgresses.id`, `book->mediaProgresses`.`mediaItemId` AS `book.mediaProgresses.mediaItemId`,
       `book->mediaProgresses`.`mediaItemType` AS `book.mediaProgresses.mediaItemType`, `book->mediaProgresses`.`duration` AS `book.mediaProgresses.duration`,
       `book->mediaProgresses`.`currentTime` AS `book.mediaProgresses.currentTime`, `book->mediaProgresses`.`isFinished` AS `book.mediaProgresses.isFinished`,
       `book->mediaProgresses`.`hideFromContinueListening` AS `book.mediaProgresses.hideFromContinueListening`,
       `book->mediaProgresses`.`ebookLocation` AS `book.mediaProgresses.ebookLocation`, `book->mediaProgresses`.`ebookProgress` AS `book.mediaProgresses.ebookProgress`,
       `book->mediaProgresses`.`finishedAt` AS `book.mediaProgresses.finishedAt`, `book->mediaProgresses`.`extraData` AS `book.mediaProgresses.extraData`,
       `book->mediaProgresses`.`createdAt` AS `book.mediaProgresses.createdAt`, `book->mediaProgresses`.`updatedAt` AS `book.mediaProgresses.updatedAt`,
       `book->mediaProgresses`.`userId` AS `book.mediaProgresses.userId`, `book->mediaProgresses`.`podcastId` AS `book.mediaProgresses.podcastId`
FROM `libraryItems` AS `libraryItem`
LEFT OUTER JOIN `books` AS `book` ON `libraryItem`.`mediaId` = `book`.`id`
LEFT OUTER JOIN `mediaProgresses` AS `book->mediaProgresses` ON `book`.`id` = `book->mediaProgresses`.`mediaItemId` AND (`book->mediaProgresses`.`mediaItemType` = 'book' AND `book->mediaProgresses`.`userId` = :userId)
WHERE `libraryItem`.`id` = :libraryItemId;

-- @id abs.progress.update
-- @src server/models/MediaProgress.js:190-250
-- @style Sequelize instance save(): changed fields only, $N bind parameters
-- @tags hot-small,hotpath,dynamic
-- @note Progress sync write every few seconds while listening: UPDATE of the changed columns by primary key. Reconstructed from ORM code.
-- @param $1 4512.75
-- @param $2 '{"libraryItemId":"1111aaaa-0000-4000-8000-000000000006","progress":0.45}'
-- @param $3 '2026-10-28 09:12:44.512 +00:00'
-- @param $4 'dddddddd-0000-4000-8000-000002000413'
UPDATE `mediaProgresses` SET `currentTime`=$1,`extraData`=$2,`updatedAt`=$3 WHERE `id` = $4;

-- @id abs.progress.insert
-- @src server/models/User.js:796-822
-- @style Sequelize model.create(): INSERT of every attribute with $N bind parameters
-- @tags hot-small,hotpath,dynamic
-- @note First progress for a book: single-row INSERT into mediaProgresses. Reconstructed from ORM code.
-- @param $1 'dddddddd-1111-4000-8000-000000000001'
-- @param $2 'b00cb00c-0000-4000-8000-000000000327'
-- @param $3 'book'
-- @param $4 41231.5
-- @param $5 12.5
-- @param $6 0
-- @param $7 0
-- @param $8 NULL
-- @param $9 0
-- @param $10 NULL
-- @param $11 '{"libraryItemId":"1111aaaa-0000-4000-8000-000000000327","progress":0.0003}'
-- @param $12 '2026-10-28 09:12:44.512 +00:00'
-- @param $13 '2026-10-28 09:12:44.512 +00:00'
-- @param $14 'eeeeeeee-0000-4000-8000-000000000002'
-- @param $15 NULL
INSERT INTO `mediaProgresses` (`id`,`mediaItemId`,`mediaItemType`,`duration`,`currentTime`,`isFinished`,`hideFromContinueListening`,`ebookLocation`,`ebookProgress`,`finishedAt`,`extraData`,`createdAt`,`updatedAt`,`userId`,`podcastId`) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15);

-- @id abs.session.sync_update
-- @src server/managers/PlaybackSessionManager.js:433-438; server/models/PlaybackSession.js:125-160
-- @style Sequelize static Model.update(values, {where: {id}, silent: true}) with $N bind parameters
-- @tags hot-small,hotpath,dynamic
-- @note Playback session sync: full-row UPDATE (22 columns, JSON text included) by primary key on every listening sync. Reconstructed from ORM code.
-- @param $1 'fefefefe-0000-4000-8000-000000000001'
-- @param $2 'b00cb00c-0000-4000-8000-000000000327'
-- @param $3 'book'
-- @param $4 '11111111-0000-4000-8000-000000000001'
-- @param $5 'The Silent Dragon'
-- @param $6 'Hiro Abbott'
-- @param $7 41231.5
-- @param $8 0
-- @param $9 'html5'
-- @param $10 1200
-- @param $11 2140.5
-- @param $12 '2.30.0'
-- @param $13 '2026-10-28 08:52:00.000 +00:00'
-- @param $14 '2026-10-28 09:12:44.512 +00:00'
-- @param $15 'eeeeeeee-0000-4000-8000-000000000002'
-- @param $16 NULL
-- @param $17 940
-- @param $18 '/audiobooks/327/cover.jpg'
-- @param $19 '{"title":"The Silent Dragon","authors":[{"name":"Hiro Abbott"}]}'
-- @param $20 '2026-10-28'
-- @param $21 'Wednesday'
-- @param $22 '{"libraryItemId":"1111aaaa-0000-4000-8000-000000000327"}'
-- @param $23 'fefefefe-0000-4000-8000-000000000001'
UPDATE `playbackSessions` SET `id`=$1,`mediaItemId`=$2,`mediaItemType`=$3,`libraryId`=$4,`displayTitle`=$5,`displayAuthor`=$6,`duration`=$7,`playMethod`=$8,`mediaPlayer`=$9,`startTime`=$10,`currentTime`=$11,`serverVersion`=$12,`createdAt`=$13,`updatedAt`=$14,`userId`=$15,`deviceId`=$16,`timeListening`=$17,`coverPath`=$18,`mediaMetadata`=$19,`date`=$20,`dayOfWeek`=$21,`extraData`=$22 WHERE `id` = $23;

-- @id abs.scanner.book_author_insert
-- @src server/scanner/BookScanner.js:227-230; trigger from server/Database.js:884-920
-- @style Sequelize model.create() with $N bind parameters
-- @tags dynamic
-- @note Scanner links an existing author to a book: a one-row INSERT that fires the AFTER INSERT trigger rebuilding libraryItems.authorNames* with GROUP_CONCAT(... ORDER BY createdAt) over a join. Reconstructed from ORM code.
-- @param $1 'ba000000-1111-4000-8000-000000000001'
-- @param $2 'b00cb00c-0000-4000-8000-000000000008'
-- @param $3 'a0a0a0a0-0000-4000-8000-000000000096'
-- @param $4 '2026-10-28 09:12:44.512 +00:00'
INSERT INTO `bookAuthors` (`id`,`bookId`,`authorId`,`createdAt`) VALUES ($1,$2,$3,$4);
