-- KOReader (koreader/koreader @ 8012773, AGPL-3.0): reading statistics (plugins/statistics.koplugin), vocabulary
-- builder and cover browser cache. Statements are Lua long strings run through lua-ljsqlite3: most take their
-- numbers via string.format("%d") (inlined here, %% unescaped to %), the rest bind with ? (here ?N).
-- "Now" in the data is 2026-10-31 23:59:59 UTC; today starts at 1793404800. id_book 51 is a heavily re-read book
-- (3.5k page turns) partly read at another layout, so page_stat rescales it. settings.max_sec = 120 (the default).
-- The page_stat view (schema.sql) joins page_stat_data to book and a 1000-row numbers table to rescale page
-- numbers to the current layout; every statistics query reads through it. These run on e-reader ARM CPUs.
-- Results use 'localtime', so hashes depend on the machine's time zone (the corpus was recorded in UTC).

-- @id koreader.stats.book_capped_totals
-- @src plugins/statistics.koplugin/main.lua:40-49
-- @style string.format %d (settings.max_sec, id_book); run at main.lua:964 and 1005 on every page-stat flush
-- @tags hotpath,analytics
-- @note Current book's read pages and capped time: per-page SUM through the rescaling view, min() cap, outer SUM
SELECT count(*),
           sum(durations)
    FROM (
        SELECT min(sum(duration), 120) AS durations
        FROM page_stat
        WHERE id_book = 51
        GROUP BY page
    );

-- @id koreader.stats.book_totals
-- @src plugins/statistics.koplugin/main.lua:52-57
-- @style string.format %d (id_book); main.lua:280, 654, 966
-- @tags hotpath,analytics
-- @note count(DISTINCT page) and total time of one book through the view
SELECT count(DISTINCT page),
           sum(duration)
    FROM   page_stat
    WHERE  id_book = 51;

-- @id koreader.stats.book_read_days
-- @src plugins/statistics.koplugin/main.lua:270-278
-- @style string.format %d (id_book); same text at main.lua:1516 and 1699
-- @tags hotpath,analytics
-- @note Number of distinct local days a book was read: strftime(localtime) per expanded row, GROUP BY in a subquery
SELECT count(*)
        FROM   (
                    SELECT strftime('%Y-%m-%d', start_time, 'unixepoch', 'localtime') AS dates
                    FROM   page_stat
                    WHERE  id_book = 51
                    GROUP  BY dates
               );

-- @id koreader.stats.today
-- @src plugins/statistics.koplugin/main.lua:1453-1468
-- @style string.format %d (start of today)
-- @tags hotpath,analytics
-- @note "Read today" in the statistics menu: pages and time since midnight, grouped per (book, page) through the view; the start_time range can't use the index through the view's join
SELECT count(*),
               sum(sum_duration)
        FROM    (
                     SELECT sum(duration)    AS sum_duration
                     FROM   page_stat
                     WHERE  start_time >= 1793404800
                     GROUP  BY id_book, page
                );

-- @id koreader.stats.book_summary_last_page
-- @src plugins/statistics.koplugin/main.lua:1711-1719
-- @style string.format %d (id_book)
-- @tags analytics
-- @note Book statistics from history: aggregate plus a scalar subquery that references the outer max(start_time) and scans the whole view again for that timestamp
SELECT sum(duration),
               count(DISTINCT page),
               min(start_time),
               (select max(ps2.page) from page_stat as ps2 where ps2.start_time = max(page_stat.start_time))
        FROM   page_stat
        WHERE  id_book = 51;

-- @id koreader.stats.daily_30_days
-- @src plugins/statistics.koplugin/main.lua:1795-1810 (sqlDaily, via getDatesFromAll(30, "daily_weekday") at main.lua:1386)
-- @style string.format %d (period_begin = start of the day 29 days ago)
-- @tags analytics
-- @note "Last 30 days" list: per-(book, page, local day) sums, then per-day counts and sums, newest first
SELECT dates,
                   count(*)             AS pages,
                   sum(sum_duration)    AS durations,
                   start_time
            FROM   (
                        SELECT strftime('%Y-%m-%d', start_time, 'unixepoch', 'localtime') AS dates,
                               sum(duration)                                                 AS sum_duration,
                               start_time
                        FROM   page_stat
                        WHERE  start_time >= 1790899200
                        GROUP  BY id_book, page, dates
                   )
            GROUP  BY dates
            ORDER  BY dates DESC;

-- @id koreader.stats.weekly_year
-- @src plugins/statistics.koplugin/main.lua:1815-1830 (sqlWeekly, via getDatesFromAll(365, "weekly") at main.lua:1420)
-- @style string.format %d (period_begin = 364 days ago)
-- @tags analytics
-- @note "Last 52 weeks": the same two-level GROUP BY on '%Y-%W' over a year of expanded rows
SELECT dates,
                   count(*)             AS pages,
                   sum(sum_duration)    AS durations,
                   start_time
            FROM   (
                        SELECT strftime('%Y-%W', start_time, 'unixepoch', 'localtime')     AS dates,
                               sum(duration)                                                 AS sum_duration,
                               start_time
                        FROM   page_stat
                        WHERE  start_time >= 1761955200
                        GROUP  BY id_book, page, dates
                   )
            GROUP  BY dates
            ORDER  BY dates DESC;

-- @id koreader.stats.monthly_all
-- @src plugins/statistics.koplugin/main.lua:1835-1850 (sqlMonthly, via getDatesFromAll(0, "monthly") at main.lua:1437)
-- @style string.format %d (period_begin = 0: all time)
-- @tags analytics
-- @note "All months": the two-level GROUP BY over the whole 4-year history (every row through the rescaling view)
SELECT dates,
                   count(*)             AS pages,
                   sum(sum_duration)    AS durations,
                   start_time
            FROM   (
                        SELECT strftime('%Y-%m', start_time, 'unixepoch', 'localtime')     AS dates,
                               sum(duration)                                                 AS sum_duration,
                               start_time
                        FROM   page_stat
                        WHERE  start_time >= 0
                        GROUP  BY id_book, page, dates
                   )
            GROUP  BY dates
            ORDER  BY dates DESC;

-- @id koreader.stats.days_of_month
-- @src plugins/statistics.koplugin/main.lua:2027-2046
-- @style string.format %d %d (October 2026)
-- @tags analytics
-- @note Days of one month from the monthly list: BETWEEN range on start_time through the view
SELECT dates,
               count(*)             AS pages,
               sum(sum_duration)    AS durations,
               start_time
        FROM   (
                    SELECT strftime('%Y-%m-%d', start_time, 'unixepoch', 'localtime') AS dates,
                           sum(duration)                                                 AS sum_duration,
                           start_time
                    FROM   page_stat
                    WHERE  start_time BETWEEN 1790812800 AND 1793491199
                    GROUP  BY id_book, page, dates
               )
        GROUP  BY dates
        ORDER  BY dates DESC;

-- @id koreader.stats.books_of_day
-- @src plugins/statistics.koplugin/main.lua:2079-2092
-- @style string.format %d %d (period_begin + 1, period_end) for 2026-10-30
-- @tags analytics
-- @note Books read on one day: implicit join of the view and book, GROUP BY book, ordered by last_open
SELECT  book_tbl.title AS title,
                count(distinct page_stat_tbl.page),
                sum(page_stat_tbl.duration),
                book_tbl.id
        FROM    page_stat AS page_stat_tbl, book AS book_tbl
        WHERE   page_stat_tbl.id_book=book_tbl.id AND page_stat_tbl.start_time BETWEEN 1793318401 AND 1793404800
        GROUP   BY book_tbl.id
        ORDER   BY book_tbl.last_open DESC;

-- @id koreader.stats.book_days
-- @src plugins/statistics.koplugin/main.lua:2188-2201
-- @style string.format %d (id_book)
-- @tags analytics
-- @note Per-day breakdown of one book: GROUP BY an expression (Date(..., 'localtime')) with min/max
SELECT date(start_time, 'unixepoch', 'localtime') AS dates,
               count(DISTINCT page)                       AS pages,
               sum(duration)                              AS durations,
               min(start_time)                            AS min_start_time,
               max(start_time)                            AS max_start_time
        FROM   page_stat
        WHERE  id_book = 51
        GROUP  BY Date(start_time, 'unixepoch', 'localtime')
        ORDER  BY dates DESC;

-- @id koreader.stats.total_time_all
-- @src plugins/statistics.koplugin/main.lua:2272-2275
-- @style no parameters
-- @tags analytics
-- @note "Total time spent reading": SUM over the whole view (every row of page_stat_data joined to book and numbers)
SELECT sum(duration)
        FROM   page_stat;

-- @id koreader.stats.books_by_last_open
-- @src plugins/statistics.koplugin/main.lua:2281-2285
-- @style no parameters
-- @tags hot-small
-- @note Book list order (400 rows, no index on last_open)
SELECT id
        FROM   book
        ORDER  BY last_open DESC;

-- @id koreader.stats.first_read
-- @src plugins/statistics.koplugin/main.lua:2767-2770
-- @style no parameters
-- @tags analytics
-- @note Calendar's first month: min(start_time) through the view (the index on page_stat_data.start_time can't serve it through the joins)
SELECT min(start_time)
        FROM   page_stat;

-- @id koreader.calendar.ratio_per_hour
-- @src plugins/statistics.koplugin/main.lua:2777-2805
-- @style ? binds (offset, 'YYYY-MM-01', 'YYYY-MM-01')
-- @tags hotpath,analytics,cpu-evidence
-- @note Calendar view hourly histogram for a month: integer start_time bounds computed by strftime('%s', ?, 'utc', ...), GROUP BY two strftime expressions. https://github.com/koreader/koreader/pull/6807: 500 ms per calendar query on a Kobo before the boundary rewrite, ~100 ms after
-- @param ?1 0
-- @param ?2 '2026-10-01'
-- @param ?3 '2026-10-01'
SELECT
            strftime('%Y-%m-%d', start_time, 'unixepoch', 'localtime') day,
            strftime('%H', start_time, 'unixepoch', 'localtime') hour,
            sum(duration)/3600.0 ratio
        FROM  (
            SELECT
                start_time-?1 as start_time,
                duration
            FROM page_stat
            WHERE  start_time BETWEEN strftime('%s', ?2, 'utc')
                                  AND strftime('%s', ?3, 'utc', '+33 days', 'start of month', '-1 second')
        )
        GROUP  BY
            strftime('%Y-%m-%d', start_time, 'unixepoch', 'localtime'),
            strftime('%H', start_time, 'unixepoch', 'localtime')
        ORDER BY day, hour;

-- @id koreader.calendar.books_by_day
-- @src plugins/statistics.koplugin/main.lua:2825-2848
-- @style ? binds (offset, 'YYYY-MM-01', 'YYYY-MM-01')
-- @tags hotpath,analytics,cpu-evidence
-- @note Calendar view: books read per day of a month (view joined to book again), grouped by day/book/title. The second calendar query of https://github.com/koreader/koreader/pull/6807 (500 ms -> 100 ms on a Kobo)
-- @param ?1 0
-- @param ?2 '2026-10-01'
-- @param ?3 '2026-10-01'
SELECT
            strftime('%Y-%m-%d', start_time, 'unixepoch', 'localtime') day,
            sum(duration) durations,
            id_book book_id,
            title book_title
        FROM  (
            SELECT start_time-?1 as start_time, duration, page_stat.id_book, book.title
            FROM page_stat
            JOIN   book ON book.id = page_stat.id_book
            WHERE  start_time BETWEEN strftime('%s', ?2, 'utc')
                                  AND strftime('%s', ?3, 'utc', '+33 days', 'start of month', '-1 second')
        )
        GROUP  BY
            strftime('%Y-%m-%d', start_time, 'unixepoch', 'localtime'),
            id_book,
            title
        ORDER BY day, durations desc, book_id, book_title;

-- @id koreader.calendar.day_timeline
-- @src plugins/statistics.koplugin/main.lua:2865-2880
-- @style ? binds (ts, ts, ts - max_sec - gap, ts + 86400 - 1 + gap) for 2026-10-30
-- @tags hotpath
-- @note Calendar day view: raw page_stat_data spans of one day (index range on start_time), joined to book
-- @param ?1 1793318400
-- @param ?2 1793318400
-- @param ?3 1793318250
-- @param ?4 1793404829
SELECT
            start_time - ?1 as start,
            start_time - ?2 + duration as finish,
            id_book book_id,
            book.title book_title
        FROM   page_stat_data
        JOIN   book ON book.id = page_stat_data.id_book
        WHERE  start_time BETWEEN ?3 AND ?4
        ORDER BY start;

-- @id koreader.stats.book_map_pages
-- @src plugins/statistics.koplugin/main.lua:2986-3005
-- @modified 'now' pinned to '2026-10-31 23:59:59', the data's \"now\" (data.sql header), so results don't drift with the clock
-- @style ? binds (settings.max_sec, id_book)
-- @tags hotpath,analytics
-- @note Book map / page browser: per-page capped time and seconds since the last read, through the view
-- @param ?1 120
-- @param ?2 51
SELECT
          page,
          min(sum(duration), ?1) AS durations,
          strftime('%s', '2026-10-31 23:59:59') - max(start_time) AS delay
        FROM page_stat
        WHERE id_book = ?2
        GROUP BY page
        ORDER BY page;

-- @id koreader.stats.insert_page_stat
-- @src plugins/statistics.koplugin/main.lua:931-945
-- @style prepared once, ? binds per flushed page turn
-- @tags hotpath,hot-small
-- @note Page-turn flush into page_stat_data (UNIQUE (id_book, page, start_time) index maintained)
-- @param ?1 51
-- @param ?2 120
-- @param ?3 1793480000
-- @param ?4 42
-- @param ?5 610
INSERT OR IGNORE INTO page_stat_data VALUES(?1, ?2, ?3, ?4, ?5);

-- @id koreader.stats.delete_short_books
-- @src plugins/statistics.koplugin/main.lua:2513-2518
-- @style ? binds (current book id, min total_read_time)
-- @tags
-- @note "Delete books read for less than N seconds": IN-subquery over book, deleting their page_stat_data rows
-- @param ?1 51
-- @param ?2 3600
DELETE FROM page_stat_data
                    WHERE  id_book IN (
                      SELECT id FROM book WHERE id != ?1 AND (total_read_time IS NULL OR total_read_time < ?2)
                    );

-- @id koreader.sync.delete_locally_removed
-- @src plugins/statistics.koplugin/main.lua:3150-3156
-- @style one exec() script; ATTACHed income_db/cached_db
-- @tags cpu-evidence
-- @modified income_db.book -> income_book, cached_db.book -> cached_book (main-schema stand-ins; the runner can't ATTACH)
-- @note Sync step: drop page_stat_data of books deleted on the other device: nested row-value IN / NOT IN over the three book tables. The sync of https://github.com/koreader/koreader/issues/14200 takes ~4 minutes on a Kobo Libra 2 with a 1.9 MB statistics DB
DELETE FROM page_stat_data WHERE id_book IN (
                SELECT id FROM book WHERE (title, authors, md5) IN (
                    SELECT title, authors, md5 FROM cached_book WHERE (title, authors, md5) NOT IN (
                        SELECT title, authors, md5 FROM income_book
                    )
                )
            );

-- @id koreader.sync.update_last_open
-- @src plugins/statistics.koplugin/main.lua:3178-3183
-- @style one exec() script; ATTACHed income_db
-- @tags cpu-evidence
-- @modified income_db.book -> income_book (main-schema stand-in)
-- @note Sync step: UPDATE ... FROM with a row-value join condition. Part of the sync in https://github.com/koreader/koreader/issues/14200
UPDATE book AS b
        SET last_open = i.last_open
        FROM income_book AS i
        WHERE (b.title, b.authors, b.md5) = (i.title, i.authors, i.md5)
          AND i.last_open > b.last_open;

-- @id koreader.sync.insert_new_books
-- @src plugins/statistics.koplugin/main.lua:3187-3195
-- @style one exec() script; ATTACHed income_db
-- @tags batch,cpu-evidence
-- @modified income_db.book -> income_book (main-schema stand-in)
-- @note Sync step: books only the other device has, via row-value NOT IN. https://github.com/koreader/koreader/issues/14200
INSERT INTO book (
            title, authors, notes, last_open, highlights, pages, series, language, md5, total_read_time, total_read_pages
        ) SELECT
            title, authors, notes, last_open, highlights, pages, series, language, md5, total_read_time, total_read_pages
        FROM income_book
        WHERE (title, authors, md5) NOT IN (
            SELECT title, authors, md5 FROM book
        );

-- @id koreader.sync.delete_stale_stat_rows
-- @src plugins/statistics.koplugin/main.lua:3213-3219
-- @style one exec() script; ATTACHed income_db/cached_db, TEMP book_id_map
-- @tags cpu-evidence
-- @modified cached_db.page_stat_data -> cached_page_stat_data, income_db.page_stat_data -> income_page_stat_data, temp book_id_map -> main book_id_map (stand-ins)
-- @note Sync step: local rows deleted on the other device since the last sync: three-column row-value IN over a NOT IN of ~200k remote rows through a LEFT JOIN. https://github.com/koreader/koreader/issues/14200
DELETE FROM page_stat_data WHERE (id_book, page, start_time) IN (
            SELECT id_book, page, start_time FROM cached_page_stat_data WHERE (id_book, page, start_time) NOT IN (
                SELECT map.mid, page, start_time FROM income_page_stat_data
                LEFT JOIN book_id_map AS map on id_book = map.iid
            )
        );

-- @id koreader.sync.merge_page_stat
-- @src plugins/statistics.koplugin/main.lua:3221-3230
-- @style one exec() script; ATTACHed income_db, TEMP book_id_map
-- @tags batch,cpu-evidence
-- @modified income_db.page_stat_data -> income_page_stat_data, temp book_id_map -> main book_id_map (stand-ins)
-- @note Sync step: upsert ~200k remote rows into the local table (ON CONFLICT on the 3-column unique index, MAX duration). https://github.com/koreader/koreader/issues/14200
INSERT INTO page_stat_data (id_book, page, start_time, duration, total_pages)
            SELECT map.mid, page, start_time, duration, total_pages
            FROM income_page_stat_data
            INNER JOIN book_id_map as map
            ON id_book = map.iid
            WHERE map.mid IS NOT null
        ON CONFLICT(id_book, page, start_time) DO UPDATE SET
        duration = MAX(duration, excluded.duration);

-- @id koreader.sync.recompute_book_totals
-- @src plugins/statistics.koplugin/main.lua:3232-3237
-- @style one exec() script
-- @tags analytics,cpu-evidence
-- @note Sync step (also the 2021 migration, main.lua:560-564): UPDATE every book with a correlated count(DISTINCT page)/sum over the rescaling view. https://github.com/koreader/koreader/issues/14200
UPDATE book SET (total_read_pages, total_read_time) =
        (SELECT count(DISTINCT page),
                sum(duration)
         FROM   page_stat
         WHERE  id_book = book.id);

-- @id koreader.vocab.due_list
-- @src plugins/vocabbuilder.koplugin/db.lua:150-162
-- @style string.format / concatenation (reload_time inlined, LIMIT 32 OFFSET start_idx-1)
-- @tags hotpath
-- @note Vocabulary builder review list: words due before now from enabled titles, newest due first
SELECT * FROM vocabulary INNER JOIN title
                              ON title_id = title.id AND filter = true
                              WHERE due_time <= 1793491199 ORDER BY due_time desc limit 32 OFFSET 0;

-- @id koreader.vocab.count_due
-- @src plugins/vocabbuilder.koplugin/db.lua:44-53
-- @style concatenation (reload_time inlined)
-- @tags hotpath,analytics
-- @note Vocabulary count for the enabled titles
SELECT count(0) FROM vocabulary INNER JOIN title ON filter=true AND title_id=id WHERE due_time <= 1793491199;

-- @id koreader.vocab.has_word
-- @src plugins/vocabbuilder.koplugin/db.lua:304-308
-- @style ? bind
-- @tags hot-small
-- @note Dictionary lookup hook: one word by primary key, joined to its title
-- @param ?1 'word00120a'
SELECT title.name as book_title, vocabulary.word, create_time, review_time, due_time, review_count, streak_count, prev_context, next_context, highlight
          FROM vocabulary INNER JOIN title ON title_id = title.id WHERE word = ?1;

-- @id koreader.bookinfo.get
-- @src plugins/coverbrowser.koplugin/bookinfomanager.lua:114-115
-- @style prepared once (column list built from BOOKINFO_COLS_SET), ? binds; run per file shown in the mosaic/list
-- @tags hotpath,hot-small
-- @note Cover browser: one cached book by (directory, filename) unique index
-- @param ?1 '/mnt/onboard/Books/Fiction/'
-- @param ?2 'book_12.epub'
SELECT directory,filename,filesize,filemtime,in_progress,unsupported,cover_fetched,has_meta,has_cover,cover_sizetag,ignore_meta,ignore_cover,pages,title,authors,series,series_index,language,keywords,description,cover_w,cover_h,cover_bb_type,cover_bb_stride,cover_bb_data FROM bookinfo WHERE directory=?1 AND filename=?2 AND in_progress=0;

