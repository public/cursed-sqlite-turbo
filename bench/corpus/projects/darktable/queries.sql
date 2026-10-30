-- darktable (darktable-org/darktable @ 9307ccbd2e8ef2f165258f16594f21af04beb8c8, GPL-3.0). C, raw sqlite3 API.
-- Most lighttable SQL is assembled with g_strdup_printf: the collection query (src/common/collection.c) is built
-- from per-property WHERE fragments (get_query_string), wrapped by the grouping clause and the sort builder, and
-- re-used by the collect module (src/libs/collect.c), the filter widgets (src/common/filter.c), the selection and
-- the thumbtable. Each such query is one representative instantiation (tagged dynamic); %d/%s values are inlined
-- as the app inlines them, real ?N binds stay binds.
-- Schema note: darktable ATTACHes data.db as `data` and an in-memory db as `memory`. The corpus uses one file,
-- so `data.` / `memory.` prefixes are dropped (data.meta_data becomes data_meta_data); `main.` stays.

-- @id darktable.collection.memory_update.folder_rating
-- @src src/common/collection.c:143-180
-- @style ?1/?2 bound (0, -1); text built by dt_collection_update (collection.c:240-386) + get_query_string (1383-1417, 2307-2370)
-- @tags hotpath,dynamic,batch
-- @note The lighttable hot path: every collection change refills memory.collected_images from the full collection query. Folder rule "2023*" plus a rating >= 2 filter, grouping on (the MIN(ABS(id-group_id)) representative subquery repeats the whole WHERE), DISTINCT over a derived table, sort by capture time.
-- @modified memory.collected_images -> collected_images (attached schema folded into one file)
-- @param ?1 0
-- @param ?2 -1
INSERT INTO collected_images (imgid)
SELECT DISTINCT sel.id
  FROM (SELECT mi.id, filename, version, datetime_taken
        FROM main.images AS mi
        WHERE  (flags & 256) != 256 AND (( (film_id IN (SELECT id FROM main.film_rolls WHERE folder LIKE '/home/demo/Pictures/2023' OR folder LIKE '/home/demo/Pictures/2023/%'))) AND ( (flags & 8 == 0 AND flags & 7 >= 2)))
          AND (group_id = 0 OR mi.id IN (SELECT id FROM (SELECT id, MIN(ABS(id-group_id)*2 + CASE WHEN (id-group_id) < 0 THEN 1 ELSE 0 END)
                                                        FROM main.images AS mi
                                                        WHERE  (flags & 256) != 256 AND (( (film_id IN (SELECT id FROM main.film_rolls WHERE folder LIKE '/home/demo/Pictures/2023' OR folder LIKE '/home/demo/Pictures/2023/%'))) AND ( (flags & 8 == 0 AND flags & 7 >= 2)))
                                                        GROUP BY group_id)))
          OR (mi.id = 0)) AS sel
 ORDER BY datetime_taken, filename, version ASC LIMIT ?1, ?2;

-- @id darktable.collection.get_nth.tag_colorlabel_rating_sort
-- @src src/common/collection.c:982-1016
-- @style ?1 nth, ?2 1; text from dt_collection_update with the tag rule (collection.c:1679-1712, case-insensitive default) and the colour-label mask filter (1419-1470)
-- @tags hotpath,dynamic
-- @note Collection "animals|birds*" (LIKE, case-insensitive) with an OR colour-label filter (red|green via a GROUP BY imgid SUM(1 << color) mask), grouping on, sorted by rating DESC then capture time; thumbtable/darkroom navigation asks for the nth image.
-- @modified data.tags -> tags (attached schema folded into one file)
-- @param ?1 10
-- @param ?2 1
SELECT DISTINCT sel.id
  FROM (SELECT mi.id, filename, version, datetime_taken, flags
        FROM main.images AS mi
        WHERE  (flags & 256) != 256 AND (( (mi.id IN (SELECT imgid FROM main.tagged_images WHERE tagid IN (SELECT id FROM tags WHERE name LIKE 'animals|birds' OR name LIKE 'animals|birds|%')))) AND ( (mi.id IN (SELECT id FROM (SELECT imgid AS id, SUM(1 << color) AS mask  FROM main.color_labels GROUP BY imgid)  WHERE ((mask & 5) <> 0)))))
          AND (group_id = 0 OR mi.id IN (SELECT id FROM (SELECT id, MIN(ABS(id-group_id)*2 + CASE WHEN (id-group_id) < 0 THEN 1 ELSE 0 END)
                                                        FROM main.images AS mi
                                                        WHERE  (flags & 256) != 256 AND (( (mi.id IN (SELECT imgid FROM main.tagged_images WHERE tagid IN (SELECT id FROM tags WHERE name LIKE 'animals|birds' OR name LIKE 'animals|birds|%')))) AND ( (mi.id IN (SELECT id FROM (SELECT imgid AS id, SUM(1 << color) AS mask  FROM main.color_labels GROUP BY imgid)  WHERE ((mask & 5) <> 0)))))
                                                        GROUP BY group_id)))
          OR (mi.id = 0)) AS sel
 ORDER BY CASE WHEN flags & 8 = 8 THEN -1 ELSE flags & 7 END DESC, datetime_taken, filename DESC, version ASC LIMIT ?1, ?2;

-- @id darktable.collection.count.textsearch_path_sort
-- @src src/common/collection.c:862-888
-- @style ?1/?2 bound (0, -1); COUNT(DISTINCT sel.id) spliced onto the no-group collection query at its first FROM; text-search filter from get_query_string (collection.c:2284-2305), path sort join (collection.c:315-322)
-- @tags hotpath,dynamic
-- @note The filter bar's free-text search: a 4-way UNION (metadata, tags+synonyms, filename/maker/model, folder) of LIKE '%sunset%' scans, counted after joining film_rolls for the folder sort.
-- @modified data.tags -> tags (attached schema folded into one file)
-- @param ?1 0
-- @param ?2 -1
SELECT COUNT(DISTINCT sel.id)
  FROM (SELECT mi.id, filename, version, film_id
        FROM main.images AS mi
        WHERE  (flags & 256) != 256 AND (( (mi.id IN (SELECT id FROM main.meta_data WHERE value LIKE '%sunset%' UNION SELECT imgid AS id         FROM main.tagged_images AS ti, tags AS t         WHERE t.id=ti.tagid AND (t.name LIKE '%sunset%' OR t.synonyms LIKE '%sunset%') UNION SELECT miu.id         FROM main.images AS miu, main.makers AS mk, main.models AS md         WHERE miu.maker_id = mk.id           AND miu.model_id = md.id           AND (filename LIKE '%sunset%' OR mk.name LIKE '%sunset%' OR md.name LIKE '%sunset%') UNION SELECT i.id         FROM main.images AS i, main.film_rolls AS fr         WHERE fr.id=i.film_id AND fr.folder LIKE '%sunset%'))))) AS sel
  JOIN (SELECT id AS film_rolls_id, folder FROM main.film_rolls) ON film_id = film_rolls_id
 ORDER BY folder, filename, filename, version ASC LIMIT ?1, ?2;

-- @id darktable.selection.select_range
-- @src src/common/selection.c:390-403
-- @style ?1 first row, ?2 row count; the no-group collection query with COLLECTION_QUERY_USE_LIMIT (collection.c:240-386), camera rule from get_query_string (1649-1678) and a month filter (2122-2185)
-- @tags dynamic,batch
-- @note Shift-click range selection: INSERT OR IGNORE of a LIMIT/OFFSET window of the collection (camera "Canon EOS R5" AND capture month in Jun-Aug via strftime over the 0001-01-01 microsecond epoch), sorted by filename.
-- @param ?1 20
-- @param ?2 150
INSERT OR IGNORE INTO main.selected_images (imgid)
SELECT DISTINCT sel.id
  FROM (SELECT mi.id, filename, version
        FROM main.images AS mi
        WHERE  (flags & 256) != 256 AND (( (camera_id IN (SELECT id FROM main.cameras WHERE maker || ' ' || model LIKE 'Canon EOS R5'))) AND ( (CAST(strftime('%m', datetime_taken / 86400000000.0 + julianday('0001-01-01')) AS INTEGER) IN (6, 7, 8))))) AS sel
 ORDER BY filename, version ASC LIMIT ?1, ?2;

-- @id darktable.thumbtable.load_next_rows
-- @src src/dtgtk/thumbtable.c:666-676
-- @style %d inlined (last rowid, thumbs to load)
-- @tags hotpath,hot-small,dynamic
-- @note Scrolling the lighttable grid: the next rows of thumbnails after the last visible rowid, with the selection flag via LEFT JOIN.
-- @modified memory.collected_images -> collected_images (attached schema folded into one file)
SELECT mi.rowid, mi.imgid, si.imgid
 FROM collected_images AS mi
 LEFT JOIN main.selected_images AS si
   ON mi.imgid = si.imgid
 WHERE rowid>4000
 ORDER BY rowid LIMIT 24;

-- @id darktable.thumbtable.select_next_in_selection
-- @src src/dtgtk/thumbtable.c:2331-2338
-- @style %d inlined (current imgid)
-- @tags hotpath,dynamic
-- @note Keyboard navigation restricted to the selection: next selected image at or after the current one; the scalar subquery looks up rowid by imgid, which has no index (full scan of collected_images).
-- @modified memory.collected_images -> collected_images (attached schema folded into one file)
SELECT m.imgid
 FROM collected_images AS m, main.selected_images AS s
 WHERE m.imgid=s.imgid
   AND m.rowid>=(SELECT rowid FROM collected_images WHERE imgid=77157)
 ORDER BY m.rowid LIMIT 1;

-- @id darktable.image_cache.load
-- @src src/common/image_cache.c:40-62
-- @style ?1 positional
-- @tags hotpath,hot-small
-- @note Image cache miss: one image row with 8 LEFT JOINed lookup tables (maker/model/lens/camera/wb/flash/program/metering); runs for every thumbnail that enters the cache.
-- @param ?1 73262
SELECT mi.id, group_id, film_id, width, height, filename,
       mk.name, md.name, ln.name,
       exposure, aperture, iso, focal_length, datetime_taken, flags,
       crop, orientation, focus_distance, raw_parameters,
       longitude, latitude, altitude, color_matrix, colorspace, version,
       raw_black, raw_maximum, aspect_ratio, exposure_bias,
       import_timestamp, change_timestamp, export_timestamp, print_timestamp,
       output_width, output_height, cm.maker, cm.model, cm.alias,
       wb.name, fl.name, ep.name, mm.name, flash_tagvalue
  FROM main.images AS mi
       LEFT JOIN main.cameras AS cm ON cm.id = mi.camera_id
       LEFT JOIN main.makers AS mk ON mk.id = mi.maker_id
       LEFT JOIN main.models AS md ON md.id = mi.model_id
       LEFT JOIN main.lens AS ln ON ln.id = mi.lens_id
       LEFT JOIN main.whitebalance AS wb ON wb.id = mi.whitebalance_id
       LEFT JOIN main.flash AS fl ON fl.id = mi.flash_id
       LEFT JOIN main.exposure_program AS ep ON ep.id = mi.exposure_program_id
       LEFT JOIN main.metering_mode AS mm ON mm.id = mi.metering_mode_id
  WHERE mi.id = ?1;

-- @id darktable.image_cache.write_release
-- @src src/common/image_cache.c:343-359
-- @style ?N positional (41 binds, numbered out of order as in the source)
-- @tags hotpath,hot-small
-- @note Write-back of a cached image after any change (rating, colour label, geotag, crop): a 39-column point UPDATE by primary key.
-- @param ?1 6000
-- @param ?2 4000
-- @param ?3 'IMG_9262.CR3'
-- @param ?4 1
-- @param ?5 2
-- @param ?6 4
-- @param ?7 0.008
-- @param ?8 5.6
-- @param ?9 400
-- @param ?10 50
-- @param ?11 3.2
-- @param ?12 294
-- @param ?13 63817000000000000
-- @param ?14 67
-- @param ?15 0.0
-- @param ?16 0
-- @param ?17 0
-- @param ?18 73262
-- @param ?19 -95.6487
-- @param ?20 27.9994
-- @param ?21 120.0
-- @param ?22 NULL
-- @param ?23 1
-- @param ?24 512
-- @param ?25 16383
-- @param ?26 1.5
-- @param ?27 0.0
-- @param ?28 63850254000000000
-- @param ?29 63890000000000000
-- @param ?30 -1
-- @param ?31 -1
-- @param ?32 6000
-- @param ?33 4000
-- @param ?35 2
-- @param ?36 2
-- @param ?37 1
-- @param ?38 3
-- @param ?39 1
-- @param ?40 73262
-- @param ?41 16
UPDATE main.images
 SET width = ?1, height = ?2, filename = ?3,
     maker_id = ?4, model_id = ?5, lens_id = ?6, camera_id = ?35,
     exposure = ?7, aperture = ?8, iso = ?9, focal_length = ?10,
     focus_distance = ?11, film_id = ?12, datetime_taken = ?13, flags = ?14,
     crop = ?15, orientation = ?16, raw_parameters = ?17, group_id = ?18,
     longitude = ?19, latitude = ?20, altitude = ?21, color_matrix = ?22,
     colorspace = ?23, raw_black = ?24, raw_maximum = ?25,
     aspect_ratio = ?26, exposure_bias = ?27,
     import_timestamp = ?28, change_timestamp = ?29, export_timestamp = ?30,
     print_timestamp = ?31, output_width = ?32, output_height = ?33,
     whitebalance_id = ?36, flash_id = ?37,
     exposure_program_id = ?38, metering_mode_id = ?39, flash_tagvalue = ?41
 WHERE id = ?40;

-- @id darktable.colorlabels.get
-- @src src/common/colorlabels.c:52-54
-- @style ?1 positional
-- @tags hotpath,hot-small
-- @note Colour labels of one image, read for every thumbnail overlay.
-- @param ?1 73277
SELECT color FROM main.color_labels WHERE imgid = ?1;

-- @id darktable.tags.is_attached
-- @src src/common/tags.c:1161-1163
-- @style ?1 ?2 positional
-- @tags hot-small
-- @note Point probe on the (imgid, tagid) primary key before attach/detach.
-- @param ?1 40000
-- @param ?2 746
SELECT imgid
 FROM main.tagged_images
 WHERE imgid = ?1 AND tagid = ?2;

-- @id darktable.selection.select_single
-- @src src/common/selection.c:76-77
-- @style %u inlined
-- @tags hotpath,hot-small,dynamic
-- @note Clicking a thumbnail (ungrouped case): single-row INSERT OR IGNORE on the unique imgid index.
INSERT OR IGNORE INTO main.selected_images (imgid) VALUES (73264);

-- @id darktable.tags.bulk_add_undo
-- @src src/common/tags.c:100-112
-- @style VALUES list built by _get_tb_added_tag_string_values (tags.c:55-79), %d inlined
-- @tags hot-small,dynamic,batch
-- @note Undo/redo of tagging: multi-row VALUES where each row's position is a scalar MAX(position) subquery masked to the high 32 bits (bit ops on the position index).
INSERT INTO main.tagged_images (imgid, tagid, position)
 VALUES (40000,120,  (SELECT (IFNULL(MAX(position),0) & 0xFFFFFFFF00000000) + (1 << 32)    FROM main.tagged_images)),(40000,1205,  (SELECT (IFNULL(MAX(position),0) & 0xFFFFFFFF00000000) + (1 << 32)    FROM main.tagged_images));

-- @id darktable.collect.tree.folders
-- @src src/libs/collect.c:1603-1616
-- @style where_ext from dt_collection_get_extended_where(collection, 0) (collection.c:447-520): rule 0 excluded as 1=1, rule 1 a camera rule
-- @tags hotpath,dynamic
-- @note Folder tree of the collections module: count per film roll joined with the folder-status table, restricted by the other collect rule (camera LIKE).
-- @modified memory.film_folder -> film_folder (attached schema folded into one file)
SELECT folder, film_rolls_id, COUNT(*) AS count, status
 FROM main.images AS mi
 JOIN (SELECT fr.id AS film_rolls_id, folder, status
       FROM main.film_rolls AS fr
       JOIN film_folder AS ff
       ON fr.id = ff.id)
   ON film_id = film_rolls_id
 WHERE (1=1 AND (camera_id IN (SELECT id FROM main.cameras WHERE maker || ' ' || model LIKE 'Canon EOS R5')))
 GROUP BY folder, film_rolls_id;

-- @id darktable.collect.tree.tags_insensitive
-- @src src/libs/collect.c:1618-1663
-- @style where_ext from dt_collection_get_extended_where(collection, 0): tag rule excluded, folder rule 1 kept
-- @tags hotpath,dynamic
-- @note Tag tree (default case-insensitive mode): per-tag counts grouped again by lower(name), UNION ALL the "not tagged" count via NOT IN over a DISTINCT/NOT IN memory table.
-- @modified data.tags -> tags, memory.darktable_tags -> darktable_tags (attached schemas folded into one file)
SELECT name, 1 AS tagid, SUM(count) AS count
 FROM (SELECT tagid, COUNT(*) as count
   FROM main.images AS mi
   JOIN main.tagged_images
     ON id = imgid
   WHERE (1=1 AND (film_id IN (SELECT id FROM main.film_rolls WHERE folder LIKE '/home/demo/Pictures/2023' OR folder LIKE '/home/demo/Pictures/2023/%')))
   GROUP BY tagid)
 JOIN (SELECT lower(name) AS name, id AS tag_id FROM tags)
   ON tagid = tag_id
   GROUP BY name
UNION ALL
SELECT 'not tagged' AS name, 0 as id, COUNT(*) AS count
FROM main.images AS mi
WHERE mi.id NOT IN
  (SELECT DISTINCT imgid FROM main.tagged_images AS ti
   WHERE ti.tagid NOT IN darktable_tags);

-- @id darktable.collect.tree.geotagging
-- @src src/libs/collect.c:1665-1689
-- @style where_ext "(1=1)" (single rule); tag root length from dt_map_location_data_tag_root() = "darktable|locations"
-- @tags dynamic
-- @note Geotagging tree: nested CASE over a LEFT JOIN to a 3-table derived (tagged_images x tags x locations) with SUBSTR of the location path, grouped by name and tag.
-- @modified data.tags -> tags, data.locations -> locations (attached schema folded into one file)
SELECT
 CASE WHEN mi.longitude IS NULL
           OR mi.latitude IS null THEN 'not tagged'
      ELSE CASE WHEN ta.imgid IS NULL THEN 'tagged'
                ELSE 'tagged' || ta.tagname
                END
      END AS name,
 ta.tagid AS tag_id, COUNT(*) AS count
 FROM main.images AS mi
 LEFT JOIN (SELECT imgid, t.id AS tagid, SUBSTR(t.name, 20) AS tagname
   FROM main.tagged_images AS ti
   JOIN tags AS t
     ON ti.tagid = t.id
   JOIN locations AS l
     ON l.tagid = t.id
   ) AS ta ON ta.imgid = mi.id
 WHERE (1=1)
 GROUP BY name, tag_id;

-- @id darktable.collect.list.camera
-- @src src/libs/collect.c:2096-2109
-- @style where_ext "(1=1)"; ASC
-- @tags hotpath,dynamic
-- @note Camera list: implicit join, TRIM of concatenated maker/model, GROUP BY/ORDER BY LOWER(alias).
SELECT TRIM(cm.maker || ' ' || cm.model) AS camera,
       1, COUNT(*) AS count
  FROM main.images AS mi, main.cameras AS cm
  WHERE mi.camera_id = cm.id
    AND (1=1)
  GROUP BY LOWER(camera)
  ORDER BY LOWER(camera) ASC;

-- @id darktable.collect.list.history
-- @src src/libs/collect.c:2111-2137
-- @style where_ext with the folder rule kept (collection.c:447-520); localised labels inlined
-- @tags dynamic
-- @note History state list: two CASE chains over blob-hash equality, LEFT JOIN to a DISTINCT derived table, GROUP BY/ORDER BY the computed order.
SELECT CASE
       WHEN basic_hash == current_hash THEN 'basic'
       WHEN auto_hash == current_hash THEN 'auto applied'
       WHEN current_hash IS NOT NULL THEN 'altered'
       ELSE 'basic'
     END as altered, 1, COUNT(*) AS count,
     CASE
       WHEN basic_hash == current_hash THEN 0
       WHEN auto_hash == current_hash THEN 1
       WHEN current_hash IS NOT NULL THEN 3
       ELSE 2
     END AS force_order
 FROM main.images AS mi
 LEFT JOIN (SELECT DISTINCT imgid, basic_hash, auto_hash, current_hash
            FROM main.history_hash) ON id = imgid
 WHERE (1=1 AND (film_id IN (SELECT id FROM main.film_rolls WHERE folder LIKE '/home/demo/Pictures/2023' OR folder LIKE '/home/demo/Pictures/2023/%')))
 GROUP BY force_order
 ORDER BY force_order ASC;

-- @id darktable.collect.list.metadata_title
-- @src src/libs/collect.c:2437-2462
-- @style keyid = property - DT_COLLECTION_PROP_METADATA_OFFSET (2 = Xmp.dc.title); where_ext "(1=1)"
-- @tags dynamic
-- @note Metadata value list (title): LEFT JOIN to a key-filtered derived table, CASE for undefined, GROUP BY lower(value) with a two-key ORDER BY.
SELECT
 CASE WHEN value IS NULL THEN 'not defined' ELSE value END AS value,
 1, COUNT(*) AS count,
 CASE WHEN value IS NULL THEN 0 ELSE 1 END AS force_order
 FROM main.images AS mi
 LEFT JOIN (SELECT id AS meta_data_id, value
            FROM main.meta_data
            WHERE key = 2)
  ON id = meta_data_id
 WHERE (1=1)
 GROUP BY lower(value)
 ORDER BY force_order ASC, lower(value) ASC;

-- @id darktable.collect.list.module
-- @src src/libs/collect.c:2361-2378
-- @style where_ext "(1=1)"
-- @tags dynamic
-- @note Processing-module list: images JOIN a DISTINCT (imgid, operation) projection of the 260k-row history JOIN the iop-name table, grouped by module name.
-- @modified memory.darktable_iop_names -> darktable_iop_names (attached schema folded into one file)
SELECT m.name AS module_name, 1, COUNT(*) AS count
 FROM main.images AS mi
 JOIN (SELECT DISTINCT imgid, operation
       FROM main.history
       WHERE enabled = 1) AS h
  ON h.imgid = mi.id
 JOIN darktable_iop_names AS m
  ON m.operation = h.operation
 WHERE (1=1)
 GROUP BY lower(module_name)
 ORDER BY lower(module_name) ASC;

-- @id darktable.collect.list.exposure
-- @src src/libs/collect.c:2306-2320
-- @style where_ext with the folder rule kept
-- @tags dynamic
-- @note Shutter-speed list: CASE building '1/N' or 'N"' strings with CAST and ROUND, grouped on the string.
SELECT CASE
         WHEN (exposure < 0.4) THEN '1/' || CAST(1/exposure + 0.9 AS INTEGER)
         ELSE ROUND(exposure,2) || '"'
       END AS _exposure, 1, COUNT(*) AS count
 FROM main.images AS mi
 WHERE (1=1 AND (film_id IN (SELECT id FROM main.film_rolls WHERE folder LIKE '/home/demo/Pictures/2023' OR folder LIKE '/home/demo/Pictures/2023/%')))
 GROUP BY _exposure
 ORDER BY exposure ASC;

-- @id darktable.filter.extension_counts
-- @src src/common/filter.c:187-218
-- @style where_ext from dt_collection_get_extended_where(collection, 99999) (src/libs/filtering.c:2378)
-- @tags hotpath,dynamic
-- @note File-type filter widget: extension extracted with nested replace/rtrim string tricks, upper(), grouped and ordered.
SELECT upper(replace(filename, rtrim(filename, replace(filename, '.', '')), '.')) AS ext, COUNT(*) AS count, flags
 FROM main.images AS mi
 WHERE ( (film_id IN (SELECT id FROM main.film_rolls WHERE folder LIKE '/home/demo/Pictures/2023' OR folder LIKE '/home/demo/Pictures/2023/%')))
 GROUP BY ext
 ORDER BY ext;

-- @id darktable.filter.duplicate_counts
-- @src src/common/filter.c:244-272
-- @style where_ext "(1=1)"
-- @tags dynamic
-- @note Duplicates filter widget: self-join of images to a GROUP BY film_id, filename HAVING COUNT(*) > 1 derived table with MIN(version).
SELECT CASE
         WHEN dups.min_version = version THEN 0
         ELSE 1
       END AS orig
     , COUNT(*) AS count
 FROM main.images AS mi
 JOIN (
   SELECT film_id AS f_id
        , filename
        , MIN(version) AS min_version
   FROM main.images
   GROUP BY f_id
          , filename
   HAVING COUNT(*) > 1
 ) dups ON mi.film_id = dups.f_id AND mi.filename = dups.filename
 WHERE (1=1)
 GROUP BY orig
 ORDER BY orig ASC;

-- @id darktable.tags.get_attached_selection
-- @src src/common/tags.c:729-797
-- @style images = dt_selection_get_list_query(sel, FALSE, FALSE) = "SELECT imgid FROM main.selected_images" (selection.c:544); ignore_dt_tags on
-- @tags hotpath,dynamic
-- @note Tagging module "attached tags" view for the selection: DISTINCT + GROUP BY with COUNT(DISTINCT imgid), IN-subquery on the selection, NOT IN a memory table, ordered by name.
-- @modified data.tags -> tags, memory.darktable_tags -> darktable_tags (attached schemas folded into one file)
SELECT DISTINCT I.tagid, T.name, T.flags, T.synonyms,
 COUNT(DISTINCT I.imgid) AS inb
 FROM main.tagged_images AS I
 JOIN tags AS T ON T.id = I.tagid
 WHERE I.imgid IN (SELECT imgid FROM main.selected_images) AND T.id NOT IN darktable_tags
 GROUP BY I.tagid
 ORDER by T.name;

-- @id darktable.tags.get_with_usage
-- @src src/common/tags.c:1585-1599
-- @style no binds
-- @tags hotpath
-- @note Tagging dictionary list: every tag LEFT JOINed with its total usage (memory.taglist) and a per-tag COUNT(DISTINCT imgid) over the selection, sorted by name.
-- @modified data.tags -> tags, memory.taglist -> taglist, memory.darktable_tags -> darktable_tags (attached schemas folded into one file); taglist is prefilled by data.sql with the suggestions INSERT (tags.c:1318-1335), a superset of the usage INSERT at tags.c:1572-1578
SELECT T.name, T.id, MT.count, CT.imgnb, T.flags, T.synonyms
  FROM tags T
  LEFT JOIN taglist MT ON MT.id = T.id
  LEFT JOIN (SELECT tagid, COUNT(DISTINCT imgid) AS imgnb
             FROM main.tagged_images
             WHERE imgid IN (SELECT imgid
                               FROM main.selected_images)
                               GROUP BY tagid) AS CT
    ON CT.tagid = T.id
  WHERE T.id NOT IN darktable_tags
  ORDER BY T.name;

-- @id darktable.tags.suggestions
-- @src src/common/tags.c:1338-1377
-- @style confidence, nb_selected, recent-tag list and nb_recent inlined with %u/%s/%d
-- @tags hotpath,dynamic
-- @note Tag suggestions: co-occurrence self-join of tagged_images (DISTINCT pairs, GROUP BY tagid1, tagid2) filtered by a confidence ratio against memory.taglist, UNION a LIMITed recent-tags list, then LEFT JOINs for names.
-- @modified data.tags -> tags, memory.taglist -> taglist, memory.darktable_tags -> darktable_tags (attached schemas folded into one file)
SELECT td.name, tagid2, t21.count, t21.count2,
 td.flags, td.synonyms FROM (
  SELECT DISTINCT tagid2 FROM (
    SELECT tagid2 FROM (
      SELECT tagid1, tagid2, count(*) AS c12
      FROM (
        SELECT DISTINCT tagid AS tagid1, imgid FROM main.tagged_images
        JOIN taglist AS t00
        ON t00.id = tagid1 AND t00.count2 > 0) AS t1
      JOIN (
        SELECT DISTINCT tagid AS tagid2, imgid FROM main.tagged_images
        WHERE tagid NOT IN darktable_tags) AS t2
      ON t2.imgid = t1.imgid AND tagid1 != tagid2
      GROUP BY tagid1, tagid2)
    JOIN taglist AS t01
    ON t01.id = tagid1
    JOIN taglist AS t02
    ON t02.id = tagid2
    WHERE (t01.count-t01.count2) != 0
      AND (100 * c12 / (t01.count-t01.count2) >= 1)
      AND t02.count2 != 246)
  UNION
  SELECT * FROM (
    SELECT tn.id AS tagid2 FROM tags AS tn
    JOIN taglist AS t02
    ON t02.id = tn.id
    WHERE tn.name IN ('animals|waders|golden 9','events|trip|red 1','places|Africa|young 12')
      AND t02.count2 != 246 LIMIT 20))
LEFT JOIN taglist AS t21
ON t21.id = tagid2
LEFT JOIN tags as td ON td.id = tagid2;

-- @id darktable.tags.attached_export
-- @src src/common/tags.c:801-822
-- @style ?1 positional
-- @tags hotpath
-- @note Export/XMP tag list for one image: tags joined to an ordered DISTINCT derived set ON id match OR "is an ancestor path" (SUBSTR/LENGTH prefix test) - a non-indexable OR join over all tags.
-- @modified data.tags -> tags, memory.darktable_tags -> darktable_tags (attached schemas folded into one file)
-- @param ?1 40000
SELECT DISTINCT T.id, T.name, T.flags, T.synonyms
 FROM tags AS T
 JOIN (SELECT DISTINCT I.tagid, T.name
       FROM main.tagged_images AS I
       JOIN tags AS T ON T.id = I.tagid
       WHERE I.imgid = ?1 AND T.id NOT IN darktable_tags
       ORDER by T.name) AS T1
 ON T.id = T1.tagid
    OR (T.name = SUBSTR(T1.name, 1, LENGTH(T.name))
       AND SUBSTR(T1.name, LENGTH(T.name) + 1, 1) = '|');

-- @id darktable.tags.similar_images
-- @src src/common/tags.c:1517-1523
-- @style no binds; memory.similar_tags filled by the INSERT at tags.c:1485-1491
-- @tags dynamic
-- @modified memory.similar_tags -> similar_tags (attached schema folded into one file); similar_tags prefilled by data.sql for keyword 'animals|birds'
-- @note Images carrying a tag or any of its descendants (tag manager rename/delete preview): DISTINCT over a join to the memory table.
SELECT DISTINCT ti.imgid
 FROM main.tagged_images AS ti
 JOIN similar_tags AS st
   ON st.tagid = ti.tagid;

-- @id darktable.map_locations.list
-- @src src/common/map_locations.c:126-135
-- @style ?1 ?2 positional (path, path || '|')
-- @tags dynamic
-- @note Map locations module list: location tags under a path with usage counts from a LEFT JOINed GROUP BY over all tagged_images (COUNT DISTINCT), prefix match via SUBSTR(name, 1, LENGTH(?2)).
-- @modified data.tags -> tags (attached schema folded into one file)
-- @param ?1 'darktable|locations'
-- @param ?2 'darktable|locations|'
SELECT t.id, t.name, ti.count
  FROM tags AS t
  LEFT JOIN (SELECT tagid,
               COUNT(DISTINCT imgid) AS count
             FROM main.tagged_images
             GROUP BY tagid) AS ti
  ON ti.tagid = t.id
  WHERE name = ?1 OR SUBSTR(name, 1, LENGTH(?2)) = ?2;

-- @id darktable.map_locations.find_locations
-- @src src/common/map_locations.c:388-408
-- @style ?1..?4 positional (imgid, MAP_LOCATION_SHAPE_ELLIPSE/RECTANGLE/POLYGONS = 0/1/2)
-- @tags hotpath
-- @note Which saved locations contain this image (run on every geotag change): join to locations ON an ellipse inequality OR bounding-box tests - arithmetic predicate evaluated for every location row.
-- @modified data.locations -> locations (attached schema folded into one file)
-- @param ?1 73264
-- @param ?2 0
-- @param ?3 1
-- @param ?4 2
SELECT l.tagid, l.type, i.longitude, i.latitude FROM main.images AS i
  JOIN locations AS l
  ON (l.type = ?2
      AND ((((i.longitude-l.longitude)*(i.longitude-l.longitude))/(delta1*delta1) +
            ((i.latitude-l.latitude)*(i.latitude-l.latitude))/(delta2*delta2)) <= 1)
    OR ((l.type = ?3 OR l.type = ?4)
        AND i.longitude>=(l.longitude-delta1)
        AND i.longitude<=(l.longitude+delta1)
        AND i.latitude>=(l.latitude-delta2)
        AND i.latitude<=(l.latitude+delta2)))
 WHERE i.id = ?1
       AND i.latitude IS NOT NULL AND i.longitude IS NOT NULL;

-- @id darktable.map.main_query_collected
-- @src src/views/map.c:3283-3301
-- @style ?1..?4 positional (lon min/max, lat max/min); plugins/map/filter_images_drawn on
-- @tags hotpath,dynamic
-- @note Map view redraw: images of the current collection inside the visible bounding box (range predicates on lon/lat, join to collected_images).
-- @modified memory.collected_images -> collected_images (attached schema folded into one file)
-- @param ?1 -60.0
-- @param ?2 60.0
-- @param ?3 40.0
-- @param ?4 -10.0
SELECT * FROM
 (SELECT id, longitude, latitude
   FROM main.images i INNER JOIN collected_images c ON i.id = c.imgid WHERE longitude >= ?1 AND longitude <= ?2
           AND latitude <= ?3 AND latitude >= ?4
           AND longitude NOT NULL AND latitude NOT NULL);
