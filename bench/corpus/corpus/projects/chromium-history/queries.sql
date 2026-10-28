-- Chromium History / Shortcuts / Top Sites (chromium/chromium @ f7be3cef8a9d088c63aced58e025afdceaf2aede, BSD-3-Clause).
-- sql::Statement with ? placeholders bound 0-based in C++; normalised to ?N. Column lists come from the
-- HISTORY_URL_ROW_FIELDS (url_database.h:376) and HISTORY_VISIT_ROW_FIELDS (visit_database.h:399) macros, expanded.
-- Times are Chromium internal values (microseconds since 1601); 'now' is 13407776000000000 in the synthetic data.

-- @id chromium.url.get_row
-- @src components/history/core/browser/url_database.cc:131-132
-- @style ? positional (sql::Statement Bind*, 0-based)
-- @tags hot-small,hotpath
-- @note URLRow by id: the most frequent history lookup (omnibox, sync, visit enrichment).
-- @param ?1 803
SELECT urls.id, urls.url, urls.title, urls.visit_count, urls.typed_count, urls.last_visit_time, urls.hidden FROM urls WHERE id=?1;

-- @id chromium.url.get_rows_in
-- @src components/history/core/browser/url_database.cc:161-170
-- @style ? positional; IN list of up to 250 placeholders built in C++ (one 12-id instance)
-- @tags hotpath,dynamic
-- @note Batch URLRow fetch for a history page of visits: rowid IN-list.
-- @param ?1 3
-- @param ?2 17
-- @param ?3 803
-- @param ?4 804
-- @param ?5 805
-- @param ?6 1200
-- @param ?7 2500
-- @param ?8 4000
-- @param ?9 7301
-- @param ?10 12000
-- @param ?11 20000
-- @param ?12 29878
SELECT urls.id, urls.url, urls.title, urls.visit_count, urls.typed_count, urls.last_visit_time, urls.hidden FROM urls WHERE id IN (?1,?2,?3,?4,?5,?6,?7,?8,?9,?10,?11,?12);

-- @id chromium.url.get_row_for_url
-- @src components/history/core/browser/url_database.cc:193-194
-- @style ? positional
-- @tags hot-small,hotpath
-- @note URL text -> row via urls_url_index; runs on every navigation commit.
-- @param ?1 'https://www.site21.com/a/2/page-804'
SELECT urls.id, urls.url, urls.title, urls.visit_count, urls.typed_count, urls.last_visit_time, urls.hidden FROM urls WHERE url=?1;

-- @id chromium.url.add_url
-- @src components/history/core/browser/url_database.cc:229-239
-- @style ? positional (ADDURL_COMMON_SUFFIX macro)
-- @tags hot-small,hotpath
-- @note New URL row on first visit.
-- @param ?1 'https://www.site21.com/a/2/new-page'
-- @param ?2 'New page'
-- @param ?3 1
-- @param ?4 0
-- @param ?5 13407776000000000
-- @param ?6 0
INSERT INTO urls (url, title, visit_count, typed_count, last_visit_time, hidden) VALUES (?1,?2,?3,?4,?5,?6);

-- @id chromium.url.significant_enumerator
-- @src components/history/core/browser/url_database.cc:365-374
-- @style ? positional; AutocompleteAgeThreshold() = now - 3 days, kLowQualityMatchVisitLimit=4, kLowQualityMatchTypedLimit=1
-- @tags hotpath
-- @note In-memory URL index (HistoryQuickProvider) rebuild: OR of three thresholds over all urls, 3-key sort in a temp b-tree.
-- @param ?1 13407516800000000
-- @param ?2 4
-- @param ?3 1
SELECT urls.id, urls.url, urls.title, urls.visit_count, urls.typed_count, urls.last_visit_time, urls.hidden FROM urls WHERE hidden = 0 AND (last_visit_time >= ?1 OR visit_count >= ?2 OR typed_count >= ?3) ORDER BY typed_count DESC, last_visit_time DESC, visit_count DESC;

-- @id chromium.url.autocomplete_prefix
-- @src components/history/core/browser/url_database.cc:396-403
-- @style ? positional; upper bound = prefix + 0xFF byte (database_utils::UpperBoundString)
-- @tags hotpath
-- @note HistoryURLProvider prefix match as the user types: url range scan on the index, top-N by typed/visit counts.
-- @param ?1 'https://www.site'
-- @param ?2 'https://www.site' || CAST(x'ff' AS TEXT)
-- @param ?3 6
SELECT urls.id, urls.url, urls.title, urls.visit_count, urls.typed_count, urls.last_visit_time, urls.hidden FROM urls WHERE url >= ?1 AND url < ?2 AND hidden = 0 ORDER BY typed_count DESC, visit_count DESC, last_visit_time DESC LIMIT ?3;

-- @id chromium.url.autocomplete_prefix_typed
-- @src components/history/core/browser/url_database.cc:388-395
-- @style ? positional; typed_only branch (IsTypedHost probes)
-- @tags hotpath
-- @note Typed-only variant used by IsTypedHost per scheme: same range scan plus typed_count > 0, LIMIT 1.
-- @param ?1 'https://github.com/'
-- @param ?2 'https://github.com/' || CAST(x'ff' AS TEXT)
-- @param ?3 1
SELECT urls.id, urls.url, urls.title, urls.visit_count, urls.typed_count, urls.last_visit_time, urls.hidden FROM urls WHERE url >= ?1 AND url < ?2 AND hidden = 0 AND typed_count > 0 ORDER BY typed_count DESC, visit_count DESC, last_visit_time DESC LIMIT ?3;

-- @id chromium.url.shortest_from_base
-- @src components/history/core/browser/url_database.cc:459-466
-- @style mixed ? and :end (StrCat; allow_base picks >=); parameter numbering ?1 :end ?3 ?4
-- @tags hotpath,dynamic
-- @note FindShortestURLFromBase: URLs that are prefixes of the typed URL, url = substr(:end, 1, length(url)) evaluated per candidate.
-- @param ?1 'https://github.com/'
-- @param :end 'https://github.com/a/12/page-99999'
-- @param ?3 1
-- @param ?4 0
SELECT urls.id, urls.url, urls.title, urls.visit_count, urls.typed_count, urls.last_visit_time, urls.hidden FROM urls WHERE url >= ?1 AND url < :end AND url = substr(:end, 1, length(url)) AND hidden = 0 AND visit_count >= ?3 AND typed_count >= ?4 ORDER BY url;

-- @id chromium.url.typed_or_searched
-- @src components/history/core/browser/url_database.cc:355-358
-- @style no parameters
-- @note InitURLEnumeratorForTypedOrSearched (in-memory DB load): OR with an IN-subquery over keyword_search_terms.
SELECT urls.id, urls.url, urls.title, urls.visit_count, urls.typed_count, urls.last_visit_time, urls.hidden FROM urls WHERE typed_count > 0 OR id IN (SELECT url_id FROM keyword_search_terms);

-- @id chromium.keyword.prefix_terms
-- @src components/history/core/browser/url_database.cc:725-739
-- @style ? positional; next_prefix = prefix with last char +1
-- @tags hotpath
-- @note Search suggestions from history while typing in a search keyword: index range on (keyword_id, normalized_term) joined to urls, ordered.
-- @param ?1 2
-- @param ?2 'ber'
-- @param ?3 'bes'
SELECT kst.term, kst.normalized_term, u.visit_count, u.last_visit_time FROM keyword_search_terms kst JOIN urls u ON kst.url_id = u.id WHERE kst.keyword_id = ?1 AND kst.normalized_term >= ?2 AND kst.normalized_term < ?3 ORDER BY kst.normalized_term, u.last_visit_time;

-- @id chromium.keyword.term_aggregate
-- @src components/history/core/browser/url_database.cc:641-644
-- @style ? positional
-- @note Visit/typed totals for one normalized term: join + GROUP BY.
-- @param ?1 'berlin flights'
SELECT SUM(u.visit_count), SUM(u.typed_count), MAX(u.last_visit_time) FROM keyword_search_terms kst JOIN urls u ON kst.url_id = u.id WHERE kst.normalized_term=?1 GROUP BY kst.normalized_term;

-- @id chromium.visit.add_visit
-- @src components/history/core/browser/visit_database.cc:383-390
-- @style ? positional
-- @tags hot-small,hotpath
-- @note Insert of every navigation (17 columns, 4 secondary indexes).
-- @param ?1 803
-- @param ?2 13407776000001000
-- @param ?3 0
-- @param ?4 ''
-- @param ?5 805306368
-- @param ?6 803
-- @param ?7 0
-- @param ?8 0
-- @param ?9 0
-- @param ?10 ''
-- @param ?11 0
-- @param ?12 0
-- @param ?13 0
-- @param ?14 0
-- @param ?15 1
-- @param ?16 0
-- @param ?17 NULL
INSERT INTO visits (url, visit_time, from_visit, external_referrer_url, transition, segment_id, visit_duration, incremented_omnibox_typed_score,opener_visit, originator_cache_guid, originator_visit_id, originator_from_visit, originator_opener_visit, is_known_to_sync, consider_for_ntp_most_visited, visited_link_id, app_id) VALUES (?1,?2,?3,?4,?5,?6,?7,?8,?9,?10,?11,?12,?13,?14,?15,?16,?17);

-- @id chromium.visit.visible_in_range
-- @src components/history/core/browser/visit_database.cc:599-719
-- @style ? positional; PrepareVisibleVisitsQuery with user visits only (not actor), kExclude404s, RECENT_FIRST, no url/client/app filter
-- @tags hotpath,dynamic
-- @note chrome://history page: last day of visits with LEFT JOIN visit_source + LEFT OUTER JOIN context_annotations, IFNULL, time-index range, ordered newest first.
-- @param ?1 6
-- @param ?2 13407689600000000
-- @param ?3 13407776000000000
SELECT visits.id,visits.url,visits.visit_time,visits.from_visit,visits.external_referrer_url,visits.transition,visits.segment_id,visits.visit_duration,visits.incremented_omnibox_typed_score,visits.opener_visit,visits.originator_cache_guid,visits.originator_visit_id,visits.originator_from_visit,visits.originator_opener_visit,visits.is_known_to_sync,visits.consider_for_ntp_most_visited,visits.visited_link_id,visits.app_id, IFNULL(visit_source.source, 1) FROM visits LEFT JOIN visit_source ON visits.id = visit_source.id LEFT OUTER JOIN context_annotations ON visits.id = context_annotations.visit_id WHERE (visit_source.source IS NULL OR visit_source.source != ?1) AND (context_annotations.response_code IS NULL OR context_annotations.response_code != 404) AND visits.visit_time >= ?2 AND visits.visit_time < ?3 ORDER BY visits.visit_time DESC, visits.id DESC;

-- @id chromium.visit.visible_for_url_synced
-- @src components/history/core/browser/visit_database.cc:599-719
-- @style ? positional; PrepareVisibleVisitsQuery with url_id, restrict_to_synced_urls, two client_ids where one is the local device (adds IS NULL / '' arm), OLDEST_FIRST
-- @tags hotpath,dynamic
-- @note Visits to one URL from selected devices: url index + OR'd IN-list on originator_cache_guid, two outer joins.
-- @param ?1 6
-- @param ?2 3
-- @param ?3 0
-- @param ?4 13407776000000000
-- @param ?5 'aWlHeY3Lm9xq8Kt1Zp0aRg=='
-- @param ?6 'TG9jYWxEZXZpY2VHdWlk'
SELECT visits.id,visits.url,visits.visit_time,visits.from_visit,visits.external_referrer_url,visits.transition,visits.segment_id,visits.visit_duration,visits.incremented_omnibox_typed_score,visits.opener_visit,visits.originator_cache_guid,visits.originator_visit_id,visits.originator_from_visit,visits.originator_opener_visit,visits.is_known_to_sync,visits.consider_for_ntp_most_visited,visits.visited_link_id,visits.app_id, IFNULL(visit_source.source, 1) FROM visits LEFT JOIN visit_source ON visits.id = visit_source.id LEFT OUTER JOIN context_annotations ON visits.id = context_annotations.visit_id WHERE (visit_source.source IS NULL OR visit_source.source != ?1) AND (context_annotations.response_code IS NULL OR context_annotations.response_code != 404) AND visits.url = ?2 AND visits.visit_time > ?3 AND visits.visit_time <= ?4 AND visits.is_known_to_sync = 1 AND (visits.originator_cache_guid IN (?5, ?6) OR visits.originator_cache_guid IS NULL OR visits.originator_cache_guid = '') ORDER BY visits.visit_time ASC, visits.id DESC;

-- @id chromium.visit.most_recent_for_url
-- @src components/history/core/browser/visit_database.cc:875-882
-- @style ? positional; kExclude404s branch
-- @tags hot-small,hotpath
-- @note Latest non-404 visit of a URL: url index, outer join, top-1 sort.
-- @param ?1 803
SELECT visits.id,visits.url,visits.visit_time,visits.from_visit,visits.external_referrer_url,visits.transition,visits.segment_id,visits.visit_duration,visits.incremented_omnibox_typed_score,visits.opener_visit,visits.originator_cache_guid,visits.originator_visit_id,visits.originator_from_visit,visits.originator_opener_visit,visits.is_known_to_sync,visits.consider_for_ntp_most_visited,visits.visited_link_id,visits.app_id FROM visits LEFT OUTER JOIN context_annotations ON visits.id=context_annotations.visit_id WHERE visits.url=?1 AND(context_annotations.response_code IS NULL OR context_annotations.response_code!=404) ORDER BY visits.visit_time DESC,visits.id DESC LIMIT 1;

-- @id chromium.visit.most_recent_visits_for_url
-- @src components/history/core/browser/visit_database.cc:916-925
-- @style ? positional; kExclude404s branch
-- @tags hotpath
-- @note Recent visits of a popular URL for omnibox scoring: top-N over ~900 visits of the Google root.
-- @param ?1 1
-- @param ?2 10
SELECT visits.id,visits.url,visits.visit_time,visits.from_visit,visits.external_referrer_url,visits.transition,visits.segment_id,visits.visit_duration,visits.incremented_omnibox_typed_score,visits.opener_visit,visits.originator_cache_guid,visits.originator_visit_id,visits.originator_from_visit,visits.originator_opener_visit,visits.is_known_to_sync,visits.consider_for_ntp_most_visited,visits.visited_link_id,visits.app_id FROM visits LEFT OUTER JOIN context_annotations ca ON visits.id=ca.visit_id WHERE visits.url=?1 AND (ca.response_code IS NULL OR ca.response_code!=404) ORDER BY visits.visit_time DESC, visits.id DESC LIMIT ?2;

-- @id chromium.visit.redirect_from
-- @src components/history/core/browser/visit_database.cc:950-958
-- @style ? positional; kExclude404s branch, IS_REDIRECT_MASK = 0xC0000000
-- @note Redirect chain walk: from_visit index, join to urls, outer join, bitmask on transition.
-- @param ?1 33
-- @param ?2 3221225472
SELECT v.id,u.url FROM visits v JOIN urls u ON v.url=u.id LEFT OUTER JOIN context_annotations ca ON v.id=ca.visit_id WHERE v.from_visit=?1 AND (ca.response_code IS NULL OR ca.response_code!=404)AND (v.transition & ?2)!=0;

-- @id chromium.visit.history_count
-- @src components/history/core/browser/visit_database.cc:1080-1086
-- @style ? positional; kExclude404s branch
-- @note GetHistoryCount for a week: visits in range with an outer join (dedup per day/url in C++).
-- @param ?1 13407171200000000
-- @param ?2 13407776000000000
SELECT v.url,v.visit_time,v.transition FROM visits v LEFT OUTER JOIN context_annotations c ON v.id=c.visit_id WHERE v.visit_time>=?1 AND v.visit_time<?2 AND (c.response_code IS NULL OR c.response_code!=404);

-- @id chromium.visit.visible_count_to_host
-- @src components/history/core/browser/visit_database.cc:1028-1035
-- @style ? positional; bounds from the origin (url >= origin/ AND url < origin0)
-- @note Page-info 'visited before': url range on urls joined to visits plus outer join, no time bound.
-- @param ?1 'https://github.com/'
-- @param ?2 'https://github.com0'
SELECT v.visit_time,transition FROM visits v INNER JOIN urls u ON v.url=u.id LEFT OUTER JOIN context_annotations c ON v.id=c.visit_id WHERE u.url>=?1 AND u.url<?2 AND (c.response_code IS NULL OR c.response_code!=404);

-- @id chromium.visit.last_visit_to_origin
-- @src components/history/core/browser/visit_database.cc:1210-1220
-- @style ? positional; kExclude404s branch, GetOriginSearchBounds
-- @tags hotpath
-- @note Last visit to an origin in a time window: url range join + time filter, top-1 by visit_time.
-- @param ?1 'https://www.youtube.com/'
-- @param ?2 'https://www.youtube.com0'
-- @param ?3 13405184000000000
-- @param ?4 13407776000000000
SELECT v.visit_time,u.url FROM visits v INNER JOIN urls u ON v.url=u.id LEFT OUTER JOIN context_annotations ca ON v.id=ca.visit_id WHERE u.url>=?1 AND u.url<?2 AND v.visit_time>=?3 AND v.visit_time<?4 AND (ca.response_code IS NULL OR ca.response_code!=404) ORDER BY v.visit_time DESC LIMIT 1;

-- @id chromium.visit.google_search_visits
-- @src components/history/core/browser/visit_database.cc:1392-1410
-- @style ? positional
-- @note Google-domain searches in a range: four OR'd LIKE patterns with _ wildcards over urls joined to visits.
-- @param ?1 13405184000000000
-- @param ?2 13407776000000000
SELECT visit_time,u.url FROM urls u JOIN visits v ON u.id=v.url WHERE (u.url LIKE 'https://www.google.__/search%' OR u.url LIKE 'https://www.google.___/search%' OR u.url LIKE 'https://www.google.__.__/search%' OR u.url LIKE 'https://www.google.___.__/search%') AND visit_time >= ?1 AND visit_time < ?2;

-- @id chromium.visit.foreign_visits
-- @src components/history/core/browser/visit_database.cc:822-832
-- @style ? positional; PAGE_TRANSITION_CHAIN_END = 0x20000000
-- @note Sync cleanup batch: visits from other devices below an id, bitmask filter, LIMIT.
-- @param ?1 536870912
-- @param ?2 100000
-- @param ?3 1000
SELECT visits.id,visits.url,visits.visit_time,visits.from_visit,visits.external_referrer_url,visits.transition,visits.segment_id,visits.visit_duration,visits.incremented_omnibox_typed_score,visits.opener_visit,visits.originator_cache_guid,visits.originator_visit_id,visits.originator_from_visit,visits.originator_opener_visit,visits.is_known_to_sync,visits.consider_for_ntp_most_visited,visits.visited_link_id,visits.app_id FROM visits WHERE originator_cache_guid IS NOT NULL AND originator_cache_guid != '' AND (transition & ?1) <> 0 AND id <= ?2 LIMIT ?3;

-- @id chromium.visit.in_range_for_transition
-- @src components/history/core/browser/visit_database.cc:794-809
-- @style ? positional; CORE_MASK = 0xFF, TYPED = 1
-- @note Typed visits in the last week: time range + masked transition equality, ORDER BY visit_time LIMIT.
-- @param ?1 13407171200000000
-- @param ?2 13407776000000000
-- @param ?3 255
-- @param ?4 1
-- @param ?5 200
SELECT visits.id,visits.url,visits.visit_time,visits.from_visit,visits.external_referrer_url,visits.transition,visits.segment_id,visits.visit_duration,visits.incremented_omnibox_typed_score,visits.opener_visit,visits.originator_cache_guid,visits.originator_visit_id,visits.originator_from_visit,visits.originator_opener_visit,visits.is_known_to_sync,visits.consider_for_ntp_most_visited,visits.visited_link_id,visits.app_id FROM visits WHERE visit_time >= ?1 AND visit_time < ?2 AND (transition & ?3) == ?4ORDER BY visit_time LIMIT ?5;

-- @id chromium.visit.all_app_ids
-- @src components/history/core/browser/visit_database.cc:835-837
-- @style no parameters
-- @note Android Custom Tab app filter list: DISTINCT with ORDER BY on a non-selected column.
SELECT DISTINCT app_id FROM visits WHERE app_id != '' ORDER BY visit_time DESC;

-- @id chromium.history.unique_domains_visited
-- @src components/history/core/browser/history_database.cc:374-384
-- @style ? positional; kExclude404s branch; CHAIN_END, CORE_MASK, AUTO_SUBFRAME=3, MANUAL_SUBFRAME=4, KEYWORD_GENERATED=10
-- @note Domains visited in a window (Settings/metrics): 4-table join with IFNULL, bitmask NOT IN list, ordered newest first.
-- @param ?1 1
-- @param ?2 536870912
-- @param ?3 255
-- @param ?4 3
-- @param ?5 4
-- @param ?6 10
-- @param ?7 13407603200000000
-- @param ?8 13407776000000000
SELECT urls.url, visits.originator_cache_guid, IFNULL(visit_source.source, ?1) FROM urls INNER JOIN visits ON urls.id=visits.url LEFT JOIN visit_source ON visits.id=visit_source.id LEFT JOIN context_annotations ca ON visits.id = ca.visit_id WHERE (transition & ?2)!=0 AND (transition & ?3) NOT IN (?4, ?5, ?6) AND hidden=0 AND visit_time>=?7 AND visit_time<?8 AND (ca.response_code IS NULL OR ca.response_code!=404) ORDER BY visit_time DESC, visits.id DESC;

-- @id chromium.history.batch_recent_visits_significant
-- @src components/history/core/browser/history_database.cc:694-701
-- @style ? positional; same thresholds as InitURLEnumeratorForSignificant
-- @tags hotpath
-- @note Omnibox index rebuild: all visits of significant URLs via IN-subquery, sorted by (url, visit_time DESC, id DESC).
-- @param ?1 13407516800000000
-- @param ?2 4
-- @param ?3 1
SELECT url, visit_time, transition FROM visits WHERE url IN ( SELECT id FROM urls WHERE hidden = 0 AND (last_visit_time >= ?1 OR visit_count >= ?2 OR typed_count >= ?3)) ORDER BY url, visit_time DESC, id DESC;

-- @id chromium.segment.usage_all
-- @src components/history/core/browser/visitsegment_database.cc:274-277
-- @style no parameters
-- @tags hotpath
-- @note New Tab Page Most Visited tiles, phase 1: every segment_usage row ordered by segment (scored in C++).
SELECT segment_id, time_slot, visit_count FROM segment_usage ORDER BY segment_id;

-- @id chromium.segment.url_for_segment
-- @src components/history/core/browser/visitsegment_database.cc:321-324
-- @style ? positional
-- @tags hot-small,hotpath
-- @note Most Visited phase 2, per top segment: segment -> url/title join.
-- @param ?1 3
SELECT urls.url, urls.title FROM urls JOIN segments ON segments.url_id = urls.id WHERE segments.id = ?1;

-- @id chromium.segment.find_by_name
-- @src components/history/core/browser/visitsegment_database.cc:197-198
-- @style ? positional
-- @tags hot-small,hotpath
-- @note Segment lookup by computed name on each qualifying navigation.
-- @param ?1 'http://github.com/'
SELECT id FROM segments WHERE name = ?1;

-- @id chromium.segment.delete_usage_for_url
-- @src components/history/core/browser/visitsegment_database.cc:380-382
-- @style ? positional
-- @note History deletion: segment_usage rows for a URL's segments via IN-subquery.
-- @param ?1 3
DELETE FROM segment_usage WHERE segment_id IN (SELECT id FROM segments WHERE url_id = ?1);

-- @id chromium.clusters.most_recent_ids
-- @src components/history/core/browser/visit_annotations_database.cc:961-970
-- @style ? positional
-- @tags hotpath
-- @note Journeys page: clusters ranked by their latest visit, GROUP BY with HAVING on MAX and ORDER BY MAX LIMIT.
-- @param ?1 13405184000000000
-- @param ?2 13407776000000000
-- @param ?3 50
SELECT cluster_id FROM clusters_and_visits JOIN visits ON visit_id=id GROUP BY cluster_id HAVING MAX(visit_time)>=?1 AND MAX(visit_time)<?2 ORDER BY MAX(visit_time) DESC LIMIT ?3;

-- @id chromium.clusters.visits_in_cluster
-- @src components/history/core/browser/visit_annotations_database.cc:983-988
-- @style ? positional
-- @tags hotpath
-- @note Visits of one journey ordered by score on the WITHOUT ROWID PK prefix.
-- @param ?1 3690
SELECT visit_id FROM clusters_and_visits WHERE cluster_id=?1 ORDER BY score DESC,visit_id DESC;

-- @id chromium.clusters.max_label_duplicates
-- @src components/history/core/browser/history_database.cc:346-347
-- @style no parameters
-- @note Cluster metrics: GROUP BY label, top-1 by count(*).
SELECT count(*) FROM clusters GROUP BY label ORDER BY count(*) DESC LIMIT 1;

-- @id chromium.shortcuts.load_all
-- @src components/omnibox/browser/shortcuts_database.cc:229-235
-- @style no parameters
-- @tags hotpath
-- @note ShortcutsProvider startup load of the whole omni_box_shortcuts table.
SELECT id,text,fill_into_edit,url,document_type,contents,contents_class,description,description_class,transition,type,keyword,last_access_time,number_of_hits FROM omni_box_shortcuts;

-- @id chromium.top_sites.shift_ranks
-- @src components/history/core/browser/top_sites_database.cc:384-390
-- @style ? positional
-- @note Top Sites reorder when a new URL enters at rank 2: range UPDATE over url_rank.
-- @param ?1 2
UPDATE top_sites SET url_rank=url_rank+1 WHERE url_rank>=?1;
