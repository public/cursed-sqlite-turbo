-- Synthetic darktable library for the corpus. Deterministic: values come from multiplicative hashes of the row
-- counter (h and g below, different bits per column). Scale 1: 400 film rolls, 100k images (~6% duplicates,
-- ~30% geotagged), ~1.5k tags, ~420k tagged_images rows, ~260k history rows, 40 map locations; collected_images
-- holds the 2023 folder (~9k images) as dt_collection_memory_update would leave it.
BEGIN;

INSERT INTO makers(id, name) VALUES (1,'Canon'),(2,'Nikon'),(3,'Sony'),(4,'Fujifilm'),(5,'OM Digital Solutions');
INSERT INTO models(id, name) VALUES
 (1,'EOS R5'),(2,'EOS 5D Mark IV'),(3,'EOS R6'),(4,'Z 6II'),(5,'D850'),(6,'Z 8'),(7,'ILCE-7M3'),(8,'ILCE-7RM4'),
 (9,'ILCE-6400'),(10,'X-T4'),(11,'X100V'),(12,'X-H2'),(13,'OM-1'),(14,'E-M1MarkIII'),(15,'E-M10MarkIV');
INSERT INTO cameras(id, maker, model, alias)
SELECT m.id, mk.name, m.name, m.name FROM models m JOIN makers mk ON mk.id = (m.id - 1) / 3 + 1;
INSERT INTO lens(id, name) VALUES
 (1,'RF24-105mm F4 L IS USM'),(2,'RF70-200mm F2.8 L IS USM'),(3,'EF50mm f/1.8 STM'),(4,'RF15-35mm F2.8 L IS USM'),
 (5,'NIKKOR Z 24-70mm f/4 S'),(6,'NIKKOR Z 50mm f/1.8 S'),(7,'AF-S NIKKOR 70-200mm f/2.8E FL ED VR'),
 (8,'FE 24-70mm F2.8 GM'),(9,'FE 85mm F1.8'),(10,'FE 100-400mm F4.5-5.6 GM OSS'),(11,'E 18-135mm F3.5-5.6 OSS'),
 (12,'XF16-80mmF4 R OIS WR'),(13,'XF23mmF2 R WR'),(14,'XF56mmF1.2 R'),(15,'XF100-400mmF4.5-5.6 R LM OIS WR'),
 (16,'M.Zuiko Digital ED 12-40mm F2.8 PRO'),(17,'M.Zuiko Digital ED 40-150mm F2.8 PRO'),(18,'M.Zuiko 25mm F1.8'),
 (19,'Sigma 35mm F1.4 DG HSM | A'),(20,'Tamron 28-75mm F/2.8 Di III RXD'),(21,'Samyang 14mm F2.8'),
 (22,'Laowa 100mm f/2.8 2x Ultra Macro APO'),(23,'Viltrox 75mm F1.2'),(24,'n/a'),(25,'');
INSERT INTO whitebalance(id, name) VALUES (1,'Auto'),(2,'Daylight'),(3,'Cloudy'),(4,'Shade'),(5,'Tungsten'),(6,'Manual');
INSERT INTO flash(id, name) VALUES (1,'No flash'),(2,'Flash fired'),(3,'Flash did not fire, compulsory'),(4,'Flash fired, red-eye reduction'),(5,'No flash function');
INSERT INTO exposure_program(id, name) VALUES (1,'Manual'),(2,'Normal program'),(3,'Aperture priority'),(4,'Shutter priority'),(5,'Creative program'),(6,'Action program');
INSERT INTO metering_mode(id, name) VALUES (1,'Matrix'),(2,'Center weighted average'),(3,'Spot'),(4,'Partial'),(5,'Multi-spot');

-- film rolls: ~10 days apart from 2015 to 2025, one folder per event under the year, some with a jpg/ subfolder
WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 400*(SELECT scale FROM _cfg)),
ev(k, w) AS (VALUES (0,'Trip'),(1,'Birthday'),(2,'Hike'),(3,'Wedding'),(4,'Street'),(5,'Birds'),(6,'Family'),(7,'Concert'),(8,'Garden'),(9,'Portraits')),
f AS (SELECT i, (i * 2654435761) % 4294967296 AS h,
             date('2015-01-01', '+' || ((i - 1) * 10 / (SELECT scale FROM _cfg)) || ' days') AS d FROM n)
INSERT INTO film_rolls(id, access_timestamp, folder)
SELECT i, 63850000000000000 + i * 86400000000,
       '/home/demo/Pictures/' || substr(d, 1, 4) || '/' || d || ' ' || (SELECT w FROM ev WHERE k = (h / 16) % 10)
       || CASE WHEN i % 13 = 0 THEN '/jpg' ELSE '' END
FROM f;
INSERT INTO film_folder(id, status) SELECT id, CASE WHEN id % 29 = 0 THEN 0 ELSE 1 END FROM film_rolls;

-- images: 250 per film roll; every 17th image is a duplicate (version 1) of the previous one
WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 100000*(SELECT scale FROM _cfg)),
b AS (SELECT i, CASE WHEN i % 17 = 0 THEN i - 1 ELSE i END AS k FROM n),
x AS (SELECT i, k, (k * 2654435761) % 4294967296 AS h, (k * 2246822519) % 4294967296 AS g,
             (i - 1) / 250 + 1 AS film FROM b),
y AS (SELECT x.*, (h / 8) % 10 AS e, (g / 64) % 15 + 1 AS cam,
             CASE WHEN (g / 32768) % 5 = 0 THEN 1 ELSE 0 END AS portrait,
             (g / 1048576) % 10 < 3 AS geo, (g / 16777216) % 40 AS loc FROM x)
INSERT INTO images(id, group_id, film_id, width, height, filename, maker_id, model_id, lens_id, camera_id,
                   exposure, aperture, iso, focal_length, focus_distance, datetime_taken, flags,
                   output_width, output_height, crop, orientation, longitude, latitude, altitude, colorspace,
                   version, max_version, position, aspect_ratio, exposure_bias,
                   import_timestamp, change_timestamp, export_timestamp, print_timestamp,
                   whitebalance_id, flash_id, exposure_program_id, metering_mode_id, flash_tagvalue)
SELECT i, k, film,
       CASE WHEN portrait THEN 4000 ELSE 6000 END - CASE WHEN e IN (6,7) THEN 2080 ELSE 0 END,
       CASE WHEN portrait THEN 6000 ELSE 4000 END - CASE WHEN e IN (6,7) THEN 1360 ELSE 0 END,
       CASE e WHEN 0 THEN 'IMG_' WHEN 1 THEN 'IMG_' WHEN 2 THEN '_DSC' WHEN 3 THEN 'DSCF' WHEN 4 THEN 'P' ELSE 'IMG_' END
         || printf('%04d', k % 10000)
         || CASE e WHEN 0 THEN '.CR3' WHEN 1 THEN '.CR3' WHEN 2 THEN '.NEF' WHEN 3 THEN '.RAF' WHEN 4 THEN '.ORF'
                   WHEN 5 THEN '.ARW' WHEN 6 THEN '.jpg' WHEN 7 THEN '.JPG' WHEN 8 THEN '.DNG' ELSE '.tif' END,
       (cam - 1) / 3 + 1, cam, (h / 1024) % 25 + 1, cam,
       CASE (h / 32768) % 11 WHEN 0 THEN 1.0/4000 WHEN 1 THEN 1.0/1000 WHEN 2 THEN 1.0/250 WHEN 3 THEN 1.0/125
            WHEN 4 THEN 1.0/60 WHEN 5 THEN 1.0/30 WHEN 6 THEN 1.0/8 WHEN 7 THEN 0.5 WHEN 8 THEN 1.0 WHEN 9 THEN 2.0 ELSE 30.0 END,
       CASE (g / 4) % 9 WHEN 0 THEN 1.4 WHEN 1 THEN 1.8 WHEN 2 THEN 2.0 WHEN 3 THEN 2.8 WHEN 4 THEN 4.0
            WHEN 5 THEN 5.6 WHEN 6 THEN 8.0 WHEN 7 THEN 11.0 ELSE 16.0 END,
       100 * (1 << ((g / 8192) % 8)),
       CASE (h / 4194304) % 9 WHEN 0 THEN 14 WHEN 1 THEN 24 WHEN 2 THEN 35 WHEN 3 THEN 50 WHEN 4 THEN 85
            WHEN 5 THEN 105 WHEN 6 THEN 135 WHEN 7 THEN 200 ELSE 400 END,
       (h % 1000) / 10.0,
       CASE WHEN i % 53 = 0 THEN 0
            ELSE CAST(((julianday('2015-01-01') - julianday('0001-01-01')) + (film - 1) * 10.0 / (SELECT scale FROM _cfg)
                       + (28800 + (i % 250) * 150) / 86400.0) * 86400000000 AS INTEGER) END,
       ((g / 512) % 6)
         | CASE WHEN (g / 2) % 20 = 0 THEN 8 ELSE 0 END
         | CASE WHEN e IN (6,7,9) THEN 32 ELSE 64 END
         | CASE WHEN i % 997 = 0 THEN 256 ELSE 0 END
         | CASE WHEN (h / 7) % 40 = 0 THEN 2048 ELSE 0 END,
       CASE WHEN portrait THEN 4000 ELSE 6000 END, CASE WHEN portrait THEN 6000 ELSE 4000 END, 0, CASE WHEN portrait THEN 6 ELSE 0 END,
       CASE WHEN geo THEN -120.0 + loc * 6.1 + ((h % 1000) / 1000.0 - 0.5) * 0.12 END,
       CASE WHEN geo THEN -40.0 + (loc * 37) % 80 + (((h / 1000) % 1000) / 1000.0 - 0.5) * 0.1 END,
       CASE WHEN geo THEN (h % 2000) END,
       1, CASE WHEN i % 17 = 0 THEN 1 ELSE 0 END, CASE WHEN (i + 1) % 17 = 0 OR i % 17 = 0 THEN 1 ELSE 0 END,
       i * 4294967296,
       round(CASE WHEN portrait THEN 4000.0 / 6000 ELSE 6000.0 / 4000 END, 2),
       CASE (h / 268435456) % 9 WHEN 0 THEN -1.0 WHEN 1 THEN -0.7 WHEN 2 THEN -0.3 WHEN 6 THEN 0.3 WHEN 7 THEN 0.7 WHEN 8 THEN 1.0 ELSE 0.0 END,
       63850000000000000 + film * 864000000000 + i * 1000000,
       CASE WHEN (g / 2) % 5 < 3 THEN 63860000000000000 + i * 3000000 ELSE -1 END,
       CASE WHEN (h / 9) % 5 = 0 THEN 63870000000000000 + i * 3000000 ELSE -1 END,
       CASE WHEN (h / 9) % 97 = 0 THEN 63880000000000000 + i * 3000000 ELSE -1 END,
       (g / 2048) % 6 + 1, (h / 512) % 5 + 1, (g / 65536) % 6 + 1, (h / 131072) % 5 + 1, (h / 512) % 5
FROM y;

-- colour labels (0 red .. 4 purple), ~20% of images, some with two
INSERT OR IGNORE INTO color_labels(imgid, color)
SELECT id, ((id * 2246822519) % 4294967296 / 3) % 5 FROM images WHERE ((id * 2654435761) % 4294967296 / 3) % 5 = 0
UNION ALL
SELECT id, (((id * 2246822519) % 4294967296 / 3) % 5 + 2) % 5 FROM images WHERE ((id * 2654435761) % 4294967296 / 3) % 25 = 0;

-- data.meta_data key definitions (data upgrade 12->13)
INSERT INTO data_meta_data(key, tagname, name, internal, visible, private, display_order) VALUES
 (0,'Xmp.dc.creator','creator',0,1,0,2),(1,'Xmp.dc.publisher','publisher',0,1,0,3),(2,'Xmp.dc.title','title',0,1,0,0),
 (3,'Xmp.dc.description','description',0,1,0,1),(4,'Xmp.dc.rights','rights',0,1,0,4),(5,'Xmp.acdsee.notes','notes',0,1,0,5),
 (6,'Xmp.darktable.version_name','version name',0,1,0,6),(7,'Xmp.darktable.image_id','image id',1,0,0,7),
 (8,'Xmp.xmpMM.PreservedFileName','preserved filename',0,1,0,8);

WITH w(k, w) AS (VALUES (0,'sunset'),(1,'harbour'),(2,'old town'),(3,'mountain lake'),(4,'kingfisher'),(5,'market'),(6,'forest path'),(7,'beach'),(8,'cathedral'),(9,'night sky'))
INSERT INTO meta_data(id, key, value)
SELECT id, 0, CASE WHEN id % 7 = 0 THEN 'Sam Example' ELSE 'Kim Example' END FROM images WHERE (id * 40503) % 10 < 6
UNION ALL
SELECT id, 2, (SELECT upper(substr(w, 1, 1)) || substr(w, 2) FROM w WHERE k = (id * 2654435761) % 4294967296 / 1048576 % 10) || ' ' || (id % 50)
FROM images WHERE (id * 2246822519) % 4294967296 / 1024 % 7 = 0
UNION ALL
SELECT id, 3, 'A ' || (SELECT w FROM w WHERE k = (id * 2246822519) % 4294967296 / 4096 % 10) || ' at dusk, shot handheld'
FROM images WHERE (id * 2654435761) % 4294967296 / 2048 % 10 = 0
UNION ALL
SELECT id, 4, 'CC BY-SA 4.0' FROM images WHERE id % 2 = 0
UNION ALL
SELECT id, 8, filename FROM images WHERE id % 10 = 0;

-- tags: darktable internal tags, 40 location tags, then a user hierarchy (top|second|leaf)
INSERT INTO tags(id, name, synonyms, flags) VALUES
 (1,'darktable|format|cr3',NULL,0),(2,'darktable|format|nef',NULL,0),(3,'darktable|format|raf',NULL,0),
 (4,'darktable|format|orf',NULL,0),(5,'darktable|format|arw',NULL,0),(6,'darktable|format|jpg',NULL,0),
 (7,'darktable|format|dng',NULL,0),(8,'darktable|format|tif',NULL,0),(9,'darktable|changed',NULL,0),
 (10,'darktable|exported',NULL,0),(11,'darktable|mode|monochrome',NULL,0);
WITH RECURSIVE n(i) AS (SELECT 0 UNION ALL SELECT i+1 FROM n WHERE i < 39)
INSERT INTO tags(id, name, synonyms, flags)
SELECT 20 + i, 'darktable|locations|' || CASE i % 4 WHEN 0 THEN 'Europe' WHEN 1 THEN 'Asia' WHEN 2 THEN 'Americas' ELSE 'Africa' END
       || '|Place ' || i, NULL, 0 FROM n;
INSERT INTO locations(tagid, type, longitude, latitude, delta1, delta2, ratio, polygons)
SELECT id, (id - 20) % 2, -120.0 + (id - 20) * 6.1, -40.0 + ((id - 20) * 37) % 80, 0.05, 0.04, 1.0, NULL FROM tags WHERE id BETWEEN 20 AND 59;

WITH top(t, tn) AS (VALUES (0,'places'),(1,'people'),(2,'animals'),(3,'events'),(4,'style'),(5,'gear')),
sec(t, s, sn) AS (VALUES
  (0,0,'Europe'),(0,1,'Asia'),(0,2,'Americas'),(0,3,'Africa'),(0,4,'Oceania'),(0,5,'Home'),(0,6,'France'),(0,7,'Japan'),(0,8,'Italy'),(0,9,'Canada'),
  (1,0,'family'),(1,1,'friends'),(1,2,'work'),(1,3,'models'),(1,4,'kids'),(1,5,'strangers'),(1,6,'band'),(1,7,'team'),(1,8,'neighbours'),(1,9,'clients'),
  (2,0,'birds'),(2,1,'mammals'),(2,2,'insects'),(2,3,'pets'),(2,4,'reptiles'),(2,5,'fish'),(2,6,'Birds'),(2,7,'waders'),(2,8,'raptors'),(2,9,'butterflies'),
  (3,0,'birthday'),(3,1,'wedding'),(3,2,'concert'),(3,3,'holiday'),(3,4,'festival'),(3,5,'sport'),(3,6,'graduation'),(3,7,'christmas'),(3,8,'party'),(3,9,'trip'),
  (4,0,'black and white'),(4,1,'long exposure'),(4,2,'macro'),(4,3,'portrait'),(4,4,'landscape'),(4,5,'street'),(4,6,'abstract'),(4,7,'night'),(4,8,'hdr'),(4,9,'panorama'),
  (5,0,'tripod'),(5,1,'filter'),(5,2,'flash'),(5,3,'drone'),(5,4,'film'),(5,5,'phone'),(5,6,'adapter'),(5,7,'extension tube'),(5,8,'teleconverter'),(5,9,'gimbal'))
INSERT INTO tags(id, name, synonyms, flags)
SELECT 100 + t, tn, NULL, 1 FROM top
UNION ALL
SELECT 110 + t * 10 + s, tn || '|' || sn, CASE WHEN s % 3 = 0 THEN sn || 's' END, 1 FROM sec JOIN top USING (t);
-- 1440 leaves: leaf j goes under second-level node j % 60
WITH RECURSIVE n(j) AS (SELECT 0 UNION ALL SELECT j+1 FROM n WHERE j < 1439),
leaf(k, w) AS (VALUES (0,'red'),(1,'blue'),(2,'old'),(3,'little'),(4,'great'),(5,'north'),(6,'south'),(7,'grey'),(8,'golden'),(9,'wild'),(10,'Green'),(11,'young'))
INSERT INTO tags(id, name, synonyms, flags)
SELECT 200 + j, (SELECT name FROM tags WHERE id = 110 + j % 60) || '|' || (SELECT w FROM leaf WHERE k = (j / 60) % 12) || ' ' || (j / 60 + 1),
       CASE WHEN j % 9 = 0 THEN 'alt ' || j END, CASE WHEN j % 50 = 0 THEN 2 ELSE 0 END
FROM n;

-- tagged_images: format tag, changed/exported, location tag for geotagged images near a location, 3 user tags
-- (one from a popular set of 37 leaves, one from 400, one from all 1440)
INSERT OR IGNORE INTO tagged_images(imgid, tagid, position)
SELECT id, CASE substr(filename, -3) WHEN 'CR3' THEN 1 WHEN 'NEF' THEN 2 WHEN 'RAF' THEN 3 WHEN 'ORF' THEN 4 WHEN 'ARW' THEN 5
                 WHEN 'jpg' THEN 6 WHEN 'JPG' THEN 6 WHEN 'DNG' THEN 7 ELSE 8 END, 4294967296 + id FROM images
UNION ALL SELECT id, 9, 2 * 4294967296 + id FROM images WHERE change_timestamp <> -1
UNION ALL SELECT id, 10, 3 * 4294967296 + id FROM images WHERE export_timestamp <> -1
UNION ALL SELECT id, 20 + ((id - (id % 17 = 0)) * 2246822519) % 4294967296 / 16777216 % 40, 4 * 4294967296 + id
          FROM images WHERE latitude IS NOT NULL AND id % 2 = 0
UNION ALL SELECT id, 200 + ((id * 2654435761) % 4294967296 / 64 % 37) * 39 % 1440, 5 * 4294967296 + id FROM images
UNION ALL SELECT id, 200 + ((id * 2246822519) % 4294967296 / 128 % 400) * 7 % 1440, 6 * 4294967296 + id FROM images WHERE id % 3 <> 0
UNION ALL SELECT id, 200 + (id * 40507) % 1440, 7 * 4294967296 + id FROM images WHERE id % 4 = 1;

-- history for the edited (~40%) images, 3..10 entries each; history_hash/module_order for edited + auto-applied
WITH RECURSIVE k(num) AS (SELECT 0 UNION ALL SELECT num+1 FROM k WHERE num < 9),
op(o, name) AS (VALUES (0,'rawprepare'),(1,'temperature'),(2,'highlights'),(3,'demosaic'),(4,'exposure'),(5,'colorin'),
                       (6,'channelmixerrgb'),(7,'filmicrgb'),(8,'colorbalancergb'),(9,'lens'),(10,'denoiseprofile'),(11,'crop'),
                       (12,'sigmoid'),(13,'toneequal'),(14,'ashift'),(15,'colorout'))
INSERT INTO history(imgid, num, module, operation, op_params, enabled, blendop_params, blendop_version, multi_priority, multi_name, multi_name_hand_edited)
SELECT i.id, k.num, 1, (SELECT name FROM op WHERE o = (k.num * 3 + i.id) % 16), zeroblob(12),
       CASE WHEN (i.id + k.num) % 11 = 0 THEN 0 ELSE 1 END, zeroblob(4), 14, 0, '', 0
FROM images i JOIN k ON k.num < 3 + (i.id * 2654435761) % 4294967296 / 16 % 8
WHERE (i.id * 2246822519) % 4294967296 / 2 % 5 < 2;

INSERT INTO history_hash(imgid, basic_hash, auto_hash, current_hash, mipmap_hash)
SELECT id,
       CASE WHEN id % 23 = 0 THEN NULL ELSE X'0b0b' END,
       X'0a0a',
       CASE c WHEN 2 THEN X'0a0a' ELSE CAST(printf('%08x', id) AS BLOB) END,
       NULL
FROM (SELECT id, (id * 2246822519) % 4294967296 / 2 % 5 AS c FROM images) WHERE c < 3;

INSERT INTO module_order(imgid, version, iop_list)
SELECT imgid, CASE WHEN imgid % 31 = 0 THEN 0 WHEN imgid % 19 = 0 THEN 2
                   WHEN (SELECT flags & 32 FROM images WHERE id = imgid) THEN 5 ELSE 4 END,
       CASE WHEN imgid % 31 = 0 THEN 'rawprepare,0,temperature,0,highlights,0,demosaic,0,exposure,0,colorin,0' END
FROM history_hash;

INSERT INTO darktable_iop_names(operation, name) VALUES
 ('rawprepare','raw black/white point'),('temperature','white balance'),('highlights','highlight reconstruction'),
 ('demosaic','demosaic'),('exposure','exposure'),('colorin','input color profile'),('channelmixerrgb','color calibration'),
 ('filmicrgb','filmic rgb'),('colorbalancergb','color balance rgb'),('lens','lens correction'),('denoiseprofile','denoise (profiled)'),
 ('crop','crop'),('sigmoid','sigmoid'),('toneequal','tone equalizer'),('ashift','rotate and perspective'),('colorout','output color profile');

-- memory.darktable_tags as dt_set_darktable_tags() fills it
INSERT INTO darktable_tags(tagid) SELECT DISTINCT id FROM tags WHERE name LIKE 'darktable|%';

-- memory.collected_images as dt_collection_memory_update() leaves it for the "2023 folder" collection, sorted by date
INSERT INTO collected_images(imgid)
SELECT mi.id FROM images AS mi JOIN film_rolls AS fr ON fr.id = mi.film_id
WHERE (fr.folder LIKE '/home/demo/Pictures/2023' OR fr.folder LIKE '/home/demo/Pictures/2023/%') AND (mi.flags & 256) != 256
ORDER BY mi.datetime_taken, mi.filename, mi.version;

-- selection: every 40th collected image plus a few images outside the collection
INSERT OR IGNORE INTO selected_images(imgid)
SELECT imgid FROM collected_images WHERE rowid % 40 = 3
UNION ALL SELECT id FROM images WHERE id % 4999 = 5;

-- memory.taglist as dt_tag_get_suggestions() fills it before its main query (src/common/tags.c:1318-1335)
INSERT INTO taglist (id, count, count2)
SELECT S.tagid, COUNT(imgid) AS count, CASE WHEN count2 IS NULL THEN 0 ELSE count2 END AS count2
FROM tagged_images AS S
LEFT JOIN (SELECT tagid, COUNT(imgid) AS count2 FROM tagged_images
           WHERE imgid IN (SELECT imgid FROM selected_images) GROUP BY tagid) AS at ON at.tagid = S.tagid
WHERE S.tagid NOT IN darktable_tags
GROUP BY S.tagid;

-- memory.similar_tags as dt_tag_get_tags_images('animals|birds') fills it
INSERT INTO similar_tags(tagid) SELECT id FROM tags WHERE name = 'animals|birds' OR SUBSTR(name, 1, LENGTH('animals|birds|')) = 'animals|birds|';
COMMIT;
