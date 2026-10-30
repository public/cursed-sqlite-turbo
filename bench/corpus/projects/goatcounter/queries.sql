-- GoatCounter (arp242/goatcounter @ c031008, EUPL-1.2). SQL comes from db/query/*.sql (zdb templates) and
-- inline strings in the Go code, resolved for SQLite by hand with zdb's rules: {{:sqlite ...}} sections kept,
-- {{:name ...}} sections kept when the parameter is set, :filter (zdb.SQL) inlined as the PathFilter.SQL text
-- ("1=1", the filter_paths join, or an expanded id list), :in -> in (db2.In for SQLite). zdb sends named
-- parameters as positional ? (one per occurrence, slices expanded); here each distinct name is one ?N.
-- time.Time parameters are bound the way mattn/go-sqlite3 formats them ('2006-01-02 15:04:05-07:00');
-- day parameters are the strings asUTCDate() formats. Dashboard range: the "last 6 months" view, 2026-05-01 .. 2026-10-30, site 1.

-- @id goatcounter.hit_list.list_top_paths
-- @src db/query/hit_list.List.sql:1-28 (HitLists.List, hit_list.go:256-266)
-- @style zdb template; :exclude empty (section dropped), :filter = 1=1
-- @tags hotpath,analytics,dynamic
-- @note Dashboard "Pages" widget: per-path sums over 6 months of hourly hit_counts with a json_group_object of the hourly series per path, top 10 (+1) by total
-- @param ?1 '60 minutes'
-- @param ?2 1
-- @param ?3 '2026-05-01 00:00:00+00:00'
-- @param ?4 '2026-10-30 23:59:59+00:00'
-- @param ?5 11
with x as (
	select
		sum(total) as total,
		path_id,
		json_group_object(substr(datetime(hour, ?1), 0, 14), total) as stats2
	from hit_counts
	where
		hit_counts.site_id = ?2 and
		1=1 and
		hour >=?3 and hour<=?4
	group by path_id
	order by total desc, path_id desc
	limit ?5
)
select
	path_id,
	paths.path,
	paths.title,
	paths.event,
	total as count,
	coalesce(stats2, '{}') as stats2
from x
join paths using (path_id)
order by total desc, path_id desc;

-- @id goatcounter.hit_list.list_top_paths_saved_filter
-- @src db/query/hit_list.List.sql:1-28; filter.go:166-174
-- @style zdb template; :filter = PathFilter.SQL with a stored filter (search matched >10k paths)
-- @tags hotpath,analytics,dynamic,cpu-evidence
-- @note Pages widget for the search "blog" (12k matching paths): the filter_paths IN-subquery that https://github.com/arp242/goatcounter/issues/858 introduced because path_id in (1M ids) spent minutes in planning (and SQLite caps variables at 32,766)
-- @param ?1 '60 minutes'
-- @param ?2 1
-- @param ?3 1
-- @param ?4 '2026-05-01 00:00:00+00:00'
-- @param ?5 '2026-10-30 23:59:59+00:00'
-- @param ?6 11
with x as (
	select
		sum(total) as total,
		path_id,
		json_group_object(substr(datetime(hour, ?1), 0, 14), total) as stats2
	from hit_counts
	where
		hit_counts.site_id = ?2 and
		path_id in (select path_id from filter_paths where filter_id = ?3) and
		hour >=?4 and hour<=?5
	group by path_id
	order by total desc, path_id desc
	limit ?6
)
select
	path_id,
	paths.path,
	paths.title,
	paths.event,
	total as count,
	coalesce(stats2, '{}') as stats2
from x
join paths using (path_id)
order by total desc, path_id desc;

-- @id goatcounter.hit_list.totals_chart
-- @src db/query/hit_list.Totals.sql:1-21 (HitList.Totals, hit_list.go:304-313)
-- @style zdb template; no_events false, :filter = 1=1
-- @tags hotpath,analytics,dynamic
-- @note Dashboard totals chart: hourly sums over the whole site for 6 months, regrouped on a timezone-shifted text key, folded into one JSON object
-- @param ?1 '60 minutes'
-- @param ?2 1
-- @param ?3 '2026-05-01 00:00:00+00:00'
-- @param ?4 '2026-10-30 23:59:59+00:00'
with x as (
	select
		sum(total) as total,
		substr(datetime(hour, ?1), 0, 14)                     as hour
	from hit_counts
	
	where
		hit_counts.site_id = ?2 and hour >= ?3 and hour <= ?4 and
		
		1=1
	group by hour
	order by hour asc
)
select coalesce(
	json_group_object(hour, total)
, '{}') as stats2
from x;

-- @id goatcounter.hit_list.totals_chart_path_ids
-- @src db/query/hit_list.Totals.sql:1-21; filter.go:180-183
-- @style zdb template; no_events true (join paths), :filter = expanded path_id list (search "api/page-2", 39 paths)
-- @tags hotpath,analytics,dynamic,cpu-evidence
-- @note Totals chart with a dashboard search: path_id in (39 bound ids) plus the paths join for "exclude events". The in-list form https://github.com/arp242/goatcounter/issues/858 is about (it switches to filter_paths above 10k ids)
-- @param ?1 '60 minutes'
-- @param ?2 1
-- @param ?3 '2026-05-01 00:00:00+00:00'
-- @param ?4 '2026-10-30 23:59:59+00:00'
-- @param ?5 250
-- @param ?6 258
-- @param ?7 2002
-- @param ?8 2010
-- @param ?9 2035
-- @param ?10 2043
-- @param ?11 2051
-- @param ?12 2076
-- @param ?13 2139
-- @param ?14 2147
-- @param ?15 2155
-- @param ?16 2221
-- @param ?17 2229
-- @param ?18 2254
-- @param ?19 2295
-- @param ?20 2303
-- @param ?21 2399
-- @param ?22 2407
-- @param ?23 2448
-- @param ?24 2473
-- @param ?25 2481
-- @param ?26 2547
-- @param ?27 2555
-- @param ?28 2563
-- @param ?29 2626
-- @param ?30 2651
-- @param ?31 2659
-- @param ?32 2667
-- @param ?33 2692
-- @param ?34 2700
-- @param ?35 2733
-- @param ?36 2741
-- @param ?37 2804
-- @param ?38 2878
-- @param ?39 2886
-- @param ?40 2911
-- @param ?41 2919
-- @param ?42 2952
-- @param ?43 2960
with x as (
	select
		sum(total) as total,
		substr(datetime(hour, ?1), 0, 14)                     as hour
	from hit_counts
	join paths using (path_id)
	where
		hit_counts.site_id = ?2 and hour >= ?3 and hour <= ?4 and
		paths.event = 0 and
		path_id in (?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15, ?16, ?17, ?18, ?19, ?20, ?21, ?22, ?23, ?24, ?25, ?26, ?27, ?28, ?29, ?30, ?31, ?32, ?33, ?34, ?35, ?36, ?37, ?38, ?39, ?40, ?41, ?42, ?43)
	group by hour
	order by hour asc
)
select coalesce(
	json_group_object(hour, total)
, '{}') as stats2
from x;

-- @id goatcounter.hit_list.total_count
-- @src db/query/hit_list.GetTotalCount.gotxt:1-34 (GetTotalCount, hit_list.go:349-358)
-- @style zdb template; total_events true, :filter = 1=1, start_utc/end_utc = the range in UTC
-- @tags hotpath,analytics,dynamic
-- @note Dashboard header totals: three full-range sums over hit_counts (local range, UTC range, events via a paths join) cross-joined
-- @param ?1 1
-- @param ?2 '2026-05-01 00:00:00+01:00'
-- @param ?3 '2026-10-30 23:59:59+01:00'
-- @param ?4 '2026-05-01 00:00:00+00:00'
-- @param ?5 '2026-10-30 23:59:59+00:00'
with x as (
	select coalesce(sum(total), 0) as total
	from hit_counts
	where site_id = ?1 and hour >= ?2 and hour <= ?3 and 1=1
), y as (
	select coalesce(sum(total), 0) as total_utc
	from hit_counts
	where site_id = ?1 and hour >= ?4 and hour <= ?5 and 1=1
)
, z as (
	select coalesce(sum(total), 0) as total_events
	from hit_counts
	join paths using (site_id, path_id)
	where hit_counts.site_id = ?1 and hour >= ?2 and hour <= ?3 and paths.event = 1 and 1=1
)
select
	*
from x, y, z;

-- @id goatcounter.hit_list.diff_total
-- @src db/query/hit_list.DiffTotal.sql:1-25 (HitLists.Diff, hit_list.go:382-390)
-- @style zdb template; :in -> in, paths = the 11 listed path ids
-- @tags hotpath,analytics,dynamic
-- @note Per-path change vs the previous period: two grouped CTEs over hit_counts for the listed paths, LEFT JOIN, ordered
-- @modified percent_diff() is a Go function GoatCounter registers on SQLite connections (helper.go:48-54); replaced by the same arithmetic in core SQL (start=0 -> +Inf as 1e999)
-- @param ?1 1
-- @param ?2 1
-- @param ?3 2
-- @param ?4 3
-- @param ?5 4
-- @param ?6 5
-- @param ?7 6
-- @param ?8 8
-- @param ?9 7
-- @param ?10 9
-- @param ?11 10
-- @param ?12 11
-- @param ?13 '2026-08-31 00:00:00+00:00'
-- @param ?14 '2026-09-30 23:59:59+00:00'
-- @param ?15 '2026-10-01 00:00:00+00:00'
-- @param ?16 '2026-10-30 23:59:59+00:00'
with prev as (
	select
		path_id,
		sum(total) as total
	from hit_counts
	where
		site_id = ?1 and path_id in (?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12) and
		hour >= ?13 and hour <= ?14
	group by path_id
),
cur as (
	select
		path_id,
		sum(c.total) as total
	from hit_counts c
	where
		site_id = ?1 and path_id in (?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12) and
		hour >= ?15 and hour <= ?16
	group by path_id
)
select
	(case when coalesce(prev.total, 0) = 0 then 1e999 else (coalesce(cur.total, 0) - coalesce(prev.total, 0)) * 1.0 / coalesce(prev.total, 0) * 100.0 end) as diff
from cur
left join prev using (path_id)
order by cur.total desc, path_id desc;

-- @id goatcounter.hit_list.path_count
-- @src db/query/hit_list.PathCount.sql:1-15 (HitList.PathCount, hit_list.go:138-143)
-- @style zdb template; start and end set
-- @tags dynamic
-- @note API /api/v0/count-style lookup: one path's total over the range via lower(path) index match
-- @param ?1 1
-- @param ?2 '/'
-- @param ?3 '2026-05-01 00:00:00+00:00'
-- @param ?4 '2026-10-30 23:59:59+00:00'
with x as (
	select path_id, path from paths
	where site_id = ?1 and lower(path) = lower(?2)
)
select
	x.path,
	coalesce(sum(total), 0) as count
from hit_counts
join x using (path_id)
where
	site_id = ?1 and
	path_id = x.path_id
	and hour >= ?3
	and hour <= ?4
group by x.path, hit_counts.path_id;

-- @id goatcounter.hit_list.list_paths_like
-- @src db/query/hit_list.ListPathsLike.gotxt:1-20 (HitLists.ListPathsLike, hit_list.go:231-236)
-- @style zdb template; match_case false, match_title true
-- @tags analytics,dynamic
-- @note Path search in the API/merge UI: case-insensitive LIKE over path and title, then summed over all hit_counts of the matches
-- @param ?1 1
-- @param ?2 '%docs/faq%'
with x as (
	select path_id, path, title from paths
	where site_id = ?1 and (
			lower(path) like lower(?2) escape '\'
			or lower(title) like lower(?2) escape '\'
	)
)
select
	path_id, path, title,
	sum(total) as count
from hit_counts
join x using(path_id)
where site_id = ?1
group by path_id, path, title
order by count desc, path_id;

-- @id goatcounter.paths.path_filter
-- @src db/query/paths.PathFilter.sql:1-14 (PathFilterFromQuery, filter.go:218-231)
-- @style zdb template; have_like, match_path, match_title set, :or = or, :not empty, invert false
-- @tags hotpath,dynamic,cpu-evidence
-- @note Resolving a dashboard search into path ids (run before every filtered widget): LIKE '%blog%' on lower(path) or lower(title) over all of the site's paths; 12k matches here, which is when the filter_paths table of https://github.com/arp242/goatcounter/issues/858 kicks in
-- @param ?1 1
-- @param ?2 '%blog%'
select path_id from paths
where
	site_id = ?1
		and (
			lower(path)  like lower(?2)
			or
			lower(title) like lower(?2)
		);

-- @id goatcounter.ref.list_top_refs
-- @src db/query/ref.ListTopRefs.sql:1-22 (HitStats.ListTopRefs, hit_stats.go:140-150)
-- @style zdb template; :filter = 1=1, has_domain true
-- @tags hotpath,analytics,dynamic
-- @note Referrers widget: group 6 months of hourly ref_counts by ref, top limit*4 in a CTE, join refs, drop the site's own domain with NOT LIKE
-- @param ?1 1
-- @param ?2 '2026-05-01 00:00:00+00:00'
-- @param ?3 '2026-10-30 23:59:59+00:00'
-- @param ?4 24
-- @param ?5 'example.com%'
-- @param ?6 7
-- @param ?7 0
with x as (
	select
        coalesce(ref_id, 1)     as ref_id,
		coalesce(sum(total), 0) as count
	from ref_counts
	where site_id = ?1 and hour >= ?2 and hour <= ?3 and 1=1
	group by ref_id
	order by count desc, ref_id
	limit ?4
)
select
	x.count,
	refs.ref_scheme as ref_scheme,
	refs.ref        as name
from x
left join refs using (ref_id)
where refs.ref not like ?5
limit ?6 offset ?7;

-- @id goatcounter.ref.by_ref
-- @src db/query/hit_stats.ByRef.sql:1-21 (HitStats.ListTopRef, hit_stats.go:167-175)
-- @style zdb template; :filter = 1=1
-- @tags analytics,dynamic
-- @note Expanding one referrer: paths it sent visitors to (lower(ref) match, ref_counts grouped by path)
-- @param ?1 'Google'
-- @param ?2 11
-- @param ?3 0
-- @param ?4 1
-- @param ?5 '2026-05-01 00:00:00+00:00'
-- @param ?6 '2026-10-30 23:59:59+00:00'
with x as (
	select ref_id, ref_scheme from refs
	where lower(ref) = lower(?1)
	limit ?2 offset ?3
),
y as (
	select
		path_id,
		coalesce(sum(total), 0) as count
	from ref_counts
	join x using (ref_id)
	where site_id = ?4 and hour >= ?5 and hour <= ?6 and 1=1
	group by path_id
	order by count desc
)
select
	paths.path as name,
	y.count
from y
join paths using(path_id)
order by count desc;

-- @id goatcounter.ref.list_refs_by_path
-- @src db/query/ref.ListRefsByPathID.sql:1-21 (HitStats.ListRefsByPathID, ref.go:256-263)
-- @style zdb template
-- @tags hotpath,analytics
-- @note Referrers of the front page (the busiest path) over 6 months
-- @param ?1 1
-- @param ?2 1
-- @param ?3 '2026-05-01 00:00:00+00:00'
-- @param ?4 '2026-10-30 23:59:59+00:00'
-- @param ?5 11
-- @param ?6 0
with x as (
	select
		ref_id,
		coalesce(sum(total), 0) as count
	from ref_counts
	where
		site_id = ?1 and path_id = ?2 and hour >= ?3 and hour <= ?4
	group by ref_id
	order by count desc, ref_id
	limit ?5 offset ?6
)
select
	x.count,
	refs.ref_scheme as ref_scheme,
	coalesce(refs.ref, '') as name
from x
left join refs using (ref_id)
order by count desc, ref_id;

-- @id goatcounter.stats.browsers
-- @src db/query/hit_stats.ListBrowsers.sql:1-19 (HitStats.ListBrowsers, hit_stats.go:189-196)
-- @style zdb template; :filter = 1=1, day range from asUTCDate()
-- @tags hotpath,analytics,dynamic
-- @note Browsers widget: 6 months of per-path daily browser_stats grouped by browser_id, then regrouped by browser name
-- @param ?1 1
-- @param ?2 '2026-05-01'
-- @param ?3 '2026-10-30'
-- @param ?4 7
-- @param ?5 0
with x as (
	select
		browser_id,
		sum(count) as count
	from browser_stats
	where site_id = ?1 and day >= ?2 and day <= ?3 and 1=1
	group by browser_id
	order by count desc
)
select
	browsers.name,
	sum(x.count) as count
from x
join browsers using (browser_id)
group by browsers.name
order by count desc
limit ?4 offset ?5;

-- @id goatcounter.stats.browser_versions
-- @src db/query/hit_stats.ListBrowser.sql:1-9 (HitStats.ListBrowser, hit_stats.go:210-218)
-- @style zdb template; :filter = 1=1, day range from asUTCDate()
-- @tags hotpath,analytics,dynamic
-- @note Browser detail: versions of one browser (lower(name) filter after the join)
-- @param ?1 1
-- @param ?2 '2026-05-01'
-- @param ?3 '2026-10-30'
-- @param ?4 'Chrome'
-- @param ?5 11
-- @param ?6 0
select
	trim(name || ' ' || version) as name,
	sum(count)            as count
from browser_stats
join browsers using (browser_id)
where site_id = ?1 and day >= ?2 and day <= ?3 and 1=1 and lower(name) = lower(?4)
group by name, version
order by count desc, name asc
limit ?5 offset ?6;

-- @id goatcounter.stats.systems
-- @src db/query/hit_stats.ListSystems.sql:1-19 (HitStats.ListSystems, hit_stats.go:232-239)
-- @style zdb template; :filter = 1=1, day range from asUTCDate()
-- @tags hotpath,analytics,dynamic,cpu-evidence
-- @note Systems widget: system_stats grouped by system_id, regrouped by name. The Systems widget is the one https://github.com/arp242/goatcounter/issues/893 saw time out on goatcounter.com
-- @param ?1 1
-- @param ?2 '2026-05-01'
-- @param ?3 '2026-10-30'
-- @param ?4 7
-- @param ?5 0
with x as (
	select
		system_id,
		sum(count) as count
	from system_stats
	where site_id = ?1 and day >= ?2 and day <= ?3 and 1=1
	group by system_id
	order by count desc
)
select
	systems.name,
	sum(x.count) as count
from x
join systems using (system_id)
group by systems.name
order by count desc
limit ?4 offset ?5;

-- @id goatcounter.stats.sizes
-- @src db/query/hit_stats.ListSizes.sql:1-7 (HitStats.ListSizes, hit_stats.go:283-288)
-- @style zdb template; :filter = 1=1, day range from asUTCDate()
-- @tags hotpath,analytics,dynamic
-- @note Sizes widget: size_stats grouped by width (bucketed into phone/tablet/desktop in Go)
-- @param ?1 1
-- @param ?2 '2026-05-01'
-- @param ?3 '2026-10-30'
select
	width             as name,
	sum(count) as count
from size_stats
where site_id = ?1 and day >= ?2 and day <= ?3 and 1=1
group by width
order by count desc, name asc;

-- @id goatcounter.stats.locations
-- @src db/query/hit_stats.ListLocations.sql:1-19 (HitStats.ListLocations, hit_stats.go:380-386)
-- @style zdb template; :filter = 1=1, day range from asUTCDate()
-- @tags hotpath,analytics,dynamic
-- @note Locations widget: location_stats grouped by the 2-letter country prefix (substr), joined back to locations
-- @param ?1 1
-- @param ?2 '2026-05-01'
-- @param ?3 '2026-10-30'
-- @param ?4 7
-- @param ?5 0
with x as (
	select
		substr(location, 0, 3) as loc,
		sum(count)      as count
	from location_stats
	where site_id = ?1 and day >= ?2 and day <= ?3 and 1=1
	group by loc
	order by count desc, loc asc
	limit ?4 offset ?5
)
select
	locations.iso_3166_2   as id,
	locations.country_name as name,
	x.count         as count
from x
join locations on locations.iso_3166_2 = x.loc
order by count desc, loc asc;

-- @id goatcounter.stats.languages
-- @src db/query/hit_stats.ListLanguages.sql:1-19 (HitStats.ListLanguages, hit_stats.go:423-429)
-- @style zdb template; :filter = 1=1, day range from asUTCDate()
-- @tags hotpath,analytics,dynamic
-- @note Languages widget: language_stats grouped by language, joined to languages
-- @param ?1 1
-- @param ?2 '2026-05-01'
-- @param ?3 '2026-10-30'
-- @param ?4 7
-- @param ?5 0
with x as (
	select
		language,
		sum(count) as count
	from language_stats
	where site_id = ?1 and day >= ?2 and day <= ?3 and 1=1
	group by language
	order by count desc, language asc
	limit ?4 offset ?5
)
select
	languages.iso_639_3 as id,
	languages.name      as name,
	x.count             as count
from x
join languages on languages.iso_639_3 = x.language
order by count desc, language asc;

-- @id goatcounter.stats.campaigns
-- @src db/query/hit_stats.ListCampaigns.sql:1-19 (HitStats.ListCampaigns, hit_stats.go:444-450)
-- @style zdb template; :filter = 1=1, day range from asUTCDate()
-- @tags hotpath,analytics,dynamic
-- @note Campaigns widget: campaign_stats grouped by campaign
-- @param ?1 1
-- @param ?2 '2026-05-01'
-- @param ?3 '2026-10-30'
-- @param ?4 7
-- @param ?5 0
with x as (
	select
		campaign_id,
		sum(count) as count
	from campaign_stats
	where site_id = ?1 and day >= ?2 and day <= ?3 and 1=1
	group by campaign_id
	order by count desc, campaign_id asc
	limit ?4 offset ?5
)
select
	campaign_id     as id,
	campaigns.name  as name,
	x.count  as count
from x
join campaigns using (campaign_id)
order by count desc, campaign_id asc;

-- @id goatcounter.stats.campaign_refs
-- @src db/query/hit_stats.ListCampaign.sql:1-12 (HitStats.ListCampaign, hit_stats.go:465-472)
-- @style zdb template; :filter = 1=1, day range from asUTCDate()
-- @tags hotpath,analytics,dynamic
-- @note Campaign detail: sources of one campaign
-- @param ?1 1
-- @param ?2 '2026-05-01'
-- @param ?3 '2026-10-30'
-- @param ?4 3
-- @param ?5 11
-- @param ?6 0
select
	ref               as name,
	sum(count) as count
from campaign_stats
join campaigns using (campaign_id)
where
	campaign_stats.site_id = ?1 and day >= ?2 and day <= ?3 and
	1=1 and
	campaign_id = ?4
group by campaign_id, ref
order by count desc, ref asc
limit ?5 offset ?6;

-- @id goatcounter.cron.hit_counts_upsert
-- @src cron/hit_count.go:12-52; hit_stats.go:28-49,56-61; zdb bulk.go (BulkInsert)
-- @style zdb.BulkInsert: multi-row VALUES with ? placeholders and the Tables.HitCounts OnConflict clause
-- @tags hotpath,batch
-- @note Cron roll-up of the last batch of hits into hourly counts: multi-row upsert adding to existing totals (target has a UNIQUE ... ON CONFLICT REPLACE constraint; the upsert clause wins)
-- @param ?1 1
-- @param ?2 14972
-- @param ?3 '2026-10-30 23:00:00'
-- @param ?4 1
-- @param ?5 1
-- @param ?6 93
-- @param ?7 '2026-10-30 23:00:00'
-- @param ?8 1
-- @param ?9 1
-- @param ?10 1
-- @param ?11 '2026-10-30 23:00:00'
-- @param ?12 3
-- @param ?13 1
-- @param ?14 460
-- @param ?15 '2026-10-30 23:00:00'
-- @param ?16 1
-- @param ?17 1
-- @param ?18 6165
-- @param ?19 '2026-10-30 23:00:00'
-- @param ?20 1
-- @param ?21 1
-- @param ?22 5
-- @param ?23 '2026-10-30 23:00:00'
-- @param ?24 1
-- @param ?25 1
-- @param ?26 1541
-- @param ?27 '2026-10-30 23:00:00'
-- @param ?28 1
-- @param ?29 1
-- @param ?30 1379
-- @param ?31 '2026-10-30 23:00:00'
-- @param ?32 1
-- @param ?33 1
-- @param ?34 19663
-- @param ?35 '2026-10-30 23:00:00'
-- @param ?36 1
-- @param ?37 1
-- @param ?38 64
-- @param ?39 '2026-10-30 23:00:00'
-- @param ?40 1
-- @param ?41 1
-- @param ?42 52
-- @param ?43 '2026-10-30 23:00:00'
-- @param ?44 1
-- @param ?45 1
-- @param ?46 2
-- @param ?47 '2026-10-30 23:00:00'
-- @param ?48 2
insert into "hit_counts" (site_id,path_id,hour,total) values (?1,?2,?3,?4),(?5,?6,?7,?8),(?9,?10,?11,?12),(?13,?14,?15,?16),(?17,?18,?19,?20),(?21,?22,?23,?24),(?25,?26,?27,?28),(?29,?30,?31,?32),(?33,?34,?35,?36),(?37,?38,?39,?40),(?41,?42,?43,?44),(?45,?46,?47,?48) on conflict(site_id,path_id,hour) do update set
	total = hit_counts.total + excluded.total;

-- @id goatcounter.cron.browser_stats_upsert
-- @src cron/browser_stat.go:12-56; hit_stats.go:28-49,68-73
-- @style zdb.BulkInsert: multi-row VALUES with ? placeholders and the Tables.BrowserStats OnConflict clause
-- @tags hotpath,batch
-- @note Cron roll-up into daily per-path browser counts (same shape for system/location/size/language stats)
-- @param ?1 1
-- @param ?2 14972
-- @param ?3 '2026-10-30'
-- @param ?4 74
-- @param ?5 1
-- @param ?6 1
-- @param ?7 93
-- @param ?8 '2026-10-30'
-- @param ?9 1
-- @param ?10 1
-- @param ?11 1
-- @param ?12 1
-- @param ?13 '2026-10-30'
-- @param ?14 58
-- @param ?15 1
-- @param ?16 1
-- @param ?17 460
-- @param ?18 '2026-10-30'
-- @param ?19 1
-- @param ?20 1
-- @param ?21 1
-- @param ?22 6165
-- @param ?23 '2026-10-30'
-- @param ?24 36
-- @param ?25 1
-- @param ?26 1
-- @param ?27 5
-- @param ?28 '2026-10-30'
-- @param ?29 109
-- @param ?30 1
-- @param ?31 1
-- @param ?32 1541
-- @param ?33 '2026-10-30'
-- @param ?34 127
-- @param ?35 1
-- @param ?36 1
-- @param ?37 1379
-- @param ?38 '2026-10-30'
-- @param ?39 1
-- @param ?40 1
-- @param ?41 1
-- @param ?42 19663
-- @param ?43 '2026-10-30'
-- @param ?44 2
-- @param ?45 1
-- @param ?46 1
-- @param ?47 64
-- @param ?48 '2026-10-30'
-- @param ?49 88
-- @param ?50 1
-- @param ?51 1
-- @param ?52 52
-- @param ?53 '2026-10-30'
-- @param ?54 27
-- @param ?55 1
-- @param ?56 1
-- @param ?57 2
-- @param ?58 '2026-10-30'
-- @param ?59 133
-- @param ?60 1
insert into "browser_stats" (site_id,path_id,day,browser_id,count) values (?1,?2,?3,?4,?5),(?6,?7,?8,?9,?10),(?11,?12,?13,?14,?15),(?16,?17,?18,?19,?20),(?21,?22,?23,?24,?25),(?26,?27,?28,?29,?30),(?31,?32,?33,?34,?35),(?36,?37,?38,?39,?40),(?41,?42,?43,?44,?45),(?46,?47,?48,?49,?50),(?51,?52,?53,?54,?55),(?56,?57,?58,?59,?60) on conflict(site_id,path_id,day,browser_id) do update set
	count = browser_stats.count + excluded.count;

-- @id goatcounter.paths.merge_hit_counts
-- @src db/query/paths.Merge.gotxt:1-9 (Path.Merge, path.go:185-211)
-- @style zdb template with Go-built column lists for Tables.HitCounts; :in -> in
-- @tags batch,dynamic
-- @note Merging 39 paths into one: INSERT ... SELECT of the grouped counts with the upsert clause ("where true" for SQLite's parsing ambiguity)
-- @param ?1 1
-- @param ?2 250
-- @param ?3 258
-- @param ?4 2002
-- @param ?5 2010
-- @param ?6 2035
-- @param ?7 2043
-- @param ?8 2051
-- @param ?9 2076
-- @param ?10 2139
-- @param ?11 2147
-- @param ?12 2155
-- @param ?13 2221
-- @param ?14 2229
-- @param ?15 2254
-- @param ?16 2295
-- @param ?17 2303
-- @param ?18 2399
-- @param ?19 2407
-- @param ?20 2448
-- @param ?21 2473
-- @param ?22 2481
-- @param ?23 2547
-- @param ?24 2555
-- @param ?25 2563
-- @param ?26 2626
-- @param ?27 2651
-- @param ?28 2659
-- @param ?29 2667
-- @param ?30 2692
-- @param ?31 2700
-- @param ?32 2733
-- @param ?33 2741
-- @param ?34 2804
-- @param ?35 2878
-- @param ?36 2886
-- @param ?37 2911
-- @param ?38 2919
-- @param ?39 2952
-- @param ?40 2960
-- @param ?41 6
with x as (
	select site_id, hour, sum(total) as total from hit_counts
	where site_id = ?1 and path_id in (?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15, ?16, ?17, ?18, ?19, ?20, ?21, ?22, ?23, ?24, ?25, ?26, ?27, ?28, ?29, ?30, ?31, ?32, ?33, ?34, ?35, ?36, ?37, ?38, ?39, ?40)
	group by hour, site_id
)
insert into hit_counts (site_id, path_id, hour, total)
	-- "where true" is needed for SQLite: https://www.sqlite.org/lang_upsert.html#parsing_ambiguity
	select site_id, ?41, hour, total from x where true
on conflict(site_id,path_id,hour) do update set
	total = hit_counts.total + excluded.total;

-- @id goatcounter.export.csv_page
-- @src exportcsv.go:375-418
-- @style inline SQL, $1..$3 (zdb rewrites to ? for SQLite)
-- @note CSV export: one 5000-row page of raw hits from a hit_id cursor with 4 joins
-- @param ?1 1
-- @param ?2 100000
-- @param ?3 5000
select
			hits.hit_id,
			hits.site_id,

			paths.path,
			paths.title,
			paths.event,

			coalesce(browsers.name || ' ' || browsers.version, '') as browser,
			coalesce(systems.name  || ' ' || systems.version, '')  as system,

			hits.session,
			coalesce(refs.ref, '')           as ref,
			coalesce(refs.ref_scheme, '')    as ref_s,
			coalesce(hits.width, 0) ||',0,1' as size,
			coalesce(hits.location, '')      as loc,
			hits.first_visit                 as first,
			hits.created_at
		from hits
		join paths         using (path_id)
		left join refs     using (ref_id)
		left join browsers using (browser_id)
		left join systems  using (system_id)
		where hits.site_id=?1 and hit_id>?2
		order by hit_id asc
		limit ?3;

-- @id goatcounter.export.json_hit_stats
-- @src exportjson.go:206-211
-- @style inline SQL; whereHour empty (full export)
-- @tags analytics
-- @note JSON export of the hourly ref_counts for the site (the hit_stats file), ordered by hour
-- @param ?1 1
select hour, path_id, ref_id, total
				from ref_counts
				where site_id=?1  order by hour asc;

-- @id goatcounter.retention.paths_with_old_counts
-- @src site.go:599-606 (Site.DeleteOlderThan)
-- @style inline SQL with Interval() inlined for SQLite: datetime(datetime(), '-30 days')
-- @tags dynamic
-- @note Data retention (30 days): paths that have hourly counts older than the cut-off, grouped
-- @param ?1 1
select path_id from hit_counts where site_id=?1 and hour <  datetime(datetime(), '-30 days')  group by path_id;

-- @id goatcounter.retention.delete_old_hit_counts
-- @src site.go:614-617 (Site.DeleteOlderThan)
-- @style inline SQL with Interval() inlined for SQLite
-- @tags dynamic
-- @note Data retention: delete hourly counts older than 30 days (~5 of the 6 months)
-- @param ?1 1
delete from hit_counts where site_id=?1 and hour <  datetime(datetime(), '-30 days');

-- @id goatcounter.paths.get_or_insert
-- @src path.go:86-89 (Path.GetOrInsert)
-- @style inline SQL, $1/$2
-- @tags hotpath,hot-small
-- @note Per-hit path lookup on cache miss: unique expression index on (site_id, lower(path))
-- @param ?1 1
-- @param ?2 '/docs/api/page-6'
select * from paths
		where site_id = ?1 and lower(path) = lower(?2)
		limit 1;

-- @id goatcounter.ref.get_or_insert
-- @src ref.go:124-127 (Ref.GetOrInsert)
-- @style inline SQL, ? positional
-- @tags hotpath,hot-small
-- @note Per-hit referrer lookup on cache miss: unique expression index on (lower(ref), ref_scheme)
-- @param ?1 'Hacker News'
-- @param ?2 'g'
select * from refs
		where lower(ref) = lower(?1) and ref_scheme = ?2
		limit 1;

-- @id goatcounter.paths.by_id
-- @src path.go:50-54 (Path.ByID)
-- @style inline SQL, ? positional
-- @tags hot-small
-- @note Rowid lookup
-- @param ?1 6
-- @param ?2 1
select * from paths where path_id=?1 and site_id=?2;
