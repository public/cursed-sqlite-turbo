-- darktable-org/darktable @ 9307ccbd2e8ef2f165258f16594f21af04beb8c8 (GPL-3.0)
-- Only the CREATE statements the queries need, taken from src/common/database.c:
--   _create_library_schema (3332-3636) plus upgrade step 56->57 (2963-2970, images.flash_tagvalue),
--   _create_data_schema (3642-3700) plus data upgrade 12->13 (3226, data.meta_data),
--   _create_memory_schema (3705-3760).
-- darktable keeps three schemas on one connection: main (library.db), data (data.db, ATTACHed) and memory
-- (':memory:', ATTACHed). The corpus runner uses one database file per project and cannot ATTACH, so the data.*
-- and memory.* tables are created as plain tables here, without the schema prefix. data.meta_data collides with
-- main.meta_data and is renamed data_meta_data. Queries drop the data./memory. prefixes accordingly (@modified).

-- main (library.db)
CREATE TABLE film_rolls (id INTEGER PRIMARY KEY, access_timestamp INTEGER, folder VARCHAR(1024) NOT NULL);
CREATE INDEX film_rolls_folder_index ON film_rolls (folder);
CREATE TABLE makers (id INTEGER PRIMARY KEY AUTOINCREMENT, name VARCHAR);
CREATE INDEX makers_name ON makers (name);
CREATE TABLE models (id INTEGER PRIMARY KEY AUTOINCREMENT, name VARCHAR);
CREATE INDEX models_name ON models (name);
CREATE TABLE lens (id INTEGER PRIMARY KEY AUTOINCREMENT, name VARCHAR);
CREATE INDEX lens_name ON lens (name);
CREATE TABLE cameras (id INTEGER PRIMARY KEY AUTOINCREMENT, maker VARCHAR, model VARCHAR, alias VARCHAR);
CREATE UNIQUE INDEX cameras_name ON cameras (maker, model, alias);
CREATE TABLE whitebalance (id INTEGER PRIMARY KEY AUTOINCREMENT, name VARCHAR);
CREATE UNIQUE INDEX whitebalance_name ON whitebalance (name);
CREATE TABLE flash (id INTEGER PRIMARY KEY AUTOINCREMENT, name VARCHAR);
CREATE UNIQUE INDEX flash_name ON flash (name);
CREATE TABLE exposure_program (id INTEGER PRIMARY KEY AUTOINCREMENT, name VARCHAR);
CREATE UNIQUE INDEX exposure_program_name ON exposure_program (name);
CREATE TABLE metering_mode (id INTEGER PRIMARY KEY AUTOINCREMENT, name VARCHAR);
CREATE UNIQUE INDEX metering_mode_name ON metering_mode (name);

CREATE TABLE images
 (id INTEGER PRIMARY KEY AUTOINCREMENT, group_id INTEGER, film_id INTEGER,
  width INTEGER, height INTEGER, filename VARCHAR,
  maker_id INTEGER, model_id INTEGER, lens_id INTEGER, camera_id INTEGER,
  exposure REAL, aperture REAL, iso REAL, focal_length REAL,
  focus_distance REAL, datetime_taken INTEGER, flags INTEGER,
  output_width INTEGER, output_height INTEGER, crop REAL,
  raw_parameters INTEGER, raw_black INTEGER, raw_maximum INTEGER,
  orientation INTEGER, longitude REAL,
  latitude REAL, altitude REAL, color_matrix BLOB, colorspace INTEGER,
  version INTEGER, max_version INTEGER, write_timestamp INTEGER,
  history_end INTEGER, position INTEGER, aspect_ratio REAL, exposure_bias REAL,
  import_timestamp INTEGER DEFAULT -1, change_timestamp INTEGER DEFAULT -1,
  export_timestamp INTEGER DEFAULT -1, print_timestamp INTEGER DEFAULT -1,
  thumb_timestamp INTEGER DEFAULT -1, thumb_maxmip INTEGER DEFAULT 0,
  whitebalance_id INTEGER, flash_id INTEGER,
  exposure_program_id INTEGER, metering_mode_id INTEGER,
  flash_tagvalue INTEGER DEFAULT -1,
  FOREIGN KEY(maker_id) REFERENCES makers(id) ON DELETE CASCADE ON UPDATE CASCADE,
  FOREIGN KEY(model_id) REFERENCES models(id) ON DELETE CASCADE ON UPDATE CASCADE,
  FOREIGN KEY(lens_id) REFERENCES lens(id) ON DELETE CASCADE ON UPDATE CASCADE,
  FOREIGN KEY(camera_id) REFERENCES cameras(id) ON DELETE CASCADE ON UPDATE CASCADE,
  FOREIGN KEY(film_id) REFERENCES film_rolls(id) ON DELETE CASCADE ON UPDATE CASCADE,
  FOREIGN KEY(group_id) REFERENCES images(id) ON DELETE RESTRICT ON UPDATE CASCADE,
  FOREIGN KEY(whitebalance_id) REFERENCES whitebalance(id) ON DELETE CASCADE ON UPDATE CASCADE,
  FOREIGN KEY(flash_id) REFERENCES flash(id) ON DELETE CASCADE ON UPDATE CASCADE,
  FOREIGN KEY(exposure_program_id) REFERENCES exposure_program(id) ON DELETE CASCADE ON UPDATE CASCADE,
  FOREIGN KEY(metering_mode_id) REFERENCES metering_mode(id) ON DELETE CASCADE ON UPDATE CASCADE);
CREATE INDEX images_group_id_index ON images (group_id, id);
CREATE INDEX images_film_id_index ON images (film_id, filename);
CREATE INDEX images_filename_index ON images (filename, version);
CREATE INDEX image_position_index ON images (position);
CREATE INDEX images_datetime_taken_nc ON images (datetime_taken);
CREATE INDEX images_latlong_index ON images (latitude DESC, longitude DESC);

CREATE TABLE selected_images (num INTEGER PRIMARY KEY AUTOINCREMENT, imgid INTEGER);
CREATE UNIQUE INDEX selected_images_ni ON selected_images (imgid);

CREATE TABLE history (imgid INTEGER, num INTEGER, module INTEGER,
  operation VARCHAR(256), op_params BLOB, enabled INTEGER,
  blendop_params BLOB, blendop_version INTEGER, multi_priority INTEGER, multi_name VARCHAR(256), multi_name_hand_edited INTEGER,
  FOREIGN KEY(imgid) REFERENCES images(id) ON UPDATE CASCADE ON DELETE CASCADE);
CREATE INDEX history_imgid_op_index ON history (imgid, operation);
CREATE INDEX history_imgid_num_index ON history (imgid, num DESC);

CREATE TABLE tagged_images (imgid INTEGER, tagid INTEGER, position INTEGER,
  PRIMARY KEY (imgid, tagid),
  FOREIGN KEY(imgid) REFERENCES images(id) ON UPDATE CASCADE ON DELETE CASCADE);
CREATE INDEX tagged_images_tagid_index ON tagged_images (tagid);
CREATE INDEX tagged_images_position_index ON tagged_images (position);

CREATE TABLE color_labels (imgid INTEGER, color INTEGER);
CREATE UNIQUE INDEX color_labels_idx ON color_labels (imgid, color);

CREATE TABLE meta_data (id INTEGER, key INTEGER, value VARCHAR,
  FOREIGN KEY(id) REFERENCES images(id) ON DELETE CASCADE ON UPDATE CASCADE);
CREATE UNIQUE INDEX metadata_index ON meta_data (id, key, value);
CREATE INDEX metadata_index_key ON meta_data (key);
CREATE INDEX metadata_index_value ON meta_data (value);

CREATE TABLE module_order (imgid INTEGER PRIMARY KEY, version INTEGER, iop_list VARCHAR);

CREATE TABLE history_hash (imgid INTEGER PRIMARY KEY,
  basic_hash BLOB, auto_hash BLOB, current_hash BLOB, mipmap_hash BLOB,
  FOREIGN KEY(imgid) REFERENCES images(id) ON UPDATE CASCADE ON DELETE CASCADE);

-- data (data.db), prefix dropped
CREATE TABLE tags (id INTEGER PRIMARY KEY, name VARCHAR, synonyms VARCHAR, flags INTEGER);
CREATE UNIQUE INDEX tags_name_idx ON tags (name);
CREATE TABLE locations (tagid INTEGER PRIMARY KEY,
  type INTEGER, longitude REAL, latitude REAL, delta1 REAL, delta2 REAL, ratio FLOAT, polygons BLOB,
  FOREIGN KEY(tagid) REFERENCES tags(id));
-- data.meta_data, renamed (collides with main.meta_data)
CREATE TABLE data_meta_data (key INTEGER PRIMARY KEY, tagname VARCHAR,
  name VARCHAR, internal INTEGER, visible INTEGER, private INTEGER, display_order INTEGER);
CREATE UNIQUE INDEX meta_data_tagname_idx ON data_meta_data (tagname);
CREATE UNIQUE INDEX meta_data_name_idx ON data_meta_data (name);

-- memory (':memory:'), prefix dropped
CREATE TABLE collected_images (rowid INTEGER PRIMARY KEY AUTOINCREMENT, imgid INTEGER);
CREATE TABLE tmp_selection (imgid INTEGER PRIMARY KEY);
CREATE TABLE taglist (tmpid INTEGER PRIMARY KEY, id INTEGER UNIQUE ON CONFLICT IGNORE,
  count INTEGER DEFAULT 0, count2 INTEGER DEFAULT 0);
CREATE TABLE similar_tags (tagid INTEGER PRIMARY KEY);
CREATE TABLE darktable_tags (tagid INTEGER PRIMARY KEY);
CREATE TABLE darktable_iop_names (operation VARCHAR(256) PRIMARY KEY, name VARCHAR(256));
CREATE TABLE film_folder (id INTEGER PRIMARY KEY, status INTEGER);
