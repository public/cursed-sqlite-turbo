-- Grocy (grocy/grocy @ 41206cb, MIT): the full final schema after replaying migrations/0001.sql .. 0257.sql in order
-- with the sqlite3 CLI (the PHP migrations 0027/0031/0063/0144/0162/0240/0242 only seed rows or touch files and were
-- skipped; data.sql provides the rows). Dumped with .schema, verbatim except one substitution:
--   products_volatile_status calls the PHP UDF grocy_user_setting('stock_due_soon_days'); the stock CLI has no such
--   function, so the call is replaced by the setting's default, 5 (config-dist.php: DefaultUserSetting('stock_due_soon_days', 5)).
-- Tables, indexes (only the app's own), views and triggers are all here; the views carry the app's logic.
CREATE TABLE locations (
	id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT UNIQUE,
	name TEXT NOT NULL UNIQUE,
	description TEXT,
	row_created_timestamp DATETIME DEFAULT (datetime('now', 'localtime'))
, is_freezer TINYINT NOT NULL DEFAULT 0, active TINYINT NOT NULL DEFAULT 1 CHECK(active IN (0, 1)));
CREATE TABLE quantity_units (
	id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT UNIQUE,
	name TEXT NOT NULL UNIQUE,
	description TEXT,
	row_created_timestamp DATETIME DEFAULT (datetime('now', 'localtime'))
, name_plural TEXT, plural_forms TEXT, active TINYINT NOT NULL DEFAULT 1 CHECK(active IN (0, 1)));
CREATE TABLE "chores" (
	id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT UNIQUE,
	name TEXT NOT NULL UNIQUE,
	description TEXT,
	period_type TEXT NOT NULL,
	period_days INTEGER,
	row_created_timestamp DATETIME DEFAULT (datetime('now', 'localtime'))
, period_config TEXT, track_date_only TINYINT DEFAULT 0, rollover TINYINT DEFAULT 0, assignment_type TEXT, assignment_config TEXT, next_execution_assigned_to_user_id INT, consume_product_on_execution TINYINT NOT NULL DEFAULT 0, product_id TINYINT, product_amount REAL, period_interval INTEGER NOT NULL DEFAULT 1 CHECK(period_interval > 0), active TINYINT NOT NULL DEFAULT 1 CHECK(active IN (0, 1)), start_date DATETIME, rescheduled_date DATETIME, rescheduled_next_execution_assigned_to_user_id INT);
CREATE TABLE batteries (
	id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT UNIQUE,
	name TEXT NOT NULL UNIQUE,
	description TEXT,
	used_in TEXT,
	charge_interval_days INTEGER NOT NULL DEFAULT 0,
	row_created_timestamp DATETIME DEFAULT (datetime('now', 'localtime'))
, active TINYINT NOT NULL DEFAULT 1 CHECK(active IN (0, 1)));
CREATE TABLE recipes (
	id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT UNIQUE,
	name TEXT NOT NULL,
	description TEXT,
	row_created_timestamp DATETIME DEFAULT (datetime('now', 'localtime'))
, picture_file_name TEXT, base_servings INTEGER DEFAULT 1, desired_servings INTEGER DEFAULT 1, not_check_shoppinglist TINYINT NOT NULL DEFAULT 0, type TEXT DEFAULT 'normal', product_id INTEGER);
CREATE TABLE users (
	id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT UNIQUE,
	username TEXT NOT NULL UNIQUE,
	first_name TEXT,
	last_name TEXT,
	password TEXT NOT NULL,
	row_created_timestamp DATETIME DEFAULT (datetime('now', 'localtime'))
, picture_file_name TEXT);
CREATE TABLE api_keys (
	id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT UNIQUE,
	api_key TEXT NOT NULL UNIQUE,
	user_id INTEGER NOT NULL,
	expires DATETIME,
	last_used DATETIME,
	row_created_timestamp DATETIME DEFAULT (datetime('now', 'localtime'))
, key_type TEXT NOT NULL DEFAULT 'default', description TEXT);
CREATE TABLE chores_log (
	id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT UNIQUE,
	chore_id INTEGER NOT NULL,
	tracked_time DATETIME,
	done_by_user_id INTEGER,
	row_created_timestamp DATETIME DEFAULT (datetime('now', 'localtime'))
, undone TINYINT NOT NULL DEFAULT 0 CHECK(undone IN (0, 1)), undone_timestamp DATETIME, skipped TINYINT NOT NULL DEFAULT 0 CHECK(skipped IN (0, 1)), scheduled_execution_time DATETIME);
CREATE TABLE task_categories (
	id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT UNIQUE,
	name TEXT NOT NULL UNIQUE,
	description TEXT,
	row_created_timestamp DATETIME DEFAULT (datetime('now', 'localtime'))
, active TINYINT NOT NULL DEFAULT 1 CHECK(active IN (0, 1)));
CREATE VIEW tasks_current
AS
SELECT *
FROM tasks
WHERE done = 0
/* tasks_current(id,name,description,due_date,done,done_timestamp,category_id,assigned_to_user_id,row_created_timestamp) */;
CREATE TABLE product_groups (
	id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT UNIQUE,
	name TEXT NOT NULL UNIQUE,
	description TEXT,
	row_created_timestamp DATETIME DEFAULT (datetime('now', 'localtime'))
, active TINYINT NOT NULL DEFAULT 1 CHECK(active IN (0, 1)));
CREATE TABLE user_settings (
	id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT UNIQUE,
	user_id INTEGER NOT NULL,
	key TEXT NOT NULL,
	value TEXT,
	row_created_timestamp DATETIME DEFAULT (datetime('now', 'localtime')),
	row_updated_timestamp DATETIME DEFAULT (datetime('now', 'localtime')),

	UNIQUE(user_id, key)
);
CREATE TABLE equipment (
	id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT UNIQUE,
	name TEXT NOT NULL UNIQUE,
	description TEXT,
	instruction_manual_file_name TEXT,
	row_created_timestamp DATETIME DEFAULT (datetime('now', 'localtime'))
);
CREATE TABLE recipes_nestings (
	id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT UNIQUE,
	recipe_id INTEGER NOT NULL,
	includes_recipe_id INTEGER NOT NULL,
	row_created_timestamp DATETIME DEFAULT (datetime('now', 'localtime')), servings INTEGER DEFAULT 1,

	UNIQUE(recipe_id, includes_recipe_id)
);
CREATE TABLE recipes_pos (
	id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT UNIQUE,
	recipe_id INTEGER NOT NULL,
	product_id INTEGER NOT NULL,
	amount REAL NOT NULL DEFAULT 0,
	note TEXT,
	qu_id INTEGER,
	only_check_single_unit_in_stock TINYINT NOT NULL DEFAULT 0,
	ingredient_group TEXT,
	not_check_stock_fulfillment TINYINT NOT NULL DEFAULT 0,
	row_created_timestamp DATETIME DEFAULT (datetime('now', 'localtime'))
, variable_amount TEXT, price_factor REAL NOT NULL DEFAULT 1, round_up TINYINT NOT NULL DEFAULT 0 CHECK(round_up IN (0, 1)));
CREATE TABLE stock (
	id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT UNIQUE,
	product_id INTEGER NOT NULL,
	amount DECIMAL(15, 2) NOT NULL,
	best_before_date DATE,
	purchased_date DATE DEFAULT (datetime('now', 'localtime')),
	stock_id TEXT NOT NULL,
	price DECIMAL(15, 2),
	open TINYINT NOT NULL DEFAULT 0 CHECK(open IN (0, 1)),
	opened_date DATETIME,
	row_created_timestamp DATETIME DEFAULT (datetime('now', 'localtime'))
, location_id INTEGER, shopping_location_id INTEGER, note TEXT);
CREATE TABLE shopping_list (
	id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT UNIQUE,
	product_id INTEGER,
	note TEXT,
	amount DECIMAL(15, 2) NOT NULL DEFAULT 0,
	row_created_timestamp DATETIME DEFAULT (datetime('now', 'localtime'))
, shopping_list_id INT DEFAULT 1, done INT DEFAULT 0, qu_id INTEGER);
CREATE TABLE shopping_lists (
	id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT UNIQUE,
	name TEXT NOT NULL UNIQUE,
	description TEXT,
	row_created_timestamp DATETIME DEFAULT (datetime('now', 'localtime'))
);
CREATE TABLE userfields (
	id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT UNIQUE,
	entity TEXT NOT NULL,
	name TEXT NOT NULL,
	caption TEXT NOT NULL,
	type TEXT NOT NULL,
	show_as_column_in_tables TINYINT NOT NULL DEFAULT 0,
	row_created_timestamp DATETIME DEFAULT (datetime('now', 'localtime')), config TEXT, sort_number INTEGER, input_required TINYINT NOT NULL DEFAULT 0 CHECK(input_required IN (0, 1)), default_value TEXT,

	UNIQUE(entity, name)
);
CREATE INDEX ix_recipes ON recipes (
	name,
	type
);
CREATE TABLE quantity_unit_conversions (
	id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT UNIQUE,
	from_qu_id INT NOT NULL,
	to_qu_id INT NOT NULL,
	factor REAL NOT NULL,
	product_id INT,
	row_created_timestamp DATETIME DEFAULT (datetime('now', 'localtime'))
);
CREATE VIEW chores_execution_users_statistics
AS
SELECT
	c.id AS id, -- Dummy, LessQL needs an id column
	c.id AS chore_id,
	caur.user_id AS user_id,
	(SELECT COUNT(1) FROM chores_log WHERE chore_id = c.id AND done_by_user_id = caur.user_id AND undone = 0) AS execution_count
FROM chores c
JOIN chores_assigned_users_resolved caur
	ON c.id = caur.chore_id
GROUP BY c.id, caur.user_id
/* chores_execution_users_statistics(id,chore_id,user_id,execution_count) */;
CREATE TABLE userentities (
	id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT UNIQUE,
	name TEXT NOT NULL,
	caption TEXT NOT NULL,
	description TEXT,
	show_in_sidebar_menu TINYINT NOT NULL DEFAULT 1,
	icon_css_class TEXT,
	row_created_timestamp DATETIME DEFAULT (datetime('now', 'localtime')),

	UNIQUE(name)
);
CREATE TABLE userobjects (
	id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT UNIQUE,
	userentity_id INTEGER NOT NULL,
	row_created_timestamp DATETIME DEFAULT (datetime('now', 'localtime'))
);
CREATE TRIGGER remove_recipe_from_meal_plans AFTER DELETE ON recipes
BEGIN
	DELETE FROM meal_plan
	WHERE recipe_id = OLD.id;
END;
CREATE TRIGGER set_products_default_location_if_empty_stock AFTER INSERT ON stock
BEGIN
	UPDATE stock
	SET location_id = (SELECT location_id FROM products where id = product_id)
	WHERE id = NEW.id
		AND location_id IS NULL;
END;
CREATE TABLE meal_plan (
	id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT UNIQUE,
	day DATE NOT NULL,
	type TEXT DEFAULT 'recipe',
	recipe_id INTEGER,
	recipe_servings INTEGER DEFAULT 1,
	note TEXT,
	product_id INTEGER,
	product_amount REAL DEFAULT 0,
	product_qu_id INTEGER,
	row_created_timestamp DATETIME DEFAULT (datetime('now', 'localtime'))
, done TINYINT NOT NULL DEFAULT 0 CHECK(done IN (0, 1)), section_id INTEGER NOT NULL DEFAULT -1);
CREATE TABLE shopping_locations (
	id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT UNIQUE,
	name TEXT NOT NULL UNIQUE,
	description TEXT,
	row_created_timestamp DATETIME DEFAULT (datetime('now', 'localtime'))
, active TINYINT NOT NULL DEFAULT 1 CHECK(active IN (0, 1)));
CREATE VIEW stock_current_locations
AS
SELECT
	1 AS id, -- Dummy, LessQL needs an id column
	s.product_id,
        SUM(s.amount) as amount,
	s.location_id AS location_id,
	l.name AS location_name,
	l.is_freezer AS location_is_freezer
FROM stock s
JOIN locations l
	ON s.location_id = l.id
GROUP BY s.product_id, s.location_id, l.name
/* stock_current_locations(id,product_id,amount,location_id,location_name,location_is_freezer) */;
CREATE TABLE product_barcodes (
	id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT UNIQUE,
	product_id INT NOT NULL,
	barcode TEXT NOT NULL,
	qu_id INT,
	amount REAL,
	shopping_location_id INTEGER,
	last_price DECIMAL(15, 2),
	row_created_timestamp DATETIME DEFAULT (datetime('now', 'localtime'))
, note TEXT);
CREATE VIEW stock_current_location_content
AS
SELECT
	IFNULL(s.location_id, p.location_id) AS location_id,
	s.product_id,
	SUM(s.amount) AS amount,
	ROUND(SUM(IFNULL(s.price, 0) * s.amount), 2) AS value,
	MIN(s.best_before_date) AS best_before_date,
	IFNULL((SELECT SUM(amount) FROM stock WHERE product_id = s.product_id AND location_id = s.location_id AND open = 1), 0) AS amount_opened
FROM stock s
JOIN products p
	ON s.product_id = p.id
	AND p.active = 1
GROUP BY IFNULL(s.location_id, p.location_id), s.product_id
/* stock_current_location_content(location_id,product_id,amount,value,best_before_date,amount_opened) */;
CREATE INDEX ix_stock_performance1 ON stock (
    product_id,
    open,
    best_before_date,
    amount
);
CREATE VIEW products_resolved
AS
SELECT
    CASE
        WHEN p.parent_product_id IS NULL THEN
            p.id
        ELSE
            p.parent_product_id
    END AS parent_product_id,
    p.id as sub_product_id
FROM products p
WHERE p.active = 1
/* products_resolved(parent_product_id,sub_product_id) */;
CREATE TRIGGER remove_items_from_deleted_shopping_list AFTER DELETE ON shopping_lists
BEGIN
    DELETE FROM shopping_list WHERE shopping_list_id = OLD.id;
END;
CREATE TABLE user_permissions
(
	id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT UNIQUE,
	permission_id INTEGER NOT NULL,
	user_id INTEGER NOT NULL,

	UNIQUE (user_id, permission_id)
);
CREATE TABLE permission_hierarchy
(
	id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT UNIQUE,
	name TEXT NOT NULL UNIQUE,
	parent INTEGER NULL -- If the user has the parent permission, the user also has the child permission
);
CREATE VIEW permission_tree
AS
WITH RECURSIVE perm AS (
	SELECT id AS root, id AS child, name, parent
	FROM permission_hierarchy
	UNION
	SELECT perm.root, ph.id, ph.name, ph.id
	FROM permission_hierarchy ph, perm
	WHERE ph.parent = perm.child
)
SELECT root AS id, name AS name
FROM perm
/* permission_tree(id,name) */;
CREATE VIEW user_permissions_resolved
AS
SELECT
	u.id AS id, -- Dummy for LessQL
	u.id AS user_id,
	pt.name AS permission_name
FROM permission_tree pt, users u
WHERE pt.id IN (SELECT permission_id FROM user_permissions sub_up WHERE sub_up.user_id = u.id)
/* user_permissions_resolved(id,user_id,permission_name) */;
CREATE VIEW uihelper_user_permissions
AS
SELECT
	ph.id AS id,
	u.id AS user_id,
	ph.name AS permission_name,
	ph.id AS permission_id,
	(ph.name IN (
			SELECT pc.permission_name
			FROM user_permissions_resolved pc
			WHERE pc.user_id = u.id
		)
	) AS has_permission,
	ph.parent AS parent
FROM users u, permission_hierarchy ph
/* uihelper_user_permissions(id,user_id,permission_name,permission_id,has_permission,parent) */;
CREATE VIEW userfield_values_resolved
AS
SELECT
	u.id, -- Dummy, LessQL needs an id column
	u.entity,
	u.name,
	u.caption,
	u.type,
	u.show_as_column_in_tables,
	u.row_created_timestamp,
	u.config,
	uv.object_id,
	uv.value
FROM userfields u
JOIN userfield_values uv
	ON u.id = uv.field_id

UNION

-- Kind of a hack, include userentity userfields also for the table userobjects
SELECT
	u.id, -- Dummy, LessQL needs an id column,
	'userobjects',
	u.name,
	u.caption,
	u.type,
	u.show_as_column_in_tables,
	u.row_created_timestamp,
	u.config,
	uv.object_id,
	uv.value
FROM userfields u
JOIN userfield_values uv
	ON u.id = uv.field_id
WHERE u.entity like 'userentity-%'
/* userfield_values_resolved(id,entity,name,caption,type,show_as_column_in_tables,row_created_timestamp,config,object_id,value) */;
CREATE VIEW uihelper_stock_journal_summary
AS
SELECT
	user_id AS id, -- Dummy, LessQL needs an id column
	user_id, u.display_name AS user_display_name,
	p.name AS product_name,
	product_id,
	transaction_type,
	qu.name AS qu_name,
	qu.name_plural AS qu_name_plural,
	SUM(amount) AS amount
FROM stock_log sl
JOIN users_dto u
	on sl.user_id = u.id
JOIN products p
	ON sl.product_id = p.id
JOIN quantity_units qu
	ON p.qu_id_stock = qu.id
WHERE undone = 0
GROUP BY user_id, product_id, transaction_type
/* uihelper_stock_journal_summary(id,user_id,user_display_name,product_name,product_id,transaction_type,qu_name,qu_name_plural,amount) */;
CREATE TABLE tasks (
	id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT UNIQUE,
	name TEXT NOT NULL,
	description TEXT,
	due_date DATETIME,
	done TINYINT NOT NULL DEFAULT 0 CHECK(done IN (0, 1)),
	done_timestamp DATETIME,
	category_id INTEGER,
	assigned_to_user_id INTEGER,
	row_created_timestamp DATETIME DEFAULT (datetime('now', 'localtime'))
);
CREATE VIEW product_barcodes_comma_separated
AS
SELECT
	pb.id, -- Dummy, LessQL needs an id column
	pb.product_id,
	GROUP_CONCAT(pb.barcode) AS barcodes
FROM product_barcodes pb
JOIN products p
	ON pb.product_id = p.id
WHERE p.active = 1
GROUP BY pb.product_id
/* product_barcodes_comma_separated(id,product_id,barcodes) */;
CREATE VIEW chores_assigned_users_resolved
AS
SELECT
	c.id AS chore_id,
	u.id AS user_id
FROM chores c
JOIN users u
	ON ',' || c.assignment_config || ',' LIKE '%,' || CAST(u.id AS TEXT) || ',%'
WHERE c.active = 1
/* chores_assigned_users_resolved(chore_id,user_id) */;
CREATE INDEX ix_chores_performance1 ON chores (
	id,
	active
);
CREATE INDEX ix_batteries_performance1 ON batteries (
	id,
	active
);
CREATE VIEW users_dto
AS
SELECT
	id,
	username,
	first_name,
	last_name,
	row_created_timestamp,
	(CASE
		WHEN IFNULL(first_name, '') = '' AND IFNULL(last_name, '') != '' THEN last_name
		WHEN IFNULL(last_name, '') = '' AND IFNULL(first_name, '') != '' THEN first_name
		WHEN IFNULL(last_name, '') != '' AND IFNULL(first_name, '') != '' THEN first_name || ' ' || last_name
		ELSE username
	END
	) AS display_name,
	picture_file_name
FROM users
/* users_dto(id,username,first_name,last_name,row_created_timestamp,display_name,picture_file_name) */;
CREATE VIEW quantity_units_resolved
AS
-- This view builds the relationship between QUs based on their (default) conversions

SELECT
	-1 AS id, -- Dummy, LessQL needs an id column
	qu.id AS qu_id,
	quc.to_qu_id AS related_qu_id,
	quc.factor
FROM quantity_units qu
JOIN quantity_unit_conversions quc
	ON qu.id = quc.from_qu_id
	AND quc.product_id IS NULL
/* quantity_units_resolved(id,qu_id,related_qu_id,factor) */;
CREATE VIEW product_qu_relations
AS
-- This view builds which product is related to which QU, direct or indirect, based on QU conversions

-- The products stock QU
SELECT
	-1 AS id, -- Dummy, LessQL needs an id column
	p.id AS product_id,
	p.qu_id_stock AS qu_id
FROM products p

UNION

-- The products purchase QU
SELECT
	-1 AS id, -- Dummy, LessQL needs an id column
	p.id AS product_id,
	p.qu_id_purchase AS qu_id
FROM products p

UNION

-- All (direct) product conversions (product overrides)
SELECT
	-1 AS id, -- Dummy, LessQL needs an id column
	quc.product_id,
	quc.to_qu_id AS qu_id
FROM quantity_unit_conversions quc
WHERE quc.product_id IS NOT NULL

UNION

-- All (indirect) default QU conversions
SELECT
	-1 AS id, -- Dummy, LessQL needs an id column
	p.id AS product_id,
	qur2.qu_id
from products p
JOIN quantity_unit_conversions quc
	ON (p.qu_id_stock = quc.from_qu_id OR p.qu_id_purchase = quc.from_qu_id)
	AND p.id = quc.product_id
JOIN quantity_units_resolved qur1
	ON quc.to_qu_id = qur1.qu_id
JOIN quantity_units_resolved qur2
	ON qur1.related_qu_id = qur2.qu_id
/* product_qu_relations(id,product_id,qu_id) */;
CREATE UNIQUE INDEX ix_product_barcodes ON product_barcodes (
	barcode
);
CREATE TABLE battery_charge_cycles (
	id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT UNIQUE,
	battery_id INTEGER NOT NULL,
	tracked_time DATETIME,
	undone TINYINT NOT NULL DEFAULT 0 CHECK(undone IN (0, 1)),
	undone_timestamp DATETIME,
	row_created_timestamp DATETIME DEFAULT (datetime('now', 'localtime'))
);
CREATE TRIGGER create_internal_recipe AFTER INSERT ON meal_plan
BEGIN
	/* This contains practically the same logic as the trigger remove_internal_recipe */

	-- Create a recipe per day
	DELETE FROM recipes
	WHERE name = NEW.day
		AND type = 'mealplan-day';

	INSERT OR REPLACE INTO recipes
		(id, name, type)
	VALUES
		((SELECT MIN(id) - 1 FROM recipes), NEW.day, 'mealplan-day');

	-- Create a recipe per week
	DELETE FROM recipes
	WHERE name = LTRIM(STRFTIME('%Y-%W', NEW.day), '0')
		AND type = 'mealplan-week';

	INSERT INTO recipes
		(id, name, type)
	VALUES
		((SELECT MIN(id) - 1 FROM recipes), LTRIM(STRFTIME('%Y-%W', NEW.day), '0'), 'mealplan-week');

	-- Delete all current nestings entries for the day and week recipe
	DELETE FROM recipes_nestings
	WHERE recipe_id IN (SELECT id FROM recipes WHERE name = NEW.day AND type = 'mealplan-day')
		OR recipe_id IN (SELECT id FROM recipes WHERE name = LTRIM(STRFTIME('%Y-%W', NEW.day), '0') AND type = 'mealplan-week');

	-- Add all recipes for this day as included recipes in the day-recipe
	INSERT INTO recipes_nestings
		(recipe_id, includes_recipe_id, servings)
	SELECT (SELECT id FROM recipes WHERE name = NEW.day AND type = 'mealplan-day'), recipe_id, SUM(recipe_servings)
	FROM meal_plan
	WHERE day = NEW.day
		AND type = 'recipe'
		AND recipe_id IS NOT NULL
	GROUP BY recipe_id;

	-- Add all recipes for this week as included recipes in the week-recipe
	INSERT INTO recipes_nestings
		(recipe_id, includes_recipe_id, servings)
	SELECT (SELECT id FROM recipes WHERE name = LTRIM(STRFTIME('%Y-%W', NEW.day), '0') AND type = 'mealplan-week'), recipe_id, SUM(recipe_servings)
	FROM meal_plan
	WHERE STRFTIME('%Y-%W', day) = STRFTIME('%Y-%W', NEW.day)
		AND type = 'recipe'
		AND recipe_id IS NOT NULL
	GROUP BY recipe_id;

	-- Add all products for this day as ingredients in the day-recipe
	INSERT INTO recipes_pos
		(recipe_id, product_id, amount, qu_id)
	SELECT (SELECT id FROM recipes WHERE name = NEW.day AND type = 'mealplan-day'), product_id, SUM(product_amount), product_qu_id
	FROM meal_plan
	WHERE day = NEW.day
		AND type = 'product'
		AND product_id IS NOT NULL
	GROUP BY product_id, product_qu_id;

	-- Add all products for this week as ingredients in the week-recipe
	INSERT INTO recipes_pos
		(recipe_id, product_id, amount, qu_id)
	SELECT (SELECT id FROM recipes WHERE name = LTRIM(STRFTIME('%Y-%W', NEW.day), '0') AND type = 'mealplan-week'), product_id, SUM(product_amount), product_qu_id
	FROM meal_plan
	WHERE STRFTIME('%Y-%W', day) = STRFTIME('%Y-%W', NEW.day)
		AND type = 'product'
		AND product_id IS NOT NULL
	GROUP BY product_id, product_qu_id;

	-- Create a shadow recipe per meal plan recipe
	INSERT INTO recipes
		(id, name, type)
	SELECT (SELECT MIN(id) - 1 FROM recipes), CAST(NEW.day AS TEXT) || '#' || CAST(id AS TEXT), 'mealplan-shadow'
	FROM meal_plan
	WHERE id = NEW.id
		AND type = 'recipe'
		AND recipe_id IS NOT NULL;

	INSERT INTO recipes_nestings
		(recipe_id, includes_recipe_id, servings)
	SELECT (SELECT id FROM recipes WHERE name = CAST(NEW.day AS TEXT) || '#' || CAST(meal_plan.id AS TEXT) AND type = 'mealplan-shadow'), recipe_id, recipe_servings
	FROM meal_plan
	WHERE id = NEW.id
		AND type = 'recipe'
		AND recipe_id IS NOT NULL;

	-- Enforce "when empty then null" for certain columns
	UPDATE meal_plan
	SET recipe_id = NULL
	WHERE id = NEW.id
		AND IFNULL(recipe_id, '') = '';

	UPDATE meal_plan
	SET product_id = NULL
	WHERE id = NEW.id
		AND IFNULL(product_id, '') = '';

	UPDATE meal_plan
	SET product_qu_id = NULL
	WHERE id = NEW.id
		AND IFNULL(product_qu_id, '') = '';
END;
CREATE TRIGGER remove_internal_recipe AFTER DELETE ON meal_plan
BEGIN
	/* This contains practically the same logic as the trigger create_internal_recipe */

	-- Create a recipe per day
	DELETE FROM recipes
	WHERE name = OLD.day
		AND type = 'mealplan-day';

	INSERT OR REPLACE INTO recipes
		(id, name, type)
	VALUES
		((SELECT MIN(id) - 1 FROM recipes), OLD.day, 'mealplan-day');

	-- Create a recipe per week
	DELETE FROM recipes
	WHERE name = LTRIM(STRFTIME('%Y-%W', OLD.day), '0')
		AND type = 'mealplan-week';

	INSERT INTO recipes
		(id, name, type)
	VALUES
		((SELECT MIN(id) - 1 FROM recipes), LTRIM(STRFTIME('%Y-%W', OLD.day), '0'), 'mealplan-week');

	-- Delete all current nestings entries for the day and week recipe
	DELETE FROM recipes_nestings
	WHERE recipe_id IN (SELECT id FROM recipes WHERE name = OLD.day AND type = 'mealplan-day')
		OR recipe_id IN (SELECT id FROM recipes WHERE name = LTRIM(STRFTIME('%Y-%W', OLD.day), '0') AND type = 'mealplan-week');

	-- Add all recipes for this day as included recipes in the day-recipe
	INSERT INTO recipes_nestings
		(recipe_id, includes_recipe_id, servings)
	SELECT (SELECT id FROM recipes WHERE name = OLD.day AND type = 'mealplan-day'), recipe_id, SUM(recipe_servings)
	FROM meal_plan
	WHERE day = OLD.day
		AND type = 'recipe'
		AND recipe_id IS NOT NULL
	GROUP BY recipe_id;

	-- Add all recipes for this week as included recipes in the week-recipe
	INSERT INTO recipes_nestings
		(recipe_id, includes_recipe_id, servings)
	SELECT (SELECT id FROM recipes WHERE name = LTRIM(STRFTIME('%Y-%W', OLD.day), '0') AND type = 'mealplan-week'), recipe_id, SUM(recipe_servings)
	FROM meal_plan
	WHERE STRFTIME('%Y-%W', day) = STRFTIME('%Y-%W', OLD.day)
		AND type = 'recipe'
		AND recipe_id IS NOT NULL
	GROUP BY recipe_id;

	-- Add all products for this day as ingredients in the day-recipe
	INSERT INTO recipes_pos
		(recipe_id, product_id, amount, qu_id)
	SELECT (SELECT id FROM recipes WHERE name = OLD.day AND type = 'mealplan-day'), product_id, SUM(product_amount), product_qu_id
	FROM meal_plan
	WHERE day = OLD.day
		AND type = 'product'
		AND product_id IS NOT NULL
	GROUP BY product_id, product_qu_id;

	-- Add all products for this week as ingredients in the week-recipe
	INSERT INTO recipes_pos
		(recipe_id, product_id, amount, qu_id)
	SELECT (SELECT id FROM recipes WHERE name = LTRIM(STRFTIME('%Y-%W', OLD.day), '0') AND type = 'mealplan-week'), product_id, SUM(product_amount), product_qu_id
	FROM meal_plan
	WHERE STRFTIME('%Y-%W', day) = STRFTIME('%Y-%W', OLD.day)
		AND type = 'product'
		AND product_id IS NOT NULL
	GROUP BY product_id, product_qu_id;

	-- Remove shadow recipes per meal plan recipe
	DELETE FROM recipes
	WHERE type = 'mealplan-shadow'
		AND name NOT IN (SELECT CAST(day AS TEXT) || '#' || CAST(id AS TEXT) FROM meal_plan WHERE type = 'recipe');
END;
CREATE TRIGGER update_internal_recipe AFTER UPDATE ON meal_plan
BEGIN
	/* This contains practically the same logic as the trigger create_internal_recipe */

	-- Create a recipe per day
	DELETE FROM recipes
	WHERE name = NEW.day
		AND type = 'mealplan-day';

	INSERT OR REPLACE INTO recipes
		(id, name, type)
	VALUES
		((SELECT MIN(id) - 1 FROM recipes), NEW.day, 'mealplan-day');

	-- Create a recipe per week
	DELETE FROM recipes
	WHERE name = LTRIM(STRFTIME('%Y-%W', NEW.day), '0')
		AND type = 'mealplan-week';

	INSERT INTO recipes
		(id, name, type)
	VALUES
		((SELECT MIN(id) - 1 FROM recipes), LTRIM(STRFTIME('%Y-%W', NEW.day), '0'), 'mealplan-week');

	-- Delete all current nestings entries for the day and week recipe
	DELETE FROM recipes_nestings
	WHERE recipe_id IN (SELECT id FROM recipes WHERE name = NEW.day AND type = 'mealplan-day')
		OR recipe_id IN (SELECT id FROM recipes WHERE name = LTRIM(STRFTIME('%Y-%W', NEW.day), '0') AND type = 'mealplan-week');

	-- Add all recipes for this day as included recipes in the day-recipe
	INSERT INTO recipes_nestings
		(recipe_id, includes_recipe_id, servings)
	SELECT (SELECT id FROM recipes WHERE name = NEW.day AND type = 'mealplan-day'), recipe_id, SUM(recipe_servings)
	FROM meal_plan
	WHERE day = NEW.day
		AND type = 'recipe'
		AND recipe_id IS NOT NULL
	GROUP BY recipe_id;

	-- Add all recipes for this week as included recipes in the week-recipe
	INSERT INTO recipes_nestings
		(recipe_id, includes_recipe_id, servings)
	SELECT (SELECT id FROM recipes WHERE name = LTRIM(STRFTIME('%Y-%W', NEW.day), '0') AND type = 'mealplan-week'), recipe_id, SUM(recipe_servings)
	FROM meal_plan
	WHERE STRFTIME('%Y-%W', day) = STRFTIME('%Y-%W', NEW.day)
		AND type = 'recipe'
		AND recipe_id IS NOT NULL
	GROUP BY recipe_id;

	-- Add all products for this day as ingredients in the day-recipe
	INSERT INTO recipes_pos
		(recipe_id, product_id, amount, qu_id)
	SELECT (SELECT id FROM recipes WHERE name = NEW.day AND type = 'mealplan-day'), product_id, SUM(product_amount), product_qu_id
	FROM meal_plan
	WHERE day = NEW.day
		AND type = 'product'
		AND product_id IS NOT NULL
	GROUP BY product_id, product_qu_id;

	-- Add all products for this week as ingredients in the week-recipe
	INSERT INTO recipes_pos
		(recipe_id, product_id, amount, qu_id)
	SELECT (SELECT id FROM recipes WHERE name = LTRIM(STRFTIME('%Y-%W', NEW.day), '0') AND type = 'mealplan-week'), product_id, SUM(product_amount), product_qu_id
	FROM meal_plan
	WHERE STRFTIME('%Y-%W', day) = STRFTIME('%Y-%W', NEW.day)
		AND type = 'product'
		AND product_id IS NOT NULL
	GROUP BY product_id, product_qu_id;

	-- Create a shadow recipe per meal plan recipe
	DELETE FROM recipes_nestings
	WHERE recipe_id IN (SELECT id FROM recipes WHERE name IN (SELECT CAST(NEW.day AS TEXT) || '#' || CAST(NEW.id AS TEXT) FROM meal_plan WHERE day = NEW.day) AND type = 'mealplan-shadow');

	DELETE FROM recipes
	WHERE type = 'mealplan-shadow'
		AND name = CAST(NEW.day AS TEXT) || '#' || CAST(NEW.id AS TEXT);

	INSERT INTO recipes
		(id, name, type)
	SELECT (SELECT MIN(id) - 1 FROM recipes), CAST(NEW.day AS TEXT) || '#' || CAST(id AS TEXT), 'mealplan-shadow'
	FROM meal_plan
	WHERE id = NEW.id
		AND type = 'recipe'
		AND recipe_id IS NOT NULL;

	INSERT INTO recipes_nestings
		(recipe_id, includes_recipe_id, servings)
	SELECT (SELECT id FROM recipes WHERE name = CAST(NEW.day AS TEXT) || '#' || CAST(meal_plan.id AS TEXT) AND type = 'mealplan-shadow'), recipe_id, recipe_servings
	FROM meal_plan
	WHERE id = NEW.id
		AND type = 'recipe'
		AND recipe_id IS NOT NULL;

	-- Enforce "when empty then null" for certain columns
	UPDATE meal_plan
	SET recipe_id = NULL
	WHERE id = NEW.id
		AND IFNULL(recipe_id, '') = '';

	UPDATE meal_plan
	SET product_id = NULL
	WHERE id = NEW.id
		AND IFNULL(product_id, '') = '';

	UPDATE meal_plan
	SET product_qu_id = NULL
	WHERE id = NEW.id
		AND IFNULL(product_qu_id, '') = '';
END;
CREATE TABLE meal_plan_sections (
	id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT UNIQUE,
	name TEXT NOT NULL UNIQUE,
	sort_number INTEGER,
	row_created_timestamp DATETIME DEFAULT (datetime('now', 'localtime'))
, time_info TEXT);
CREATE TABLE stock_log (
	id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT UNIQUE,
	product_id INTEGER NOT NULL,
	amount DECIMAL(15, 2) NOT NULL,
	best_before_date DATE,
	purchased_date DATE,
	used_date DATE,
	spoiled INTEGER NOT NULL DEFAULT 0,
	stock_id TEXT NOT NULL,
	transaction_type TEXT NOT NULL,
	price DECIMAL(15, 2),
	undone TINYINT NOT NULL DEFAULT 0 CHECK(undone IN (0, 1)),
	undone_timestamp DATETIME,
	opened_date DATETIME,
	location_id INTEGER,
	recipe_id INTEGER,
	correlation_id TEXT,
	transaction_id TEXT,
	stock_row_id INTEGER,
	shopping_location_id INTEGER,
	user_id INTEGER NOT NULL,
	row_created_timestamp DATETIME DEFAULT (datetime('now', 'localtime'))
, note TEXT);
CREATE TRIGGER set_products_default_location_if_empty_stock_log AFTER INSERT ON stock_log
BEGIN
	UPDATE stock_log
	SET location_id = (SELECT location_id FROM products where id = product_id)
	WHERE id = NEW.id
		AND location_id IS NULL;
END;
CREATE VIEW recipes_missing_product_counts
AS
SELECT
	recipe_id,
	COUNT(*) AS missing_products_count
FROM recipes_pos_resolved
WHERE need_fulfilled = 0
GROUP BY recipe_id;
CREATE TRIGGER default_start_date_when_empty_INS AFTER INSERT ON chores
BEGIN
	UPDATE chores
	SET start_date =  DATETIME('now', 'localtime')
	WHERE id = NEW.id
		AND IFNULL(start_date, '') = '';
END;
CREATE TRIGGER default_start_date_when_empty_UPD AFTER UPDATE ON chores
BEGIN
	UPDATE chores
	SET start_date =  DATETIME('now', 'localtime')
	WHERE id = NEW.id
		AND IFNULL(start_date, '') = '';
END;
CREATE INDEX ix_chores_log_performance1 ON chores_log (
	chore_id,
	undone,
	tracked_time
);
CREATE VIEW chores_execution_timeline
AS

SELECT
	cl.chore_id,
	cl.tracked_time,
	(SELECT tracked_time FROM chores_log WHERE chore_id = cl.chore_id AND undone = 0 AND tracked_time < cl.tracked_time ORDER BY tracked_time DESC LIMIT 1) AS tracked_time_before,
	CAST((JULIANDAY(cl.tracked_time) - JULIANDAY((SELECT tracked_time FROM chores_log WHERE chore_id = cl.chore_id AND undone = 0 AND tracked_time < cl.tracked_time ORDER BY tracked_time DESC LIMIT 1))) * 24 AS INT) AS frequency_hours
FROM chores_log cl
WHERE cl.undone = 0
/* chores_execution_timeline(chore_id,tracked_time,tracked_time_before,frequency_hours) */;
CREATE VIEW chores_execution_average_frequency
AS

SELECT
	cet.chore_id,
	AVG(cet.frequency_hours) AS average_frequency_hours
FROM chores_execution_timeline cet
GROUP BY cet.chore_id
/* chores_execution_average_frequency(chore_id,average_frequency_hours) */;
CREATE TRIGGER default_qu_INS AFTER INSERT ON product_barcodes
BEGIN
	UPDATE product_barcodes
	SET qu_id = (SELECT qu_id_stock FROM products WHERE id = product_barcodes.product_id)
	WHERE id = NEW.id
		AND IFNULL(qu_id, 0) = 0;
END;
CREATE TRIGGER default_qu_UPD AFTER UPDATE ON product_barcodes
BEGIN
	UPDATE product_barcodes
	SET qu_id = (SELECT qu_id_stock FROM products WHERE id = product_barcodes.product_id)
	WHERE id = NEW.id
		AND IFNULL(qu_id, 0) = 0;
END;
CREATE TRIGGER remove_conversions AFTER DELETE ON quantity_units
BEGIN
	DELETE FROM quantity_unit_conversions
	WHERE from_qu_id = OLD.id
		OR to_qu_id = OLD.id;
END;
CREATE VIEW batteries_current
AS
SELECT
	b.id, -- Dummy, LessQL needs an id column
	b.id AS battery_id,
	MAX(l.tracked_time) AS last_tracked_time,
	CASE WHEN b.charge_interval_days = 0
		THEN '2999-12-31 23:59:59'
		ELSE datetime(MAX(l.tracked_time), '+' || CAST(b.charge_interval_days AS TEXT) || ' day')
	END AS next_estimated_charge_time
FROM batteries b
LEFT JOIN battery_charge_cycles l
	ON b.id = l.battery_id
	AND l.undone = 0
WHERE b.active = 1
GROUP BY b.id, b.charge_interval_days
/* batteries_current(id,battery_id,last_tracked_time,next_estimated_charge_time) */;
CREATE VIEW products_volatile_status
AS
SELECT
	-1 AS id, -- Dummy
	p.id AS product_id,
	p.name AS product_name,
	CASE WHEN JULIANDAY(sc.best_before_date) - JULIANDAY('now', 'localtime') < 0 THEN
		CASE WHEN p.due_type = 1 THEN 'overdue' ELSE 'expired' END
	ELSE
		CASE WHEN JULIANDAY(sc.best_before_date) - JULIANDAY('now', 'localtime') < CAST(5 AS INT) THEN
			'due_soon'
		ELSE
			'ok'
		END
	END AS current_due_status,
	CASE WHEN smp.id IS NOT NULL THEN 1 ELSE 0 END AS is_currently_below_min_stock_amount
FROM products p
LEFT JOIN stock_current sc
	ON p.id = sc.product_id
LEFT JOIN stock_missing_products smp
	ON p.id = smp.id;
CREATE TABLE userfield_values (
	id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT UNIQUE,
	field_id INTEGER NOT NULL,
	object_id TEXT NOT NULL,
	value TEXT NOT NULL,
	row_created_timestamp DATETIME DEFAULT (datetime('now', 'localtime')),

	UNIQUE(field_id, object_id)
);
CREATE TRIGGER prevent_empty_userfields_INS AFTER INSERT ON userfield_values
BEGIN
	DELETE FROM userfield_values
	WHERE id = NEW.id
		AND IFNULL(value, '') = '';
END;
CREATE TRIGGER prevent_empty_userfields_UPD AFTER UPDATE ON userfield_values
BEGIN
	DELETE FROM userfield_values
	WHERE id = NEW.id
		AND IFNULL(value, '') = '';
END;
CREATE VIEW stock_splits
AS

/*
	Helper view which shows splitted stock rows which could be compacted

	Stock entries with a stock_id starting with "x"
	and those with userfields shouldn't be compacted
*/

SELECT
	s.product_id,
	SUM(s.amount) AS total_amount,
	MIN(s.stock_id) AS stock_id_to_keep,
	MAX(s.id) AS id_to_keep,
	GROUP_CONCAT(s.id) AS id_group,
	GROUP_CONCAT(s.stock_id) AS stock_id_group,
	s.id -- Dummy
FROM stock s
WHERE s.stock_id NOT LIKE 'x%'
	AND NOT EXISTS(
		SELECT 1 FROM userfield_values
		WHERE object_id = s.stock_id
			AND field_id IN (SELECT id FROM userfields WHERE entity = 'stock')
			AND IFNULL(value, '') != ''
		)
GROUP BY s.product_id, s.best_before_date, s.purchased_date, s.price, s.open, s.opened_date, s.location_id, s.shopping_location_id, IFNULL(s.note, '')
HAVING COUNT(*) > 1
/* stock_splits(product_id,total_amount,stock_id_to_keep,id_to_keep,id_group,stock_id_group,id) */;
CREATE VIEW uihelper_stock_journal
AS
SELECT
	sl.id,
	sl.row_created_timestamp,
	sl.correlation_id,
	sl.undone,
	sl.undone_timestamp,
	sl.transaction_type,
	sl.spoiled,
	sl.amount,
	sl.location_id,
	l.name AS location_name,
	p.name AS product_name,
	qu.name AS qu_name,
	qu.name_plural AS qu_name_plural,
	u.display_name AS user_display_name,
	p.id AS product_id,
	sl.note,
	sl.stock_id
FROM stock_log sl
LEFT JOIN users_dto u
	ON sl.user_id = u.id
JOIN products p
	ON sl.product_id = p.id
JOIN locations l
	ON sl.location_id = l.id
JOIN quantity_units qu
	ON p.qu_id_stock = qu.id
/* uihelper_stock_journal(id,row_created_timestamp,correlation_id,undone,undone_timestamp,transaction_type,spoiled,amount,location_id,location_name,product_name,qu_name,qu_name_plural,user_display_name,product_id,note,stock_id) */;
CREATE TRIGGER cascade_chore_removal AFTER DELETE ON chores
BEGIN
	DELETE FROM chores_log
	WHERE chore_id = OLD.id;

	DELETE FROM userfield_values
	WHERE object_id = OLD.id
		AND field_id IN (SELECT id FROM userfields WHERE entity = 'chores');
END;
CREATE TRIGGER cascade_battery_removal AFTER DELETE ON batteries
BEGIN
	DELETE FROM battery_charge_cycles
	WHERE battery_id = OLD.id;

	DELETE FROM userfield_values
	WHERE object_id = OLD.id
		AND field_id IN (SELECT id FROM userfields WHERE entity = 'batteries');
END;
CREATE TRIGGER cascade_userfield_removal AFTER DELETE ON userfields
BEGIN
	DELETE FROM userfield_values
	WHERE object_id = OLD.id
		AND field_id = OLD.id;
END;
CREATE VIEW chores_current
AS
SELECT
	x.chore_id AS id, -- Dummy, LessQL needs an id column
	x.chore_id,
	x.chore_name,
	x.last_tracked_time,
	CASE WHEN x.rollover = 1 AND DATETIME('now', 'localtime') > x.next_estimated_execution_time THEN
		CASE WHEN IFNULL(x.track_date_only, 0) = 1 THEN
			DATETIME(STRFTIME('%Y-%m-%d', DATETIME('now', 'localtime')) || ' 23:59:59')
		ELSE
			DATETIME(STRFTIME('%Y-%m-%d', DATETIME('now', 'localtime')) || ' ' || STRFTIME('%H:%M:%S', x.next_estimated_execution_time))
		END
	ELSE
		CASE WHEN IFNULL(x.track_date_only, 0) = 1 THEN
			DATETIME(STRFTIME('%Y-%m-%d', x.next_estimated_execution_time) || ' 23:59:59')
		ELSE
			x.next_estimated_execution_time
		END
	END AS next_estimated_execution_time,
	x.track_date_only,
	x.next_execution_assigned_to_user_id,
	CASE WHEN IFNULL(x.rescheduled_date, '') != '' THEN 1 ELSE 0 END AS is_rescheduled,
	CASE WHEN IFNULL(x.rescheduled_next_execution_assigned_to_user_id, '') != '' THEN 1 ELSE 0 END AS is_reassigned
FROM (

SELECT
	h.id AS chore_id,
	h.name AS chore_name,
	MAX(l.tracked_time) AS last_tracked_time,
	CASE WHEN IFNULL(h.rescheduled_date, '') != '' THEN
		h.rescheduled_date
	ELSE
		CASE WHEN MAX(l.tracked_time) IS NULL AND h.period_type != 'manually' THEN
			h.start_date
		ELSE
			CASE h.period_type
				WHEN 'manually' THEN NULL
				WHEN 'hourly' THEN DATETIME(MAX(l.tracked_time), '+' || CAST(h.period_interval AS TEXT) || ' hour')
				WHEN 'daily' THEN DATETIME(SUBSTR(CAST(DATETIME(MAX(l.tracked_time), '+' || CAST(h.period_interval AS TEXT) || ' days') AS TEXT), 1, 11) || SUBSTR(CAST(h.start_date AS TEXT), -8))
				WHEN 'weekly' THEN (
					SELECT next
						FROM (
						SELECT 'sunday' AS day, DATETIME((SELECT tracked_time FROM chores_log WHERE chore_id = h.id ORDER BY tracked_time DESC LIMIT 1), '1 days', '+' || CAST((h.period_interval - 1) * 7 AS TEXT) || ' days', 'weekday 0') AS next
						UNION
						SELECT 'monday' AS day, DATETIME((SELECT tracked_time FROM chores_log WHERE chore_id = h.id ORDER BY tracked_time DESC LIMIT 1), '1 days', '+' || CAST((h.period_interval - 1) * 7 AS TEXT) || ' days', 'weekday 1') AS next
						UNION
						SELECT 'tuesday' AS day, DATETIME((SELECT tracked_time FROM chores_log WHERE chore_id = h.id ORDER BY tracked_time DESC LIMIT 1), '1 days', '+' || CAST((h.period_interval - 1) * 7 AS TEXT) || ' days', 'weekday 2') AS next
						UNION
						SELECT 'wednesday' AS day, DATETIME((SELECT tracked_time FROM chores_log WHERE chore_id = h.id ORDER BY tracked_time DESC LIMIT 1), '1 days', '+' || CAST((h.period_interval - 1) * 7 AS TEXT) || ' days', 'weekday 3') AS next
						UNION
						SELECT 'thursday' AS day, DATETIME((SELECT tracked_time FROM chores_log WHERE chore_id = h.id ORDER BY tracked_time DESC LIMIT 1), '1 days', '+' || CAST((h.period_interval - 1) * 7 AS TEXT) || ' days', 'weekday 4') AS next
						UNION
						SELECT 'friday' AS day, DATETIME((SELECT tracked_time FROM chores_log WHERE chore_id = h.id ORDER BY tracked_time DESC LIMIT 1), '1 days', '+' || CAST((h.period_interval - 1) * 7 AS TEXT) || ' days', 'weekday 5') AS next
						UNION
						SELECT 'saturday' AS day, DATETIME((SELECT tracked_time FROM chores_log WHERE chore_id = h.id ORDER BY tracked_time DESC LIMIT 1), '1 days', '+' || CAST((h.period_interval - 1) * 7 AS TEXT) || ' days', 'weekday 6') AS next
					)
					WHERE INSTR(period_config, day) > 0
					ORDER BY next
					LIMIT 1
				)
				WHEN 'monthly' THEN DATETIME(MAX(l.tracked_time), 'start of month', '+' || CAST(h.period_interval AS TEXT) || ' month', '+' || CAST(h.period_days - 1 AS TEXT) || ' day')
				WHEN 'yearly' THEN DATETIME(SUBSTR(CAST(DATETIME(MAX(l.tracked_time), '+' || CAST(h.period_interval AS TEXT) || ' years') AS TEXT), 1, 4) || SUBSTR(CAST(h.start_date AS TEXT), 5, 6) || SUBSTR(CAST(DATETIME(MAX(l.tracked_time), '+' || CAST(h.period_interval AS TEXT) || ' years') AS TEXT), -9))
				WHEN 'adaptive' THEN DATETIME(MAX(l.tracked_time), '+' || CAST(IFNULL((SELECT average_frequency_hours FROM chores_execution_average_frequency WHERE chore_id = h.id), 0) AS TEXT) || ' hour')
			END
		END
	END AS next_estimated_execution_time,
	h.track_date_only,
	h.rollover,
	h.next_execution_assigned_to_user_id,
	h.rescheduled_date,
	h.rescheduled_next_execution_assigned_to_user_id
FROM chores h
LEFT JOIN chores_log l
	ON h.id = l.chore_id
	AND l.undone = 0
WHERE h.active = 1
GROUP BY h.id, h.name, h.period_days
) x
/* chores_current(id,chore_id,chore_name,last_tracked_time,next_estimated_execution_time,track_date_only,next_execution_assigned_to_user_id,is_rescheduled,is_reassigned) */;
CREATE VIEW stock_average_product_shelf_life
AS
SELECT
	p.id,
	CASE WHEN x.product_id IS NULL THEN -1 ELSE AVG(x.shelf_life_days) END AS average_shelf_life_days
FROM products p
LEFT JOIN (
		SELECT
			sl_p.product_id,
			JULIANDAY(sl_p.best_before_date) - JULIANDAY(sl_p.purchased_date) AS shelf_life_days
		FROM stock_log sl_p
		WHERE sl_p.undone = 0
			AND (
				(sl_p.transaction_type IN ('purchase', 'inventory-correction', 'self-production') AND sl_p.stock_id NOT IN (SELECT stock_id FROM stock_edited_entries))
				OR (sl_p.transaction_type = 'stock-edit-new' AND sl_p.stock_id IN (SELECT stock_id FROM stock_edited_entries))
			)
	) x
	ON p.id = x.product_id
GROUP BY p.id
/* stock_average_product_shelf_life(id,average_shelf_life_days) */;
CREATE TRIGGER userfield_values_special_handling_INS AFTER INSERT ON userfield_values
BEGIN
	-- Entity stock:
	-- object_id is the transaction_id on insert -> replace it by the corresponding stock_id
	INSERT OR REPLACE INTO userfield_values
		(field_id, object_id, value)
	SELECT uv.field_id, sl.stock_id, uv.value
	FROM userfield_values uv
	JOIN stock_log sl
		ON uv.object_id = sl.transaction_id
		AND sl.transaction_type IN ('purchase', 'inventory-correction', 'stock-edit-new')
	WHERE uv.field_id IN (SELECT id FROM userfields WHERE entity = 'stock')
		AND uv.field_id = NEW.field_id
		AND uv.object_id = NEW.object_id;

	DELETE FROM userfield_values
	WHERE field_id IN (SELECT id FROM userfields WHERE entity = 'stock')
		AND field_id = NEW.field_id
		AND object_id = NEW.object_id;
END;
CREATE VIEW stock_next_use
AS

/*
	The default consume rule is:
	Opened first, then first due first, then first in first out
	Apart from that products at their default consume location should be consumed first

	This orders the stock entries by that
	=> Highest "priority" per product = the stock entry to use next
	=> ORDER BY clause = ORDER BY priority DESC, open DESC, best_before_date ASC, purchased_date ASC
*/

SELECT
	(ROW_NUMBER() OVER(PARTITION BY s.product_id ORDER BY CASE WHEN IFNULL(p.default_consume_location_id, -1) = s.location_id THEN 0 ELSE 1 END ASC, s.open DESC, s.best_before_date ASC, s.purchased_date ASC)) * -1 AS priority,
	s.*
FROM stock s
JOIN products p
	ON p.id = s.product_id
ORDER BY CASE WHEN IFNULL(p.default_consume_location_id, -1) = s.location_id THEN 0 ELSE 1 END ASC, s.open DESC, s.best_before_date ASC, s.purchased_date ASC
/* stock_next_use(priority,id,product_id,amount,best_before_date,purchased_date,stock_id,price,open,opened_date,row_created_timestamp,location_id,shopping_location_id,note) */;
CREATE TRIGGER stock_next_use_INS INSTEAD OF INSERT ON stock_next_use
BEGIN
	INSERT INTO stock
		(product_id, amount, best_before_date, purchased_date, stock_id,
		price, open, opened_date, location_id, shopping_location_id, note)
	VALUES
		(NEW.product_id, NEW.amount, NEW.best_before_date, NEW.purchased_date, NEW.stock_id,
		NEW.price, NEW.open, NEW.opened_date, NEW.location_id, NEW.shopping_location_id, NEW.note);
END;
CREATE TRIGGER stock_next_use_UPD INSTEAD OF UPDATE ON stock_next_use
BEGIN
	UPDATE stock
	SET product_id = NEW.product_id,
	amount = NEW.amount,
	best_before_date = NEW.best_before_date,
	purchased_date = NEW.purchased_date,
	stock_id = NEW.stock_id,
	price = NEW.price,
	open = NEW.open,
	opened_date = NEW.opened_date,
	location_id = NEW.location_id,
	shopping_location_id = NEW.shopping_location_id,
	note = NEW.note
	WHERE id = NEW.id;
END;
CREATE TRIGGER stock_next_use_DEL INSTEAD OF DELETE ON stock_next_use
BEGIN
	DELETE FROM stock
	WHERE id = OLD.id;
END;
CREATE VIEW products_current_substitutions
AS

/*
	When a parent product is not in stock itself,
	any sub product (the next based on the default consume rule) should be used

	This view lists all parent products and in the column "product_id_effective" either itself,
	when the corresponding parent product is currently in stock itself, or otherwise the next sub product to use
*/

SELECT
	-1, -- Dummy
	p_sub.id AS parent_product_id,
	CASE WHEN p_sub.has_sub_products = 1 THEN
		CASE WHEN IFNULL(sc.amount, 0) = 0 THEN -- Parent product itself is currently not in stock => use the next sub product
			(
			SELECT x_snu.product_id
			FROM products_resolved x_pr
			JOIN stock_next_use x_snu
				ON x_pr.sub_product_id = x_snu.product_id
			WHERE x_pr.parent_product_id = p_sub.id
				AND x_pr.parent_product_id != x_pr.sub_product_id
			ORDER BY x_snu.priority DESC, x_snu.open DESC, x_snu.best_before_date ASC, x_snu.purchased_date ASC
			LIMIT 1
			)
		ELSE -- Parent product itself is currently in stock => use it
			p_sub.id
		END
	END AS product_id_effective
FROM products_view p
JOIN products_resolved pr
	ON p.id = pr.parent_product_id
JOIN products_view p_sub
	ON pr.sub_product_id = p_sub.id
JOIN stock_current sc
	ON p_sub.id = sc.product_id
WHERE p_sub.has_sub_products = 1
/* products_current_substitutions("-1",parent_product_id,product_id_effective) */;
CREATE TABLE products (
	id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT UNIQUE,
	name TEXT NOT NULL UNIQUE,
	description TEXT,
	product_group_id INTEGER,
	active TINYINT NOT NULL DEFAULT 1 CHECK(active IN (0, 1)),
	location_id INTEGER NOT NULL,
	shopping_location_id INTEGER,
	qu_id_purchase INTEGER NOT NULL,
	qu_id_stock INTEGER NOT NULL,
	min_stock_amount INTEGER NOT NULL DEFAULT 0,
	default_best_before_days INTEGER NOT NULL DEFAULT 0,
	default_best_before_days_after_open INTEGER NOT NULL DEFAULT 0,
	default_best_before_days_after_freezing INTEGER NOT NULL DEFAULT 0,
	default_best_before_days_after_thawing INTEGER NOT NULL DEFAULT 0,
	picture_file_name TEXT,
	enable_tare_weight_handling TINYINT NOT NULL DEFAULT 0,
	tare_weight REAL NOT NULL DEFAULT 0,
	not_check_stock_fulfillment_for_recipes TINYINT DEFAULT 0,
	parent_product_id INT,
	calories INTEGER,
	cumulate_min_stock_amount_of_sub_products TINYINT DEFAULT 0,
	due_type TINYINT NOT NULL DEFAULT 1 CHECK(due_type IN (1, 2)),
	quick_consume_amount REAL NOT NULL DEFAULT 1,
	hide_on_stock_overview TINYINT NOT NULL DEFAULT 0 CHECK(hide_on_stock_overview IN (0, 1)),
	default_stock_label_type INTEGER NOT NULL DEFAULT 0,
	should_not_be_frozen TINYINT NOT NULL DEFAULT 0 CHECK(should_not_be_frozen IN (0, 1)),
	treat_opened_as_out_of_stock TINYINT NOT NULL DEFAULT 1 CHECK(treat_opened_as_out_of_stock IN (0, 1)),
	no_own_stock TINYINT NOT NULL DEFAULT 0 CHECK(no_own_stock IN (0, 1)),
	default_consume_location_id INTEGER,
	move_on_open TINYINT NOT NULL DEFAULT 0 CHECK(move_on_open IN (0, 1)),
	row_created_timestamp DATETIME DEFAULT (datetime('now', 'localtime'))
, qu_id_consume INTEGER, auto_reprint_stock_label TINYINT NOT NULL DEFAULT 0 CHECK(auto_reprint_stock_label IN (0, 1)), quick_open_amount REAL NOT NULL DEFAULT 1, qu_id_price INTEGER, disable_open TINYINT NOT NULL DEFAULT 0 CHECK(disable_open IN (0, 1)), default_purchase_price_type TINYINT NOT NULL DEFAULT 1 CHECK(default_purchase_price_type IN (1, 2, 3)));
CREATE TRIGGER enforce_parent_product_id_null_when_empty_INS AFTER INSERT ON products
BEGIN
	UPDATE products
	SET parent_product_id = NULL
	WHERE id = NEW.id
		AND IFNULL(parent_product_id, '') = '';
END;
CREATE TRIGGER enforce_parent_product_id_null_when_empty_UPD AFTER UPDATE ON products
BEGIN
	UPDATE products
	SET parent_product_id = NULL
	WHERE id = NEW.id
		AND IFNULL(parent_product_id, '') = '';
END;
CREATE TRIGGER cascade_product_removal AFTER DELETE ON products
BEGIN
	DELETE FROM stock
	WHERE product_id = OLD.id;

	DELETE FROM stock_log
	WHERE product_id = OLD.id;

	DELETE FROM product_barcodes
	WHERE product_id = OLD.id;

	DELETE FROM quantity_unit_conversions
	WHERE product_id = OLD.id;

	DELETE FROM recipes_pos
	WHERE product_id = OLD.id;

	UPDATE recipes
	SET product_id = NULL
	WHERE product_id = OLD.id;

	DELETE FROM meal_plan
	WHERE product_id = OLD.id
		AND type = 'product';

	DELETE FROM shopping_list
	WHERE product_id = OLD.id;

	DELETE FROM userfield_values
	WHERE object_id = OLD.id
		AND field_id IN (SELECT id FROM userfields WHERE entity = 'products');
END;
CREATE TRIGGER enforce_min_stock_amount_for_cumulated_childs_INS AFTER INSERT ON products
BEGIN
	/*
		When a parent product has cumulate_min_stock_amount_of_sub_products enabled,
		the child should not have any min_stock_amount
	*/

	UPDATE products
	SET min_stock_amount = 0
	WHERE id IN (
			SELECT
				p_child.id
			FROM products p_parent
			JOIN products p_child
				ON p_child.parent_product_id = p_parent.id
			WHERE p_parent.id = NEW.id
				AND IFNULL(p_parent.cumulate_min_stock_amount_of_sub_products, 0) = 1
			)
		AND min_stock_amount > 0;
END;
CREATE TRIGGER enforce_min_stock_amount_for_cumulated_childs_UPD AFTER UPDATE ON products
BEGIN
	/*
		When a parent product has cumulate_min_stock_amount_of_sub_products enabled,
		the child should not have any min_stock_amount
	*/

	UPDATE products
	SET min_stock_amount = 0
	WHERE id IN (
			SELECT
				p_child.id
			FROM products p_parent
			JOIN products p_child
				ON p_child.parent_product_id = p_parent.id
			WHERE p_parent.id = NEW.id
				AND IFNULL(p_parent.cumulate_min_stock_amount_of_sub_products, 0) = 1
			)
		AND min_stock_amount > 0;
END;
CREATE INDEX ix_products_performance1 ON products (
    parent_product_id
);
CREATE INDEX ix_products_performance2 ON products (
    CASE WHEN parent_product_id IS NULL THEN id ELSE parent_product_id END,
    active
);
CREATE TRIGGER default_qu_id_consume AFTER INSERT ON products
BEGIN
	UPDATE products
	SET qu_id_consume = qu_id_stock
	WHERE id = NEW.id
		AND IFNULL(qu_id_consume, 0) = 0;
END;
CREATE TRIGGER cascade_change_qu_id_stock2 AFTER UPDATE ON products WHEN NEW.qu_id_stock != OLD.qu_id_stock
BEGIN
	-- See also the trigger "cascade_change_qu_id_stock BEFORE UPDATE ON products"
	-- This here applies the needed changes to the products table itself only AFTER the update

	UPDATE products
	SET quick_consume_amount = quick_consume_amount * IFNULL((SELECT factor FROM quantity_unit_conversions_resolved WHERE product_id = NEW.id AND from_qu_id = OLD.qu_id_stock AND to_qu_id = NEW.qu_id_stock LIMIT 1), 1.0),
	quick_open_amount = quick_open_amount * IFNULL((SELECT factor FROM quantity_unit_conversions_resolved WHERE product_id = NEW.id AND from_qu_id = OLD.qu_id_stock AND to_qu_id = NEW.qu_id_stock LIMIT 1), 1.0),
	calories = calories / IFNULL((SELECT factor FROM quantity_unit_conversions_resolved WHERE product_id = NEW.id AND from_qu_id = OLD.qu_id_stock AND to_qu_id = NEW.qu_id_stock LIMIT 1), 1.0),
	tare_weight = tare_weight * IFNULL((SELECT factor FROM quantity_unit_conversions_resolved WHERE product_id = NEW.id AND from_qu_id = OLD.qu_id_stock AND to_qu_id = NEW.qu_id_stock LIMIT 1), 1.0)
	WHERE id = NEW.id;
END;
CREATE VIEW stock_missing_products
AS

SELECT *
FROM (

-- Products WITHOUT sub products where the amount of the sub products SHOULD NOT be cumulated
SELECT
	p.id,
	MAX(p.name) AS name,
	p.min_stock_amount - IFNULL(SUM(s.amount), 0) + (CASE WHEN p.treat_opened_as_out_of_stock = 1 THEN IFNULL(SUM(s.amount_opened), 0) ELSE 0 END) AS amount_missing,
	CASE WHEN IFNULL(SUM(s.amount), 0) > 0 THEN 1 ELSE 0 END AS is_partly_in_stock
FROM products_view p
LEFT JOIN stock_current s
	ON p.id = s.product_id
WHERE p.min_stock_amount != 0
	AND p.cumulate_min_stock_amount_of_sub_products = 0
	AND p.has_sub_products = 0
	AND p.parent_product_id IS NULL
	AND IFNULL(p.active, 0) = 1
GROUP BY p.id

UNION

-- Parent products WITH sub products where the amount of the sub products SHOULD be cumulated
SELECT
	p.id,
	MAX(p.name) AS name,
	SUM(sub_p.min_stock_amount) - IFNULL(SUM(s.amount_aggregated), 0) + (CASE WHEN p.treat_opened_as_out_of_stock = 1 THEN IFNULL(SUM(s.amount_opened_aggregated), 0) ELSE 0 END) AS amount_missing,
	CASE WHEN IFNULL(SUM(s.amount), 0) > 0 THEN 1 ELSE 0 END AS is_partly_in_stock
FROM products_view p
JOIN products_resolved pr
	ON p.id = pr.parent_product_id
JOIN products sub_p
	ON pr.sub_product_id = sub_p.id
LEFT JOIN stock_current s
	ON pr.sub_product_id = s.product_id
WHERE sub_p.min_stock_amount != 0
	AND p.cumulate_min_stock_amount_of_sub_products = 1
	AND IFNULL(p.active, 0) = 1
GROUP BY p.id

UNION

-- Sub products where the amount SHOULD NOT be cumulated into the parent product
SELECT
	sub_p.id,
	MAX(sub_p.name) AS name,
	SUM(sub_p.min_stock_amount) - IFNULL(SUM(s.amount_aggregated), 0) + (CASE WHEN p.treat_opened_as_out_of_stock = 1 THEN IFNULL(SUM(s.amount_opened_aggregated), 0) ELSE 0 END) AS amount_missing,
	CASE WHEN IFNULL(SUM(s.amount), 0) > 0 THEN 1 ELSE 0 END AS is_partly_in_stock
FROM products p
JOIN products_resolved pr
	ON p.id = pr.parent_product_id
JOIN products sub_p
	ON pr.sub_product_id = sub_p.id
LEFT JOIN stock_current s
	ON pr.sub_product_id = s.product_id
WHERE sub_p.min_stock_amount != 0
	AND p.cumulate_min_stock_amount_of_sub_products = 0
	AND IFNULL(p.active, 0) = 1
GROUP BY sub_p.id
) x
WHERE x.amount_missing > 0
/* stock_missing_products(id,name,amount_missing,is_partly_in_stock) */;
CREATE VIEW meal_plan_internal_recipe_relation
AS

-- Relation between a meal plan (day) and the corresponding internal recipe(s)

SELECT mp.day, r.id AS recipe_id
FROM meal_plan mp
JOIN recipes r
	ON r.name = CAST(mp.day AS TEXT)
	AND r.type = 'mealplan-day'

UNION

SELECT mp.day, r.id AS recipe_id
FROM meal_plan mp
JOIN recipes r
	ON r.name = LTRIM(STRFTIME('%Y-%W', mp.day), '0')
	AND r.type = 'mealplan-week'

UNION

SELECT mp.day, r.id AS recipe_id
FROM meal_plan mp
JOIN recipes r
	ON r.name = CAST(mp.day AS TEXT) || '#' || CAST(mp.id AS TEXT)
	AND r.type = 'mealplan-shadow'
/* meal_plan_internal_recipe_relation(day,recipe_id) */;
CREATE TRIGGER default_qu_id_price AFTER INSERT ON products
BEGIN
	UPDATE products
	SET qu_id_price = qu_id_purchase
	WHERE id = NEW.id
		AND IFNULL(qu_id_price, 0) = 0;
END;
CREATE VIEW uihelper_stock_entries
AS
SELECT
	*
FROM stock s
JOIN products_view p
	ON s.product_id = p.id
/* uihelper_stock_entries(id,product_id,amount,best_before_date,purchased_date,stock_id,price,open,opened_date,row_created_timestamp,location_id,shopping_location_id,note,"id:1",name,description,product_group_id,active,"location_id:1","shopping_location_id:1",qu_id_purchase,qu_id_stock,min_stock_amount,default_best_before_days,default_best_before_days_after_open,default_best_before_days_after_freezing,default_best_before_days_after_thawing,picture_file_name,enable_tare_weight_handling,tare_weight,not_check_stock_fulfillment_for_recipes,parent_product_id,calories,cumulate_min_stock_amount_of_sub_products,due_type,quick_consume_amount,hide_on_stock_overview,default_stock_label_type,should_not_be_frozen,treat_opened_as_out_of_stock,no_own_stock,default_consume_location_id,move_on_open,"row_created_timestamp:1",qu_id_consume,auto_reprint_stock_label,quick_open_amount,qu_id_price,disable_open,default_purchase_price_type,has_sub_products,qu_factor_purchase_to_stock,qu_factor_consume_to_stock,qu_factor_price_to_stock) */;
CREATE INDEX ix_stock_log_performance1 ON stock_log (
	stock_id,
	transaction_type,
	amount
);
CREATE INDEX ix_stock_log_performance2 ON stock_log (
	product_id,
	best_before_date,
	purchased_date,
	transaction_type,
	stock_id,
	undone
);
CREATE TABLE cache__quantity_unit_conversions_resolved (
	id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT UNIQUE,
	product_id INT,
	from_qu_id INT,
	from_qu_name TEXT,
	from_qu_name_plural TEXT,
	to_qu_id INT,
	to_qu_name TEXT,
	to_qu_name_plural TEXT,
	factor TEXT,
	path TEXT
);
CREATE INDEX ix_cache__quantity_unit_conversions_resolved_performance1 ON cache__quantity_unit_conversions_resolved (
	product_id,
	from_qu_id,
	to_qu_id
);
CREATE TRIGGER quantity_unit_conversions_INS AFTER INSERT ON quantity_unit_conversions
BEGIN
	-- Create the inverse QU conversion
	INSERT OR REPLACE INTO quantity_unit_conversions
		(from_qu_id, to_qu_id, factor, product_id)
	VALUES
		(NEW.to_qu_id, NEW.from_qu_id, 1 / IFNULL(NEW.factor, 1), NEW.product_id);

	-- Update quantity_unit_conversions_resolved cache
	DELETE FROM cache__quantity_unit_conversions_resolved
	WHERE path LIKE '%/' || NEW.to_qu_id || '/%'
		OR path LIKE '%/' || NEW.from_qu_id || '/%';

	INSERT INTO cache__quantity_unit_conversions_resolved
		(product_id, from_qu_id, from_qu_name, from_qu_name_plural, to_qu_id, to_qu_name, to_qu_name_plural, factor, path)
	SELECT product_id, from_qu_id, from_qu_name, from_qu_name_plural, to_qu_id, to_qu_name, to_qu_name_plural, factor, path
	FROM quantity_unit_conversions_resolved
	WHERE path LIKE '%/' || NEW.to_qu_id || '/%'
		OR path LIKE '%/' || NEW.from_qu_id || '/%';
END;
CREATE TRIGGER quantity_unit_conversions_UPD AFTER UPDATE ON quantity_unit_conversions
BEGIN
	-- Update the inverse QU conversion
	UPDATE quantity_unit_conversions
	SET factor = 1 / IFNULL(NEW.factor, 1),
	from_qu_id = NEW.to_qu_id,
	to_qu_id = NEW.from_qu_id
	WHERE from_qu_id = OLD.to_qu_id
		AND to_qu_id = OLD.from_qu_id
		AND IFNULL(product_id, -1) = IFNULL(NEW.product_id, -1);

	-- Update quantity_unit_conversions_resolved cache
	DELETE FROM cache__quantity_unit_conversions_resolved
	WHERE path LIKE '%/' || NEW.to_qu_id || '/%'
		OR path LIKE '%/' || NEW.from_qu_id || '/%';

	INSERT INTO cache__quantity_unit_conversions_resolved
		(product_id, from_qu_id, from_qu_name, from_qu_name_plural, to_qu_id, to_qu_name, to_qu_name_plural, factor, path)
	SELECT product_id, from_qu_id, from_qu_name, from_qu_name_plural, to_qu_id, to_qu_name, to_qu_name_plural, factor, path
	FROM quantity_unit_conversions_resolved
	WHERE path LIKE '%/' || NEW.to_qu_id || '/%'
		OR path LIKE '%/' || NEW.from_qu_id || '/%';
END;
CREATE TRIGGER quantity_unit_conversions_DEL AFTER DELETE ON quantity_unit_conversions
BEGIN
	-- Delete the inverse QU conversion
	DELETE FROM quantity_unit_conversions
	WHERE from_qu_id = OLD.to_qu_id
		AND to_qu_id = OLD.from_qu_id
		AND IFNULL(product_id, -1) = IFNULL(OLD.product_id, -1);

	-- Update quantity_unit_conversions_resolved cache
	DELETE FROM cache__quantity_unit_conversions_resolved
	WHERE path LIKE '%/' || OLD.to_qu_id || '/%'
		OR path LIKE '%/' || OLD.from_qu_id || '/%';

	INSERT INTO cache__quantity_unit_conversions_resolved
		(product_id, from_qu_id, from_qu_name, from_qu_name_plural, to_qu_id, to_qu_name, to_qu_name_plural, factor, path)
	SELECT product_id, from_qu_id, from_qu_name, from_qu_name_plural, to_qu_id, to_qu_name, to_qu_name_plural, factor, path
	FROM quantity_unit_conversions_resolved
	WHERE path LIKE '%/' || OLD.to_qu_id || '/%'
		OR path LIKE '%/' || OLD.from_qu_id || '/%';
END;
CREATE TRIGGER products_INS AFTER INSERT ON products
BEGIN
	-- Update quantity_unit_conversions_resolved cache
	DELETE FROM cache__quantity_unit_conversions_resolved
	WHERE product_id = NEW.id;

	INSERT INTO cache__quantity_unit_conversions_resolved
		(product_id, from_qu_id, from_qu_name, from_qu_name_plural, to_qu_id, to_qu_name, to_qu_name_plural, factor, path)
	SELECT product_id, from_qu_id, from_qu_name, from_qu_name_plural, to_qu_id, to_qu_name, to_qu_name_plural, factor, path
	FROM quantity_unit_conversions_resolved
	WHERE product_id = NEW.id;
END;
CREATE TRIGGER products_UPD AFTER UPDATE ON products
BEGIN
	-- Update quantity_unit_conversions_resolved cache
	DELETE FROM cache__quantity_unit_conversions_resolved
	WHERE product_id = NEW.id;

	INSERT INTO cache__quantity_unit_conversions_resolved
		(product_id, from_qu_id, from_qu_name, from_qu_name_plural, to_qu_id, to_qu_name, to_qu_name_plural, factor, path)
	SELECT product_id, from_qu_id, from_qu_name, from_qu_name_plural, to_qu_id, to_qu_name, to_qu_name_plural, factor, path
	FROM quantity_unit_conversions_resolved
	WHERE product_id = NEW.id;
END;
CREATE TRIGGER products_DELETE AFTER DELETE ON products
BEGIN
	-- Update quantity_unit_conversions_resolved cache
	DELETE FROM cache__quantity_unit_conversions_resolved
	WHERE product_id = OLD.id;
END;
CREATE VIEW products_view
AS
SELECT
	p.*,
	CASE WHEN (SELECT 1 FROM products WHERE parent_product_id = p.id) NOTNULL THEN 1 ELSE 0 END AS has_sub_products,
	IFNULL(quc_purchase.factor, 1.0) AS qu_factor_purchase_to_stock,
	IFNULL(quc_consume.factor, 1.0) AS qu_factor_consume_to_stock,
	IFNULL(quc_price.factor, 1.0) AS qu_factor_price_to_stock
FROM products p
LEFT JOIN cache__quantity_unit_conversions_resolved quc_purchase
	ON p.id = quc_purchase.product_id
	AND p.qu_id_purchase = quc_purchase.from_qu_id
	AND p.qu_id_stock = quc_purchase.to_qu_id
LEFT JOIN cache__quantity_unit_conversions_resolved quc_consume
	ON p.id = quc_consume.product_id
	AND p.qu_id_consume = quc_consume.from_qu_id
	AND p.qu_id_stock = quc_consume.to_qu_id
LEFT JOIN cache__quantity_unit_conversions_resolved quc_price
	ON p.id = quc_price.product_id
	AND p.qu_id_price = quc_price.from_qu_id
	AND p.qu_id_stock = quc_price.to_qu_id
/* products_view(id,name,description,product_group_id,active,location_id,shopping_location_id,qu_id_purchase,qu_id_stock,min_stock_amount,default_best_before_days,default_best_before_days_after_open,default_best_before_days_after_freezing,default_best_before_days_after_thawing,picture_file_name,enable_tare_weight_handling,tare_weight,not_check_stock_fulfillment_for_recipes,parent_product_id,calories,cumulate_min_stock_amount_of_sub_products,due_type,quick_consume_amount,hide_on_stock_overview,default_stock_label_type,should_not_be_frozen,treat_opened_as_out_of_stock,no_own_stock,default_consume_location_id,move_on_open,row_created_timestamp,qu_id_consume,auto_reprint_stock_label,quick_open_amount,qu_id_price,disable_open,default_purchase_price_type,has_sub_products,qu_factor_purchase_to_stock,qu_factor_consume_to_stock,qu_factor_price_to_stock) */;
CREATE TABLE cache__products_average_price (
	id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT UNIQUE,
	product_id INT,
	price DECIMAL(15, 2),

	UNIQUE(product_id)
);
CREATE TABLE cache__products_last_purchased (
	id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT UNIQUE,
	product_id INT,
	amount DECIMAL(15, 2),
	best_before_date DATE,
	purchased_date DATE,
	price DECIMAL(15, 2),
	location_id INT,
	shopping_location_id INT,

	UNIQUE(product_id)
);
CREATE TRIGGER stock_log_INS AFTER INSERT ON stock_log
BEGIN
	-- Update products_average_price cache
	INSERT OR REPLACE INTO cache__products_average_price
		(product_id, price)
	SELECT product_id, price
	FROM products_average_price
	WHERE product_id = NEW.product_id;

	-- Update products_last_purchased cache
	INSERT OR REPLACE INTO cache__products_last_purchased
		(product_id, amount, best_before_date, purchased_date, price, location_id, shopping_location_id)
	SELECT product_id, amount, best_before_date, purchased_date, price, location_id, shopping_location_id
	FROM products_last_purchased
	WHERE product_id = NEW.product_id;
END;
CREATE TRIGGER stock_log_UPD AFTER UPDATE ON stock_log
BEGIN
	-- Update products_average_price cache
	INSERT OR REPLACE INTO cache__products_average_price
		(product_id, price)
	SELECT product_id, price
	FROM products_average_price
	WHERE product_id = NEW.product_id;

	-- Update products_last_purchased cache
	INSERT OR REPLACE INTO cache__products_last_purchased
		(product_id, amount, best_before_date, purchased_date, price, location_id, shopping_location_id)
	SELECT product_id, amount, best_before_date, purchased_date, price, location_id, shopping_location_id
	FROM products_last_purchased
	WHERE product_id = NEW.product_id;
END;
CREATE TRIGGER stock_log_DEL AFTER DELETE ON stock_log
BEGIN
	-- Update products_average_price cache
	DELETE FROM cache__products_average_price
	WHERE product_id = OLD.id;

	-- Update products_last_purchased cache
	DELETE FROM cache__products_last_purchased
	WHERE product_id = OLD.id;
END;
CREATE VIEW products_current_price
AS

/*
	Current price per product,
	based on the stock entry to use next,
	or on the last price if the product is currently not in stock
*/

SELECT
	-1 AS id, -- Dummy,
	p.id AS product_id,
	IFNULL(snu.price, plp.price) AS price
FROM products p
LEFT JOIN (
	SELECT
		product_id,
		MAX(priority),
		price -- Bare column, ref https://www.sqlite.org/lang_select.html#bare_columns_in_an_aggregate_query
	FROM stock_next_use
	GROUP BY product_id
	ORDER BY priority DESC, open DESC, best_before_date ASC, purchased_date ASC
	) snu
	ON p.id = snu.product_id
LEFT JOIN cache__products_last_purchased plp
	ON p.id = plp.product_id
/* products_current_price(id,product_id,price) */;
CREATE VIEW stock_edited_entries
AS
/*
	Returns stock_id's which have been edited manually
*/
SELECT
	x.stock_id,
	x.stock_log_id_of_newest_edited_entry,

	-- When an origin entry was edited, the new origin amount is the one of the newest "stock-edit-new" + all
	-- previous consume transactions (mind that consume transaction amounts are negative, hence here - instead of +)
	(
		SELECT amount
		FROM stock_log sli
		WHERE sli.id = x.stock_log_id_of_newest_edited_entry
	)
	-
	IFNULL((
		SELECT SUM(amount)
		FROM stock_log sli_consumed
		WHERE sli_consumed.stock_id = x.stock_id
			AND sli_consumed.transaction_type IN ('consume', 'inventory-correction')
			AND sli_consumed.id < x.stock_log_id_of_newest_edited_entry
			AND sli_consumed.amount < 0
			AND sli_consumed.undone = 0), 0) AS edited_origin_amount
FROM (
	SELECT
		sl_add.stock_id,
		MAX(sl_edit.id) AS stock_log_id_of_newest_edited_entry
	FROM stock_log sl_add
	JOIN stock_log sl_edit
		ON sl_add.stock_id = sl_edit.stock_id
		AND sl_edit.transaction_type = 'stock-edit-new'
	WHERE sl_add.transaction_type IN ('purchase', 'inventory-correction', 'self-production')
		AND sl_add.amount > 0
GROUP BY sl_add.stock_id
) x
JOIN stock_log sl_edit
	ON x.stock_log_id_of_newest_edited_entry = sl_edit.id
/* stock_edited_entries(stock_id,stock_log_id_of_newest_edited_entry,edited_origin_amount) */;
CREATE VIEW products_average_price
AS
SELECT
	1 AS id, -- Dummy, LessQL needs an id column
	sl.product_id,
	SUM(IFNULL(sl.edited_origin_amount, sl.amount) * sl.price) / SUM(IFNULL(sl.edited_origin_amount, sl.amount)) as price
FROM (
	SELECT sl.*, CASE WHEN sl.transaction_type = 'stock-edit-new' THEN see.edited_origin_amount END AS edited_origin_amount
	FROM stock_log sl
	LEFT JOIN stock_edited_entries see
		ON sl.stock_id = see.stock_id
) sl
WHERE sl.undone = 0
	AND (
		(sl.transaction_type IN ('purchase', 'inventory-correction', 'self-production') AND sl.stock_id NOT IN (SELECT stock_id FROM stock_edited_entries)) -- Unedited origin entries
		OR (sl.transaction_type = 'stock-edit-new' AND sl.id IN (SELECT stock_log_id_of_newest_edited_entry FROM stock_edited_entries)) -- Edited origin entries => take the newest "stock-edit-new" one
	)
	AND IFNULL(sl.price, 0) > 0
	AND IFNULL(sl.amount, 0) > 0
GROUP BY sl.product_id
/* products_average_price(id,product_id,price) */;
CREATE VIEW quantity_unit_conversions_resolved
AS

WITH RECURSIVE

-- Default QU conversions are handled in a later CTE, as we can't determine yet, for which products they are applicable.
default_conversions(from_qu_id, to_qu_id, factor)
AS (
	SELECT
		from_qu_id,
		to_qu_id,
		factor
	FROM quantity_unit_conversions
	WHERE product_id IS NULL
),

-- First find the closure for all default conversions. This will allow for further pruning when looking for product closure.
default_closure(depth, from_qu_id, to_qu_id, factor, path)
AS (
	-- As a base case, select all available default conversions
	SELECT
		1 as depth,
		from_qu_id,
		to_qu_id,
		factor,
		'/' || from_qu_id || '/' || to_qu_id || '/' -- We need to keep track of the conversion path in order to prevent cycles
	FROM default_conversions

	UNION

	-- Recursive case: Find all paths
	SELECT
		c.depth + 1,
		c.from_qu_id,
		s.to_qu_id,
		c.factor * s.factor,
		c.path || s.to_qu_id || '/'
	FROM default_closure c
	JOIN default_conversions s
		ON c.to_qu_id = s.from_qu_id
	WHERE c.path NOT LIKE ('%/' || s.to_qu_id || '/%') -- Prevent cycles
		AND NOT EXISTS(SELECT 1 FROM default_conversions ci WHERE ci.from_qu_id = c.from_qu_id AND ci.to_qu_id = s.to_qu_id) -- Prune if one of the existing conversions repeats (saves a lot of processing time)

),

default_closure_distinct(from_qu_id, to_qu_id, factor, path)
AS (
	SELECT DISTINCT
		from_qu_id,
		to_qu_id,
		FIRST_VALUE(factor) OVER win AS factor,
		FIRST_VALUE(path) OVER win AS path
	FROM default_closure
	GROUP BY from_qu_id, to_qu_id
	WINDOW win AS (PARTITION BY from_qu_id, to_qu_id ORDER BY depth)
	ORDER BY from_qu_id, to_qu_id
),

product_conversions(product_id, from_qu_id, to_qu_id, factor)
AS (
	-- Priority 1: Product-specific QU overrides
	-- Note that the quantity_unit_conversions table already contains both conversion directions for every conversion.
	SELECT
		product_id,
		from_qu_id,
		to_qu_id,
		factor
	FROM quantity_unit_conversions
	WHERE product_id IS NOT NULL

	UNION

	-- Priority 2: QU conversions with a factor of 1.0 from the stock unit to the stock unit
	SELECT
		id,
		qu_id_stock,
		qu_id_stock,
		1.0
	FROM products
),

product_closure(depth, product_id, from_qu_id, to_qu_id, factor, path)
AS (
	-- As a base case, select all available product-specific conversions
	SELECT
		1 as depth,
		product_id,
		from_qu_id,
		to_qu_id,
		factor,
		'/' || from_qu_id || '/' || to_qu_id || '/' -- We need to keep track of the conversion path in order to prevent cycles
	FROM product_conversions

	UNION

	-- Recursive case: Find all paths
	SELECT
		c.depth + 1,
		c.product_id,
		c.from_qu_id,
		s.to_qu_id,
		c.factor * s.factor,
		c.path || s.to_qu_id || '/'
	FROM product_closure c
	JOIN product_conversions s
		ON c.product_id = s.product_id
		AND c.to_qu_id = s.from_qu_id
	WHERE c.path NOT LIKE ('%/' || s.to_qu_id || '/%') -- Prevent cycles
		AND NOT EXISTS(SELECT 1 FROM product_conversions ci WHERE ci.product_id = c.product_id AND ci.from_qu_id = c.from_qu_id AND ci.to_qu_id = s.to_qu_id) -- Prune if one of the existing conversions repeats (saves a lot of processing time)
),

product_closure_distinct(product_id, from_qu_id, to_qu_id, factor, path)
AS (
	SELECT DISTINCT
		product_id,
		from_qu_id,
		to_qu_id,
		FIRST_VALUE(factor) OVER win AS factor,
		FIRST_VALUE(path) OVER win AS path
	FROM product_closure
	GROUP BY product_id, from_qu_id, to_qu_id
	WINDOW win AS (PARTITION BY product_id, from_qu_id, to_qu_id ORDER BY depth)
	ORDER BY product_id, from_qu_id, to_qu_id
),

-- Now we connect the two closures by adding the reachable conversions from product specific conversions to default conversions
product_reachable(product_id, from_qu_id, to_qu_id, factor, path)
AS (
	SELECT
		product_id,
		from_qu_id,
		to_qu_id,
		factor,
		path
	FROM product_closure_distinct

	UNION

	SELECT
		cd.product_id,
		dcd.from_qu_id,
		dcd.to_qu_id,
		dcd.factor,
		'/' || dcd.from_qu_id || '/' || dcd.to_qu_id || '/'
	FROM product_closure_distinct cd
	JOIN default_closure_distinct dcd
		ON cd.to_qu_id = dcd.from_qu_id
		OR cd.to_qu_id = dcd.to_qu_id
	WHERE NOT EXISTS(SELECT 1 FROM product_closure_distinct ci WHERE ci.product_id = cd.product_id AND ci.from_qu_id = dcd.from_qu_id AND ci.to_qu_id = dcd.to_qu_id)
),

product_reachable_distinct(product_id, from_qu_id, to_qu_id, factor, path)
AS (
	SELECT DISTINCT
		product_id,
		from_qu_id,
		to_qu_id,
		FIRST_VALUE(factor) OVER win AS factor,
		FIRST_VALUE(path) OVER win AS path
	FROM product_reachable
	GROUP BY product_id, from_qu_id, to_qu_id
	WINDOW win AS (PARTITION BY product_id, from_qu_id, to_qu_id)
	ORDER BY product_id, from_qu_id, to_qu_id
),

-- Finally we build the combined closure
closure_final(depth, product_id, from_qu_id, to_qu_id, factor, path)
AS (
	-- As a base case, select the product closure
	SELECT
		1,
		product_id,
		from_qu_id,
		to_qu_id,
		factor,
		path -- We need to keep track of the conversion path in order to prevent cycles
	FROM product_reachable_distinct

	UNION

	-- Add a default unit conversion to the *end* of the conversion chain
	SELECT
		c.depth + 1,
		c.product_id,
		c.from_qu_id,
		s.to_qu_id,
		c.factor * s.factor,
		c.path || s.to_qu_id || '/'
	FROM closure_final c
	JOIN product_reachable_distinct s
		ON c.product_id = s.product_id
		AND c.to_qu_id = s.from_qu_id
	WHERE c.path NOT LIKE ('%/' || s.to_qu_id || '/%') -- Prevent cycles
		AND NOT EXISTS(SELECT 1 FROM product_reachable_distinct ci WHERE ci.product_id = c.product_id AND ci.from_qu_id = c.from_qu_id AND ci.to_qu_id = s.to_qu_id) -- Prune (if already exists)
)

SELECT DISTINCT
	-1 AS id, -- Dummy, LessQL needs an id column
	c.product_id,
	c.from_qu_id,
	qu_from.name AS from_qu_name,
	qu_from.name_plural AS from_qu_name_plural,
	c.to_qu_id,
	qu_to.name AS to_qu_name,
	qu_to.name_plural AS to_qu_name_plural,
	FIRST_VALUE(c.factor) OVER win AS factor,
	FIRST_VALUE(c.path) OVER win AS path
FROM closure_final c
JOIN quantity_units qu_from
	ON c.from_qu_id = qu_from.id
JOIN quantity_units qu_to
	ON c.to_qu_id = qu_to.id
GROUP BY c.product_id, c.from_qu_id, c.to_qu_id
WINDOW win AS (PARTITION BY c.product_id, c.from_qu_id, c.to_qu_id ORDER BY c.depth)
ORDER BY c.product_id, c.from_qu_id, c.to_qu_id
/* quantity_unit_conversions_resolved(id,product_id,from_qu_id,from_qu_name,from_qu_name_plural,to_qu_id,to_qu_name,to_qu_name_plural,factor,path) */;
CREATE VIEW stock_current
AS
SELECT
	pr.parent_product_id AS product_id,
	IFNULL((SELECT SUM(amount) FROM stock WHERE product_id = pr.parent_product_id), 0) AS amount,
	SUM(s.amount * IFNULL(qucr.factor, 1.0)) AS amount_aggregated,
	IFNULL(ROUND((SELECT SUM(IFNULL(price,0) * amount) FROM stock WHERE product_id = pr.parent_product_id), 2), 0)  AS value,
	MIN(s.best_before_date) AS best_before_date,
	IFNULL((SELECT SUM(amount) FROM stock WHERE product_id = pr.parent_product_id AND open = 1), 0) AS amount_opened,
	IFNULL((SELECT SUM(amount) FROM stock WHERE product_id IN (SELECT sub_product_id FROM products_resolved WHERE parent_product_id = pr.parent_product_id) AND open = 1), 0) * IFNULL(qucr.factor, 1) AS amount_opened_aggregated,
	CASE WHEN COUNT(p_sub.parent_product_id) > 0  THEN 1 ELSE 0 END AS is_aggregated_amount,
	MAX(p_parent.due_type) AS due_type
FROM products_resolved pr
JOIN stock s
	ON pr.sub_product_id = s.product_id
JOIN products p_parent
	ON pr.parent_product_id = p_parent.id
	AND p_parent.active = 1
JOIN products p_sub
	ON pr.sub_product_id = p_sub.id
	AND p_sub.active = 1
LEFT JOIN cache__quantity_unit_conversions_resolved qucr
	ON pr.sub_product_id = qucr.product_id
	AND p_sub.qu_id_stock = qucr.from_qu_id
	AND p_parent.qu_id_stock = qucr.to_qu_id
GROUP BY pr.parent_product_id
HAVING SUM(s.amount) > 0

UNION

-- This is the same as above but sub products not rolled up (no QU conversion and column is_aggregated_amount = 0 here)
SELECT
	pr.sub_product_id AS product_id,
	SUM(s.amount) AS amount,
	SUM(s.amount) AS amount_aggregated,
	ROUND(SUM(IFNULL(s.price, 0) * s.amount), 2) AS value,
	MIN(s.best_before_date) AS best_before_date,
	IFNULL((SELECT SUM(amount) FROM stock WHERE product_id = s.product_id AND open = 1), 0) AS amount_opened,
	IFNULL((SELECT SUM(amount) FROM stock WHERE product_id = s.product_id AND open = 1), 0) AS amount_opened_aggregated,
	0 AS is_aggregated_amount,
	MAX(p_sub.due_type) AS due_type
FROM products_resolved pr
JOIN stock s
	ON pr.sub_product_id = s.product_id
JOIN products p_sub
	ON pr.sub_product_id = p_sub.id
	AND p_sub.active = 1
WHERE pr.parent_product_id != pr.sub_product_id
GROUP BY pr.sub_product_id
HAVING SUM(s.amount) > 0
/* stock_current(product_id,amount,amount_aggregated,value,best_before_date,amount_opened,amount_opened_aggregated,is_aggregated_amount,due_type) */;
CREATE VIEW uihelper_product_details
AS
SELECT
	p.id,
	plp.purchased_date AS last_purchased_date,
	plp.price AS last_purchased_price,
	plp.shopping_location_id AS last_purchased_shopping_location_id,
	pap.price AS average_price,
	sl.average_shelf_life_days,
	pcp.price AS current_price,
	last_used.used_date AS last_used_date,
	next_due.best_before_date AS next_due_date,
	IFNULL((spoil_count.amount * 100.0) / consume_count.amount, 0) AS spoil_rate,
	CAST(IFNULL(quc_purchase2stock.factor, 1.0) AS REAL) AS qu_factor_purchase_to_stock,
	CAST(IFNULL(quc_price2stock.factor, 1.0) AS REAL) AS qu_factor_price_to_stock,
	CASE WHEN EXISTS(SELECT 1 FROM products px WHERE px.parent_product_id = p.id) THEN 1 ELSE 0 END AS has_childs
FROM products p
LEFT JOIN cache__products_last_purchased plp
	ON p.id = plp.product_id
LEFT JOIN cache__products_average_price pap
	ON p.id = pap.product_id
LEFT JOIN stock_average_product_shelf_life sl
	ON p.id = sl.id
LEFT JOIN products_current_price pcp
	ON p.id = pcp.product_id
LEFT JOIN cache__quantity_unit_conversions_resolved quc_purchase2stock
	ON p.id = quc_purchase2stock.product_id
	AND p.qu_id_purchase = quc_purchase2stock.from_qu_id
	AND p.qu_id_stock = quc_purchase2stock.to_qu_id
LEFT JOIN cache__quantity_unit_conversions_resolved quc_price2stock
	ON p.id = quc_price2stock.product_id
	AND p.qu_id_price = quc_price2stock.from_qu_id
	AND p.qu_id_stock = quc_price2stock.to_qu_id
LEFT JOIN (
	SELECT product_id, MAX(used_date) AS used_date
	FROM stock_log
	WHERE transaction_type = 'consume'
		AND undone = 0
	GROUP BY product_id
) last_used
	ON p.id = last_used.product_id
LEFT JOIN (
	SELECT product_id,MIN(best_before_date) AS best_before_date
	FROM stock
	GROUP BY product_id
) next_due
	ON p.id = next_due.product_id
LEFT JOIN (
	SELECT product_id, SUM(amount) AS amount
	FROM stock_log
	WHERE transaction_type = 'consume'
		AND undone = 0
	GROUP BY product_id
) consume_count
	ON p.id = consume_count.product_id
LEFT JOIN (
	SELECT product_id, SUM(amount) AS amount
	FROM stock_log
	WHERE transaction_type = 'consume'
		AND undone = 0
		AND spoiled = 1
	GROUP BY product_id
) spoil_count
	ON p.id = spoil_count.product_id
/* uihelper_product_details(id,last_purchased_date,last_purchased_price,last_purchased_shopping_location_id,average_price,average_shelf_life_days,current_price,last_used_date,next_due_date,spoil_rate,qu_factor_purchase_to_stock,qu_factor_price_to_stock,has_childs) */;
CREATE VIEW shopping_lists_view
AS
SELECT
	*,
	(SELECT IFNULL(COUNT(*), 0) FROM shopping_list WHERE shopping_list_id = sl.id) AS item_count
FROM shopping_lists sl
/* shopping_lists_view(id,name,description,row_created_timestamp,item_count) */;
CREATE VIEW products_last_purchased
AS
SELECT
	1 AS id, -- Dummy, LessQL needs an id column
	sl.product_id,
	sl.amount,
	sl.best_before_date,
	sl.purchased_date,
	sl.location_id,
	sl.shopping_location_id,
	IFNULL((SELECT price FROM products_price_history WHERE product_id = sl.product_id ORDER BY purchased_date DESC LIMIT 1), 0) AS price
FROM stock_log sl
JOIN (
	/*
		This subquery gets the ID of the stock_log row (per product) which referes to the last purchase transaction,
		while taking undone and edited transactions into account
	*/
	SELECT
		sl1.product_id,
		MAX(sl1.id) stock_log_id_of_last_purchase
	FROM stock_log sl1
	JOIN (
		/*
			This subquery finds the last purchased date per product,
			there can be multiple purchase transactions per day, therefore a JOIN by purchased_date
			for the outer query on this and then take MAX id of stock_log (of that day)
		*/
		SELECT
			sl2.product_id,
			MAX(sl2.purchased_date) AS last_purchased_date
		FROM stock_log sl2
		WHERE sl2.undone = 0
			AND (
				(sl2.transaction_type IN ('purchase', 'inventory-correction', 'self-production') AND sl2.stock_id NOT IN (SELECT stock_id FROM stock_edited_entries))
				OR (sl2.transaction_type = 'stock-edit-new' AND sl2.stock_id IN (SELECT stock_id FROM stock_edited_entries) AND sl2.id IN (SELECT stock_log_id_of_newest_edited_entry FROM stock_edited_entries))
			)
		GROUP BY sl2.product_id
	) x2
		ON sl1.product_id = x2.product_id
		AND sl1.purchased_date = x2.last_purchased_date
	WHERE sl1.undone = 0
		AND (
			(sl1.transaction_type IN ('purchase', 'inventory-correction', 'self-production') AND sl1.stock_id NOT IN (SELECT stock_id FROM stock_edited_entries))
			OR (sl1.transaction_type = 'stock-edit-new' AND sl1.stock_id IN (SELECT stock_id FROM stock_edited_entries) AND sl1.id IN (SELECT stock_log_id_of_newest_edited_entry FROM stock_edited_entries))
		)
	GROUP BY sl1.product_id
) x
	ON sl.product_id = x.product_id
	AND sl.id = x.stock_log_id_of_last_purchase
/* products_last_purchased(id,product_id,amount,best_before_date,purchased_date,location_id,shopping_location_id,price) */;
CREATE TRIGGER recipes_desired_servings_default AFTER INSERT ON recipes
BEGIN
	UPDATE recipes
	SET desired_servings = base_servings
	WHERE id = NEW.id;
END;
CREATE VIEW product_barcodes_view
AS
SELECT
	pb.id,
	pb.product_id,
	pb.barcode,
	pb.qu_id,
	pb.amount,
	pb.shopping_location_id,
	pb.last_price,
	pb.note
FROM product_barcodes pb

UNION ALL

-- Product Grocycodes
SELECT
	p.id,
	p.id AS product_id,
	'grcy:p:' || CAST(p.id AS TEXT) AS barcode,
	p.qu_id_stock AS qu_id,
	NULL AS amount,
	NULL AS shopping_location_id,
	NULL AS last_price,
	NULL AS note
FROM products p
/* product_barcodes_view(id,product_id,barcode,qu_id,amount,shopping_location_id,last_price,note) */;
CREATE VIEW products_price_history
AS
SELECT
	sl.product_id AS id, -- Dummy, LessQL needs an id column
	sl.product_id,
	sl.price,
	IFNULL(sl.edited_origin_amount, sl.amount) AS amount,
	sl.purchased_date,
	sl.shopping_location_id,
	sl.transaction_type
FROM (
	SELECT sl.*, CASE WHEN sl.transaction_type = 'stock-edit-new' THEN see.edited_origin_amount END AS edited_origin_amount
	FROM stock_log sl
	LEFT JOIN stock_edited_entries see
		ON sl.stock_id = see.stock_id
) sl
WHERE sl.undone = 0
	AND (
		(sl.transaction_type IN ('purchase', 'inventory-correction', 'self-production') AND sl.stock_id NOT IN (SELECT stock_id FROM stock_edited_entries)) -- Unedited origin entries
		OR (sl.transaction_type = 'stock-edit-new' AND sl.id IN (SELECT stock_log_id_of_newest_edited_entry FROM stock_edited_entries)) -- Edited origin entries => take the newest "stock-edit-new" one
	)
	AND IFNULL(sl.price, 0) > 0
	AND IFNULL(sl.amount, 0) > 0
/* products_price_history(id,product_id,price,amount,purchased_date,shopping_location_id,transaction_type) */;
CREATE VIEW recipes_nestings_resolved
AS
WITH RECURSIVE r1(recipe_id, includes_recipe_id, includes_servings, level)
AS (
	SELECT
		id AS recipe_id,
		id AS includes_recipe_id,
		1 AS includes_servings,
		0 AS level
	FROM recipes

	UNION ALL

	SELECT
		rn.recipe_id,
		r1.includes_recipe_id,
		rn.servings * r1.includes_servings AS includes_servings,
		r1.level + 1 AS level
	FROM recipes_nestings rn, r1 r1
	WHERE rn.includes_recipe_id = r1.recipe_id
)
SELECT
	*,
	1 AS id -- Dummy, LessQL needs an id column
FROM r1
/* recipes_nestings_resolved(recipe_id,includes_recipe_id,includes_servings,level,id) */;
CREATE VIEW recipes_resolved
AS
SELECT
	1 AS id, -- Dummy, LessQL needs an id column
	r.id AS recipe_id,
	IFNULL(MIN(rpr.need_fulfilled), 1) AS need_fulfilled,
	IFNULL(MIN(rpr.need_fulfilled_with_shopping_list), 1) AS need_fulfilled_with_shopping_list,
	IFNULL(rmpc.missing_products_count, 0) AS missing_products_count,
	IFNULL(SUM(rpr.costs), 0) AS costs,
	IFNULL(SUM(rpr.costs) / CASE WHEN IFNULL(r.desired_servings, 0) = 0 THEN 1 ELSE r.desired_servings END, 0) AS costs_per_serving,
	IFNULL(SUM(rpr.calories), 0) AS calories,
	IFNULL(SUM(rpr.due_score), 0) AS due_score,
	GROUP_CONCAT(rpr.product_name) AS product_names_comma_separated,
	CASE WHEN MIN(IFNULL(rpr.costs, 0)) = 0 THEN 1 ELSE 0 END AS prices_incomplete
FROM recipes r
LEFT JOIN recipes_pos_resolved rpr
	ON r.id = rpr.recipe_id
LEFT JOIN recipes_missing_product_counts rmpc
	ON r.id = rmpc.recipe_id
GROUP BY r.id;
CREATE VIEW recipes_pos_resolved
AS

-- Multiplication by 1.0 to force conversion to float (REAL)

-- Resolved amount (here used multiple times):
-- CASE WHEN rnr.recipe_id = rnr.includes_recipe_id THEN rp.amount * ((r.desired_servings*1.0) / (r.base_servings*1.0)) ELSE rp.amount * ((r.desired_servings*1.0) / (r.base_servings*1.0)) * ((rnr.includes_servings*1.0) / (rnrr.base_servings*1.0)) END

SELECT
	r.id AS recipe_id,
	rp.id AS recipe_pos_id,
	rp.product_id AS product_id,
	CASE WHEN rp.round_up = 1 THEN CEIL(CASE WHEN rnr.recipe_id = rnr.includes_recipe_id THEN rp.amount * ((r.desired_servings*1.0) / (r.base_servings*1.0)) ELSE rp.amount * ((r.desired_servings*1.0) / (r.base_servings*1.0)) * ((rnr.includes_servings*1.0) / (rnrr.base_servings*1.0)) END) ELSE CASE WHEN rnr.recipe_id = rnr.includes_recipe_id THEN rp.amount * ((r.desired_servings*1.0) / (r.base_servings*1.0)) ELSE rp.amount * ((r.desired_servings*1.0) / (r.base_servings*1.0)) * ((rnr.includes_servings*1.0) / (rnrr.base_servings*1.0)) END END AS recipe_amount,
	IFNULL(sc.amount_aggregated, 0) AS stock_amount,
	CASE WHEN IFNULL(sc.amount_aggregated, 0) >= CASE WHEN rp.only_check_single_unit_in_stock = 1 THEN 0.00000001 ELSE CASE WHEN rp.round_up = 1 THEN CEIL(CASE WHEN rnr.recipe_id = rnr.includes_recipe_id THEN rp.amount * ((r.desired_servings*1.0) / (r.base_servings*1.0)) ELSE rp.amount * ((r.desired_servings*1.0) / (r.base_servings*1.0)) * ((rnr.includes_servings*1.0) / (rnrr.base_servings*1.0)) END) ELSE CASE WHEN rnr.recipe_id = rnr.includes_recipe_id THEN rp.amount * ((r.desired_servings*1.0) / (r.base_servings*1.0)) ELSE rp.amount * ((r.desired_servings*1.0) / (r.base_servings*1.0)) * ((rnr.includes_servings*1.0) / (rnrr.base_servings*1.0)) END END END THEN 1 ELSE 0 END AS need_fulfilled,
	CASE WHEN IFNULL(sc.amount_aggregated, 0) - CASE WHEN rp.only_check_single_unit_in_stock = 1 THEN 0.00000001 ELSE CASE WHEN rp.round_up = 1 THEN CEIL(CASE WHEN rnr.recipe_id = rnr.includes_recipe_id THEN rp.amount * ((r.desired_servings*1.0) / (r.base_servings*1.0)) ELSE rp.amount * ((r.desired_servings*1.0) / (r.base_servings*1.0)) * ((rnr.includes_servings*1.0) / (rnrr.base_servings*1.0)) END) ELSE CASE WHEN rnr.recipe_id = rnr.includes_recipe_id THEN rp.amount * ((r.desired_servings*1.0) / (r.base_servings*1.0)) ELSE rp.amount * ((r.desired_servings*1.0) / (r.base_servings*1.0)) * ((rnr.includes_servings*1.0) / (rnrr.base_servings*1.0)) END END END < 0 THEN ABS(IFNULL(sc.amount_aggregated, 0) - (CASE WHEN rp.round_up = 1 THEN CEIL(CASE WHEN rnr.recipe_id = rnr.includes_recipe_id THEN rp.amount * ((r.desired_servings*1.0) / (r.base_servings*1.0)) ELSE rp.amount * ((r.desired_servings*1.0) / (r.base_servings*1.0)) * ((rnr.includes_servings*1.0) / (rnrr.base_servings*1.0)) END) ELSE CASE WHEN rnr.recipe_id = rnr.includes_recipe_id THEN rp.amount * ((r.desired_servings*1.0) / (r.base_servings*1.0)) ELSE rp.amount * ((r.desired_servings*1.0) / (r.base_servings*1.0)) * ((rnr.includes_servings*1.0) / (rnrr.base_servings*1.0)) END END)) ELSE 0 END AS missing_amount,
	IFNULL(sl.amount, 0) AS amount_on_shopping_list,
	CASE WHEN ROUND(IFNULL(sc.amount_aggregated, 0) + CASE WHEN r.not_check_shoppinglist = 1 THEN 0 ELSE IFNULL(sl.amount, 0) END, 2) >= ROUND(CASE WHEN rp.only_check_single_unit_in_stock = 1 THEN 0.00000001 ELSE CASE WHEN rp.round_up = 1 THEN CEIL(CASE WHEN rnr.recipe_id = rnr.includes_recipe_id THEN rp.amount * ((r.desired_servings*1.0) / (r.base_servings*1.0)) ELSE rp.amount * ((r.desired_servings*1.0) / (r.base_servings*1.0)) * ((rnr.includes_servings*1.0) / (rnrr.base_servings*1.0)) END) ELSE CASE WHEN rnr.recipe_id = rnr.includes_recipe_id THEN rp.amount * ((r.desired_servings*1.0) / (r.base_servings*1.0)) ELSE rp.amount * ((r.desired_servings*1.0) / (r.base_servings*1.0)) * ((rnr.includes_servings*1.0) / (rnrr.base_servings*1.0)) END END END, 2) THEN 1 ELSE 0 END AS need_fulfilled_with_shopping_list,
	rp.qu_id,
	(r.desired_servings*1.0 / r.base_servings*1.0) * CASE WHEN rp.only_check_single_unit_in_stock = 1 THEN IFNULL(qucr.factor, 1.0) ELSE 1 END * (rnr.includes_servings*1.0 / CASE WHEN rnr.recipe_id != rnr.includes_recipe_id THEN rnrr.base_servings*1.0 ELSE 1 END) * rp.amount * IFNULL(pcp.price, 0) * rp.price_factor * CASE WHEN rp.product_id != p_effective.id THEN IFNULL(qucr.factor, 1.0) ELSE 1.0 END AS costs,
	CASE WHEN rnr.recipe_id = rnr.includes_recipe_id THEN 0 ELSE 1 END AS is_nested_recipe_pos,
	rp.ingredient_group,
	pg.name as product_group,
	rp.id, -- Just a dummy id column
	r.type as recipe_type,
	rnr.includes_recipe_id as child_recipe_id,
	rp.note,
	rp.variable_amount AS recipe_variable_amount,
	rp.only_check_single_unit_in_stock,
	rp.amount * CASE WHEN rp.only_check_single_unit_in_stock = 1 THEN IFNULL(qucr.factor, 1.0) ELSE 1 END / r.base_servings*1.0 * (rnr.includes_servings*1.0 / CASE WHEN rnr.recipe_id != rnr.includes_recipe_id THEN rnrr.base_servings*1.0 ELSE 1 END) * IFNULL(p_effective.calories, 0) * CASE WHEN rp.product_id != p_effective.id THEN IFNULL(qucr.factor, 1.0) ELSE 1.0 END AS calories,
	p.active AS product_active,
	CASE pvs.current_due_status
		WHEN 'ok' THEN 0
		WHEN 'due_soon' THEN 1
		WHEN 'overdue' THEN 10
		WHEN 'expired' THEN 20
	END AS due_score,
	IFNULL(pcs.product_id_effective, rp.product_id) AS product_id_effective,
	p.name AS product_name
FROM recipes r
JOIN recipes_nestings_resolved rnr
	ON r.id = rnr.recipe_id
JOIN recipes rnrr
	ON rnr.includes_recipe_id = rnrr.id
JOIN recipes_pos rp
	ON rnr.includes_recipe_id = rp.recipe_id
JOIN products p
	ON rp.product_id = p.id
JOIN products_volatile_status pvs
	ON rp.product_id = pvs.product_id
LEFT JOIN product_groups pg
	ON p.product_group_id = pg.id
LEFT JOIN (
	SELECT product_id, SUM(amount) AS amount
	FROM shopping_list
	GROUP BY product_id) sl
	ON rp.product_id = sl.product_id
LEFT JOIN stock_current sc
	ON rp.product_id = sc.product_id
LEFT JOIN products_current_substitutions pcs
	ON rp.product_id = pcs.parent_product_id
LEFT JOIN products_current_price pcp
	ON IFNULL(pcs.product_id_effective, rp.product_id) = pcp.product_id
LEFT JOIN products p_effective
	ON IFNULL(pcs.product_id_effective, rp.product_id) = p_effective.id
LEFT JOIN cache__quantity_unit_conversions_resolved qucr
	ON IFNULL(pcs.product_id_effective, rp.product_id) = qucr.product_id
	AND CASE WHEN rp.product_id != p_effective.id THEN p.qu_id_stock ELSE rp.qu_id END = qucr.from_qu_id
	AND IFNULL(p_effective.qu_id_stock, p.qu_id_stock) = qucr.to_qu_id
WHERE rp.not_check_stock_fulfillment = 0

UNION

-- Just add all recipe positions which should not be checked against stock with fulfilled need

SELECT
	r.id AS recipe_id,
	rp.id AS recipe_pos_id,
	rp.product_id AS product_id,
	CASE WHEN rp.round_up = 1 THEN CEIL(CASE WHEN rnr.recipe_id = rnr.includes_recipe_id THEN rp.amount * ((r.desired_servings*1.0) / (r.base_servings*1.0)) ELSE rp.amount * ((r.desired_servings*1.0) / (r.base_servings*1.0)) * ((rnr.includes_servings*1.0) / (rnrr.base_servings*1.0)) END) ELSE CASE WHEN rnr.recipe_id = rnr.includes_recipe_id THEN rp.amount * ((r.desired_servings*1.0) / (r.base_servings*1.0)) ELSE rp.amount * ((r.desired_servings*1.0) / (r.base_servings*1.0)) * ((rnr.includes_servings*1.0) / (rnrr.base_servings*1.0)) END END AS recipe_amount,
	IFNULL(sc.amount_aggregated, 0) AS stock_amount,
	1 AS need_fulfilled,
	0 AS missing_amount,
	IFNULL(sl.amount, 0) AS amount_on_shopping_list,
	1 AS need_fulfilled_with_shopping_list,
	rp.qu_id,
	(r.desired_servings*1.0 / r.base_servings*1.0) * CASE WHEN rp.only_check_single_unit_in_stock = 1 THEN IFNULL(qucr.factor, 1.0) ELSE 1 END * (rnr.includes_servings*1.0 / CASE WHEN rnr.recipe_id != rnr.includes_recipe_id THEN rnrr.base_servings*1.0 ELSE 1 END) * rp.amount * IFNULL(pcp.price, 0) * rp.price_factor * CASE WHEN rp.product_id != p_effective.id THEN IFNULL(qucr.factor, 1.0) ELSE 1.0 END AS costs,
	CASE WHEN rnr.recipe_id = rnr.includes_recipe_id THEN 0 ELSE 1 END AS is_nested_recipe_pos,
	rp.ingredient_group,
	pg.name as product_group,
	rp.id, -- Just a dummy id column
	r.type as recipe_type,
	rnr.includes_recipe_id as child_recipe_id,
	rp.note,
	rp.variable_amount AS recipe_variable_amount,
	rp.only_check_single_unit_in_stock,
	rp.amount * CASE WHEN rp.only_check_single_unit_in_stock = 1 THEN IFNULL(qucr.factor, 1.0) ELSE 1 END / r.base_servings*1.0 * (rnr.includes_servings*1.0 / CASE WHEN rnr.recipe_id != rnr.includes_recipe_id THEN rnrr.base_servings*1.0 ELSE 1 END) * IFNULL(p_effective.calories, 0) * CASE WHEN rp.product_id != p_effective.id THEN IFNULL(qucr.factor, 1.0) ELSE 1.0 END AS calories,
	p.active AS product_active,
	CASE pvs.current_due_status
		WHEN 'ok' THEN 0
		WHEN 'due_soon' THEN 1
		WHEN 'overdue' THEN 10
		WHEN 'expired' THEN 20
	END AS due_score,
	IFNULL(pcs.product_id_effective, rp.product_id) AS product_id_effective,
	p.name AS product_name
FROM recipes r
JOIN recipes_nestings_resolved rnr
	ON r.id = rnr.recipe_id
JOIN recipes rnrr
	ON rnr.includes_recipe_id = rnrr.id
JOIN recipes_pos rp
	ON rnr.includes_recipe_id = rp.recipe_id
JOIN products p
	ON rp.product_id = p.id
JOIN products_volatile_status pvs
	ON rp.product_id = pvs.product_id
LEFT JOIN product_groups pg
	ON p.product_group_id = pg.id
LEFT JOIN (
	SELECT product_id, SUM(amount) AS amount
	FROM shopping_list
	GROUP BY product_id) sl
	ON rp.product_id = sl.product_id
LEFT JOIN stock_current sc
	ON rp.product_id = sc.product_id
LEFT JOIN products_current_substitutions pcs
	ON rp.product_id = pcs.parent_product_id
LEFT JOIN products_current_price pcp
	ON IFNULL(pcs.product_id_effective, rp.product_id) = pcp.product_id
LEFT JOIN products p_effective
	ON IFNULL(pcs.product_id_effective, rp.product_id) = p_effective.id
LEFT JOIN cache__quantity_unit_conversions_resolved qucr
	ON IFNULL(pcs.product_id_effective, rp.product_id) = qucr.product_id
	AND CASE WHEN rp.product_id != p_effective.id THEN p.qu_id_stock ELSE rp.qu_id END = qucr.from_qu_id
	AND IFNULL(p_effective.qu_id_stock, p.qu_id_stock) = qucr.to_qu_id
WHERE rp.not_check_stock_fulfillment = 1;
CREATE TRIGGER shopping_list_defaults_INS AFTER INSERT ON shopping_list
BEGIN
	UPDATE shopping_list
	SET qu_id = (SELECT qu_id_purchase FROM products WHERE id = product_id)
	WHERE IFNULL(qu_id, '') = ''
		AND id = NEW.id;

	UPDATE shopping_list
	SET amount = 0
	WHERE TYPEOF(amount) NOT IN ('integer', 'real')
		AND id = NEW.id;
END;
CREATE TRIGGER shopping_list_defaults_UPD AFTER UPDATE ON shopping_list
BEGIN
	UPDATE shopping_list
	SET qu_id = (SELECT qu_id_purchase FROM products WHERE id = product_id)
	WHERE IFNULL(qu_id, '') = ''
		AND id = NEW.id;

	UPDATE shopping_list
	SET amount = 0
	WHERE TYPEOF(amount) NOT IN ('integer', 'real')
		AND id = NEW.id;
END;
CREATE VIEW uihelper_shopping_list
AS
SELECT
	sl.*,
	p.name AS product_name,
	plp.price * IFNULL(quc.factor, 1.0) AS last_price_unit,
	plp.price * sl.amount AS last_price_total,
	plp.price AS price,
	st.name AS default_shopping_location_name,
	qu.name AS qu_name,
	qu.name_plural AS qu_name_plural,
	pg.id AS product_group_id,
	pg.name AS product_group_name,
	pbcs.barcodes AS product_barcodes
FROM shopping_list sl
LEFT JOIN products p
	ON sl.product_id = p.id
LEFT JOIN cache__products_last_purchased plp
	ON sl.product_id = plp.product_id
LEFT JOIN shopping_locations st
	ON p.shopping_location_id = st.id
LEFT JOIN quantity_units qu
	ON sl.qu_id = qu.id
LEFT JOIN product_groups pg
	ON p.product_group_id = pg.id
LEFT JOIN cache__quantity_unit_conversions_resolved quc
	ON p.id = quc.product_id
	AND p.qu_id_stock = quc.to_qu_id
	AND sl.qu_id = quc.from_qu_id
LEFT JOIN product_barcodes_comma_separated pbcs
	ON sl.product_id = pbcs.product_id
/* uihelper_shopping_list(id,product_id,note,amount,row_created_timestamp,shopping_list_id,done,qu_id,product_name,last_price_unit,last_price_total,price,default_shopping_location_name,qu_name,qu_name_plural,product_group_id,product_group_name,product_barcodes) */;
CREATE VIEW uihelper_stock_current_overview
AS
SELECT
	p.id,
	sc.amount_opened AS amount_opened,
	p.tare_weight AS tare_weight,
	p.enable_tare_weight_handling AS enable_tare_weight_handling,
	sc.amount AS amount,
	sc.value as value,
	sc.product_id AS product_id,
	IFNULL(sc.best_before_date, '2888-12-31') AS best_before_date,
	EXISTS(SELECT id FROM stock_missing_products WHERE id = sc.product_id) AS product_missing,
	p.name AS product_name,
	pg.name AS product_group_name,
	sl.name AS default_store_name,
	EXISTS(SELECT * FROM shopping_list WHERE shopping_list.product_id = sc.product_id) AS on_shopping_list,
	qu_stock.name AS qu_stock_name,
	qu_stock.name_plural AS qu_stock_name_plural,
	qu_purchase.name AS qu_purchase_name,
	qu_purchase.name_plural AS qu_purchase_name_plural,
	qu_consume.name AS qu_consume_name,
	qu_consume.name_plural AS qu_consume_name_plural,
	qu_price.name AS qu_price_name,
	qu_price.name_plural AS qu_price_name_plural,
	sc.is_aggregated_amount,
	sc.amount_opened_aggregated,
	sc.amount_aggregated,
	p.calories AS product_calories,
	sc.amount * p.calories AS calories,
	sc.amount_aggregated * p.calories AS calories_aggregated,
	p.quick_consume_amount,
	p.quick_consume_amount / p.qu_factor_consume_to_stock AS quick_consume_amount_qu_consume,
	p.quick_open_amount,
	p.quick_open_amount / p.qu_factor_consume_to_stock AS quick_open_amount_qu_consume,
	p.due_type,
	plp.purchased_date AS last_purchased,
	plp.price AS last_price,
	pap.price as average_price,
	p.min_stock_amount,
	pbcs.barcodes AS product_barcodes,
	p.description AS product_description,
	l.name AS product_default_location_name,
	p_parent.id AS parent_product_id,
	p_parent.name AS parent_product_name,
	p.picture_file_name AS product_picture_file_name,
	p.no_own_stock AS product_no_own_stock,
	p.qu_factor_purchase_to_stock AS product_qu_factor_purchase_to_stock,
	p.qu_factor_price_to_stock AS product_qu_factor_price_to_stock,
	sc.is_in_stock_or_below_min_stock,
	p.disable_open
FROM (
	SELECT *, 1 AS is_in_stock_or_below_min_stock
	FROM stock_current
	WHERE best_before_date IS NOT NULL
	UNION
	SELECT m.id, 0, 0, 0, null, 0, 0, 0, p.due_type, 1 AS is_in_stock_or_below_min_stock
	FROM stock_missing_products m
	JOIN products p
		ON m.id = p.id
	WHERE m.id NOT IN (SELECT product_id FROM stock_current)
	UNION
	SELECT p2.id, 0, 0, 0, null, 0, 0, 0, p2.due_type, 0 AS is_in_stock_or_below_min_stock
	FROM products p2
	WHERE active = 1
		AND p2.id NOT IN (SELECT product_id FROM stock_current UNION SELECT id FROM stock_missing_products)
	) sc
JOIN products_view p
    ON sc.product_id = p.id
JOIN locations l
	ON p.location_id = l.id
JOIN quantity_units qu_stock
	ON p.qu_id_stock = qu_stock.id
JOIN quantity_units qu_purchase
	ON p.qu_id_purchase = qu_purchase.id
JOIN quantity_units qu_consume
	ON p.qu_id_consume = qu_consume.id
JOIN quantity_units qu_price
	ON p.qu_id_price = qu_price.id
LEFT JOIN product_groups pg
	ON p.product_group_id = pg.id
LEFT JOIN shopping_locations sl
	ON p.shopping_location_id = sl.id
LEFT JOIN cache__products_last_purchased plp
	ON sc.product_id = plp.product_id
LEFT JOIN cache__products_average_price pap
	ON sc.product_id = pap.product_id
LEFT JOIN product_barcodes_comma_separated pbcs
	ON sc.product_id = pbcs.product_id
LEFT JOIN products p_parent
	ON p.parent_product_id = p_parent.id
WHERE p.hide_on_stock_overview = 0
/* uihelper_stock_current_overview(id,amount_opened,tare_weight,enable_tare_weight_handling,amount,value,product_id,best_before_date,product_missing,product_name,product_group_name,default_store_name,on_shopping_list,qu_stock_name,qu_stock_name_plural,qu_purchase_name,qu_purchase_name_plural,qu_consume_name,qu_consume_name_plural,qu_price_name,qu_price_name_plural,is_aggregated_amount,amount_opened_aggregated,amount_aggregated,product_calories,calories,calories_aggregated,quick_consume_amount,quick_consume_amount_qu_consume,quick_open_amount,quick_open_amount_qu_consume,due_type,last_purchased,last_price,average_price,min_stock_amount,product_barcodes,product_description,product_default_location_name,parent_product_id,parent_product_name,product_picture_file_name,product_no_own_stock,product_qu_factor_purchase_to_stock,product_qu_factor_price_to_stock,is_in_stock_or_below_min_stock,disable_open) */;
CREATE TRIGGER prevent_self_nested_recipes_INS BEFORE INSERT ON recipes_nestings
BEGIN
SELECT CASE WHEN((
	SELECT 1
	FROM recipes_nestings
	WHERE NEW.recipe_id = NEW.includes_recipe_id
	)
	NOTNULL) THEN RAISE(ABORT, 'Recursive nested recipe detected') END;
END;
CREATE TRIGGER prevent_self_nested_recipes_UPD BEFORE UPDATE ON recipes_nestings
BEGIN
SELECT CASE WHEN((
	SELECT 1
	FROM recipes_nestings
	WHERE NEW.recipe_id = NEW.includes_recipe_id
	)
	NOTNULL) THEN RAISE(ABORT, 'Recursive nested recipe detected') END;
END;
CREATE TRIGGER prevent_infinite_nested_recipes_INS BEFORE INSERT ON recipes_nestings
BEGIN
    SELECT CASE WHEN((
        SELECT 1
        FROM recipes_nestings_resolved rnr
        WHERE NEW.recipe_id = rnr.includes_recipe_id
            AND NEW.includes_recipe_id = rnr.recipe_id
    ) NOTNULL) THEN RAISE(ABORT, 'Recursive nested recipe detected') END;
END;
CREATE TRIGGER prevent_infinite_nested_recipes_UPD BEFORE UPDATE ON recipes_nestings
BEGIN
    SELECT CASE WHEN((
        SELECT 1
        FROM recipes_nestings_resolved rnr
        WHERE NEW.recipe_id = rnr.includes_recipe_id
            AND NEW.includes_recipe_id = rnr.recipe_id
    ) NOTNULL) THEN RAISE(ABORT, 'Recursive nested recipe detected') END;
END;
CREATE TRIGGER enfore_product_nesting_level BEFORE UPDATE ON products
BEGIN
	-- Currently only 1 level is supported
    SELECT CASE WHEN((
        SELECT 1
        FROM products p
        WHERE IFNULL(NEW.parent_product_id, '') != ''
            AND IFNULL(parent_product_id, '') = NEW.id
    ) NOTNULL) THEN RAISE(ABORT, 'Unsupported product nesting level detected (currently only 1 level is supported)') END;
END;
CREATE TRIGGER prevent_internal_meal_plan_section_removal BEFORE DELETE ON meal_plan_sections
BEGIN
	SELECT CASE WHEN((
		SELECT 1
		FROM meal_plan_sections
		WHERE id = OLD.id
			AND id = -1
	) NOTNULL) THEN RAISE(ABORT, 'This is an internally used/required default section and therefore can''t be deleted') END;
END;
CREATE TRIGGER cascade_change_qu_id_stock BEFORE UPDATE ON products WHEN NEW.qu_id_stock != OLD.qu_id_stock
BEGIN
	-- All amounts anywhere are related to the products stock QU,
	-- so apply the appropriate unit conversion to all amounts everywhere on change
	-- (and enforce that such a conversion need to exist when the product was once added to stock)

	SELECT CASE WHEN((
		SELECT 1
		FROM quantity_unit_conversions_resolved
		WHERE product_id = NEW.id
			AND from_qu_id = OLD.qu_id_stock
			AND to_qu_id = NEW.qu_id_stock
	) ISNULL)
	AND
	((
        SELECT 1
        FROM stock_log
		WHERE product_id = NEW.id
			AND NEW.qu_id_stock != OLD.qu_id_stock
    ) NOTNULL) THEN RAISE(ABORT, 'qu_id_stock can only be changed when a corresponding QU conversion (old QU => new QU) exists when the product was once added to stock') END;

	UPDATE chores
	SET product_amount = product_amount * IFNULL((SELECT factor FROM quantity_unit_conversions_resolved WHERE product_id = NEW.id AND from_qu_id = OLD.qu_id_stock AND to_qu_id = NEW.qu_id_stock LIMIT 1), 1.0)
	WHERE product_id = NEW.id;

	UPDATE meal_plan
	SET product_amount = product_amount * IFNULL((SELECT factor FROM quantity_unit_conversions_resolved WHERE product_id = NEW.id AND from_qu_id = OLD.qu_id_stock AND to_qu_id = NEW.qu_id_stock LIMIT 1), 1.0)
	WHERE type = 'product'
		AND product_id = NEW.id;

	UPDATE recipes_pos
	SET amount = amount * IFNULL((SELECT factor FROM quantity_unit_conversions_resolved WHERE product_id = NEW.id AND from_qu_id = OLD.qu_id_stock AND to_qu_id = NEW.qu_id_stock LIMIT 1), 1.0)
	WHERE product_id = NEW.id;

	UPDATE shopping_list
	SET amount = amount * IFNULL((SELECT factor FROM quantity_unit_conversions_resolved WHERE product_id = NEW.id AND from_qu_id = OLD.qu_id_stock AND to_qu_id = NEW.qu_id_stock LIMIT 1), 1.0)
	WHERE product_id = NEW.id
		AND product_id IS NOT NULL;

	UPDATE stock
	SET amount = amount * IFNULL((SELECT factor FROM quantity_unit_conversions_resolved WHERE product_id = NEW.id AND from_qu_id = OLD.qu_id_stock AND to_qu_id = NEW.qu_id_stock LIMIT 1), 1.0),
	price = price / IFNULL((SELECT factor FROM quantity_unit_conversions_resolved WHERE product_id = NEW.id AND from_qu_id = OLD.qu_id_stock AND to_qu_id = NEW.qu_id_stock LIMIT 1), 1.0)
	WHERE product_id = NEW.id;

	UPDATE stock_log
	SET amount = amount * IFNULL((SELECT factor FROM quantity_unit_conversions_resolved WHERE product_id = NEW.id AND from_qu_id = OLD.qu_id_stock AND to_qu_id = NEW.qu_id_stock LIMIT 1), 1.0),
	price = price / IFNULL((SELECT factor FROM quantity_unit_conversions_resolved WHERE product_id = NEW.id AND from_qu_id = OLD.qu_id_stock AND to_qu_id = NEW.qu_id_stock LIMIT 1), 1.0)
	WHERE product_id = NEW.id;
END;
CREATE TRIGGER prevent_adding_no_own_stock_products_to_stock AFTER INSERT ON stock
BEGIN
	SELECT CASE WHEN((
		SELECT 1
		FROM products p
		WHERE id = NEW.product_id
			AND no_own_stock = 1
	) NOTNULL) THEN RAISE(ABORT, 'no_own_stock = 1 products can''t be added to stock') END;
END;
CREATE TRIGGER qu_conversions_custom_constraint_INS BEFORE INSERT ON quantity_unit_conversions
BEGIN
	/*
		Necessary because unique constraints don''t include NULL values in SQLite
	*/
SELECT CASE WHEN((
	SELECT 1
	FROM quantity_unit_conversions
	WHERE from_qu_id = NEW.from_qu_id
		AND to_qu_id = NEW.to_qu_id
		AND IFNULL(product_id, 0) = IFNULL(NEW.product_id, 0)
	)
	NOTNULL) THEN RAISE(ABORT, 'QU conversion already exists') END;
END;
CREATE TRIGGER prevent_adding_barcodes_for_not_existing_products AFTER INSERT ON product_barcodes
BEGIN
	SELECT CASE WHEN((
		SELECT 1
		FROM products p
		WHERE id = NEW.product_id
	) ISNULL) THEN RAISE(ABORT, 'product_id doesn''t reference a existing product') END;
END;
CREATE TRIGGER recipes_pos_qu_id_default AFTER INSERT ON recipes_pos
BEGIN
	UPDATE recipes_pos
	SET qu_id = (SELECT qu_id_stock FROM products where id = product_id)
	WHERE id = NEW.id
		AND IFNULL(qu_id, '') = '';

	SELECT CASE WHEN((
		SELECT 1
		FROM recipes_pos rp
		JOIN quantity_unit_conversions_resolved qucr
			ON qucr.product_id = rp.product_id
			AND qucr.to_qu_id = rp.qu_id
		WHERE rp.id = NEW.id

		UNION

		-- only_check_single_unit_in_stock = 1 ingredients can have any QU
		SELECT 1
		FROM recipes_pos rp
		WHERE rp.id = NEW.id
			AND IFNULL(rp.only_check_single_unit_in_stock, 0) = 1
	) ISNULL) THEN RAISE(ABORT, 'Provided qu_id doesn''t have a related conversion for that product') END;
END;
CREATE TRIGGER qu_conversions_custom_constraint_UPD BEFORE UPDATE ON quantity_unit_conversions
BEGIN
	/* This contains practically the same logic as the trigger qu_conversions_custom_constraint_INS */

	/*
		Necessary because unique constraints don''t include NULL values in SQLite
	*/
SELECT CASE WHEN((
	SELECT 1
	FROM quantity_unit_conversions
	WHERE from_qu_id = NEW.from_qu_id
		AND to_qu_id = NEW.to_qu_id
		AND IFNULL(product_id, 0) = IFNULL(NEW.product_id, 0)
		AND id != NEW.id
	)
	NOTNULL) THEN RAISE(ABORT, 'QU conversion already exists') END;
END;
CREATE TRIGGER products_default_qu_conversions_INS AFTER INSERT ON products
BEGIN
	-- Create product specific 1:1 conversions when QU stock != QU purchase/consume/price
	-- and when no default QU conversion apply

	-- with qu_id_stock != qu_id_purchase
	INSERT INTO quantity_unit_conversions
		(from_qu_id, to_qu_id, factor, product_id)
	SELECT p.qu_id_purchase, p.qu_id_stock, 1, p.id
	FROM products p
	WHERE p.id = NEW.id
		AND p.qu_id_stock != qu_id_purchase
		AND NOT EXISTS(SELECT 1 FROM quantity_unit_conversions_resolved WHERE product_id = p.id AND from_qu_id = p.qu_id_stock AND to_qu_id = p.qu_id_purchase);

	-- with qu_id_stock != qu_id_consume
	INSERT INTO quantity_unit_conversions
		(from_qu_id, to_qu_id, factor, product_id)
	SELECT p.qu_id_consume, p.qu_id_stock, 1, p.id
	FROM products p
	WHERE p.id = NEW.id
		AND p.qu_id_stock != qu_id_consume
		AND NOT EXISTS(SELECT 1 FROM quantity_unit_conversions_resolved WHERE product_id = p.id AND from_qu_id = p.qu_id_stock AND to_qu_id = p.qu_id_consume);

	-- with qu_id_stock != qu_id_price
	INSERT INTO quantity_unit_conversions
		(from_qu_id, to_qu_id, factor, product_id)
	SELECT p.qu_id_price, p.qu_id_stock, 1, p.id
	FROM products p
	WHERE p.id = NEW.id
		AND p.qu_id_stock != qu_id_price
		AND NOT EXISTS(SELECT 1 FROM quantity_unit_conversions_resolved WHERE product_id = p.id AND from_qu_id = p.qu_id_stock AND to_qu_id = p.qu_id_price);
END;
CREATE TRIGGER products_default_qu_conversions_UPD AFTER UPDATE ON products
BEGIN
	-- Create product specific 1:1 conversions when QU stock != QU purchase/consume/price
	-- and when no default QU conversion apply

	-- with qu_id_stock != qu_id_purchase
	INSERT INTO quantity_unit_conversions
		(from_qu_id, to_qu_id, factor, product_id)
	SELECT p.qu_id_purchase, p.qu_id_stock, 1, p.id
	FROM products p
	WHERE p.id = NEW.id
		AND p.qu_id_stock != qu_id_purchase
		AND NOT EXISTS(SELECT 1 FROM quantity_unit_conversions_resolved WHERE product_id = p.id AND from_qu_id = p.qu_id_stock AND to_qu_id = p.qu_id_purchase);

	-- with qu_id_stock != qu_id_consume
	INSERT INTO quantity_unit_conversions
		(from_qu_id, to_qu_id, factor, product_id)
	SELECT p.qu_id_consume, p.qu_id_stock, 1, p.id
	FROM products p
	WHERE p.id = NEW.id
		AND p.qu_id_stock != qu_id_consume
		AND NOT EXISTS(SELECT 1 FROM quantity_unit_conversions_resolved WHERE product_id = p.id AND from_qu_id = p.qu_id_stock AND to_qu_id = p.qu_id_consume);

	-- with qu_id_stock != qu_id_price
	INSERT INTO quantity_unit_conversions
		(from_qu_id, to_qu_id, factor, product_id)
	SELECT p.qu_id_price, p.qu_id_stock, 1, p.id
	FROM products p
	WHERE p.id = NEW.id
		AND p.qu_id_stock != qu_id_price
		AND NOT EXISTS(SELECT 1 FROM quantity_unit_conversions_resolved WHERE product_id = p.id AND from_qu_id = p.qu_id_stock AND to_qu_id = p.qu_id_price);
END;
CREATE TABLE sessions (
	id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT UNIQUE,
	user_id INTEGER NOT NULL,
	token_type TINYINT NOT NULL,
	token_hash TEXT NOT NULL UNIQUE,
	expires DATETIME NOT NULL,
	last_used DATETIME,
	client_info TEXT,
	row_created_timestamp DATETIME DEFAULT (datetime('now', 'localtime'))
);
CREATE INDEX ix_sessions_performance1 ON sessions (
	token_type,
	token_hash
);
CREATE TRIGGER prevent_self_referenced_parent_product_INS AFTER INSERT ON products
BEGIN
SELECT CASE WHEN((
	SELECT 1
	FROM products p
	WHERE p.id = NEW.id
		AND p.id = p.parent_product_id
	)
	NOTNULL) THEN RAISE(ABORT, 'A product cannot reference itself as a parent product') END;
END;
CREATE TRIGGER prevent_self_referenced_parent_product_UPD AFTER UPDATE ON products
BEGIN
	SELECT CASE WHEN((
		SELECT 1
		FROM products p
		WHERE p.id = NEW.id
			AND p.id = p.parent_product_id
    ) NOTNULL) THEN RAISE(ABORT, 'A product cannot reference itself as a parent product') END;
END;
