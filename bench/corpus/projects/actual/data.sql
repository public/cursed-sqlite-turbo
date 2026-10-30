-- Synthetic data for an Actual Budget file. Deterministic (no random()): values come from multiplicative hashes of
-- the row number. "Today" is 2026-10-30; history starts 2018-11-01 (8 years). Dates are INTEGER yyyymmdd, amounts
-- integer cents, ids uuid-shaped text, as Actual stores them.
-- Scale 1: 14 accounts (9 on-budget, 5 off-budget, 2 closed), 10 category groups / 80 categories (5 income),
-- 150 payees + 20 merged (tombstoned) payees + 14 transfer payees, ~60k transactions: 57k plain rows, 1.1k split
-- parents with 2-3 children each, 900 transfer pairs, 14 starting balances; ~1 % tombstoned. Density grows towards
-- today; two credit cards and the checking account hold ~75 % of rows; payee use is Zipf-like.
-- 97 months x 75 expense categories of zero_budgets (7.3k) and the same in reflect_budgets, 120 rules.
-- _cfg.scale multiplies the transaction counts (same 8-year span, denser).
BEGIN;

CREATE TEMP TABLE _acc(k INTEGER PRIMARY KEY, id TEXT, name TEXT, offbudget INT, closed INT, lo INT, hi INT);
-- lo/hi: share of plain transactions (per mille) assigned to the account
INSERT INTO _acc VALUES
 (1,'a1c0ffee-0001-4a11-8a11-c4ec0000a001','Checking',0,0,0,300),
 (2,'a1c0ffee-0002-4a11-8a11-c4ec0000a002','Visa Rewards',0,0,300,640),
 (3,'a1c0ffee-0003-4a11-8a11-c4ec0000a003','Amex Gold',0,0,640,760),
 (4,'a1c0ffee-0004-4a11-8a11-c4ec0000a004','Joint Checking',0,0,760,840),
 (5,'a1c0ffee-0005-4a11-8a11-c4ec0000a005','Cash',0,0,840,880),
 (6,'a1c0ffee-0006-4a11-8a11-c4ec0000a006','PayPal',0,0,880,920),
 (7,'a1c0ffee-0007-4a11-8a11-c4ec0000a007','Savings',0,0,920,940),
 (8,'a1c0ffee-0008-4a11-8a11-c4ec0000a008','Old Checking',0,1,940,960),
 (9,'a1c0ffee-0009-4a11-8a11-c4ec0000a009','HSA',0,0,960,975),
 (10,'a1c0ffee-0010-4a11-8a11-c4ec0000a010','401k',1,0,975,983),
 (11,'a1c0ffee-0011-4a11-8a11-c4ec0000a011','Brokerage',1,0,983,991),
 (12,'a1c0ffee-0012-4a11-8a11-c4ec0000a012','Mortgage',1,0,991,997),
 (13,'a1c0ffee-0013-4a11-8a11-c4ec0000a013','Car Loan',1,1,997,999),
 (14,'a1c0ffee-0014-4a11-8a11-c4ec0000a014','House',1,0,999,1000);

INSERT INTO accounts(id, account_id, name, balance_current, mask, official_name, subtype, bank, offbudget, closed,
                     tombstone, sort_order, type, account_sync_source, last_sync, last_reconciled, account_group_id)
SELECT id, CASE WHEN k IN (1,2,3) THEN 'ext-' || k END, name, NULL, CASE WHEN k IN (1,2,3) THEN printf('%04d', k*1111) END,
       NULL, NULL, NULL, offbudget, closed, 0, k * 16384.0, NULL,
       CASE WHEN k IN (1,2,3) THEN 'simpleFin' END, CASE WHEN k IN (1,2,3) THEN '1793300000000' END,
       CASE WHEN k IN (1,2) THEN '1792000000000' END, NULL
FROM _acc;

CREATE TEMP TABLE _grp(k INTEGER PRIMARY KEY, id TEXT, name TEXT, is_income INT);
INSERT INTO _grp VALUES
 (1,'9a000001-c0de-4c0d-8c0d-00000000c001','Housing',0),(2,'9a000002-c0de-4c0d-8c0d-00000000c002','Food',0),
 (3,'9a000003-c0de-4c0d-8c0d-00000000c003','Transportation',0),(4,'9a000004-c0de-4c0d-8c0d-00000000c004','Bills',0),
 (5,'9a000005-c0de-4c0d-8c0d-00000000c005','Personal',0),(6,'9a000006-c0de-4c0d-8c0d-00000000c006','Kids',0),
 (7,'9a000007-c0de-4c0d-8c0d-00000000c007','Health',0),(8,'9a000008-c0de-4c0d-8c0d-00000000c008','Fun',0),
 (9,'9a000009-c0de-4c0d-8c0d-00000000c009','Savings Goals',0),(10,'9a000010-c0de-4c0d-8c0d-00000000c010','Income',1);
INSERT INTO category_groups(id, name, is_income, sort_order, tombstone, hidden)
SELECT id, name, is_income, k * 16384.0, 0, CASE WHEN k = 9 THEN 1 ELSE 0 END FROM _grp;

-- 75 expense categories (k 1..75; low k = the most used) and 5 income categories (k 76..80)
CREATE TEMP TABLE _cat(k INTEGER PRIMARY KEY, id TEXT, name TEXT, grp INT);
WITH names(k, name) AS (VALUES
 (1,'Groceries'),(2,'Restaurants'),(3,'Gas'),(4,'Shopping'),(5,'Coffee'),(6,'Amazon'),(7,'Utilities'),(8,'Rent'),
 (9,'Phone'),(10,'Internet'),(11,'Entertainment'),(12,'Clothing'),(13,'Household'),(14,'Pharmacy'),(15,'Doctor'),
 (16,'Car Maintenance'),(17,'Parking'),(18,'Public Transit'),(19,'Subscriptions'),(20,'Gifts'),(21,'Pets'),
 (22,'Kids Activities'),(23,'School'),(24,'Childcare'),(25,'Haircut'),(26,'Gym'),(27,'Travel'),(28,'Hotels'),
 (29,'Flights'),(30,'Insurance'),(31,'Car Insurance'),(32,'Home Insurance'),(33,'Electricity'),(34,'Water'),
 (35,'Trash'),(36,'Streaming'),(37,'Books'),(38,'Hobbies'),(39,'Games'),(40,'Charity'),(41,'Dentist'),
 (42,'Vision'),(43,'Home Improvement'),(44,'Furniture'),(45,'Electronics'),(46,'Software'),(47,'Taxes'),
 (48,'Bank Fees'),(49,'Interest'),(50,'Alcohol'),(51,'Takeout'),(52,'Lunch'),(53,'Snacks'),(54,'Baby'),
 (55,'Toys'),(56,'Allowance'),(57,'Tuition'),(58,'Postage'),(59,'Laundry'),(60,'Cleaning'),(61,'Garden'),
 (62,'Ride Share'),(63,'Tolls'),(64,'Car Payment'),(65,'Registration'),(66,'Concerts'),(67,'Sports'),
 (68,'Vacation Fund'),(69,'Emergency Fund'),(70,'New Car Fund'),(71,'Christmas'),(72,'Birthday'),
 (73,'Misc'),(74,'Cash Spending'),(75,'Reimbursable'),
 (76,'Salary'),(77,'Bonus'),(78,'Interest Income'),(79,'Dividends'),(80,'Other Income'))
INSERT INTO _cat
SELECT k, printf('%08x-%04x-4%03x-9%03x-%012x', (k * 2654435761) % 4294967296, (k * 40503) % 65536,
                 (k * 7919) % 4096, (k * 104729) % 4096, (k * 2246822519) % 281474976710656),
       name,
       CASE WHEN k > 75 THEN 10
            WHEN k IN (8,7,33,34,35,43,44,61,32) THEN 1 WHEN k IN (1,2,5,50,51,52,53) THEN 2
            WHEN k IN (3,16,17,18,31,62,63,64,65) THEN 3 WHEN k IN (9,10,19,30,36,46,47,48,49) THEN 4
            WHEN k IN (22,23,24,54,55,56,57) THEN 6 WHEN k IN (14,15,26,41,42) THEN 7
            WHEN k IN (11,27,28,29,37,38,39,66,67) THEN 8 WHEN k IN (68,69,70,71,72) THEN 9 ELSE 5 END
FROM names;
INSERT INTO categories(id, name, is_income, cat_group, sort_order, tombstone, hidden, goal_def, template_settings, cleanup_def)
SELECT c.id, c.name, CASE WHEN c.k > 75 THEN 1 ELSE 0 END, g.id, c.k * 16384.0, 0,
       CASE WHEN c.k IN (73, 75) THEN 1 ELSE 0 END,
       CASE WHEN c.k % 9 = 0 THEN '[{"type":"simple","monthly":' || (c.k * 10) || ',"directive":"template","priority":0}]' END,
       '{"source": "notes"}', NULL
FROM _cat c JOIN _grp g ON g.k = c.grp;
-- Actual keeps a category_mapping row per category (id -> itself) and remaps merged categories
INSERT INTO category_mapping(id, transferId) SELECT id, id FROM _cat;

-- 150 payees (k 1..150, Zipf-used), each with a default category; 20 merged payees (k 151..170) tombstoned and
-- mapped to a surviving payee; 14 transfer payees (k 201..214), one per account, name '' as Actual stores them.
CREATE TEMP TABLE _pay(k INTEGER PRIMARY KEY, id TEXT, name TEXT, cat INT);
WITH base(b, name, cat) AS (VALUES
 (0,'Kroger',1),(1,'Starbucks',5),(2,'Shell',3),(3,'Amazon',6),(4,'Target',4),(5,'Walmart',1),(6,'Chipotle',2),
 (7,'Costco',1),(8,'Whole Foods',1),(9,'Netflix',36),(10,'Spotify',36),(11,'Comcast',10),(12,'Verizon',9),
 (13,'City Water',34),(14,'PG&E',33),(15,'Landlord LLC',8),(16,'CVS',14),(17,'Walgreens',14),(18,'Uber',62),
 (19,'Lyft',62),(20,'Home Depot',43),(21,'IKEA',44),(22,'Best Buy',45),(23,'Apple',46),(24,'Steam',39),
 (25,'Trader Joes',1),(26,'Safeway',1),(27,'Dunkin',5),(28,'McDonalds',51),(29,'Panera',52),(30,'Chevron',3),
 (31,'Exxon',3),(32,'GEICO',31),(33,'State Farm',32),(34,'Petco',21),(35,'Chewy',21),(36,'Planet Fitness',26),
 (37,'Great Clips',25),(38,'Delta',29),(39,'Marriott',28),(40,'Airbnb',27),(41,'Etsy',20),(42,'eBay',4),
 (43,'USPS',58),(44,'Audible',37),(45,'Disney Plus',36),(46,'Hulu',36),(47,'DoorDash',51),(48,'Grubhub',51),
 (49,'Acme Corp Payroll',76))
INSERT INTO _pay
SELECT b * 3 + v + 1,
       printf('%08x-%04x-4%03x-a%03x-%012x', ((b*3+v+1) * 2246822519) % 4294967296, ((b*3+v+1) * 31337) % 65536,
              ((b*3+v+1) * 7919) % 4096, ((b*3+v+1) * 6151) % 4096, ((b*3+v+1) * 2654435761) % 281474976710656),
       CASE v WHEN 0 THEN name WHEN 1 THEN name || ' #' || (100 + b * 7) ELSE upper(name) || ' ONLINE' END,
       CASE WHEN v = 2 AND cat < 76 THEN ((cat + b) % 75) + 1 ELSE cat END
FROM base, (SELECT 0 AS v UNION ALL SELECT 1 UNION ALL SELECT 2);
WITH RECURSIVE n(k) AS (SELECT 151 UNION ALL SELECT k + 1 FROM n WHERE k < 170)
INSERT INTO _pay
SELECT k, printf('%08x-%04x-4%03x-a%03x-%012x', (k * 2246822519) % 4294967296, (k * 31337) % 65536, (k * 7919) % 4096,
                 (k * 6151) % 4096, (k * 2654435761) % 281474976710656),
       'Old payee ' || k, NULL FROM n;
INSERT INTO _pay SELECT 200 + k, printf('7a0b0000-%04x-4000-8000-0000000000%02d', k, k), '', NULL FROM _acc;

INSERT INTO payees(id, name, category, tombstone, transfer_acct, favorite, learn_categories)
SELECT p.id, p.name, c.id, CASE WHEN p.k BETWEEN 151 AND 170 THEN 1 ELSE 0 END,
       (SELECT a.id FROM _acc a WHERE a.k = p.k - 200), CASE WHEN p.k IN (1,2,4,10) THEN 1 ELSE 0 END, 1
FROM _pay p LEFT JOIN _cat c ON c.k = p.cat;
INSERT INTO payee_mapping(id, targetId)
SELECT p.id, CASE WHEN p.k BETWEEN 151 AND 170 THEN (SELECT t.id FROM _pay t WHERE t.k = (p.k - 150) * 3) ELSE p.id END
FROM _pay p;

-- Plain transactions. u, v, w: independent uniform hashes in [0,1). Half the rows are uniform over the 2920 days,
-- half with density rising linearly towards today (max of two uniforms), so recent years are denser.
CREATE TEMP TABLE _t(i INTEGER PRIMARY KEY, id TEXT, acct INT, pay INT, cat INT, amount INT, day INT, kind INT);
WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i + 1 FROM n WHERE i < 57000 * (SELECT scale FROM _cfg)),
h AS (SELECT i, ((i * 2654435761) % 4294967296) / 4294967296.0 AS u,
             ((i * 2246822519 + 374761393) % 4294967296) / 4294967296.0 AS v,
             ((i * 3266489917 + 668265263) % 4294967296) / 4294967296.0 AS w,
             ((i * 668265263 + 2654435761) % 4294967296) / 4294967296.0 AS z FROM n),
r AS (SELECT i, u, v, w,
             CAST(CASE WHEN i % 2 = 0 THEN 2920 * u ELSE 2920 * max(u, z) END AS INT) AS day,
             CASE WHEN w < 0.03 THEN 1 ELSE 0 END AS income,
             CAST(147 * v * v * v AS INT) + 1 AS pay
      FROM h)
INSERT INTO _t
SELECT i, printf('%08x-%04x-4%03x-b%03x-%012x', (i * 2654435761) % 4294967296, (i * 40503) % 65536, (i * 7919) % 4096,
                 (i * 104729) % 4096, (i * 2246822519) % 281474976710656),
       CASE WHEN income = 1 THEN CASE WHEN i % 5 = 0 THEN 4 ELSE 1 END
            ELSE (SELECT a.k FROM _acc a WHERE a.lo <= CAST(w * 1000 AS INT) AND CAST(w * 1000 AS INT) < a.hi) END,
       CASE WHEN income = 1 THEN 148 ELSE pay END,
       CASE WHEN income = 1 THEN 76 + (i % 7 = 0) * (1 + i % 4)
            WHEN (i / 7) % 10 < 8 THEN (SELECT p.cat FROM _pay p WHERE p.k = pay)
            WHEN (i / 7) % 50 = 9 THEN NULL
            ELSE CAST(75 * u * v AS INT) + 1 END,
       CASE WHEN income = 1 THEN 150000 + (i % 97) * 2500
            WHEN pay IN (46, 47, 48) THEN -(185000 + (day / 365) * 5000)
            ELSE -(150 + CAST(9000 * v * w AS INT) + (i % 13) * 37 + CASE WHEN i % 61 = 0 THEN 60000 ELSE 0 END) END,
       day,
       CASE WHEN i % 50 = 7 THEN 1 ELSE 0 END
FROM r;
-- Closed accounts stop receiving rows halfway; Old Checking only exists for the first half of the history.
UPDATE _t SET acct = 1 WHERE acct IN (8, 13) AND day > 1400;
UPDATE _t SET pay = 148, cat = 76 WHERE pay = 148 AND cat IS NULL;

INSERT INTO transactions(id, isParent, isChild, acct, category, amount, description, notes, date, financial_id, type,
                         imported_description, starting_balance_flag, transferred_id, sort_order, tombstone, cleared,
                         pending, parent_id, schedule, reconciled, raw_synced_data)
SELECT t.id, t.kind, 0, a.id, CASE WHEN t.kind = 1 THEN NULL ELSE c.id END, t.amount, p.id,
       CASE WHEN t.i % 7 = 0 THEN 'note ' || (t.i % 300)
            WHEN t.i % 23 = 0 THEN '#' || CASE t.i % 3 WHEN 0 THEN 'vacation' WHEN 1 THEN 'work' ELSE 'gift' END || ' trip ' || (t.i % 40)
            ELSE NULL END,
       CAST(strftime('%Y%m%d', '2018-11-01', '+' || t.day || ' days') AS INT),
       CASE WHEN t.acct IN (1, 2, 3) AND t.day > 1200 THEN 'FIT' || t.i END, NULL,
       CASE WHEN t.acct IN (1, 2, 3) THEN upper(p.name) || ' ' || (t.i % 9999) END,
       0, NULL, 1541030400000.0 + t.day * 86400000.0 + t.i, CASE WHEN t.i % 97 = 0 THEN 1 ELSE 0 END,
       CASE WHEN t.day > 2900 AND t.i % 3 = 0 THEN 0 ELSE 1 END, 0, NULL,
       CASE WHEN t.pay IN (28, 29, 30, 34, 35, 36, 46, 47, 48) THEN 'sched-' || t.pay END,
       CASE WHEN t.day < 2860 AND t.acct IN (1, 2, 3, 4) THEN 1 ELSE 0 END, NULL
FROM _t t JOIN _acc a ON a.k = t.acct JOIN _pay p ON p.k = t.pay LEFT JOIN _cat c ON c.k = t.cat;

-- Split children: every parent gets 2 (or 3) children carrying the category and summing to the parent amount
INSERT INTO transactions(id, isParent, isChild, acct, category, amount, description, notes, date, financial_id,
                         starting_balance_flag, sort_order, tombstone, cleared, pending, parent_id, reconciled)
SELECT printf('%s-c%d', substr(t.id, 1, 33), j.j), 0, 1, x.acct,
       (SELECT c.id FROM _cat c WHERE c.k = ((t.i * j.j * 13) % 75) + 1),
       CASE j.j WHEN 1 THEN t.amount / 2 WHEN 2 THEN CASE WHEN t.i % 3 = 0 THEN t.amount / 4 ELSE t.amount - t.amount / 2 END
                ELSE t.amount - t.amount / 2 - t.amount / 4 END,
       x.description, CASE WHEN j.j = 2 THEN 'split part' END, x.date, NULL, 0, x.sort_order - j.j / 10.0, x.tombstone,
       x.cleared, 0, t.id, x.reconciled
FROM _t t JOIN transactions x ON x.id = t.id,
     (SELECT 1 AS j UNION ALL SELECT 2 UNION ALL SELECT 3) j
WHERE t.kind = 1 AND (j.j < 3 OR t.i % 3 = 0);

-- Transfer pairs: card payments and savings moves between on-budget accounts (no category), 401k/brokerage
-- contributions and mortgage payments to off-budget accounts (category on the on-budget leg).
WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i + 1 FROM n WHERE i < 900 * (SELECT scale FROM _cfg)),
x AS (SELECT i, CAST(2920 * max(((i * 2654435761) % 4294967296) / 4294967296.0,
                                 ((i * 668265263 + 2654435761) % 4294967296) / 4294967296.0) AS INT) AS day,
             CASE i % 9 WHEN 0 THEN 7 WHEN 1 THEN 7 WHEN 2 THEN 3 WHEN 3 THEN 10 WHEN 4 THEN 11 WHEN 5 THEN 12
                        WHEN 6 THEN 4 ELSE 2 END AS dst,
             -(20000 + (i * 7919) % 250000) AS amount FROM n)
INSERT INTO _t(i, id, acct, pay, cat, amount, day, kind)
SELECT 1000000 + i * 2, printf('%08x-%04x-4%03x-c%03x-00000000%04x', (i * 2654435761) % 4294967296, i % 65536, i % 4096, 1, i % 65536),
       1, 200 + dst, CASE WHEN dst IN (10, 11) THEN 69 WHEN dst = 12 THEN 8 END, amount, day, 2 FROM x
UNION ALL
SELECT 1000000 + i * 2 + 1, printf('%08x-%04x-4%03x-c%03x-00000000%04x', (i * 2654435761) % 4294967296, i % 65536, i % 4096, 2, i % 65536),
       dst, 201, NULL, -amount, day, 3 FROM x;

INSERT INTO transactions(id, isParent, isChild, acct, category, amount, description, notes, date, starting_balance_flag,
                         transferred_id, sort_order, tombstone, cleared, pending, reconciled)
SELECT t.id, 0, 0, a.id, c.id, t.amount, p.id, NULL,
       CAST(strftime('%Y%m%d', '2018-11-01', '+' || t.day || ' days') AS INT), 0,
       (SELECT o.id FROM _t o WHERE o.i = CASE t.kind WHEN 2 THEN t.i + 1 ELSE t.i - 1 END),
       1541030400000.0 + t.day * 86400000.0 + t.i, 0, 1, 0, CASE WHEN t.day < 2860 THEN 1 ELSE 0 END
FROM _t t JOIN _acc a ON a.k = t.acct JOIN _pay p ON p.k = t.pay LEFT JOIN _cat c ON c.k = t.cat
WHERE t.kind IN (2, 3);

-- Starting balances (one per account, on the account's first day), payee "Starting Balance" -> the Other Income category
INSERT INTO transactions(id, isParent, isChild, acct, category, amount, description, date, starting_balance_flag,
                         sort_order, tombstone, cleared, pending, reconciled)
SELECT printf('5ba1a0ce-%04x-4000-8000-000000000000', a.k), 0, 0, a.id,
       CASE WHEN a.offbudget = 0 THEN (SELECT id FROM _cat WHERE k = 80) END,
       CASE a.k WHEN 12 THEN -32000000 WHEN 13 THEN -2400000 WHEN 14 THEN 41000000 ELSE 100000 * a.k END,
       NULL, 20181101, 1, 1541030400000.0, 0, 1, 0, 1
FROM _acc a;

-- Monthly budgets: 97 months (2018-11 .. 2026-11) x 75 expense categories, envelope and tracking tables
WITH RECURSIVE m(j) AS (SELECT 0 UNION ALL SELECT j + 1 FROM m WHERE j < 96),
mm AS (SELECT CAST(strftime('%Y%m', '2018-11-01', '+' || j || ' months') AS INT) AS month, j FROM m)
INSERT INTO zero_budgets(id, month, category, amount, carryover, goal, long_goal)
SELECT mm.month || '-' || c.id, mm.month, c.id,
       CASE WHEN c.k > 60 AND (mm.j + c.k) % 4 = 0 THEN 0 ELSE (80 - c.k) * 1000 + ((mm.j * c.k) % 11) * 500 END,
       CASE WHEN c.k IN (68, 69, 70) THEN 1 ELSE 0 END, NULL, NULL
FROM mm, _cat c WHERE c.k <= 75;
INSERT INTO reflect_budgets(id, month, category, amount, carryover, goal, long_goal)
SELECT id, month, category, amount, 0, NULL, NULL FROM zero_budgets;

-- 120 rules: payee rules (description is <payee id> -> set category), imported-payee contains rules,
-- and a few referencing merged payees.
WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i + 1 FROM n WHERE i < 120)
INSERT INTO rules(id, stage, conditions, actions, tombstone, conditions_op)
SELECT printf('4e1e0000-%04x-4000-8000-000000000000', i), CASE WHEN i % 10 = 0 THEN 'pre' END,
       CASE WHEN i % 4 = 3 THEN json_array(json_object('op', 'contains', 'field', 'imported_description', 'value',
                                  upper((SELECT name FROM _pay WHERE k = i)), 'type', 'string'))
            ELSE json_array(json_object('op', 'is', 'field', 'description', 'value',
                                  (SELECT id FROM _pay WHERE k = CASE WHEN i > 110 THEN i + 40 ELSE i END), 'type', 'id')) END,
       json_array(json_object('op', 'set', 'field', 'category', 'value',
                              (SELECT c.id FROM _cat c WHERE c.k = (i % 75) + 1), 'type', 'id')),
       CASE WHEN i % 31 = 0 THEN 1 ELSE 0 END, 'and'
FROM n;

-- 9 schedules ('sched-<payee k>', the ids the recurring transactions above carry), each with its rule, next date
-- and the json paths of its conditions, as the schedules code writes them.
INSERT INTO rules(id, stage, conditions, actions, tombstone, conditions_op)
SELECT 'rule-sched-' || p.k, NULL,
       json_array(json_object('op', 'is', 'field', 'description', 'value', p.id, 'type', 'id'),
                  json_object('op', 'is', 'field', 'account', 'value', (SELECT id FROM _acc WHERE k = 1), 'type', 'id'),
                  json_object('op', 'isapprox', 'field', 'amount', 'value', -(1500 + p.k * 100), 'type', 'number'),
                  json_object('op', 'isapprox', 'field', 'date', 'type', 'date', 'value',
                              json_object('start', '2019-01-' || printf('%02d', 1 + p.k % 27), 'frequency', 'monthly',
                                          'interval', 1, 'patterns', json_array(), 'skipWeekend', json('false'),
                                          'weekendSolveMode', 'after', 'endMode', 'never'))),
       json_array(json_object('op', 'link-schedule', 'value', 'sched-' || p.k)), 0, 'and'
FROM _pay p WHERE p.k IN (28, 29, 30, 34, 35, 36, 46, 47, 48);
INSERT INTO schedules(id, rule, active, completed, posts_transaction, tombstone, name, custom_upcoming_length, sort_order)
SELECT 'sched-' || p.k, 'rule-sched-' || p.k, 1, CASE WHEN p.k = 30 THEN 1 ELSE 0 END, CASE WHEN p.k IN (46, 47, 48) THEN 1 ELSE 0 END,
       0, p.name, NULL, p.k
FROM _pay p WHERE p.k IN (28, 29, 30, 34, 35, 36, 46, 47, 48);
INSERT INTO schedules_next_date(id, schedule_id, local_next_date, local_next_date_ts, base_next_date, base_next_date_ts, tombstone)
SELECT 'nd-' || p.k, 'sched-' || p.k, 202611 * 100 + 1 + p.k % 27, 1793000000000 + p.k, 202611 * 100 + 1 + p.k % 27,
       1793000000000 + p.k, 0
FROM _pay p WHERE p.k IN (28, 29, 30, 34, 35, 36, 46, 47, 48);
INSERT INTO schedules_json_paths(schedule_id, payee, account, amount, date)
SELECT 'sched-' || p.k, '$[0]', '$[1]', '$[2]', '$[3]' FROM _pay p WHERE p.k IN (28, 29, 30, 34, 35, 36, 46, 47, 48);

DROP TABLE _t; DROP TABLE _pay; DROP TABLE _cat; DROP TABLE _grp; DROP TABLE _acc;
COMMIT;
