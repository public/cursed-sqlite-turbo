-- Grocy (grocy/grocy @ 41206cb, MIT). Nearly all logic lives in SQL views (schema.sql); pages query them through
-- LessQL (berrnd/lessql fork @ bab1170), which emits SELECT * FROM `view` WHERE (cond) [ORDER BY `col` dir] with
-- backtick identifiers, inlines where('col', v) values quoted as strings ('65'), and binds where('... :1', v)
-- arguments as PDO strings (bound here as text literals too). Raw SQL from services goes through PDO unchanged.
-- Values the app inlines that depend on today (meal plan start, report ranges) are bound as ?N computed from
-- 'now', so the windows follow the data (which is also relative to now).

-- @id grocy.recipes.overview_resolved
-- @src controllers/RecipesController.php:86
-- @style LessQL where() string; RecipesService::GetRecipesResolved('recipe_id > 0') (services/RecipesService.php:148)
-- @tags hotpath,analytics,cpu-evidence
-- @note /recipes list with fulfilment, costs and calories per recipe: GROUP BY over recipes_pos_resolved (nested-recipe recursive CTE x stock_current x price views, top-level UNION). https://github.com/grocy/grocy/issues/2992 measured 15.7 s on SQLite 3.53 vs 0.3 s on 3.45 (the 3.53 sort-and-merge UNION); /recipes and /mealplan took 10-15 s
SELECT * FROM `recipes_resolved` WHERE (recipe_id > 0);

-- @id grocy.recipes.pos_resolved_all
-- @src services/RecipesService.php:134-138
-- @style raw PDO, no parameters
-- @tags analytics,cpu-evidence
-- @note GetRecipesPosResolved(): every resolved ingredient of every recipe (AddNotFulfilledProductsToShoppingList, recipe API). https://github.com/grocy/grocy/issues/2995: 6.4 s on 3.53 vs 0.13 s with UNION ALL; the two UNION arms are disjoint (not_check_stock_fulfillment = 0 / 1)
SELECT * FROM recipes_pos_resolved;

-- @id grocy.recipes.selected_positions
-- @src controllers/RecipesController.php:113
-- @style LessQL where('recipe_id', $id): shortcut form, value inlined and quoted
-- @tags hotpath,cpu-evidence
-- @note Positions of the selected recipe (recipe 65 includes a sub recipe which includes a base). Same view as https://github.com/grocy/grocy/issues/2995; the recipe_id filter has to be pushed through the UNION into both arms
SELECT * FROM `recipes_pos_resolved` WHERE (`recipe_id` = '65');

-- @id grocy.recipes.positions_not_nested
-- @src controllers/RecipesController.php:141
-- @style LessQL where('recipe_id = :1 AND is_nested_recipe_pos = 0', $id) with PDO string bind; orderBy twice
-- @tags hotpath,dynamic
-- @note Per included recipe on the recipe page: own (not nested) positions grouped for display
-- @param :1 '65'
SELECT * FROM `recipes_pos_resolved` WHERE (recipe_id = :1 AND is_nested_recipe_pos = 0) ORDER BY `ingredient_group` ASC, `product_group` ASC;

-- @id grocy.recipes.subrecipes
-- @src controllers/RecipesController.php:127
-- @style LessQL where() with :1 bound twice (PDO string), orderBy('name', 'COLLATE NOCASE')
-- @tags hotpath,cpu-evidence
-- @note IN over the recursive recipes_nestings_resolved view; https://github.com/grocy/grocy/issues/2591 found the planner materialising this CTE instead of pushing recipe_id down (0.9 s per evaluation on 4k nestings)
-- @param :1 '65'
SELECT * FROM `recipes` WHERE (id IN (SELECT includes_recipe_id FROM recipes_nestings_resolved WHERE recipe_id = :1 AND includes_recipe_id != :1)) ORDER BY `name` COLLATE NOCASE;

-- @id grocy.recipes.resolved_one
-- @src services/RecipesService.php:129
-- @style LessQL where('recipe_id = :1', $id)->fetch()
-- @tags cpu-evidence
-- @note Consume-recipe path: one recipe's resolved row; the GROUP BY r.id view must be filtered before aggregating. View from https://github.com/grocy/grocy/issues/2992
-- @param :1 '65'
SELECT * FROM `recipes_resolved` WHERE (recipe_id = :1);

-- @id grocy.mealplan.recipes_resolved_week
-- @src controllers/RecipesController.php:73
-- @style LessQL where() string built in PHP; $start (today) and $weekRecipeId inlined by the app, bound here as ?1/?2
-- @tags hotpath,analytics,dynamic,cpu-evidence
-- @note /mealplan: fulfilment of the internal day/week recipes in the 13-day window; IN over the 3-way UNION view meal_plan_internal_recipe_relation, OR'd with the week recipe. https://github.com/grocy/grocy/issues/2992 (/mealplan 10-15 s on 3.53)
-- @param ?1 date('now', 'localtime')
-- @param ?2 (SELECT id FROM recipes WHERE type = 'mealplan-week' AND name = LTRIM(STRFTIME('%Y-%W', DATE('now', 'localtime')), '0'))
SELECT * FROM `recipes_resolved` WHERE (recipe_id IN (SELECT recipe_id FROM meal_plan_internal_recipe_relation WHERE day BETWEEN DATE(?1, '-6 days') AND DATE(?1, '+6 days')) OR recipe_id = ?2);

-- @id grocy.mealplan.internal_recipes
-- @src controllers/RecipesController.php:72
-- @style LessQL where() string; $start and $weekRecipeId inlined by the app, bound here as ?1/?2
-- @tags hotpath,dynamic
-- @note Internal recipes of the visible window: IN over the UNION view plus an OR'd id
-- @param ?1 date('now', 'localtime')
-- @param ?2 (SELECT id FROM recipes WHERE type = 'mealplan-week' AND name = LTRIM(STRFTIME('%Y-%W', DATE('now', 'localtime')), '0'))
SELECT * FROM `recipes` WHERE (id IN (SELECT recipe_id FROM meal_plan_internal_recipe_relation WHERE day BETWEEN DATE(?1, '-6 days') AND DATE(?1, '+6 days')) OR id = ?2);

-- @id grocy.mealplan.entries
-- @src controllers/RecipesController.php:34
-- @style LessQL where() string; $start inlined by the app, bound here as ?1
-- @tags hotpath,hot-small,dynamic
-- @note Meal plan entries of the visible 13 days (no index on day: a short scan)
-- @param ?1 date('now', 'localtime')
SELECT * FROM `meal_plan` WHERE (day BETWEEN DATE(?1, '-6 days') AND DATE(?1, '+6 days'));

-- @id grocy.mealplan.add_entry
-- @src controllers/Api/GenericEntityApiController.php:53-54
-- @style LessQL createRow()->save(): insertDefault, values inlined and quoted
-- @tags cpu-evidence
-- @note Adding a recipe to today's meal plan runs create_internal_recipe: rebuilds the day/week recipes and their nestings, each nesting insert running prevent_infinite_nested_recipes_INS over the recursive recipes_nestings_resolved. https://github.com/grocy/grocy/issues/2591 (inserts timing out once a week has ~10 entries)
INSERT INTO `meal_plan` (`day`, `type`, `recipe_id`, `recipe_servings`, `section_id`) VALUES (date('now', 'localtime'), 'recipe', '72', '2', '3');

-- @id grocy.stock.overview
-- @src controllers/StockController.php:154
-- @style LessQL where($where) string, default setting (stock_overview_show_all_out_of_stock_products = 0)
-- @tags hotpath,analytics,cpu-evidence
-- @note Stock overview page: 3-way UNION of stock_current (itself a UNION of two GROUP BYs with correlated sums) and stock_missing_products, joined to products_view, 4 QU joins, caches and barcodes. https://github.com/grocy/grocy/issues/2591 reported >60 s on SQLite 3.46.1 from a bad join order with 917 products
SELECT * FROM `uihelper_stock_current_overview` WHERE (is_in_stock_or_below_min_stock = 1);

-- @id grocy.stock.current_locations
-- @src services/StockService.php:719-723
-- @style raw PDO
-- @tags hotpath,analytics
-- @note Stock overview / location filter: amount per product and location
SELECT * FROM stock_current_locations;

-- @id grocy.stock.missing_products
-- @src services/StockService.php:742-746
-- @style raw PDO
-- @tags hotpath,analytics
-- @note Below-min-stock products (shopping list page, overview): 3-way UNION of GROUP BYs over products_view and stock_current
SELECT * FROM stock_missing_products;

-- @id grocy.stock.due_products
-- @src services/StockService.php:693-694
-- @style raw PDO; GetDueProducts(5, true) suffix from services/StockService.php:729
-- @tags hotpath,dynamic
-- @note Due-soon widget / API: filter on the aggregated stock_current view
SELECT * FROM stock_current WHERE best_before_date <= date('now', '5 days') AND best_before_date >= date();

-- @id grocy.stock.due_products_rows
-- @src services/StockService.php:695
-- @style LessQL where() wrapping the raw statement as a derived table
-- @tags hotpath,dynamic
-- @note The matching product rows: IN over a derived table over the UNION view
SELECT * FROM `products` WHERE (id IN (SELECT product_id FROM (SELECT * FROM stock_current WHERE best_before_date <= date('now', '5 days') AND best_before_date >= date()) x));

-- @id grocy.stock.location_content
-- @src services/StockService.php:707-716
-- @style raw PDO; $leftJoin = '' (default)
-- @tags analytics
-- @note Location content sheet: GROUP BY with a correlated opened-amount sum per group
SELECT IFNULL(sclc.location_id, p.location_id) AS location_id, p.id AS product_id, IFNULL(sclc.amount, 0) AS amount, IFNULL(sclc.amount_opened, 0) AS amount_opened FROM products p  JOIN stock_current_location_content sclc ON sclc.product_id = p.id WHERE p.active = 1 ORDER BY p.name;

-- @id grocy.stock.journal
-- @src controllers/StockController.php:62-84
-- @style LessQL where($where) string (default 6 months), orderBy('row_created_timestamp', 'DESC')
-- @tags hotpath
-- @note Stock journal page: 6 months of stock_log joined to users_dto, products, locations, QUs, newest first (no index on row_created_timestamp)
SELECT * FROM `uihelper_stock_journal` WHERE (row_created_timestamp > DATE(DATE('now', 'localtime'), '-6 months')) ORDER BY `row_created_timestamp` DESC;

-- @id grocy.stock.journal_summary
-- @src controllers/StockController.php:606
-- @style LessQL, no filter
-- @tags analytics
-- @note Journal summary: SUM(amount) over all of stock_log grouped by user, product and transaction type
SELECT * FROM `uihelper_stock_journal_summary`;

-- @id grocy.stock.product_details
-- @src services/StockService.php:774
-- @style LessQL where('id', $productId): shortcut form, value inlined and quoted
-- @tags hotpath,cpu-evidence
-- @note Product card / purchase page: caches, shelf life, products_current_price (ROW_NUMBER window over all stock via stock_next_use), and three GROUP BY subqueries over all of stock_log. https://github.com/grocy/grocy/issues/2283: /stock/products/{id} up to 10x slower in v4.0.0 because of products_current_price
SELECT * FROM `uihelper_product_details` WHERE (`id` = '12');

-- @id grocy.stock.price_history
-- @src services/StockService.php:853
-- @style LessQL where('product_id = :1', $id) with PDO string bind, orderBy('purchased_date', 'DESC')
-- @tags analytics
-- @note Price history chart: stock_log LEFT JOIN stock_edited_entries (self-join GROUP BY) with NOT IN / IN subqueries over the same view
-- @param :1 '12'
SELECT * FROM `products_price_history` WHERE (product_id = :1) ORDER BY `purchased_date` DESC;

-- @id grocy.reports.spendings_by_product
-- @src controllers/StockReportsController.php:13-60
-- @style raw PDO; $where built in PHP (default range: this month)
-- @tags analytics,dynamic
-- @note Spendings report grouped by product: products_price_history over the whole journal, then a date filter
SELECT p.id AS id, p.name AS name, pg.id AS group_id, pg.name AS group_name, SUM(pph.amount * pph.price) AS total FROM products_price_history pph JOIN products p ON pph.product_id = p.id LEFT JOIN product_groups pg ON p.product_group_id = pg.id WHERE pph.transaction_type != 'self-production' AND pph.purchased_date >= DATE(DATE('now', 'localtime'), 'start of month') GROUP BY p.id, p.name, pg.id, pg.name ORDER BY p.name COLLATE NOCASE;

-- @id grocy.reports.spendings_by_group
-- @src controllers/StockReportsController.php:62-78
-- @style raw PDO; start_date/end_date inlined by the app (last 12 months), bound here as ?1/?2
-- @tags analytics,dynamic
-- @note Spendings per product group over a year
-- @param ?1 date('now', 'localtime', '-12 months')
-- @param ?2 date('now', 'localtime')
SELECT pg.id AS id, pg.name AS name, SUM(pph.amount * pph.price) AS total FROM products_price_history pph JOIN products p ON pph.product_id = p.id LEFT JOIN product_groups pg ON p.product_group_id = pg.id WHERE pph.transaction_type != 'self-production' AND pph.purchased_date BETWEEN ?1 AND ?2 GROUP BY pg.id, pg.name ORDER BY pg.name COLLATE NOCASE;

-- @id grocy.reports.spendings_by_store
-- @src controllers/StockReportsController.php:79-95
-- @style raw PDO; start_date/end_date inlined by the app (5 years), bound here as ?1/?2
-- @tags analytics,dynamic
-- @note Spendings per store over the whole journal
-- @param ?1 date('now', 'localtime', '-5 years')
-- @param ?2 date('now', 'localtime')
SELECT sl.id AS id, sl.name AS name, SUM(pph.amount * pph.price) AS total FROM products_price_history pph JOIN products p ON pph.product_id = p.id LEFT JOIN shopping_locations sl ON pph.shopping_location_id = sl.id WHERE pph.transaction_type != 'self-production' AND pph.purchased_date BETWEEN ?1 AND ?2 GROUP BY sl.id, sl.name ORDER BY sl.NAME COLLATE NOCASE;

-- @id grocy.stock.purchase_log_insert
-- @src services/StockService.php:249-263
-- @style LessQL createRow()->save(): insertDefault, values inlined and quoted
-- @tags hotpath
-- @note A purchase: the stock_log_INS trigger recomputes products_average_price and products_last_purchased for the product (both scan stock_log through stock_edited_entries)
INSERT INTO `stock_log` (`product_id`, `amount`, `best_before_date`, `purchased_date`, `stock_id`, `transaction_type`, `price`, `location_id`, `transaction_id`, `shopping_location_id`, `user_id`, `note`) VALUES ('12', '2', '2026-11-20', '2026-10-30', '6720f1a3b9c4e', 'purchase', '2.49', '1', '6720f1a3b9c51', '1', '1', NULL);

-- @id grocy.shoppinglist.items
-- @src controllers/StockController.php:429
-- @style LessQL where('shopping_list_id = :1', $listId) with PDO string bind, orderBy('product_name', 'COLLATE NOCASE')
-- @tags hotpath
-- @note Shopping list page: list items with last price, QU conversion, barcodes (GROUP_CONCAT view)
-- @param :1 '1'
SELECT * FROM `uihelper_shopping_list` WHERE (shopping_list_id = :1) ORDER BY `product_name` COLLATE NOCASE;

-- @id grocy.chores.current
-- @src services/ChoresService.php:147
-- @style LessQL, no filter
-- @tags hotpath,analytics
-- @note Chores overview: GROUP BY over 4 years of chores_log, per-period CASE with a 7-way correlated UNION for weekly chores and the adaptive average-frequency view
SELECT * FROM `chores_current`;

-- @id grocy.chores.user_stats
-- @src services/ChoresService.php:91
-- @style LessQL where('chore_id = :1', $id)->orderBy('execution_count')->limit(1)
-- @tags analytics
-- @note "Who least did first" assignment: correlated COUNT per user over a LIKE-joined assignment view
-- @param :1 '3'
SELECT * FROM `chores_execution_users_statistics` WHERE (chore_id = :1) ORDER BY `execution_count` ASC LIMIT 1;

-- @id grocy.chores.last_tracked
-- @src services/ChoresService.php:115
-- @style LessQL where(...)->max('tracked_time')
-- @tags hot-small
-- @note Chore details: index range on ix_chores_log_performance1
-- @param :1 '3'
SELECT MAX(tracked_time) FROM `chores_log` WHERE (chore_id = :1 AND undone = 0 AND skipped = 0);

-- @id grocy.batteries.current
-- @src services/BatteriesService.php:30
-- @style LessQL, no filter
-- @tags hotpath,analytics
-- @note Batteries overview: last charge per battery
SELECT * FROM `batteries_current`;

-- @id grocy.qu.conversion_lookup
-- @src services/RecipesService.php:42
-- @style LessQL where('product_id = :1 AND from_qu_id = :2 AND to_qu_id = :3', ...)->fetch()
-- @tags hot-small
-- @note Point lookup on the conversion cache index, done per recipe position
-- @param :1 '12'
-- @param :2 '2'
-- @param :3 '1'
SELECT * FROM `cache__quantity_unit_conversions_resolved` WHERE (product_id = :1 AND from_qu_id = :2 AND to_qu_id = :3);
