-- Anki (ankitects/anki @ d87cb22, AGPL-3.0-or-later). rusqlite with `?`, `?N` and `:name` parameters. Most statements
-- are .sql files under rslib/src/storage/ that Rust includes with include_str! and often extends with concat!/format!
-- (a WHERE or ORDER BY tail); browser searches are built by rslib/src/search/sqlwriter.rs. Clock used throughout:
-- collection day 1500, now = 1767200000, next_day_at = 1767240000 (learn-ahead 1200 s). Anki registers fnvhash(),
-- regexp_fields(), process_text(), extract_fsrs_*() and a Rust `regexp`; those are avoided or substituted (@modified).

-- @id anki.deck_tree.due_counts
-- @src rslib/src/storage/deck/due_counts.sql:1-28 (+ " group by did" in rslib/src/storage/deck/mod.rs:310)
-- @style :name named
-- @tags hotpath
-- @note The deck list's per-deck new/review/learn counts: one full pass over cards with five boolean-sum aggregates, grouped by deck.
-- @param :new_queue 0
-- @param :review_queue 2
-- @param :day_cutoff 1500
-- @param :daylearn_queue 3
-- @param :learn_queue 1
-- @param :learn_cutoff 1767201200
-- @param :preview_queue 4
SELECT did,
  sum(queue = :new_queue),
  sum(queue = :review_queue AND due <= :day_cutoff),
  sum(queue = :daylearn_queue AND due <= :day_cutoff),
  sum(((queue = :learn_queue AND due < :learn_cutoff) OR (queue = :preview_queue AND due <= :learn_cutoff))),
  COUNT(1)
FROM cards
group by did;

-- @id anki.scheduler.deck_due_counts
-- @src rslib/src/storage/card/deck_due_counts.sql:1-13
-- @style none
-- @note Review load forecast per (original deck, due day): CASE-computed grouping keys over all review cards.
SELECT CASE WHEN odid == 0 THEN did ELSE odid END AS original_did,
  CASE WHEN odid == 0 THEN due ELSE odue END AS true_due,
  COUNT() AS COUNT
FROM cards
WHERE type = 2 AND queue != -1
GROUP BY original_did, true_due;

-- @id anki.queue.due_reviews_day_order
-- @src rslib/src/storage/card/due_cards.sql:1-16 (ORDER BY from review_order_sql, rslib/src/storage/card/mod.rs:294-298, 860-905)
-- @style ? positional, ORDER BY appended with format!
-- @tags hotpath,dynamic
-- @note Queue builder: due reviews in the active deck tree (IN over the active_decks temp table), ordered by day then a per-card hash.
-- @modified the app's fnvhash(id, mod) tiebreak (a Rust-registered function) is replaced by ((id * 2654435761 + mod) % 4294967296)
-- @param ?1 2
-- @param ?2 1500
SELECT id, nid, due, cast(ivl AS integer), cast(mod AS integer), did, odid, reps
FROM cards
WHERE did IN (SELECT id FROM active_decks)
  AND (queue = ?1 AND due <= ?2)
order by due, ((id * 2654435761 + mod) % 4294967296);

-- @id anki.queue.due_reviews_deck_then_day
-- @src rslib/src/storage/card/due_cards.sql:1-16 (ReviewCardOrder::DeckThenDay, rslib/src/storage/card/mod.rs:817-823, 860-905)
-- @style ? positional, ORDER BY appended with format!
-- @tags hotpath,dynamic
-- @note Same gather with the deck-then-day order: a correlated rowid lookup in active_decks per card as the leading sort key.
-- @modified fnvhash(id, mod) replaced by ((id * 2654435761 + mod) % 4294967296)
-- @param ?1 2
-- @param ?2 1500
SELECT id, nid, due, cast(ivl AS integer), cast(mod AS integer), did, odid, reps
FROM cards
WHERE did IN (SELECT id FROM active_decks)
  AND (queue = ?1 AND due <= ?2)
order by (select rowid from active_decks ad where ad.id = did), due, ((id * 2654435761 + mod) % 4294967296);

-- @id anki.queue.due_reviews_relative_overdueness
-- @src rslib/src/storage/card/mod.rs:838-850 (RelativeOverdueness, fsrs off) with rslib/src/storage/card/due_cards.sql:1-16
-- @style ? positional, ORDER BY appended with format!
-- @tags dynamic
-- @note Review order "relative overdueness": an arithmetic sort key with an inline day constant, so every card is sorted by a computed real.
-- @modified fnvhash(id, mod) replaced by ((id * 2654435761 + mod) % 4294967296)
-- @param ?1 2
-- @param ?2 1500
SELECT id, nid, due, cast(ivl AS integer), cast(mod AS integer), did, odid, reps
FROM cards
WHERE did IN (SELECT id FROM active_decks)
  AND (queue = ?1 AND due <= ?2)
order by -(1 + cast(1500-due+0.001 as real)/ivl) asc, ((id * 2654435761 + mod) % 4294967296);

-- @id anki.queue.intraday_learning
-- @src rslib/src/storage/card/intraday_due.sql:1-15 (rslib/src/storage/card/mod.rs:262)
-- @style ? positional
-- @tags hotpath
-- @note Learning cards due before the learn-ahead cutoff (epoch seconds) in the active decks.
-- @param ?1 1767201200
SELECT id, nid, due, cast(mod AS integer), did, odid, reps
FROM cards
WHERE did IN (SELECT id FROM active_decks)
  AND (queue IN (1, 4) AND due <= ?1);

-- @id anki.queue.new_cards_active_decks
-- @src rslib/src/storage/card/active_new_cards.sql:1-11 (ORDER BY NewCardSorting::LowestPosition, rslib/src/storage/card/mod.rs:358-362, 926)
-- @style none, ORDER BY appended with format!
-- @tags hotpath,dynamic
-- @note New-card gather for the active deck tree, by position then template ordinal.
SELECT id, nid, ord, cast(mod AS integer), did, odid
FROM cards
WHERE did IN (SELECT id FROM active_decks)
  AND queue = 0
ORDER BY due ASC, ord ASC;

-- @id anki.queue.new_cards_in_deck
-- @src rslib/src/storage/card/new_cards.sql:1-8 (ORDER BY NewCardSorting::HighestPosition, rslib/src/storage/card/mod.rs:333-337, 927)
-- @style ? positional, ORDER BY appended with format!
-- @tags hotpath,dynamic
-- @note Per-deck new-card gather (deck-by-deck new order), newest position first.
-- @param ?1 1600000000001
SELECT id, nid, ord, cast(mod AS integer), did, odid
FROM cards
WHERE did = ?1
  AND queue = 0
ORDER BY due DESC, ord ASC;

-- @id anki.scheduler.congrats
-- @src rslib/src/storage/card/congrats.sql:1-27 (rslib/src/storage/card/mod.rs:668-695)
-- @style :name named
-- @note Congrats screen: six conditional aggregates over the active decks, with nested coalesce/max/min(CASE).
-- @param :review_queue 2
-- @param :day_learn_queue 3
-- @param :today 1500
-- @param :new_queue 0
-- @param :sched_buried_queue -2
-- @param :user_buried_queue -3
-- @param :learn_queue 1
SELECT coalesce(sum(queue IN (:review_queue, :day_learn_queue) AND due <= :today), 0) AS review_count,
  coalesce(sum(queue = :new_queue), 0) AS new_count,
  coalesce(sum(queue = :sched_buried_queue), 0) AS sched_buried,
  coalesce(sum(queue = :user_buried_queue), 0) AS user_buried,
  coalesce(sum(queue = :learn_queue), 0) AS learn_count,
  max(0, coalesce(min(CASE WHEN queue = :learn_queue THEN due ELSE NULL END), 0)) AS first_learn_due
FROM cards
WHERE did IN (SELECT id FROM active_decks);

-- @id anki.scheduler.studied_today
-- @src rslib/src/storage/revlog/studied_today.sql:1-5 (rslib/src/storage/revlog/mod.rs:185)
-- @style ? positional
-- @tags hotpath
-- @note "Studied N cards in M minutes today" under the deck list: range scan on the revlog id (ms timestamp).
-- @param ?1 1767153600000
-- @param ?2 4
-- @param ?3 5
SELECT COUNT(), coalesce(sum(time) / 1000.0, 0.0)
FROM revlog
WHERE id > ?1 AND type != ?2 AND type != ?3;

-- @id anki.scheduler.studied_today_by_deck
-- @src rslib/src/storage/revlog/studied_today_by_deck.sql:1-13 (rslib/src/storage/revlog/mod.rs:210)
-- @style ? positional
-- @tags hotpath
-- @note Today's distinct reviewed cards per original deck: revlog range joined to cards, COUNT(DISTINCT) grouped by a CASE key.
-- @param ?1 1767153600000
SELECT CASE WHEN c.odid == 0 THEN c.did ELSE c.odid END AS original_did,
  COUNT(DISTINCT r.cid) AS cnt
FROM revlog AS r
  JOIN cards AS c ON r.cid = c.id
WHERE r.id > ?1
  AND r.ease > 0
  AND (r.type < 3 OR r.factor != 0)
GROUP BY original_did;

-- @id anki.revlog.time_of_last_review
-- @src rslib/src/storage/revlog/time_of_last_review.sql:1-9 (rslib/src/storage/revlog/mod.rs:100)
-- @style $1 positional
-- @tags hot-small,hotpath
-- @note Per answered card: newest real review via ix_revlog_cid, top-1 by id.
-- @param $1 1719148000000
SELECT id / 1000
FROM revlog
WHERE cid = $1
  AND ease BETWEEN 1 AND 4
  AND (type != 3 OR factor != 0)
ORDER BY id DESC
LIMIT 1;

-- @id anki.card.get_by_id
-- @src rslib/src/storage/card/get_card.sql:1-18 (+ " where id = ?", rslib/src/storage/card/mod.rs:127)
-- @style ? positional
-- @tags hot-small,hotpath
-- @note Card fetch on every review and every browser row.
-- @param ?1 1729453600001
SELECT id, nid, did, ord, cast(mod AS integer), usn, type, queue, due, cast(ivl AS integer), factor, reps, lapses, left, odue, odid, flags, data
FROM cards
where id = ?1;

-- @id anki.note.get_by_id
-- @src rslib/src/storage/note/get.sql:1-9 (+ " where id = ?", rslib/src/storage/note/mod.rs:29)
-- @style ? positional
-- @tags hot-small,hotpath
-- @note Note fetch when rendering a card or editing.
-- @param ?1 1719208000000
SELECT id, guid, mid, mod, usn, tags, flds, cast(sfld AS text), csum
FROM notes
where id = ?1;

-- @id anki.card.add
-- @src rslib/src/storage/card/add_card.sql:1-50 (rslib/src/storage/card/mod.rs:167)
-- @style ?1 then ? positional
-- @tags hot-small
-- @note Adding a card: the id is taken as given unless it collides, then max(id)+1, via a CASE with IN and scalar subqueries in VALUES.
-- @param ?1 1767100000000
-- @param ?2 1767100000000
-- @param ?3 1600000000001
-- @param ?4 3
-- @param ?5 1767200000
-- @param ?6 -1
-- @param ?7 0
-- @param ?8 0
-- @param ?9 20001
-- @param ?10 0
-- @param ?11 0
-- @param ?12 0
-- @param ?13 0
-- @param ?14 0
-- @param ?15 0
-- @param ?16 0
-- @param ?17 0
-- @param ?18 ''
INSERT INTO cards (id, nid, did, ord, mod, usn, type, queue, due, ivl, factor, reps, lapses, left, odue, odid, flags, data)
VALUES ((CASE WHEN ?1 IN (SELECT id FROM cards) THEN (SELECT max(id) + 1 FROM cards) ELSE ?1 END),
  ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15, ?16, ?17, ?18);

-- @id anki.revlog.add
-- @src rslib/src/storage/revlog/add.sql:1-34 (rslib/src/storage/revlog/mod.rs:73)
-- @style ?1/?2 then ? positional
-- @tags hot-small,hotpath
-- @note Logging an answer: INSERT OR IGNORE with a collision-avoiding CASE id.
-- @param ?1 1
-- @param ?2 1767200000000
-- @param ?3 1719148000000
-- @param ?4 -1
-- @param ?5 3
-- @param ?6 12
-- @param ?7 5
-- @param ?8 2500
-- @param ?9 6400
-- @param ?10 1
INSERT OR IGNORE INTO revlog (id, cid, usn, ease, ivl, lastIvl, factor, time, type)
VALUES ((CASE WHEN ?1 AND ?2 IN (SELECT id FROM revlog) THEN (SELECT max(id) + 1 FROM revlog) ELSE ?2 END),
  ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10);

-- @id anki.card.update
-- @src rslib/src/storage/card/update_card.sql:1-18 (rslib/src/storage/card/mod.rs:141)
-- @style ? positional
-- @tags hot-small,hotpath
-- @note After every answer: full-row card update by id.
-- @param ?1 1719208000000
-- @param ?2 1600000000003
-- @param ?3 0
-- @param ?4 1767200100
-- @param ?5 -1
-- @param ?6 2
-- @param ?7 2
-- @param ?8 1530
-- @param ?9 30
-- @param ?10 2500
-- @param ?11 9
-- @param ?12 1
-- @param ?13 0
-- @param ?14 0
-- @param ?15 0
-- @param ?16 0
-- @param ?17 ''
-- @param ?18 1719208000000
UPDATE cards
SET nid = ?1, did = ?2, ord = ?3, mod = ?4, usn = ?5, type = ?6, queue = ?7, due = ?8, ivl = ?9, factor = ?10,
  reps = ?11, lapses = ?12, left = ?13, odue = ?14, odid = ?15, flags = ?16, data = ?17
WHERE id = ?18;

-- @id anki.card.siblings_for_bury
-- @src rslib/src/storage/card/siblings_for_bury.sql:1-18 (rslib/src/storage/card/mod.rs:531-560)
-- @style :name named
-- @tags hotpath
-- @note Burying siblings after an answer: INSERT ... SELECT with parameter-gated OR branches on queue.
-- @param :card_id 1719208000001
-- @param :note_id 1719208000000
-- @param :include_new 1
-- @param :new_queue 0
-- @param :include_reviews 1
-- @param :review_queue 2
-- @param :include_day_learn 0
-- @param :daylearn_queue 3
INSERT OR IGNORE INTO search_cids
SELECT id
FROM cards
WHERE id != :card_id
  AND nid = :note_id
  AND ((:include_new AND queue = :new_queue)
    OR (:include_reviews AND queue = :review_queue)
    OR (:include_day_learn AND queue = :daylearn_queue));

-- @id anki.browser.search_text_sort_field
-- @src rslib/src/search/sqlwriter.rs:73-86, 206-300 (write_table_sql + write_unqualified), sort from rslib/src/search/mod.rs:376
-- @style ?1 positional, text built by SqlWriter
-- @tags hotpath,dynamic
-- @note Browser search `casa -is:suspended` in card mode sorted by sort field: double LIKE over sfld/flds with ESCAPE, NOT state filter, NOCASE sort.
-- @param ?1 '%casa%'
select c.id from cards c, notes n where c.nid=n.id and ((n.sfld like ?1 escape '\' or n.flds like ?1 escape '\') and not (c.queue = -1)) order by n.sfld collate nocase asc, c.ord asc;

-- @id anki.browser.search_deck_due
-- @src rslib/src/search/sqlwriter.rs:505-538 (write_deck), 460-503 (write_state, Due); sort from rslib/src/search/mod.rs:367
-- @style ?1 positional, text built by SqlWriter
-- @tags hotpath,dynamic,regexp
-- @note `deck:Spanish is:due` sorted by due: deck-name REGEXP subqueries (did or odid), a two-branch due predicate and a CASE sort key.
-- @modified the app binds '(?i)^Spanish($|\x1f)' for its Rust regexp; the CLI's regexp has no (?i) flag, so the pattern is '^Spanish($|' || char(31) || ')'
-- @param ?1 '^Spanish($|' || char(31) || ')'
select c.id from cards c where ((c.did in (select id from decks where name regexp ?1) or (c.odid != 0 and c.odid in (select id from decks where name regexp ?1))) and ((c.queue in (2,3) and c.due <= 1500) or (c.queue in (1,4) and c.due <= 1767201200))) order by (case when c.due > 1000000000 or c.type = 0 then due else (due - 1500) * 86400 + 1767200000 end) asc;

-- @id anki.browser.search_notes_tag_added
-- @src rslib/src/search/sqlwriter.rs:73-86 (notes mode), 303-334 (write_tag), 881-885 (write_added); sort from rslib/src/search/mod.rs:405
-- @style ?1 positional, text built by SqlWriter
-- @tags hotpath,dynamic,regexp
-- @note Notes-mode browser `tag:med::* added:400`: SELECT DISTINCT over the cards-notes join, tag REGEXP, id-as-timestamp cutoff, NOCASE sort.
-- @modified the app's pattern is '(?i).* med::.*(::| ).*' for its Rust regexp; the CLI regexp has no (?i), so the flag is dropped
-- @param ?1 '.* med::\S*(::| ).*'
select distinct n.id from cards c, notes n where c.nid=n.id and (n.tags regexp ?1 and c.id > 1732680000000) order by n.sfld collate nocase asc;

-- @id anki.browser.search_rated_sorted_by_deck
-- @src rslib/src/search/sqlwriter.rs:336-372 (write_rated), 407 (prop:ivl); sort from rslib/src/search/mod.rs:366 + rslib/src/search/deck_order.sql
-- @style text built by SqlWriter, no args
-- @tags dynamic
-- @note `rated:7:1 prop:ivl>30` sorted by the Deck column: IN (revlog subquery) and a correlated sort_order lookup as the ORDER BY key.
select c.id from cards c where (c.id in (select cid from revlog where id >= 1766635200000 and ease = 1) and ivl > 30) order by (select pos from sort_order where did = c.did) asc;

-- @id anki.browser.search_introduced_into_table
-- @src rslib/src/search/sqlwriter.rs:893-908 (write_introduced), rslib/src/search/mod.rs:227-252 (search_cards_into_table)
-- @style text built by SqlWriter, no args
-- @tags dynamic,batch
-- @note `introduced:30` into search_cids: correlated min(id) per card from revlog plus a redundant IN to speed it up.
INSERT OR IGNORE INTO search_cids select c.id from cards c where (((SELECT coalesce(min(id) > 1764648000000, false) FROM revlog WHERE cid = c.id AND ease != 0) AND c.id IN (SELECT cid FROM revlog WHERE id > 1764648000000)));

-- @id anki.browser.search_template_name_flag
-- @src rslib/src/search/sqlwriter.rs:553-572 (write_template), 187 (flag)
-- @style ? positional, text built by SqlWriter
-- @tags dynamic
-- @note `"card:Card 2" flag:1` sorted by note creation: row-value IN over templates.
-- @param ?1 'Card 2'
select c.id from cards c, notes n where c.nid=n.id and ((n.mid,c.ord) in (select ntid,ord from templates where name = ?1) and (c.flags & 7) == 1) order by n.id asc, c.ord asc;

-- @id anki.browser.sort_notes_by_deck
-- @src rslib/src/search/note_decks_order.sql:1-19 (prepare_sort, rslib/src/search/mod.rs:415-443)
-- @style none
-- @tags batch
-- @note Notes-mode Deck column sort setup: cards joined to a row_number() window over decks, grouped by note, ordered by COUNT(DISTINCT did) then deck position.
INSERT INTO sort_order (nid)
SELECT nid
FROM cards
  JOIN (SELECT id, row_number() OVER(ORDER BY name) AS pos FROM decks) decks ON cards.did = decks.id
GROUP BY nid
ORDER BY COUNT(DISTINCT did), decks.pos;

-- @id anki.browser.decks_of_search_notes
-- @src rslib/src/storage/deck/all_decks_of_search_notes.sql:1-8 (rslib/src/storage/deck/mod.rs:150)
-- @style none
-- @note First card's deck per searched note via SQLite's bare-column HAVING ord = MIN(ord).
SELECT nid, did
FROM cards
WHERE nid IN (SELECT nid FROM search_nids)
GROUP BY nid
HAVING ord = MIN(ord);

-- @id anki.browser.decks_and_original_of_search_cards
-- @src rslib/src/storage/deck/mod.rs:135-145 (get_deck.sql + all_decks_and_original_of_search_cards.sql)
-- @style none
-- @note Decks for the selected cards: get_deck wrapped around a CTE + UNION of did and odid.
SELECT id, name, mtime_secs, usn, common, kind
FROM decks
WHERE id IN (
  WITH cids AS (SELECT cid FROM search_cids)
  SELECT did FROM cards WHERE id IN cids
  UNION
  SELECT odid FROM cards WHERE odid != 0 AND id IN cids
);

-- @id anki.stats.revlog_for_search
-- @src rslib/src/storage/revlog/get.sql:1-9 (+ " where cid in (select cid from search_cids) order by cid, id", rslib/src/storage/revlog/mod.rs:149-151)
-- @style none
-- @tags hotpath
-- @note Stats/graphs input: every review of the searched cards in (cid, id) order.
SELECT id, cid, usn, ease, cast(ivl AS integer), cast(lastIvl AS integer), factor, time, type
FROM revlog
where cid in (select cid from search_cids) order by cid, id;

-- @id anki.notetype.use_counts
-- @src rslib/src/storage/notetype/get_use_counts.sql:1-8 (rslib/src/storage/notetype/mod.rs:156)
-- @style none
-- @note Note types manager: correlated COUNT(*) per notetype.
SELECT nt.id, nt.name, (SELECT COUNT(*) FROM notes n WHERE nt.id = n.mid)
FROM notetypes nt
ORDER BY nt.name;

-- @id anki.deck.children_by_name_range
-- @src rslib/src/storage/deck/get_deck.sql:1-6 (+ " where name >= ? and name < ? order by name", rslib/src/storage/deck/mod.rs:234-241)
-- @style ? positional
-- @tags hot-small
-- @note Child decks of a parent: a half-open name range on the NOCASE unique index (parent + \x1f to parent + \x20).
-- @param ?1 'Spanish' || char(31)
-- @param ?2 'Spanish' || char(32)
SELECT id, name, mtime_secs, usn, common, kind
FROM decks
where name >= ?1 and name < ?2 order by name;
