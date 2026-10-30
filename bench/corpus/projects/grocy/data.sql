-- Synthetic data for Grocy: a busy household-plus instance. Deterministic (no random()): values come from
-- multiplicative hashes of the row number. Dates are relative to date('now', 'localtime') because the views
-- compare against 'now' themselves (due status, journal windows, meal plan week).
-- Scale 1: 30 quantity units with 11 chained default conversions, 600 products (40 parents with ~40 sub products),
-- ~240 product-specific conversions, 80 normal recipes with ~13 ingredients each and 2-level nestings, 60 days of
-- meal plan (~140 entries, which the app's triggers turn into ~190 day/week/shadow recipes), 5 years of stock
-- journal (~35k stock_log rows), ~1k current stock entries, 2 shopping lists, 40 chores with 4 years of log,
-- 15 batteries. _cfg.scale multiplies products, stock_log and chores_log; the recipe set and meal plan stay fixed
-- (on SQLite 3.53+ the recipes views grow roughly with recipes^2 x positions; scale 1 already takes 7-15 s).
-- Rows go in through the app's triggers (the meal plan trigger builds the day/week/shadow recipes), except the
-- nine per-row cache triggers listed below, which are dropped during the load and re-created verbatim.
BEGIN;

CREATE TEMP TABLE _s AS SELECT (SELECT scale FROM _cfg) AS s;

-- Triggers that re-evaluate a recursive view per inserted row (quantity_unit_conversions_resolved,
-- recipes_nestings_resolved, products_average_price/products_last_purchased) make a bulk load quadratic.
-- They are dropped here, the cache__ tables they maintain are filled once below with the triggers' own
-- statements for every row, and the triggers are re-created verbatim at the end. Every other trigger runs.
DROP TRIGGER products_INS;
DROP TRIGGER products_UPD;
DROP TRIGGER products_default_qu_conversions_INS;
DROP TRIGGER products_default_qu_conversions_UPD;
DROP TRIGGER recipes_pos_qu_id_default;
DROP TRIGGER prevent_infinite_nested_recipes_INS;
DROP TRIGGER stock_log_INS;
DROP TRIGGER stock_log_UPD;
DROP TRIGGER stock_log_DEL;

-- Seed rows the SQL migrations insert
INSERT INTO shopping_lists (id, name) VALUES (1, 'Shopping list'), (2, 'Party');
INSERT INTO meal_plan_sections (id, name, sort_number) VALUES (-1, '', -1);
INSERT INTO meal_plan_sections (name, sort_number, time_info) VALUES ('Breakfast', 1, '07:30'), ('Lunch', 2, '12:30'), ('Dinner', 3, '19:00');

INSERT INTO users (id, username, first_name, last_name, password) VALUES
  (1, 'admin', NULL, NULL, 'x'), (2, 'anna', 'Anna', 'Berg', 'x'), (3, 'ben', 'Ben', 'Berg', 'x'), (4, 'kid', 'Lea', NULL, 'x');

INSERT INTO quantity_units (id, name, name_plural) VALUES
  (1,'Piece','Pieces'),(2,'Pack','Packs'),(3,'Gram','Grams'),(4,'Kilogram','Kilograms'),(5,'Milliliter','Milliliters'),
  (6,'Liter','Liters'),(7,'Can','Cans'),(8,'Bottle','Bottles'),(9,'Jar','Jars'),(10,'Bag','Bags'),(11,'Box','Boxes'),
  (12,'Slice','Slices'),(13,'Teaspoon','Teaspoons'),(14,'Tablespoon','Tablespoons'),(15,'Cup','Cups'),(16,'Bunch','Bunches'),
  (17,'Clove','Cloves'),(18,'Pinch','Pinches'),(19,'Ounce','Ounces'),(20,'Pound','Pounds'),(21,'Pint','Pints'),
  (22,'Quart','Quarts'),(23,'Gallon','Gallons'),(24,'Dozen','Dozens'),(25,'Roll','Rolls'),(26,'Tube','Tubes'),
  (27,'Carton','Cartons'),(28,'Tray','Trays'),(29,'Sachet','Sachets'),(30,'Portion','Portions');

INSERT INTO locations (id, name, is_freezer) VALUES
  (1,'Fridge',0),(2,'Pantry',0),(3,'Freezer',1),(4,'Cellar',0),(5,'Spice rack',0),(6,'Bathroom',0),(7,'Garage freezer',1),
  (8,'Kitchen cupboard',0),(9,'Fruit bowl',0),(10,'Drinks shelf',0),(11,'Baking drawer',0),(12,'Kids snacks',0);
INSERT INTO product_groups (id, name) VALUES
  (1,'Dairy'),(2,'Meat'),(3,'Fish'),(4,'Vegetables'),(5,'Fruit'),(6,'Bakery'),(7,'Grains & pasta'),(8,'Canned'),
  (9,'Spices'),(10,'Drinks'),(11,'Snacks'),(12,'Frozen'),(13,'Household'),(14,'Baking'),(15,'Sauces');
INSERT INTO shopping_locations (id, name) VALUES
  (1,'Supermarket'),(2,'Discounter'),(3,'Farmers market'),(4,'Butcher'),(5,'Bakery'),(6,'Drugstore'),(7,'Online'),(8,'Wholesale');

-- Default (product_id NULL) conversions, chained so the recursive closure has work: kg>g, l>ml, tsp>ml, tbsp>tsp,
-- cup>ml, lb>oz, oz>g, pint>cup, quart>pint, gallon>quart, dozen>piece. The INS trigger adds each inverse.
INSERT INTO quantity_unit_conversions (from_qu_id, to_qu_id, factor) VALUES (4, 3, 1000);
INSERT INTO quantity_unit_conversions (from_qu_id, to_qu_id, factor) VALUES (6, 5, 1000);
INSERT INTO quantity_unit_conversions (from_qu_id, to_qu_id, factor) VALUES (13, 5, 5);
INSERT INTO quantity_unit_conversions (from_qu_id, to_qu_id, factor) VALUES (14, 13, 3);
INSERT INTO quantity_unit_conversions (from_qu_id, to_qu_id, factor) VALUES (15, 5, 240);
INSERT INTO quantity_unit_conversions (from_qu_id, to_qu_id, factor) VALUES (20, 19, 16);
INSERT INTO quantity_unit_conversions (from_qu_id, to_qu_id, factor) VALUES (19, 3, 28.35);
INSERT INTO quantity_unit_conversions (from_qu_id, to_qu_id, factor) VALUES (21, 15, 2);
INSERT INTO quantity_unit_conversions (from_qu_id, to_qu_id, factor) VALUES (22, 21, 2);
INSERT INTO quantity_unit_conversions (from_qu_id, to_qu_id, factor) VALUES (23, 22, 4);
INSERT INTO quantity_unit_conversions (from_qu_id, to_qu_id, factor) VALUES (24, 1, 12);

-- Product unit plan (by product id i):
--   i%4=0: stock Piece, purchase Pack (product conversion Pack>Piece)
--   i%7=0: stock Gram, purchase Piece (product conversion Piece>Gram)
--   i%5=0: stock Milliliter, purchase Liter (default conversion)
--   i%3=0: stock Gram, purchase Kilogram (default conversion)
--   else : Piece/Piece
CREATE TEMP TABLE _p AS
WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 600 * (SELECT s FROM _s))
SELECT i, (i * 2654435761) % 4294967296 AS h,
  CASE WHEN i%4=0 THEN 1 WHEN i%7=0 THEN 3 WHEN i%5=0 THEN 5 WHEN i%3=0 THEN 3 ELSE 1 END AS qs,
  CASE WHEN i%4=0 THEN 2 WHEN i%7=0 THEN 1 WHEN i%5=0 THEN 6 WHEN i%3=0 THEN 4 ELSE 1 END AS qp
FROM n;

-- Product-specific conversions first (no products yet, so each trigger's cache refresh stays small)
INSERT INTO quantity_unit_conversions (from_qu_id, to_qu_id, factor, product_id)
SELECT 2, 1, 4 + (h / 64) % 9, i FROM _p WHERE i % 4 = 0;
INSERT INTO quantity_unit_conversions (from_qu_id, to_qu_id, factor, product_id)
SELECT 1, 3, 50 + (h / 512) % 450, i FROM _p WHERE i % 7 = 0 AND i % 4 != 0;

-- Products: ids 1..40 are parents; every third id in 41..160 is a sub product of one of them
INSERT INTO products (id, name, description, product_group_id, active, location_id, shopping_location_id,
  qu_id_purchase, qu_id_stock, qu_id_consume, qu_id_price, min_stock_amount, default_best_before_days,
  default_best_before_days_after_open, parent_product_id, calories, cumulate_min_stock_amount_of_sub_products,
  due_type, quick_consume_amount, hide_on_stock_overview, treat_opened_as_out_of_stock, no_own_stock,
  default_consume_location_id)
SELECT i,
  (CASE (h / 16) % 15 WHEN 0 THEN 'Milk' WHEN 1 THEN 'Chicken' WHEN 2 THEN 'Salmon' WHEN 3 THEN 'Carrot' WHEN 4 THEN 'Apple'
     WHEN 5 THEN 'Bread' WHEN 6 THEN 'Pasta' WHEN 7 THEN 'Tomatoes' WHEN 8 THEN 'Paprika' WHEN 9 THEN 'Juice'
     WHEN 10 THEN 'Crisps' WHEN 11 THEN 'Peas' WHEN 12 THEN 'Dish soap' WHEN 13 THEN 'Flour' ELSE 'Pesto' END)
     || ' ' || i,
  CASE WHEN i % 6 = 0 THEN 'Brand ' || ((h / 4096) % 40) || ', bought regularly' END,
  1 + (h / 16) % 15,
  CASE WHEN i % 50 = 0 THEN 0 ELSE 1 END,
  1 + (h / 256) % 12,
  1 + (h / 8192) % 8,
  qp, qs, qs, qp,
  CASE WHEN i % 3 = 0 THEN 1 + (h / 65536) % 4 ELSE 0 END,
  CASE (h / 1048576) % 5 WHEN 0 THEN 3 WHEN 1 THEN 7 WHEN 2 THEN 14 WHEN 3 THEN 90 ELSE 365 END,
  CASE WHEN i % 2 = 0 THEN 3 ELSE 0 END,
  CASE WHEN i BETWEEN 41 AND 160 AND i % 3 = 0 THEN 1 + (i % 40) END,
  40 + (h / 2048) % 520,
  CASE WHEN i <= 40 AND i % 2 = 0 THEN 1 ELSE 0 END,
  CASE WHEN i % 10 = 0 THEN 2 ELSE 1 END,
  1,
  CASE WHEN i % 97 = 0 THEN 1 ELSE 0 END,
  1,
  CASE WHEN i % 151 = 0 THEN 1 ELSE 0 END,
  CASE WHEN i % 9 = 0 THEN 1 + (h / 256) % 12 END
FROM _p ORDER BY i;

DELETE FROM cache__quantity_unit_conversions_resolved;
INSERT INTO cache__quantity_unit_conversions_resolved
  (product_id, from_qu_id, from_qu_name, from_qu_name_plural, to_qu_id, to_qu_name, to_qu_name_plural, factor, path)
SELECT product_id, from_qu_id, from_qu_name, from_qu_name_plural, to_qu_id, to_qu_name, to_qu_name_plural, factor, path
FROM quantity_unit_conversions_resolved;

-- Fill cache__quantity_unit_conversions_resolved the way products_INS/products_UPD would, for every product
DELETE FROM cache__quantity_unit_conversions_resolved;
INSERT INTO cache__quantity_unit_conversions_resolved
  (product_id, from_qu_id, from_qu_name, from_qu_name_plural, to_qu_id, to_qu_name, to_qu_name_plural, factor, path)
SELECT product_id, from_qu_id, from_qu_name, from_qu_name_plural, to_qu_id, to_qu_name, to_qu_name_plural, factor, path
FROM quantity_unit_conversions_resolved;

INSERT INTO product_barcodes (product_id, barcode, amount, shopping_location_id)
SELECT i, printf('40%011d', (h % 99999999999)), 1, 1 + (h / 8192) % 8 FROM _p;
INSERT INTO product_barcodes (product_id, barcode, amount, shopping_location_id)
SELECT i, printf('50%011d', ((h / 3) % 99999999999)), 6, 8 FROM _p WHERE i % 5 = 0;

-- Stock journal: 5 years of purchases, skewed to ~80 staples (products 1..80 get about half of all purchases).
-- Purchase k has stock_id 'k<k>'; older purchases are consumed (some spoiled), the newest ~1.5k are still in stock.
CREATE TEMP TABLE _buy AS
WITH RECURSIVE n(k) AS (SELECT 1 UNION ALL SELECT k+1 FROM n WHERE k < 18000 * (SELECT s FROM _s))
SELECT k, h, pid, (SELECT qs FROM _p WHERE i = pid) AS qs,
  date('now', 'localtime', '-' || (1826 - (k * 1826) / (18000 * (SELECT s FROM _s))) || ' days') AS pdate
FROM (SELECT k, (k * 2654435761) % 4294967296 AS h,
        CASE WHEN ((k * 2654435761) % 4294967296) % 2 = 0 THEN 1 + (((k * 2654435761) % 4294967296) / 2) % 80
             ELSE 1 + (((k * 2654435761) % 4294967296) / 2) % (600 * (SELECT s FROM _s)) END AS pid
      FROM n)
WHERE pid % 151 != 0 AND pid % 50 != 0;

INSERT INTO stock_log (product_id, amount, best_before_date, purchased_date, stock_id, transaction_type, price,
  location_id, correlation_id, transaction_id, shopping_location_id, user_id, row_created_timestamp, note, undone)
SELECT pid,
  CASE qs WHEN 3 THEN 250 * (1 + (h / 64) % 4) WHEN 5 THEN 500 * (1 + (h / 64) % 3) ELSE 1 + (h / 64) % 4 END,
  date(pdate, '+' || (3 + (h / 1024) % 200) || ' days'),
  pdate, 'k' || k, CASE WHEN k % 97 = 0 THEN 'inventory-correction' ELSE 'purchase' END,
  CASE qs WHEN 3 THEN round(0.002 + ((h / 4096) % 30) / 1000.0, 4) WHEN 5 THEN round(0.001 + ((h / 4096) % 5) / 1000.0, 4)
          ELSE round(0.49 + ((h / 4096) % 1200) / 100.0, 2) END,
  1 + (h / 256) % 12, NULL, 't' || (k / 6), 1 + (h / 8192) % 8, 1 + (h / 131072) % 4,
  pdate || ' 1' || ((h / 32) % 10) || ':' || printf('%02d', (h / 8) % 60) || ':00',
  CASE WHEN k % 41 = 0 THEN 'on offer' END,
  CASE WHEN k % 211 = 0 THEN 1 ELSE 0 END
FROM _buy ORDER BY k;

-- Consumptions (and spoilage) of everything except the newest purchases
INSERT INTO stock_log (product_id, amount, best_before_date, purchased_date, used_date, spoiled, stock_id,
  transaction_type, price, location_id, recipe_id, transaction_id, user_id, row_created_timestamp, undone)
SELECT b.pid, -sl.amount, sl.best_before_date, sl.purchased_date,
  date(sl.purchased_date, '+' || (1 + (b.h / 2048) % 20) || ' days'),
  CASE WHEN b.k % 17 = 0 THEN 1 ELSE 0 END, sl.stock_id, 'consume', sl.price, sl.location_id,
  CASE WHEN b.k % 3 = 0 THEN 1 + (b.h / 4096) % 200 END, 'c' || b.k, 1 + (b.h / 524288) % 4,
  date(sl.purchased_date, '+' || (1 + (b.h / 2048) % 20) || ' days') || ' 18:30:00', 0
FROM _buy b JOIN stock_log sl ON sl.stock_id = 'k' || b.k AND sl.transaction_type IN ('purchase', 'inventory-correction')
WHERE sl.undone = 0 AND (b.k <= 18000 * (SELECT s FROM _s) - 1500 OR b.k % 3 = 0)
ORDER BY b.k;

-- Opened entries and manual stock edits (stock-edit-old / stock-edit-new) for ~1 % of recent purchases
INSERT INTO stock_log (product_id, amount, best_before_date, purchased_date, stock_id, transaction_type, price,
  location_id, opened_date, user_id, row_created_timestamp)
SELECT product_id, amount, best_before_date, purchased_date, stock_id, 'product-opened', price, location_id,
  date(purchased_date, '+2 days'), user_id, date(purchased_date, '+2 days') || ' 08:00:00'
FROM stock_log WHERE transaction_type = 'purchase' AND id % 5 = 0
  AND stock_id NOT IN (SELECT stock_id FROM stock_log WHERE transaction_type = 'consume');
INSERT INTO stock_log (product_id, amount, best_before_date, purchased_date, stock_id, transaction_type, price,
  location_id, correlation_id, user_id, row_created_timestamp)
SELECT product_id, amount, best_before_date, purchased_date, stock_id, 'stock-edit-old', price, location_id,
  'e' || id, user_id, purchased_date || ' 21:00:00'
FROM stock_log WHERE transaction_type = 'purchase' AND id % 89 = 0;
INSERT INTO stock_log (product_id, amount, best_before_date, purchased_date, stock_id, transaction_type, price,
  location_id, correlation_id, user_id, row_created_timestamp)
SELECT product_id, amount * 2, date(best_before_date, '+10 days'), purchased_date, stock_id, 'stock-edit-new',
  round(price * 0.9, 4), location_id, correlation_id, user_id, purchased_date || ' 21:00:01'
FROM stock_log WHERE transaction_type = 'stock-edit-old';

-- Current stock = purchases without a consume row
INSERT INTO stock (product_id, amount, best_before_date, purchased_date, stock_id, price, open, opened_date,
  location_id, shopping_location_id, note, row_created_timestamp)
SELECT sl.product_id, sl.amount, sl.best_before_date, sl.purchased_date, sl.stock_id, sl.price,
  CASE WHEN o.id IS NOT NULL THEN 1 ELSE 0 END, o.opened_date, sl.location_id, sl.shopping_location_id, sl.note,
  sl.row_created_timestamp
FROM stock_log sl
LEFT JOIN stock_log o ON o.stock_id = sl.stock_id AND o.transaction_type = 'product-opened'
WHERE sl.transaction_type IN ('purchase', 'inventory-correction') AND sl.undone = 0
  AND sl.stock_id NOT IN (SELECT stock_id FROM stock_log WHERE transaction_type = 'consume')
ORDER BY sl.id;

-- Fill the caches the dropped triggers maintain, with the triggers' own statements for every product
INSERT OR REPLACE INTO cache__products_average_price (product_id, price)
SELECT product_id, price FROM products_average_price;
INSERT OR REPLACE INTO cache__products_last_purchased
  (product_id, amount, best_before_date, purchased_date, price, location_id, shopping_location_id)
SELECT product_id, amount, best_before_date, purchased_date, price, location_id, shopping_location_id
FROM products_last_purchased;

-- Recipes: ids 1..30 are bases (sauces, doughs), 31..60 include a base, every 5th later recipe includes a 31..60 one
INSERT INTO recipes (id, name, description, base_servings, desired_servings, not_check_shoppinglist, type, product_id)
WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 80)
SELECT i,
  (CASE (i * 7) % 12 WHEN 0 THEN 'Lasagne' WHEN 1 THEN 'Curry' WHEN 2 THEN 'Soup' WHEN 3 THEN 'Salad' WHEN 4 THEN 'Risotto'
     WHEN 5 THEN 'Stew' WHEN 6 THEN 'Pancakes' WHEN 7 THEN 'Chili' WHEN 8 THEN 'Pie' WHEN 9 THEN 'Bowl' WHEN 10 THEN 'Sauce'
     ELSE 'Bake' END) || ' #' || i,
  '<p>Step 1: prepare. Step 2: cook for ' || (10 + i % 50) || ' minutes.</p>',
  1 + ((i * 2654435761) % 4294967296 / 16) % 6,
  CASE WHEN i % 3 = 0 THEN 4 ELSE 1 + ((i * 2654435761) % 4294967296 / 16) % 6 END,
  CASE WHEN i % 11 = 0 THEN 1 ELSE 0 END, 'normal',
  CASE WHEN i <= 30 AND i % 3 = 0 THEN 100 + i END
FROM n;

INSERT INTO recipes_pos (recipe_id, product_id, amount, note, qu_id, only_check_single_unit_in_stock, ingredient_group,
  not_check_stock_fulfillment, variable_amount, price_factor, round_up)
SELECT r, pid,
  CASE p.qs WHEN 3 THEN 50 * (1 + (x.h / 64) % 8) WHEN 5 THEN 100 * (1 + (x.h / 64) % 5) ELSE 1 + (x.h / 64) % 3 END,
  CASE WHEN x.h % 13 = 0 THEN 'finely chopped' END, p.qs,
  CASE WHEN x.h % 19 = 0 THEN 1 ELSE 0 END,
  CASE WHEN j > 8 THEN 'Topping' WHEN j > 4 THEN 'Sauce' END,
  CASE WHEN x.h % 10 = 0 THEN 1 ELSE 0 END,
  CASE WHEN x.h % 23 = 0 THEN 'to taste' END, 1.0,
  CASE WHEN x.h % 31 = 0 THEN 1 ELSE 0 END
FROM (
  WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 80 * 20)
  SELECT 1 + (i - 1) / 20 AS r, 1 + (i - 1) % 20 AS j, (i * 2654435761) % 4294967296 AS h,
    CASE WHEN ((i * 2654435761) % 4294967296) % 5 < 3 THEN 1 + (((i * 2654435761) % 4294967296) / 8) % 80
         ELSE 1 + (((i * 2654435761) % 4294967296) / 8) % (600 * (SELECT s FROM _s)) END AS pid
  FROM n) x
JOIN _p p ON p.i = x.pid
WHERE j <= 6 + (((r * 2246822519) % 4294967296) / 4) % 14 AND pid % 50 != 0
ORDER BY r, j;

INSERT INTO recipes_nestings (recipe_id, includes_recipe_id, servings)
WITH RECURSIVE n(i) AS (SELECT 31 UNION ALL SELECT i+1 FROM n WHERE i < 80)
SELECT i, CASE WHEN i <= 60 THEN 1 + (i * 7) % 30 ELSE 31 + (i * 13) % 30 END, 1 + i % 3
FROM n WHERE i <= 60 OR i % 5 = 0;
INSERT INTO recipes_nestings (recipe_id, includes_recipe_id, servings)
WITH RECURSIVE n(i) AS (SELECT 61 UNION ALL SELECT i+1 FROM n WHERE i < 80)
SELECT i, 1 + (i * 11) % 30, 1 FROM n WHERE i % 5 = 0 AND i % 2 = 0;

-- Meal plan: 180 days back to 30 days ahead, lunch + dinner recipes, some product and note entries.
-- Each insert runs the app's create_internal_recipe trigger (day/week/shadow recipes and their nestings).
INSERT INTO meal_plan (day, type, recipe_id, recipe_servings, note, product_id, product_amount, product_qu_id, done, section_id)
WITH RECURSIVE d(i) AS (SELECT -45 UNION ALL SELECT i+1 FROM d WHERE i < 14),
slot(k, sec) AS (VALUES (0, 2), (1, 3), (2, 1), (3, 3))
SELECT date('now', 'localtime', i || ' days'),
  CASE WHEN k < 2 THEN 'recipe' WHEN k = 2 THEN 'product' ELSE 'note' END,
  CASE WHEN k < 2 THEN 31 + ((i + 200) * 2654435761 + k * 977) % 4294967296 % 50 END,
  CASE WHEN k < 2 THEN 2 + (i + 200) % 3 END,
  CASE WHEN k = 3 THEN 'Leftovers' END,
  CASE WHEN k = 2 THEN 1 + ((i + 200) * 40503) % 80 END,
  CASE WHEN k = 2 THEN 1 END,
  CASE WHEN k = 2 THEN (SELECT qs FROM _p WHERE _p.i = 1 + ((d.i + 200) * 40503) % 80) END,
  CASE WHEN i < 0 THEN 1 ELSE 0 END, sec
FROM d, slot
WHERE k < 2 OR (k = 2 AND (i + 200) % 5 = 0) OR (k = 3 AND (i + 200) % 7 = 0)
ORDER BY i, k;

-- Shopping lists
INSERT INTO shopping_list (product_id, note, amount, shopping_list_id, done, qu_id)
SELECT i, CASE WHEN i % 9 = 0 THEN 'the organic one' END, 1 + (h / 64) % 3, CASE WHEN i % 11 = 0 THEN 2 ELSE 1 END,
  CASE WHEN i % 13 = 0 THEN 1 ELSE 0 END, qs
FROM _p WHERE (h / 32) % 8 = 0 AND i % 50 != 0;
INSERT INTO shopping_list (note, amount, shopping_list_id) VALUES ('Birthday candles', 1, 2), ('Ice', 2, 2);

-- Chores (40 x scale) with ~4 years of history, batteries with charge cycles
INSERT INTO chores (id, name, description, period_type, period_days, period_config, track_date_only, rollover,
  assignment_type, assignment_config, next_execution_assigned_to_user_id, period_interval, active, start_date)
WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 40 * (SELECT s FROM _s))
SELECT i, 'Chore ' || i, NULL,
  CASE i % 6 WHEN 0 THEN 'daily' WHEN 1 THEN 'weekly' WHEN 2 THEN 'monthly' WHEN 3 THEN 'adaptive'
             WHEN 4 THEN 'yearly' ELSE 'manually' END,
  CASE WHEN i % 6 = 2 THEN 1 + i % 28 END,
  CASE WHEN i % 6 = 1 THEN 'monday,thursday' END,
  i % 2, CASE WHEN i % 5 = 0 THEN 1 ELSE 0 END,
  CASE WHEN i % 3 = 0 THEN 'who-least-did-first' ELSE 'in-alphabetical-order' END, '1,2,3', 1 + i % 3,
  1 + i % 2, CASE WHEN i % 23 = 0 THEN 0 ELSE 1 END,
  datetime('now', 'localtime', '-1500 days', '+' || (i % 24) || ' hours')
FROM n;

INSERT INTO chores_log (chore_id, tracked_time, done_by_user_id, undone, skipped, scheduled_execution_time, row_created_timestamp)
WITH RECURSIVE n(k) AS (SELECT 1 UNION ALL SELECT k+1 FROM n WHERE k < 9000 * (SELECT s FROM _s))
SELECT c, t, 1 + (h / 64) % 3, CASE WHEN k % 101 = 0 THEN 1 ELSE 0 END, CASE WHEN k % 37 = 0 THEN 1 ELSE 0 END, t, t
FROM (SELECT k, (k * 2654435761) % 4294967296 AS h,
        CASE WHEN k % 3 = 0 THEN 1 + (k / 3) % 7 ELSE 1 + ((k * 2654435761) % 4294967296) % (40 * (SELECT s FROM _s)) END AS c,
        datetime('now', 'localtime', '-' || (1460 - (k * 1460) / (9000 * (SELECT s FROM _s))) || ' days', '+' || (k % 16) || ' hours') AS t
      FROM n);

INSERT INTO batteries (id, name, description, used_in, charge_interval_days, active)
WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 15)
SELECT i, 'Battery ' || i, 'AA rechargeable', CASE i % 3 WHEN 0 THEN 'Remote' WHEN 1 THEN 'Smoke alarm' ELSE 'Camera' END,
  CASE WHEN i % 4 = 0 THEN 0 ELSE 30 * (1 + i % 4) END, 1 FROM n;
INSERT INTO battery_charge_cycles (battery_id, tracked_time, undone)
WITH RECURSIVE n(k) AS (SELECT 1 UNION ALL SELECT k+1 FROM n WHERE k < 900)
SELECT 1 + k % 15, datetime('now', 'localtime', '-' || (1460 - k * 1460 / 900) || ' days'), CASE WHEN k % 53 = 0 THEN 1 ELSE 0 END FROM n;

INSERT INTO tasks (name, description, due_date, done, category_id, assigned_to_user_id)
WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i < 80)
SELECT 'Task ' || i, NULL, date('now', 'localtime', (i - 40) || ' days'), CASE WHEN i % 3 = 0 THEN 1 ELSE 0 END, NULL, 1 + i % 3 FROM n;

INSERT INTO user_settings (user_id, key, value) VALUES
  (1, 'stock_due_soon_days', '5'), (1, 'stock_overview_show_all_out_of_stock_products', '0'), (1, 'chores_due_soon_days', '5');

-- Re-create the dropped triggers (verbatim from the schema)
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
CREATE TRIGGER prevent_infinite_nested_recipes_INS BEFORE INSERT ON recipes_nestings
BEGIN
    SELECT CASE WHEN((
        SELECT 1
        FROM recipes_nestings_resolved rnr
        WHERE NEW.recipe_id = rnr.includes_recipe_id
            AND NEW.includes_recipe_id = rnr.recipe_id
    ) NOTNULL) THEN RAISE(ABORT, 'Recursive nested recipe detected') END;
END;
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

DROP TABLE _p;
DROP TABLE _buy;
COMMIT;
