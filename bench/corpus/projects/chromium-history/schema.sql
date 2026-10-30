-- Chromium History, Shortcuts and Top Sites databases (chromium/chromium @ f7be3cef8a9d088c63aced58e025afdceaf2aede,
-- BSD-3-Clause). Chromium has no schema file: each table is created by C++ string literals at Init time. These
-- CREATE statements are those literals concatenated, comments dropped. In the browser, History, Shortcuts and
-- Top Sites are three separate files; here they share one database.

-- components/history/core/browser/url_database.cc:845-858 (CreateURLTable) and :866-867 (CreateMainURLIndex)
CREATE TABLE urls(id INTEGER PRIMARY KEY AUTOINCREMENT,url LONGVARCHAR,title LONGVARCHAR,visit_count INTEGER DEFAULT 0 NOT NULL,typed_count INTEGER DEFAULT 0 NOT NULL,last_visit_time INTEGER NOT NULL,hidden INTEGER DEFAULT 0 NOT NULL);
CREATE INDEX IF NOT EXISTS urls_url_index ON urls (url);

-- url_database.cc:552-588 (InitKeywordSearchTermsTable, CreateKeywordSearchTermsIndices)
CREATE TABLE keyword_search_terms (keyword_id INTEGER NOT NULL,url_id INTEGER NOT NULL,term LONGVARCHAR NOT NULL,normalized_term LONGVARCHAR NOT NULL);
CREATE INDEX IF NOT EXISTS keyword_search_terms_index1 ON keyword_search_terms (keyword_id, normalized_term);
CREATE INDEX IF NOT EXISTS keyword_search_terms_index2 ON keyword_search_terms (url_id);
CREATE INDEX IF NOT EXISTS keyword_search_terms_index3 ON keyword_search_terms (term);

-- components/history/core/browser/visit_database.cc:146-256 (InitVisitTable)
CREATE TABLE visits(id INTEGER PRIMARY KEY AUTOINCREMENT,url INTEGER NOT NULL,visit_time INTEGER NOT NULL,from_visit INTEGER,external_referrer_url TEXT,transition INTEGER DEFAULT 0 NOT NULL,segment_id INTEGER,visit_duration INTEGER DEFAULT 0 NOT NULL,incremented_omnibox_typed_score BOOLEAN DEFAULT FALSE NOT NULL,opener_visit INTEGER,originator_cache_guid TEXT,originator_visit_id INTEGER,originator_from_visit INTEGER,originator_opener_visit INTEGER,is_known_to_sync BOOLEAN DEFAULT FALSE NOT NULL,consider_for_ntp_most_visited BOOLEAN DEFAULT FALSE NOT NULL,visited_link_id INTEGER DEFAULT 0 NOT NULL,app_id TEXT);
CREATE TABLE visit_source(id INTEGER PRIMARY KEY,source INTEGER NOT NULL);
CREATE INDEX IF NOT EXISTS visits_url_index ON visits (url);
CREATE INDEX IF NOT EXISTS visits_from_index ON visits (from_visit);
CREATE INDEX IF NOT EXISTS visits_time_index ON visits (visit_time);
CREATE INDEX IF NOT EXISTS visits_originator_id_index ON visits (originator_visit_id);

-- components/history/core/browser/visitsegment_database.cc:110-148 (InitSegmentTables)
CREATE TABLE segments (id INTEGER PRIMARY KEY,name VARCHAR,url_id INTEGER NON NULL);
CREATE INDEX segments_name ON segments(name);
CREATE INDEX IF NOT EXISTS segments_url_id ON segments(url_id);
CREATE TABLE segment_usage (id INTEGER PRIMARY KEY,segment_id INTEGER NOT NULL,time_slot INTEGER NOT NULL,visit_count INTEGER DEFAULT 0 NOT NULL);
CREATE INDEX segment_usage_time_slot_segment_id ON segment_usage(time_slot, segment_id);
CREATE INDEX IF NOT EXISTS segments_usage_seg_id ON segment_usage(segment_id);

-- components/history/core/browser/visit_annotations_database.cc:246-260, :274-299, :1514-1540
CREATE TABLE IF NOT EXISTS context_annotations(visit_id INTEGER PRIMARY KEY,context_annotation_flags INTEGER NOT NULL,duration_since_last_visit INTEGER,page_end_reason INTEGER,total_foreground_duration INTEGER,browser_type INTEGER DEFAULT 0 NOT NULL,window_id INTEGER DEFAULT -1 NOT NULL,tab_id INTEGER DEFAULT -1 NOT NULL,task_id INTEGER DEFAULT -1 NOT NULL,root_task_id INTEGER DEFAULT -1 NOT NULL,parent_task_id INTEGER DEFAULT -1 NOT NULL,response_code INTEGER DEFAULT 0 NOT NULL);
CREATE TABLE IF NOT EXISTS clusters(cluster_id INTEGER PRIMARY KEY AUTOINCREMENT,should_show_on_prominent_ui_surfaces BOOLEAN NOT NULL,label VARCHAR NOT NULL,raw_label VARCHAR NOT NULL,triggerability_calculated BOOLEAN NOT NULL,originator_cache_guid TEXT NOT NULL,originator_cluster_id INTEGER NOT NULL);
CREATE TABLE IF NOT EXISTS clusters_and_visits(cluster_id INTEGER NOT NULL,visit_id INTEGER NOT NULL,score NUMERIC DEFAULT 0 NOT NULL,engagement_score NUMERIC DEFAULT 0 NOT NULL,url_for_deduping LONGVARCHAR NOT NULL,normalized_url LONGVARCHAR NOT NULL,url_for_display LONGVARCHAR NOT NULL,interaction_state INTEGER DEFAULT 0 NOT NULL,PRIMARY KEY(cluster_id,visit_id))WITHOUT ROWID;
CREATE INDEX IF NOT EXISTS clusters_for_visit ON clusters_and_visits(visit_id);
CREATE TABLE IF NOT EXISTS cluster_keywords(cluster_id INTEGER NOT NULL,keyword VARCHAR NOT NULL,type INTEGER NOT NULL,score NUMERIC NOT NULL,collections VARCHAR NOT NULL);
CREATE INDEX IF NOT EXISTS cluster_keywords_cluster_id_index ON cluster_keywords(cluster_id);

-- components/omnibox/browser/shortcuts_database.cc:358-364 (Shortcuts file)
CREATE TABLE omni_box_shortcuts(id VARCHAR PRIMARY KEY,text VARCHAR,fill_into_edit VARCHAR,url VARCHAR,document_type INTEGER,contents VARCHAR,contents_class VARCHAR,description VARCHAR,description_class VARCHAR,transition INTEGER,type INTEGER,keyword VARCHAR,last_access_time INTEGER,number_of_hits INTEGER);

-- components/history/core/browser/top_sites_database.cc:66-69 (Top Sites file)
CREATE TABLE IF NOT EXISTS top_sites(url TEXT NOT NULL PRIMARY KEY,url_rank INTEGER NOT NULL,title TEXT NOT NULL);
