-- GoatCounter (arp242/goatcounter @ c031008a8d28c85b36708824f23b28957e7ed262, EUPL-1.2 (modified appendix), (c) Martin Tournoij).
-- Source: db/schema.gotxt, rendered for SQLite with zdb's template functions (zgo.at/zdb tpl.go @ e580739:
-- auto_increment -> integer primary key autoincrement, jsonb -> varchar, check_timestamp/check_date -> strftime
-- checks, psql/cluster/replica sections dropped). Only the CREATE statements the queries need are reproduced here;
-- the full file is fetched by tools/fetch.sh (meta.json fetch_paths). Indexes are the app's own (the final state
-- after migration 2026-02-25-1-indexes, which schema.gotxt already reflects).
CREATE TABLE paths (
	path_id        integer        primary key autoincrement,
	site_id        integer        not null,

	path           varchar        not null,
	title          varchar        not null default '',
	event          integer        default 0
);
CREATE UNIQUE INDEX "paths#site_id#path" on paths(site_id, lower(path));
CREATE INDEX "paths#title"        on paths(lower(title));

CREATE TABLE refs (
	ref_id         integer        primary key autoincrement,
	ref            varchar        not null,
	ref_scheme     varchar        not null
);
CREATE UNIQUE INDEX "refs#ref#ref_scheme" on refs(lower(ref), ref_scheme);

CREATE TABLE browsers (
	browser_id     integer        primary key autoincrement,

	name           varchar,
	version        varchar
);
CREATE UNIQUE INDEX "browsers#name#version" on browsers(name, version);

CREATE TABLE systems (
	system_id      integer        primary key autoincrement,

	name           varchar,
	version        varchar
);
CREATE UNIQUE INDEX "systems#name#version"  on systems(name, version);

CREATE TABLE campaigns (
	campaign_id    integer        primary key autoincrement,
	site_id        integer        not null,
	name           varchar        not null
);

CREATE TABLE locations (
	location_id    integer        primary key autoincrement,

	iso_3166_2     varchar        generated always as (country || (case region when '' then '' else ('-' || region) end)) stored,
	country        varchar        not null,
	region         varchar        not null,
	country_name   varchar        not null,
	region_name    varchar        not null
);
CREATE UNIQUE INDEX "locations#iso_3166_2" on locations(iso_3166_2);

CREATE TABLE languages (
	iso_639_3      varchar        not null,
	name           varchar        not null
);
CREATE UNIQUE INDEX "languages#iso_639_3" on languages(iso_639_3);

CREATE TABLE hits (
	hit_id         integer        primary key autoincrement,
	site_id        integer        not null,
	path_id        integer        not null,
	ref_id         integer        not null default 1,

	session        blob           default null,
	first_visit    integer        default 0,

	browser_id     integer        not null,
	system_id      integer        not null,
	campaign       integer        default null,
	width          int            null,
	location       varchar        not null default '',
	language       varchar,

	created_at     timestamp      not null                 check(created_at = strftime('%Y-%m-%d %H:%M:%S', created_at))
);
CREATE INDEX "hits#site_id#created_at" on hits(site_id, created_at desc);

CREATE TABLE hit_counts (
	site_id        integer        not null,
	path_id        integer        not null,

	hour           timestamp      not null                 check(hour = strftime('%Y-%m-%d %H:%M:%S', hour)),
	total          integer        not null,

	constraint "hit_counts#site_id#path_id#hour" unique(site_id, path_id, hour) on conflict replace
);
CREATE INDEX "hit_counts#hour"    on hit_counts (hour);
CREATE INDEX "hit_counts#site_id" on hit_counts(site_id);

CREATE TABLE ref_counts (
	site_id        integer        not null,
	path_id        integer        not null,

	ref_id         integer        not null,
	hour           timestamp      not null                 check(hour = strftime('%Y-%m-%d %H:%M:%S', hour)),
	total          integer        not null,

	constraint "ref_counts#site_id#path_id#ref_id#hour" unique(site_id, path_id, ref_id, hour) on conflict replace
);
CREATE INDEX "ref_counts#hour"    on ref_counts (hour);
CREATE INDEX "ref_counts#site_id" on ref_counts(site_id);

CREATE TABLE browser_stats (
	site_id        integer        not null,
	path_id        integer        not null,
	browser_id     integer        not null,

	day            date           not null                 check(day = strftime('%Y-%m-%d', day)),
	count          integer        not null,

	constraint "browser_stats#site_id#path_id#day#browser_id" unique(site_id, path_id, day, browser_id) on conflict replace
);
CREATE INDEX "browser_stats#day"        on browser_stats (day);
CREATE INDEX "browser_stats#site_id"    on browser_stats(site_id);
CREATE INDEX "browser_stats#browser_id" on browser_stats(browser_id);

CREATE TABLE system_stats (
	site_id        integer        not null,
	path_id        integer        not null,
	system_id      integer        not null,

	day            date           not null                 check(day = strftime('%Y-%m-%d', day)),
	count          integer        not null,

	constraint "system_stats#site_id#path_id#day#system_id" unique(site_id, path_id, day, system_id) on conflict replace
);
CREATE INDEX "system_stats#day"       on system_stats (day);
CREATE INDEX "system_stats#site_id"   on system_stats(site_id);
CREATE INDEX "system_stats#system_id" on system_stats(system_id);

CREATE TABLE location_stats (
	site_id        integer        not null,
	path_id        integer        not null,

	day            date           not null                 check(day = strftime('%Y-%m-%d', day)),
	location       varchar        not null,
	count          integer        not null,

	constraint "location_stats#site_id#path_id#day#location" unique(site_id, path_id, day, location) on conflict replace
);
CREATE INDEX "location_stats#day"      on location_stats (day);
CREATE INDEX "location_stats#site_id"  on location_stats(site_id);
CREATE INDEX "location_stats#location" on location_stats(location);

CREATE TABLE size_stats (
	site_id        integer        not null,
	path_id        integer        not null,

	day            date           not null                 check(day = strftime('%Y-%m-%d', day)),
	width          integer        not null,
	count          integer        not null,

	constraint "size_stats#site_id#path_id#day#width" unique(site_id, path_id, day, width) on conflict replace
);
CREATE INDEX "size_stats#day"     on size_stats (day);
CREATE INDEX "size_stats#site_id" on size_stats(site_id);
CREATE INDEX "size_stats#width"   on size_stats(width);

CREATE TABLE language_stats (
	site_id        integer        not null,
	path_id        integer        not null,

	day            date           not null                 check(day = strftime('%Y-%m-%d', day)),
	language       varchar        not null,
	count          integer        not null,

	constraint "language_stats#site_id#path_id#day#language" unique(site_id, path_id, day, language) on conflict replace
);
CREATE INDEX "language_stats#day"      on language_stats (day);
CREATE INDEX "language_stats#site_id"  on language_stats(site_id);
CREATE INDEX "language_stats#language" on language_stats(language);

CREATE TABLE campaign_stats (
	site_id        integer        not null,
	path_id        integer        not null,

	day            date           not null,
	campaign_id    integer        not null,
	ref            varchar        not null,
	count          integer        not null,

	constraint "campaign_stats#site_id#path_id#campaign_id#ref#day" unique(site_id, path_id, campaign_id, ref, day) on conflict replace
);
CREATE INDEX "campaign_stats#day"         on campaign_stats (day);
CREATE INDEX "campaign_stats#site_id"     on campaign_stats(site_id);
CREATE INDEX "campaign_stats#campaign_id" on campaign_stats(campaign_id);

CREATE TABLE filters (
	filter_id     int        not null,
	site_id       int        not null,
	matches       int        not null,
	invert        bool       not null default false,
	query         text       not null,
	created_at    timestamp  not null   check(created_at = strftime('%Y-%m-%d %H:%M:%S', created_at)),
	last_used_at  timestamp  not null   check(created_at = strftime('%Y-%m-%d %H:%M:%S', created_at))
);
CREATE UNIQUE INDEX "filters#filter_id" on filters(filter_id);

CREATE TABLE filter_paths (
	filter_id  int   not null,
	path_id    int   not null
);
CREATE INDEX "filter_paths#filter_id" on filter_paths(filter_id);

