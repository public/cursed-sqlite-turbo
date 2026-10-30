-- Actual Budget (actualbudget/actual @ e82ea4dc3594e7e0c32ba7b1039913c19e6ce9f9, MIT).
-- Most statements come from AQL: the app's query builders (desktop-client report spreadsheets, bindings, the
-- account register, loot-core schedules) were replayed against the real loot-core AQL compiler, schema and
-- executors, bundled from the pinned source with esbuild and run on node:sqlite against this data; every SQL
-- statement sent to the database was recorded verbatim (whitespace reflowed). AQL inlines values as literals, so
-- there are no bind parameters. The budget and payee statements are raw SQL strings in loot-core with their
-- template interpolation resolved. "Today" is 2026-10-30.
-- Actual registers UNICODE_LIKE / NORMALISE / UNICODE_LOWER on its connection (sql.js, better-sqlite3); search
-- filters that use them are rewritten to core lower(x) LIKE p and marked @modified.

-- @id actual.budget.sum_amounts_by_month
-- @src packages/loot-core/src/server/budget/base.ts:109-129
-- @style raw SQL string in loot-core; values interpolated with template literals (copied, interpolation resolved)
-- @tags analytics,cpu-evidence
-- @note Cold budget build / budget-cache reset: every category x month spend total in one grouped scan of v_transactions_internal_alive (3 nested views) over all 8 years. Replaced one SUM per category per month (PR #8140, #9143); budget load slowness: https://github.com/actualbudget/actual/issues/4045
SELECT t.category AS category,
t.date / 100 AS month,
SUM(t.amount) AS amount
FROM v_transactions_internal_alive t
LEFT JOIN accounts a ON a.id = t.account
WHERE t.date >= 20181101 AND t.date <= 20261130
AND t.category IS NOT NULL
AND a.offbudget = 0
GROUP BY t.category, t.date / 100;

-- @id actual.budget.sum_amount_cell
-- @src packages/loot-core/src/server/budget/base.ts:174-192
-- @style raw SQL string in loot-core; values interpolated with template literals (copied, interpolation resolved)
-- @tags hotpath,hot-small,cpu-evidence
-- @note The per-cell spreadsheet query (sum-amount-<category> for one month): recomputed for every category x month on budget edits and warm loads; the category comes through category_mapping so no transactions index applies. https://github.com/actualbudget/actual/issues/4045 (adding a category stalls 10-20 s)
SELECT SUM(amount) as amount FROM v_transactions_internal_alive t
LEFT JOIN accounts a ON a.id = t.account
WHERE t.date >= 20261001 AND t.date <= 20261031
AND category = '9e3779b1-9e37-4eef-9919-000085ebca77' AND a.offbudget = 0;

-- @id actual.budget.latest_allocated_month
-- @src packages/loot-core/src/server/budget/base.ts:66-80
-- @style raw SQL string in loot-core; values interpolated with template literals (copied, interpolation resolved)
-- @tags analytics
-- @note Budget range on load: MAX(month) over non-zero envelope budget rows joined to live categories.
SELECT MAX(b.month) AS month FROM zero_budgets b
JOIN categories c ON c.id = b.category
WHERE c.tombstone = 0 AND b.amount != 0;

-- @id actual.budget.earliest_transaction
-- @src packages/loot-core/src/server/budget/base.ts:462-466
-- @style raw SQL string in loot-core; values interpolated with template literals (copied, interpolation resolved)
-- @tags hot-small
-- @note createAllBudgets: first transaction date via the trans_date index (top-1).
SELECT * FROM transactions WHERE isChild=0 AND date IS NOT NULL ORDER BY date ASC LIMIT 1;

-- @id actual.binding.account_balance
-- @src packages/desktop-client/src/spreadsheet/bindings.ts:23-31
-- @style AQL compiled by the real loot-core compiler + executors (bundled from the pinned source, run on node:sqlite); values inlined as literals by the compiler, no binds
-- @tags hotpath,analytics,cpu-evidence,dynamic
-- @note Sidebar account balance: q('transactions').filter({account}).options({splits:'none'}).calculate({$sum}); the account test is on the joined accounts row. Per-account sums were 68 ms under 4x throttling before idx_transactions_acct_tombstone: https://github.com/actualbudget/actual/pull/8335
SELECT SUM(v_transactions_internal_alive.amount) AS result FROM v_transactions_internal_alive
LEFT JOIN accounts accounts1 ON accounts1.id = v_transactions_internal_alive.account AND accounts1.tombstone = 0
WHERE (accounts1.id = 'a1c0ffee-0002-4a11-8a11-c4ec0000a002') AND v_transactions_internal_alive.parent_id IS NULL AND v_transactions_internal_alive.tombstone = 0
ORDER BY v_transactions_internal_alive.date desc, v_transactions_internal_alive.starting_balance_flag, v_transactions_internal_alive.sort_order desc, v_transactions_internal_alive.id;

-- @id actual.binding.category_balance_month
-- @src packages/desktop-client/src/spreadsheet/bindings.ts:106-120
-- @style AQL compiled by the real loot-core compiler + executors (bundled from the pinned source, run on node:sqlite); values inlined as literals by the compiler, no binds
-- @tags hotpath,analytics,dynamic
-- @note Category balance for a month (mobile budget, category drill-down): $month transform compiles to CAST(SUBSTR(date,1,6) AS integer), category via the v_categories join.
SELECT SUM(v_transactions_internal_alive.amount) AS result FROM v_transactions_internal_alive
LEFT JOIN v_categories categories1 ON categories1.id = v_transactions_internal_alive.category AND categories1.tombstone = 0
WHERE (categories1.id = '9e3779b1-9e37-4eef-9919-000085ebca77'
AND CAST(SUBSTR(v_transactions_internal_alive.date, 1, 6) AS integer) = 202610) AND v_transactions_internal_alive.is_parent = 0 AND v_transactions_internal_alive.tombstone = 0
ORDER BY v_transactions_internal_alive.date desc, v_transactions_internal_alive.starting_balance_flag, v_transactions_internal_alive.sort_order desc, v_transactions_internal_alive.id;

-- @id actual.binding.uncategorized_balance
-- @src packages/desktop-client/src/spreadsheet/bindings.ts:156-161; packages/desktop-client/src/queries/index.ts:142-153
-- @style AQL compiled by the real loot-core compiler + executors (bundled from the pinned source, run on node:sqlite); values inlined as literals by the compiler, no binds
-- @tags hotpath,analytics,dynamic
-- @note Uncategorized total shown on the budget page: 4 LEFT JOINs (account, category, payee, payee transfer account) and an IS NULL / OR filter over all live rows.
SELECT SUM(v_transactions_internal_alive.amount) AS result FROM v_transactions_internal_alive
LEFT JOIN accounts accounts1 ON accounts1.id = v_transactions_internal_alive.account AND accounts1.tombstone = 0
LEFT JOIN v_categories categories2 ON categories2.id = v_transactions_internal_alive.category AND categories2.tombstone = 0
LEFT JOIN v_payees payees3 ON payees3.id = v_transactions_internal_alive.payee AND payees3.tombstone = 0
LEFT JOIN accounts accounts4 ON accounts4.id = payees3.transfer_acct AND accounts4.tombstone = 0
WHERE (accounts1.offbudget = 0
AND categories2.id IS NULL
AND (accounts4.offbudget = 1
OR accounts4.id IS NULL)) AND v_transactions_internal_alive.is_parent = 0 AND v_transactions_internal_alive.tombstone = 0
ORDER BY v_transactions_internal_alive.date desc, v_transactions_internal_alive.starting_balance_flag, v_transactions_internal_alive.sort_order desc, v_transactions_internal_alive.id;

-- @id actual.register.page_account
-- @src packages/desktop-client/src/components/accounts/Account.tsx:486-585; packages/loot-core/src/server/aql/schema/executors.ts:97-146
-- @style AQL compiled by the real loot-core compiler + executors (bundled from the pinned source, run on node:sqlite); values inlined as literals by the compiler, no binds
-- @tags hotpath,cpu-evidence,dynamic
-- @note Account register, first page of 150 (splits 'grouped', happy path): group ids of one account through 4 view joins incl. v_schedules, default order date desc, sort_order desc. Large-register slowness: https://github.com/actualbudget/actual/issues/5619 (33k transactions)
SELECT v_transactions_internal.id as group_id
FROM v_transactions_internal
LEFT JOIN accounts accounts1 ON accounts1.id = v_transactions_internal.account AND accounts1.tombstone = 0
LEFT JOIN v_categories categories2 ON categories2.id = v_transactions_internal.category AND categories2.tombstone = 0
LEFT JOIN v_payees payees3 ON payees3.id = v_transactions_internal.payee AND payees3.tombstone = 0
LEFT JOIN v_schedules schedules4 ON schedules4.id = v_transactions_internal.schedule AND schedules4.tombstone = 0
WHERE (accounts1.id = 'a1c0ffee-0002-4a11-8a11-c4ec0000a002') AND is_child = 0 AND v_transactions_internal.tombstone = 0
ORDER BY v_transactions_internal.date desc, v_transactions_internal.starting_balance_flag, v_transactions_internal.sort_order desc, v_transactions_internal.id
LIMIT 150;

-- @id actual.register.page_account.fetch_rows
-- @src packages/loot-core/src/server/aql/schema/executors.ts:179-188
-- @style AQL compiled by the real loot-core compiler + executors (bundled from the pinned source, run on node:sqlite); values inlined as literals by the compiler, no binds
-- @tags hotpath,dynamic
-- @note Second statement of the grouped executor: the page's parents and children by IFNULL(parent_id, id) IN (150 literal ids from the first statement); the expression matches no index, so it walks every row of the view.
SELECT v_transactions_internal.id AS id, v_transactions_internal.is_parent AS is_parent, v_transactions_internal.is_child AS is_child, v_transactions_internal.parent_id AS parent_id, accounts1.id AS account, categories2.id AS category, v_transactions_internal.amount AS amount, payees3.id AS payee, v_transactions_internal.notes AS notes, v_transactions_internal.date AS date, v_transactions_internal.imported_id AS imported_id, v_transactions_internal.error AS error, v_transactions_internal.imported_payee AS imported_payee, v_transactions_internal.starting_balance_flag AS starting_balance_flag, v_transactions_internal.transfer_id AS transfer_id, v_transactions_internal.sort_order AS sort_order, v_transactions_internal.cleared AS cleared, v_transactions_internal.reconciled AS reconciled, v_transactions_internal.tombstone AS tombstone, schedules4.id AS schedule, v_transactions_internal.raw_synced_data AS raw_synced_data, parent_id AS _parent_id FROM v_transactions_internal
LEFT JOIN accounts accounts1 ON accounts1.id = v_transactions_internal.account AND accounts1.tombstone = 0
LEFT JOIN v_categories categories2 ON categories2.id = v_transactions_internal.category AND categories2.tombstone = 0
LEFT JOIN v_payees payees3 ON payees3.id = v_transactions_internal.payee AND payees3.tombstone = 0
LEFT JOIN v_schedules schedules4 ON schedules4.id = v_transactions_internal.schedule AND schedules4.tombstone = 0
WHERE IFNULL(v_transactions_internal.parent_id, v_transactions_internal.id) IN ('ffffd2e5-a223-4e3b-b56d-674ba7911b63','520ae071-f577-402f-bdd9-65e1a631d1b7','1a9b9ab7-d7a1-4da9-b18f-49b5ca7cc561','e935b883-b4b5-475d-b43b-39c779eb1575','ffeb2974-cdac-470c-b694-374bdfd52aac','ffe9e752-e1fe-4fee-b7a2-20edb3ee367e','b1c672c9-96df-44d7-b7f1-1d9b9e36091f','ffef1cf5-ee93-4e2b-bdfd-131abbf8ebd3','fff45298-fb28-4c68-b458-0547c403a128','a5b3abbd-a10b-4c63-ba05-052087ef504b','ffd652e8-9b58-4e18-bd28-6e97bfaa5558','2cb7c549-c85f-4257-be71-6e6e6be6da9f','ffdb888b-a7ed-4c55-b383-60c4c7b50aad','ffe0be2e-b482-4a92-b9de-52f1cfbfc002','ffda4669-bc3f-4537-b491-4a669bce167f','ffe5f3d1-c117-48cf-b039-451ed7ca7557','ffdf7c0c-c8d4-4374-baec-3c93a3d8cbd4','ffe4b1af-d569-41b1-b147-2ec0abe38129','ffe8a530-f650-48d0-b8b0-0a8f88074250','c3e29d5b-879d-4985-b4d3-42543fa01e5d','927cbb27-64b1-4339-b77f-3265ef0e6e71','ffc06755-db33-4fcb-bf5d-2839cc077073','ffc59cf8-e7c8-4e08-b5b8-1a66d41225c8','5b0d756d-46db-40b3-bb35-163a1359621b','ffbf2533-ef85-48ad-b06b-11dba0207c45','ffc45ad6-fc1a-46ea-b6c6-0408a82b319a','ffb235a9-0179-4179-c002-000000000179','ffa65b26-9c4a-489a-bf96-6d58a3d1e5ca','ffb2088e-a122-4c32-bb3e-6810dfce44a2','d5fec7ed-785b-4e33-b1b5-670ce10a339b','ffab90c9-a8df-46d7-b5f1-5f85abdc9b1f','ffb73e31-adb7-4a6f-b199-5a3de7d8f9f7','ffb0c66c-b574-4514-bc4c-51b2b3e75074','9e8f8233-5a85-4bad-b56b-4ae105552745','ffb5fc0f-c209-4351-b2a7-43dfbbf205c9','6d299fff-3799-4561-b817-3af2b4c37759','ffbb31b2-ce9e-418e-b902-360cc3fcbb1e','ffb4b9ed-d65b-4c33-b3b5-2d81900b119b','ffb9ef90-e2f0-4a70-ba10-1fae9815c6f0','35ba5a45-19c3-42db-bbcd-1ec6d90e6b03','29a79339-23ef-4a67-bde1-064bc2c7b22f','b0abacc5-4b43-405b-b24d-6f99a6bf3c83','ff906f93-dc25-4a4d-b1cb-26fab02f00e5','ff95a536-e8ba-488a-b826-1927b839b63a','04547811-f6d7-4c8f-be79-0ed8887cbb17','ff9adad9-f54f-46c7-be81-0b54c0446b8f','ff946314-fd0c-416c-b934-02c98c52c20c','ff8210cc-a214-46b4-bdac-66d1c3f5d514','7f45ca91-2857-4a0f-b4f9-5fab562d8c97','ff7b9907-a9d1-4159-b85f-5e4690042b91','ff87466f-aea9-44f1-b407-58fecc008a69','ff80ceaa-b666-4f96-beba-5073980ee0e6','ff8c7c12-bb3e-432e-ba62-4b2bd40b3fbe','47d684d7-0a81-4789-b8af-437f7a788041','ff86044d-c2fb-4dd3-b515-42a0a019963b','ff8b39f0-cf90-4c10-bb70-34cda8244b90','1670a2a3-e795-413d-bb5b-339129e6d055','ff89f7ce-e3e2-44f2-bc7e-1e6f7c3d5762','df015ce9-c9bf-4eb7-bf11-17654e31c3ff','ff8f2d71-f077-432f-b2d9-109c84480cb7','ff646b52-02f2-42f2-c002-0000000002f2','59f2af69-fb3f-4c37-b591-68381be2957f','228369af-dd69-49b1-b947-4c0c402d8929','f11d877b-ba7d-4365-bbf3-3c1def9bd93d','ff66ef96-d55a-4a2a-b986-2e46c8483ada','ff65ad74-e9ac-430c-ba94-17e89c6146ac','ff6ae317-f641-4149-b0ef-0a15a46bfc01','ad9b7ab5-a6d3-486b-b1bd-0776fda01413','ff646b52-fdfe-4bee-bba2-018a707a527e','ff4ce367-9671-42f9-b9bf-7365a012b031','349f9441-ce27-4e5f-b629-70c4e1979e67','ff5890cf-9b49-4691-b567-6e1ddc0f0f09','ff52190a-a306-4136-b01a-6592a81d6586','ff574ead-af9b-4f73-b675-57bfb0281adb','ff5c8450-bc30-4db0-bcd0-49ecb832d030','ff560c8b-c3ed-4855-b783-4161844126ad','ff61b9f3-c8c5-4bed-b32b-3c19c03d8585','ff5b422e-d082-4692-bdde-338e8c4bdc02','ff6077d1-dd17-44cf-b439-25bb94569157','88485f8d-79bb-4a93-b255-1003c3551cfb','56e27d59-56cf-4447-b501-001572c36d0f','0339b20d-ab3b-4813-b8d5-60d69105ee7b','cbca6c53-8d65-458d-bc8b-44aab550e225','9a648a1f-6a79-4f41-bf37-34bc64bf3239','ff36f7d4-d64c-44ac-bbf4-2d07ac6fcb4c','ff3c2d77-e2e1-42e9-b24f-1f34b47a80a1','62f54465-4ca3-4cbb-b2ed-1890890a25e3','ff3aeb55-f733-4bcb-b35d-08d688938c73','ff28990d-9c3b-4113-b7d5-6cdec0369f7b','dde696e5-7e23-4a3b-b96d-696356baf763','ff222148-a3f8-4bb8-b288-64538c44f5f8','ff2dceb0-a8d0-4f50-be30-5f0bc84154d0','ff2756eb-b08d-49f5-b8e3-5680944fab4d','ff2c8c8e-bd22-4832-bf3e-48ad9c5a60a2','75116ef7-3d61-4169-bfcf-3d492a743b21','ff31c231-c9b7-466f-b599-3adaa46515f7','ff2b4a6c-d174-4114-b04c-324f70736c74','ff30800f-de09-4f51-b6a7-247c787e21c9','ff35b5b2-ea9e-4d8e-bd02-16a98088d71e','318f6231-29b7-466f-b599-08a2387875f7','ff1ceba5-9763-4d7b-bc2d-7226843a40a3','b8937bbd-510b-4c63-ba05-71f01c70004b','43ab8cc3-1a75-4b1d-b27b-2d5ad9e28b35','ff0c35b5-e3d3-4d6b-b4bd-1df598a21113','0c3c4709-fc9f-4897-b631-112efe2d7edf','ff116b58-f068-4ba8-bb18-1022a0acc668','ff0af393-f825-464d-b5cb-07976cbb1ce5','ff16a0fb-fcfd-49e5-b173-024fa8b77bbd','dad664d5-d9b3-424b-b8dd-0140ad9bcef3','fef8a14b-9d2d-4b95-ba43-6b9fa45e2fed','872d9989-2e1f-4617-bcb1-6201cbde505f','fefdd6ee-a9c2-49d2-b09e-5dccac68e542','fef75f29-b17f-4477-bb51-554178773bbf','ff030c91-b657-480f-b6f9-4ff9b4739a97','fefc94cc-be14-42b4-b1ac-476e8081f114','4fbe53cf-1049-4391-b067-45d5f0294409','ff084234-c2ec-464c-bd54-4226bc7e4fec','ff01ca6f-caa9-40f1-b807-399b888ca669','1e58719b-ed5d-4d45-b313-35e79f97941d','ff070012-d73e-4f2e-be62-2bc890975bbe','e6e92be1-cf87-4abf-b6c9-19bbc3e287c7','ff05bdf0-eb90-4810-bf70-156a64b06790','fee6a939-0209-4209-c002-000000000209','61da7e61-0107-483f-bd49-6a8e91935947','f9055673-c045-4f6d-b3ab-3e74654c9d05','fedd8015-d073-4f0b-b61d-3314a8b095b3','fee2b5b8-dd08-4d48-bc78-2541b0bb4b08','fedc3df3-e4c5-47ed-b72b-1cb67cc9a185','fee17396-f15a-462a-bd86-0ee384d456da','b58349ad-ac9b-4473-b975-09cd7350d7db','fee6a939-fdef-4467-b3e1-01108cdf0c2f','3c876339-d3ef-4a67-bde1-731b5748622f','fecf214e-9662-4b72-b1fe-72ebbc7769e2','fec8a989-9e1f-4617-bcb1-6a608885c05f','0b218105-b103-441b-b08d-632d06b6b243','fecddf2c-aab4-4454-b30c-5c8d909075b4','fed314cf-b749-4291-b967-4eba989b2b09','fecc9d0a-bf06-4d36-b41a-462f64a98186','fed84a72-c3de-40ce-bfc2-40e7a0a5e05e','fed1d2ad-cb9b-4b73-ba75-385c6cb436db','c79f743f-9d59-4921-b657-2e8614baed19','fed70850-d830-49b0-b0d0-2a8974beec30','90302e85-7f83-469b-ba0d-125a3905e0c3','fedafbd1-f917-40cf-b839-065850e2ad57','5eca4c51-5c97-404f-bcb9-026be87430d7','d3b23b4b-932d-4195-b443-47012b01a5ed','a24c5917-7041-4b49-b6ef-3712da6ff601','feb2bdf6-ddfa-47ca-bee6-240294e2db7a','feb7f399-ea8f-4607-b541-162f9ced90cf','feb17bd4-f24c-40ac-bff4-0da468fbe74c') AND v_transactions_internal.tombstone = 0
ORDER BY v_transactions_internal.date desc, v_transactions_internal.starting_balance_flag, v_transactions_internal.sort_order desc, v_transactions_internal.id;

-- @id actual.register.page_all_accounts
-- @src packages/desktop-client/src/components/accounts/Account.tsx:486-585; packages/loot-core/src/server/aql/schema/executors.ts:97-146
-- @style AQL compiled by the real loot-core compiler + executors (bundled from the pinned source, run on node:sqlite); values inlined as literals by the compiler, no binds
-- @tags hotpath,dynamic
-- @note All-accounts register, first page: no filter, so the ORDER BY over every live non-child row of the view decides the plan.
SELECT v_transactions_internal.id as group_id
FROM v_transactions_internal
LEFT JOIN accounts accounts1 ON accounts1.id = v_transactions_internal.account AND accounts1.tombstone = 0
LEFT JOIN v_categories categories2 ON categories2.id = v_transactions_internal.category AND categories2.tombstone = 0
LEFT JOIN v_payees payees3 ON payees3.id = v_transactions_internal.payee AND payees3.tombstone = 0
LEFT JOIN v_schedules schedules4 ON schedules4.id = v_transactions_internal.schedule AND schedules4.tombstone = 0
WHERE is_child = 0 AND v_transactions_internal.tombstone = 0
ORDER BY v_transactions_internal.date desc, v_transactions_internal.starting_balance_flag, v_transactions_internal.sort_order desc, v_transactions_internal.id
LIMIT 150;

-- @id actual.register.count_account
-- @src packages/desktop-client/src/queries/pagedQuery.ts:78-82; packages/loot-core/src/server/aql/schema/executors.ts:102-122
-- @style AQL compiled by the real loot-core compiler + executors (bundled from the pinned source, run on node:sqlite); values inlined as literals by the compiler, no binds
-- @tags hotpath,analytics,dynamic
-- @note pagedQuery.fetchCount on the register: an aggregate on a grouped query falls back to the inline type (is_parent = 0) and the alive view.
SELECT COUNT('*') AS result FROM v_transactions_internal_alive v_transactions_internal
LEFT JOIN accounts accounts1 ON accounts1.id = v_transactions_internal.account AND accounts1.tombstone = 0
WHERE (accounts1.id = 'a1c0ffee-0002-4a11-8a11-c4ec0000a002') AND v_transactions_internal.is_parent = 0 AND v_transactions_internal.tombstone = 0
ORDER BY v_transactions_internal.date desc, v_transactions_internal.starting_balance_flag, v_transactions_internal.sort_order desc, v_transactions_internal.id;

-- @id actual.register.search_all
-- @src packages/desktop-client/src/queries/index.ts:84-140; packages/loot-core/src/server/aql/schema/executors.ts:147-171
-- @style AQL compiled by the real loot-core compiler + executors (bundled from the pinned source, run on node:sqlite); values inlined as literals by the compiler, no binds
-- @tags hotpath,cpu-evidence,dynamic
-- @note Register search for 'coffee' over all accounts (unhappy path): GROUP_CONCAT of matched ids per split group, then re-join every view to sort and page. https://github.com/actualbudget/actual/issues/5619
-- @modified UNICODE_LIKE(p, NORMALISE(x)) (app functions registered on the connection: case-insensitive, diacritic-stripping LIKE) replaced with core lower(x) LIKE p; UNICODE_LOWER(x) -> lower(x)
SELECT group_id, matched FROM (
SELECT
group_id,
GROUP_CONCAT(id) as matched
FROM (
SELECT v_transactions_internal.id, IFNULL(v_transactions_internal.parent_id, v_transactions_internal.id) as group_id
FROM v_transactions_internal
LEFT JOIN transactions _t2 ON v_transactions_internal.is_child = 1 AND _t2.id = v_transactions_internal.parent_id
LEFT JOIN accounts accounts1 ON accounts1.id = v_transactions_internal.account AND accounts1.tombstone = 0
LEFT JOIN v_categories categories2 ON categories2.id = v_transactions_internal.category AND categories2.tombstone = 0
LEFT JOIN v_payees payees3 ON payees3.id = v_transactions_internal.payee AND payees3.tombstone = 0
LEFT JOIN v_schedules schedules4 ON schedules4.id = v_transactions_internal.schedule AND schedules4.tombstone = 0
LEFT JOIN accounts accounts5 ON accounts5.id = payees3.transfer_acct AND accounts5.tombstone = 0
WHERE ((lower(payees3.name) LIKE '%coffee%'
OR lower(accounts5.name) LIKE '%coffee%'
OR lower(v_transactions_internal.notes) LIKE '%coffee%'
OR lower(categories2.name) LIKE '%coffee%'
OR lower(accounts1.name) LIKE '%coffee%')) AND v_transactions_internal.tombstone = 0 AND IFNULL(_t2.tombstone, 0) = 0
)
GROUP BY group_id
)
LEFT JOIN v_transactions_internal ON v_transactions_internal.id = group_id
LEFT JOIN accounts accounts1 ON accounts1.id = v_transactions_internal.account AND accounts1.tombstone = 0
LEFT JOIN v_categories categories2 ON categories2.id = v_transactions_internal.category AND categories2.tombstone = 0
LEFT JOIN v_payees payees3 ON payees3.id = v_transactions_internal.payee AND payees3.tombstone = 0
LEFT JOIN v_schedules schedules4 ON schedules4.id = v_transactions_internal.schedule AND schedules4.tombstone = 0
LEFT JOIN accounts accounts5 ON accounts5.id = payees3.transfer_acct AND accounts5.tombstone = 0
ORDER BY v_transactions_internal.date desc, v_transactions_internal.starting_balance_flag, v_transactions_internal.sort_order desc, v_transactions_internal.id
LIMIT 150;

-- @id actual.register.running_balance
-- @src packages/desktop-client/src/components/accounts/Account.tsx:776-794; packages/loot-core/src/server/aql/compiler.ts:550-560
-- @style AQL compiled by the real loot-core compiler + executors (bundled from the pinned source, run on node:sqlite); values inlined as literals by the compiler, no binds
-- @tags hotpath,analytics,cpu-evidence,dynamic
-- @note Running balances for the whole Checking register: $sumOver compiles to SUM() OVER (ORDER BY ... ROWS BETWEEN CURRENT ROW AND UNBOUNDED FOLLOWING), no LIMIT. 802 ms under 4x throttling in the browser before PR https://github.com/actualbudget/actual/pull/8335
SELECT (SUM(v_transactions_internal_alive.amount) OVER (ORDER BY v_transactions_internal_alive.date desc, v_transactions_internal_alive.starting_balance_flag, v_transactions_internal_alive.sort_order desc, v_transactions_internal_alive.id ROWS BETWEEN CURRENT ROW AND UNBOUNDED FOLLOWING)) AS balance, v_transactions_internal_alive.id AS id FROM v_transactions_internal_alive
LEFT JOIN accounts accounts1 ON accounts1.id = v_transactions_internal_alive.account AND accounts1.tombstone = 0
WHERE (accounts1.id = 'a1c0ffee-0001-4a11-8a11-c4ec0000a001') AND v_transactions_internal_alive.parent_id IS NULL AND v_transactions_internal_alive.tombstone = 0
ORDER BY v_transactions_internal_alive.date desc, v_transactions_internal_alive.starting_balance_flag, v_transactions_internal_alive.sort_order desc, v_transactions_internal_alive.id;

-- @id actual.register.filter_category_notes
-- @src packages/desktop-client/src/components/accounts/Account.tsx:1653-1700; packages/loot-core/src/server/transactions/transaction-rules.ts:493-720
-- @style AQL compiled by the real loot-core compiler + executors (bundled from the pinned source, run on node:sqlite); values inlined as literals by the compiler, no binds
-- @tags hotpath,dynamic
-- @note Register filter 'category one of Restaurants/Takeout/Coffee AND notes contains trip': conditions compiled by the real conditionsToAQL, so a non-account filter takes the GROUP_CONCAT path.
-- @modified UNICODE_LIKE(p, NORMALISE(x)) (app functions registered on the connection: case-insensitive, diacritic-stripping LIKE) replaced with core lower(x) LIKE p; UNICODE_LOWER(x) -> lower(x)
SELECT group_id, matched FROM (
SELECT
group_id,
GROUP_CONCAT(id) as matched
FROM (
SELECT v_transactions_internal.id, IFNULL(v_transactions_internal.parent_id, v_transactions_internal.id) as group_id
FROM v_transactions_internal
LEFT JOIN transactions _t2 ON v_transactions_internal.is_child = 1 AND _t2.id = v_transactions_internal.parent_id
LEFT JOIN accounts accounts1 ON accounts1.id = v_transactions_internal.account AND accounts1.tombstone = 0
LEFT JOIN v_categories categories2 ON categories2.id = v_transactions_internal.category AND categories2.tombstone = 0
LEFT JOIN v_payees payees3 ON payees3.id = v_transactions_internal.payee AND payees3.tombstone = 0
LEFT JOIN v_schedules schedules4 ON schedules4.id = v_transactions_internal.schedule AND schedules4.tombstone = 0
WHERE (((categories2.id = '3c6ef362-3c6e-4dde-9232-00010bd794ee'
OR categories2.id = '850d3e43-84f5-499d-9ffb-001aadf955b5'
OR categories2.id = '17156075-1713-4aab-9d7d-00029d9af453')
AND lower(lower(v_transactions_internal.notes)) LIKE '%trip%')) AND v_transactions_internal.tombstone = 0 AND IFNULL(_t2.tombstone, 0) = 0
)
GROUP BY group_id
)
LEFT JOIN v_transactions_internal ON v_transactions_internal.id = group_id
LEFT JOIN accounts accounts1 ON accounts1.id = v_transactions_internal.account AND accounts1.tombstone = 0
LEFT JOIN v_categories categories2 ON categories2.id = v_transactions_internal.category AND categories2.tombstone = 0
LEFT JOIN v_payees payees3 ON payees3.id = v_transactions_internal.payee AND payees3.tombstone = 0
LEFT JOIN v_schedules schedules4 ON schedules4.id = v_transactions_internal.schedule AND schedules4.tombstone = 0
ORDER BY v_transactions_internal.date desc, v_transactions_internal.starting_balance_flag, v_transactions_internal.sort_order desc, v_transactions_internal.id
LIMIT 150;

-- @id actual.report.custom_monthly_debts
-- @src packages/desktop-client/src/components/reports/spreadsheets/makeQuery.ts:6-75; packages/desktop-client/src/components/reports/spreadsheets/fetchSpreadsheetQueryData.ts:54-77
-- @style AQL compiled by the real loot-core compiler + executors (bundled from the pinned source, run on node:sqlite); values inlined as literals by the compiler, no binds
-- @tags analytics,dynamic
-- @note Custom report (default: spending by category, monthly, last 12 months), debts half: GROUP BY month, account, payee, category, transfer account with 5 LEFT JOINs and a CAST(SUBSTR()) month filter that no index can use.
SELECT CAST(SUBSTR(v_transactions_internal_alive.date, 1, 6) AS integer) AS date, categories1.id AS category, categories1.hidden AS categoryHidden, categories1.is_income AS categoryIncome, category_groups2.id AS categoryGroup, category_groups2.hidden AS categoryGroupHidden, accounts3.id AS account, accounts3.offbudget AS accountOffBudget, payees4.id AS payee, accounts5.id AS transferAccount, SUM(v_transactions_internal_alive.amount) AS amount FROM v_transactions_internal_alive
LEFT JOIN v_categories categories1 ON categories1.id = v_transactions_internal_alive.category AND categories1.tombstone = 0
LEFT JOIN category_groups category_groups2 ON category_groups2.id = categories1."group" AND category_groups2.tombstone = 0
LEFT JOIN accounts accounts3 ON accounts3.id = v_transactions_internal_alive.account AND accounts3.tombstone = 0
LEFT JOIN v_payees payees4 ON payees4.id = v_transactions_internal_alive.payee AND payees4.tombstone = 0
LEFT JOIN accounts accounts5 ON accounts5.id = payees4.transfer_acct AND accounts5.tombstone = 0
WHERE (1
AND (CAST(SUBSTR(v_transactions_internal_alive.date, 1, 6) AS integer) >= 202511
AND CAST(SUBSTR(v_transactions_internal_alive.date, 1, 6) AS integer) <= 202610)
AND v_transactions_internal_alive.amount < 0) AND v_transactions_internal_alive.is_parent = 0 AND v_transactions_internal_alive.tombstone = 0
GROUP BY CAST(SUBSTR(v_transactions_internal_alive.date, 1, 6) AS integer), accounts3.id, payees4.id, categories1.id, accounts5.id
ORDER BY v_transactions_internal_alive.date desc, v_transactions_internal_alive.starting_balance_flag, v_transactions_internal_alive.sort_order desc, v_transactions_internal_alive.id;

-- @id actual.report.custom_yearly_alltime
-- @src packages/desktop-client/src/components/reports/spreadsheets/makeQuery.ts:6-75
-- @style AQL compiled by the real loot-core compiler + executors (bundled from the pinned source, run on node:sqlite); values inlined as literals by the compiler, no binds
-- @tags analytics,dynamic
-- @note Custom report, yearly interval over all time (2018-2026): $year transform = CAST(SUBSTR(date,1,4) AS integer), grouping nearly every live row.
SELECT CAST(SUBSTR(v_transactions_internal_alive.date, 1, 4) AS integer) AS date, categories1.id AS category, categories1.hidden AS categoryHidden, categories1.is_income AS categoryIncome, category_groups2.id AS categoryGroup, category_groups2.hidden AS categoryGroupHidden, accounts3.id AS account, accounts3.offbudget AS accountOffBudget, payees4.id AS payee, accounts5.id AS transferAccount, SUM(v_transactions_internal_alive.amount) AS amount FROM v_transactions_internal_alive
LEFT JOIN v_categories categories1 ON categories1.id = v_transactions_internal_alive.category AND categories1.tombstone = 0
LEFT JOIN category_groups category_groups2 ON category_groups2.id = categories1."group" AND category_groups2.tombstone = 0
LEFT JOIN accounts accounts3 ON accounts3.id = v_transactions_internal_alive.account AND accounts3.tombstone = 0
LEFT JOIN v_payees payees4 ON payees4.id = v_transactions_internal_alive.payee AND payees4.tombstone = 0
LEFT JOIN accounts accounts5 ON accounts5.id = payees4.transfer_acct AND accounts5.tombstone = 0
WHERE (1
AND (CAST(SUBSTR(v_transactions_internal_alive.date, 1, 4) AS integer) >= 2018
AND CAST(SUBSTR(v_transactions_internal_alive.date, 1, 4) AS integer) <= 2026)
AND v_transactions_internal_alive.amount < 0) AND v_transactions_internal_alive.is_parent = 0 AND v_transactions_internal_alive.tombstone = 0
GROUP BY CAST(SUBSTR(v_transactions_internal_alive.date, 1, 4) AS integer), accounts3.id, payees4.id, categories1.id, accounts5.id
ORDER BY v_transactions_internal_alive.date desc, v_transactions_internal_alive.starting_balance_flag, v_transactions_internal_alive.sort_order desc, v_transactions_internal_alive.id;

-- @id actual.report.custom_by_tag
-- @src packages/desktop-client/src/components/reports/spreadsheets/makeQuery.ts:6-75
-- @style AQL compiled by the real loot-core compiler + executors (bundled from the pinned source, run on node:sqlite); values inlined as literals by the compiler, no binds
-- @tags analytics,dynamic
-- @note Custom report grouped by Tag: notes joins the GROUP BY key list, 24 months.
SELECT CAST(SUBSTR(v_transactions_internal_alive.date, 1, 6) AS integer) AS date, categories1.id AS category, categories1.hidden AS categoryHidden, categories1.is_income AS categoryIncome, category_groups2.id AS categoryGroup, category_groups2.hidden AS categoryGroupHidden, accounts3.id AS account, accounts3.offbudget AS accountOffBudget, payees4.id AS payee, accounts5.id AS transferAccount, SUM(v_transactions_internal_alive.amount) AS amount, v_transactions_internal_alive.notes AS notes FROM v_transactions_internal_alive
LEFT JOIN v_categories categories1 ON categories1.id = v_transactions_internal_alive.category AND categories1.tombstone = 0
LEFT JOIN category_groups category_groups2 ON category_groups2.id = categories1."group" AND category_groups2.tombstone = 0
LEFT JOIN accounts accounts3 ON accounts3.id = v_transactions_internal_alive.account AND accounts3.tombstone = 0
LEFT JOIN v_payees payees4 ON payees4.id = v_transactions_internal_alive.payee AND payees4.tombstone = 0
LEFT JOIN accounts accounts5 ON accounts5.id = payees4.transfer_acct AND accounts5.tombstone = 0
WHERE (1
AND (CAST(SUBSTR(v_transactions_internal_alive.date, 1, 6) AS integer) >= 202411
AND CAST(SUBSTR(v_transactions_internal_alive.date, 1, 6) AS integer) <= 202610)
AND v_transactions_internal_alive.amount < 0) AND v_transactions_internal_alive.is_parent = 0 AND v_transactions_internal_alive.tombstone = 0
GROUP BY CAST(SUBSTR(v_transactions_internal_alive.date, 1, 6) AS integer), accounts3.id, payees4.id, categories1.id, accounts5.id, v_transactions_internal_alive.notes
ORDER BY v_transactions_internal_alive.date desc, v_transactions_internal_alive.starting_balance_flag, v_transactions_internal_alive.sort_order desc, v_transactions_internal_alive.id;

-- @id actual.report.custom_filtered_categories
-- @src packages/desktop-client/src/components/reports/spreadsheets/makeQuery.ts:6-75; packages/loot-core/src/server/transactions/transaction-rules.ts:685-691
-- @style AQL compiled by the real loot-core compiler + executors (bundled from the pinned source, run on node:sqlite); values inlined as literals by the compiler, no binds
-- @tags analytics,dynamic
-- @note Custom report filtered to 4 categories over 3 years: conditionsToAQL 'oneOf' becomes an OR of equalities on the joined v_categories id.
SELECT CAST(SUBSTR(v_transactions_internal_alive.date, 1, 6) AS integer) AS date, categories1.id AS category, categories1.hidden AS categoryHidden, categories1.is_income AS categoryIncome, category_groups2.id AS categoryGroup, category_groups2.hidden AS categoryGroupHidden, accounts3.id AS account, accounts3.offbudget AS accountOffBudget, payees4.id AS payee, accounts5.id AS transferAccount, SUM(v_transactions_internal_alive.amount) AS amount FROM v_transactions_internal_alive
LEFT JOIN v_categories categories1 ON categories1.id = v_transactions_internal_alive.category AND categories1.tombstone = 0
LEFT JOIN category_groups category_groups2 ON category_groups2.id = categories1."group" AND category_groups2.tombstone = 0
LEFT JOIN accounts accounts3 ON accounts3.id = v_transactions_internal_alive.account AND accounts3.tombstone = 0
LEFT JOIN v_payees payees4 ON payees4.id = v_transactions_internal_alive.payee AND payees4.tombstone = 0
LEFT JOIN accounts accounts5 ON accounts5.id = payees4.transfer_acct AND accounts5.tombstone = 0
WHERE (((categories1.id = '9e3779b1-9e37-4eef-9919-000085ebca77'
OR categories1.id = '3c6ef362-3c6e-4dde-9232-00010bd794ee'
OR categories1.id = 'daa66d13-daa5-4ccd-9b4b-000191c35f65'
OR categories1.id = '78dde6c4-78dc-4bbc-9464-000217af29dc'))
AND (CAST(SUBSTR(v_transactions_internal_alive.date, 1, 6) AS integer) >= 202311
AND CAST(SUBSTR(v_transactions_internal_alive.date, 1, 6) AS integer) <= 202610)
AND v_transactions_internal_alive.amount < 0) AND v_transactions_internal_alive.is_parent = 0 AND v_transactions_internal_alive.tombstone = 0
GROUP BY CAST(SUBSTR(v_transactions_internal_alive.date, 1, 6) AS integer), accounts3.id, payees4.id, categories1.id, accounts5.id
ORDER BY v_transactions_internal_alive.date desc, v_transactions_internal_alive.starting_balance_flag, v_transactions_internal_alive.sort_order desc, v_transactions_internal_alive.id;

-- @id actual.report.spending_daily
-- @src packages/desktop-client/src/components/reports/spreadsheets/makeQuery.ts:6-75; packages/desktop-client/src/components/reports/spreadsheets/spending-spreadsheet.ts:121-142
-- @style AQL compiled by the real loot-core compiler + executors (bundled from the pinned source, run on node:sqlite); values inlined as literals by the compiler, no binds
-- @tags analytics,dynamic
-- @note Spending report (month-to-date vs average): makeQuery with the Daily interval, grouping by day over 4 months.
SELECT v_transactions_internal_alive.date AS date, categories1.id AS category, categories1.hidden AS categoryHidden, categories1.is_income AS categoryIncome, category_groups2.id AS categoryGroup, category_groups2.hidden AS categoryGroupHidden, accounts3.id AS account, accounts3.offbudget AS accountOffBudget, payees4.id AS payee, accounts5.id AS transferAccount, SUM(v_transactions_internal_alive.amount) AS amount FROM v_transactions_internal_alive
LEFT JOIN v_categories categories1 ON categories1.id = v_transactions_internal_alive.category AND categories1.tombstone = 0
LEFT JOIN category_groups category_groups2 ON category_groups2.id = categories1."group" AND category_groups2.tombstone = 0
LEFT JOIN accounts accounts3 ON accounts3.id = v_transactions_internal_alive.account AND accounts3.tombstone = 0
LEFT JOIN v_payees payees4 ON payees4.id = v_transactions_internal_alive.payee AND payees4.tombstone = 0
LEFT JOIN accounts accounts5 ON accounts5.id = payees4.transfer_acct AND accounts5.tombstone = 0
WHERE (1
AND (v_transactions_internal_alive.date >= 20260701
AND v_transactions_internal_alive.date <= 20261031)
AND v_transactions_internal_alive.amount < 0) AND v_transactions_internal_alive.is_parent = 0 AND v_transactions_internal_alive.tombstone = 0
GROUP BY v_transactions_internal_alive.date, accounts3.id, payees4.id, categories1.id, accounts5.id
ORDER BY v_transactions_internal_alive.date desc, v_transactions_internal_alive.starting_balance_flag, v_transactions_internal_alive.sort_order desc, v_transactions_internal_alive.id;

-- @id actual.report.spending_budgets
-- @src packages/desktop-client/src/components/reports/spreadsheets/spending-spreadsheet.ts:214-226
-- @style AQL compiled by the real loot-core compiler + executors (bundled from the pinned source, run on node:sqlite); values inlined as literals by the compiler, no binds
-- @tags analytics,dynamic
-- @note Spending report budget line: zero_budgets for one month grouped by category (no index on month).
SELECT zero_budgets.category AS category, SUM(zero_budgets.amount) AS amount FROM zero_budgets
WHERE ((zero_budgets.month = 202610))
GROUP BY zero_budgets.category;

-- @id actual.report.net_worth_account_monthly
-- @src packages/desktop-client/src/components/reports/spreadsheets/net-worth-spreadsheet.ts:150-180
-- @style AQL compiled by the real loot-core compiler + executors (bundled from the pinned source, run on node:sqlite); values inlined as literals by the compiler, no binds
-- @tags analytics,dynamic
-- @note Net worth graph: per-account monthly sums, run once per account (14x per render); here Checking over all 8 years.
SELECT CAST(SUBSTR(v_transactions_internal_alive.date, 1, 6) AS integer) AS date, SUM(v_transactions_internal_alive.amount) AS amount FROM v_transactions_internal_alive
LEFT JOIN accounts accounts1 ON accounts1.id = v_transactions_internal_alive.account AND accounts1.tombstone = 0
WHERE (1
AND accounts1.id = 'a1c0ffee-0001-4a11-8a11-c4ec0000a001'
AND (v_transactions_internal_alive.date >= 20181101
AND v_transactions_internal_alive.date <= 20261031)) AND v_transactions_internal_alive.is_parent = 0 AND v_transactions_internal_alive.tombstone = 0
GROUP BY CAST(SUBSTR(v_transactions_internal_alive.date, 1, 6) AS integer)
ORDER BY v_transactions_internal_alive.date desc, v_transactions_internal_alive.starting_balance_flag, v_transactions_internal_alive.sort_order desc, v_transactions_internal_alive.id;

-- @id actual.report.net_worth_transfer_legs
-- @src packages/desktop-client/src/components/reports/spreadsheets/net-worth-spreadsheet.ts:118-135
-- @style AQL compiled by the real loot-core compiler + executors (bundled from the pinned source, run on node:sqlite); values inlined as literals by the compiler, no binds
-- @tags analytics,dynamic
-- @note Net worth: every transfer leg of the 14 accounts up to the end date (account IN list on the joined accounts row, transfer_id IS NOT NULL).
SELECT v_transactions_internal_alive.id AS id, accounts1.id AS account, v_transactions_internal_alive.amount AS amount, v_transactions_internal_alive.date AS date, v_transactions_internal_alive.transfer_id AS transfer_id FROM v_transactions_internal_alive
LEFT JOIN accounts accounts1 ON accounts1.id = v_transactions_internal_alive.account AND accounts1.tombstone = 0
WHERE (1
AND accounts1.id IN ('a1c0ffee-0001-4a11-8a11-c4ec0000a001','a1c0ffee-0002-4a11-8a11-c4ec0000a002','a1c0ffee-0003-4a11-8a11-c4ec0000a003','a1c0ffee-0004-4a11-8a11-c4ec0000a004','a1c0ffee-0005-4a11-8a11-c4ec0000a005','a1c0ffee-0006-4a11-8a11-c4ec0000a006','a1c0ffee-0007-4a11-8a11-c4ec0000a007','a1c0ffee-0008-4a11-8a11-c4ec0000a008','a1c0ffee-0009-4a11-8a11-c4ec0000a009','a1c0ffee-0010-4a11-8a11-c4ec0000a010','a1c0ffee-0011-4a11-8a11-c4ec0000a011','a1c0ffee-0012-4a11-8a11-c4ec0000a012','a1c0ffee-0013-4a11-8a11-c4ec0000a013','a1c0ffee-0014-4a11-8a11-c4ec0000a014')
AND v_transactions_internal_alive.transfer_id IS NOT NULL
AND v_transactions_internal_alive.date <= 20261031) AND v_transactions_internal_alive.is_parent = 0 AND v_transactions_internal_alive.tombstone = 0
ORDER BY v_transactions_internal_alive.date desc, v_transactions_internal_alive.starting_balance_flag, v_transactions_internal_alive.sort_order desc, v_transactions_internal_alive.id;

-- @id actual.report.cash_flow_daily_income
-- @src packages/desktop-client/src/components/reports/spreadsheets/cash-flow-spreadsheet.tsx:97-139
-- @style AQL compiled by the real loot-core compiler + executors (bundled from the pinned source, run on node:sqlite); values inlined as literals by the compiler, no binds
-- @tags analytics,dynamic
-- @note Cash flow report, 12 months daily, income half: GROUP BY date and the payee's transfer account.
SELECT v_transactions_internal_alive.date AS date, accounts2.id AS isTransfer, SUM(v_transactions_internal_alive.amount) AS amount FROM v_transactions_internal_alive
LEFT JOIN v_payees payees1 ON payees1.id = v_transactions_internal_alive.payee AND payees1.tombstone = 0
LEFT JOIN accounts accounts2 ON accounts2.id = payees1.transfer_acct AND accounts2.tombstone = 0
LEFT JOIN accounts accounts3 ON accounts3.id = v_transactions_internal_alive.account AND accounts3.tombstone = 0
WHERE (1
AND (CAST(SUBSTR(v_transactions_internal_alive.date, 1, 6) AS integer) >= 202511
AND CAST(SUBSTR(v_transactions_internal_alive.date, 1, 6) AS integer) <= 202610)
AND accounts3.offbudget = 0
AND v_transactions_internal_alive.amount > 0) AND v_transactions_internal_alive.is_parent = 0 AND v_transactions_internal_alive.tombstone = 0
GROUP BY v_transactions_internal_alive.date, accounts2.id
ORDER BY v_transactions_internal_alive.date desc, v_transactions_internal_alive.starting_balance_flag, v_transactions_internal_alive.sort_order desc, v_transactions_internal_alive.id;

-- @id actual.report.cash_flow_concise_expense
-- @src packages/desktop-client/src/components/reports/spreadsheets/cash-flow-spreadsheet.tsx:97-139
-- @style AQL compiled by the real loot-core compiler + executors (bundled from the pinned source, run on node:sqlite); values inlined as literals by the compiler, no binds
-- @tags analytics,dynamic
-- @note Cash flow report, 3 years (concise = monthly), expense half: GROUP BY CAST(SUBSTR(date,1,6)) and transfer account.
SELECT CAST(SUBSTR(v_transactions_internal_alive.date, 1, 6) AS integer) AS date, accounts2.id AS isTransfer, SUM(v_transactions_internal_alive.amount) AS amount FROM v_transactions_internal_alive
LEFT JOIN v_payees payees1 ON payees1.id = v_transactions_internal_alive.payee AND payees1.tombstone = 0
LEFT JOIN accounts accounts2 ON accounts2.id = payees1.transfer_acct AND accounts2.tombstone = 0
LEFT JOIN accounts accounts3 ON accounts3.id = v_transactions_internal_alive.account AND accounts3.tombstone = 0
WHERE (1
AND (CAST(SUBSTR(v_transactions_internal_alive.date, 1, 6) AS integer) >= 202311
AND CAST(SUBSTR(v_transactions_internal_alive.date, 1, 6) AS integer) <= 202610)
AND accounts3.offbudget = 0
AND v_transactions_internal_alive.amount < 0) AND v_transactions_internal_alive.is_parent = 0 AND v_transactions_internal_alive.tombstone = 0
GROUP BY CAST(SUBSTR(v_transactions_internal_alive.date, 1, 6) AS integer), accounts2.id
ORDER BY v_transactions_internal_alive.date desc, v_transactions_internal_alive.starting_balance_flag, v_transactions_internal_alive.sort_order desc, v_transactions_internal_alive.id;

-- @id actual.report.summary_avg_per_month
-- @src packages/desktop-client/src/components/reports/spreadsheets/summary-spreadsheet.ts:85-118
-- @style AQL compiled by the real loot-core compiler + executors (bundled from the pinned source, run on node:sqlite); values inlined as literals by the compiler, no binds
-- @tags analytics,dynamic
-- @note Summary card (average per month): SUM and COUNT grouped by date for 12 months.
SELECT v_transactions_internal_alive.date AS date, SUM(v_transactions_internal_alive.amount) AS amount, COUNT('*') AS count FROM v_transactions_internal_alive
WHERE ((v_transactions_internal_alive.date >= 20251101
AND v_transactions_internal_alive.date <= 20261031)
AND 1) AND v_transactions_internal_alive.is_parent = 0 AND v_transactions_internal_alive.tombstone = 0
GROUP BY v_transactions_internal_alive.date
ORDER BY v_transactions_internal_alive.date desc, v_transactions_internal_alive.starting_balance_flag, v_transactions_internal_alive.sort_order desc, v_transactions_internal_alive.id;

-- @id actual.report.crossover_expenses
-- @src packages/desktop-client/src/components/reports/spreadsheets/crossover-spreadsheet.ts:128-143
-- @style AQL compiled by the real loot-core compiler + executors (bundled from the pinned source, run on node:sqlite); values inlined as literals by the compiler, no binds
-- @tags analytics,dynamic
-- @note Crossover-point report: monthly expenses for all 75 expense categories, built as a 75-way OR of category equalities, over all 8 years.
SELECT CAST(SUBSTR(v_transactions_internal_alive.date, 1, 6) AS integer) AS date, SUM(v_transactions_internal_alive.amount) AS amount FROM v_transactions_internal_alive
LEFT JOIN v_categories categories1 ON categories1.id = v_transactions_internal_alive.category AND categories1.tombstone = 0
WHERE (((categories1.id = '9e3779b1-9e37-4eef-9919-000085ebca77'
OR categories1.id = '3c6ef362-3c6e-4dde-9232-00010bd794ee'
OR categories1.id = 'daa66d13-daa5-4ccd-9b4b-000191c35f65'
OR categories1.id = '78dde6c4-78dc-4bbc-9464-000217af29dc'
OR categories1.id = '17156075-1713-4aab-9d7d-00029d9af453'
OR categories1.id = 'b54cda26-b54a-499a-9696-00032386beca'
OR categories1.id = '538453d7-5381-4889-9faf-0003a9728941'
OR categories1.id = 'f1bbcd88-f1b8-4778-98c8-00042f5e53b8'
OR categories1.id = '8ff34739-8fef-4667-91e1-0004b54a1e2f'
OR categories1.id = '2e2ac0ea-2e26-4556-9afa-00053b35e8a6'
OR categories1.id = 'cc623a9b-cc5d-4445-9413-0005c121b31d'
OR categories1.id = '6a99b44c-6a94-4334-9d2c-0006470d7d94'
OR categories1.id = '08d12dfd-08cb-4223-9645-0006ccf9480b'
OR categories1.id = 'a708a7ae-a702-4112-9f5e-000752e51282'
OR categories1.id = '4540215f-4539-4001-9877-0007d8d0dcf9'
OR categories1.id = 'e3779b10-e370-4ef0-9190-00085ebca770'
OR categories1.id = '81af14c1-81a7-4ddf-9aa9-0008e4a871e7'
OR categories1.id = '1fe68e72-1fde-4cce-93c2-00096a943c5e'
OR categories1.id = 'be1e0823-be15-4bbd-9cdb-0009f08006d5'
OR categories1.id = '5c5581d4-5c4c-4aac-95f4-000a766bd14c'
OR categories1.id = 'fa8cfb85-fa83-499b-9f0d-000afc579bc3'
OR categories1.id = '98c47536-98ba-488a-9826-000b8243663a'
OR categories1.id = '36fbeee7-36f1-4779-913f-000c082f30b1'
OR categories1.id = 'd5336898-d528-4668-9a58-000c8e1afb28'
OR categories1.id = '736ae249-735f-4557-9371-000d1406c59f'
OR categories1.id = '11a25bfa-1196-4446-9c8a-000d99f29016'
OR categories1.id = 'afd9d5ab-afcd-4335-95a3-000e1fde5a8d'
OR categories1.id = '4e114f5c-4e04-4224-9ebc-000ea5ca2504'
OR categories1.id = 'ec48c90d-ec3b-4113-97d5-000f2bb5ef7b'
OR categories1.id = '8a8042be-8a72-4002-90ee-000fb1a1b9f2'
OR categories1.id = '28b7bc6f-28a9-4ef1-9a07-0010378d8469'
OR categories1.id = 'c6ef3620-c6e0-4de0-9320-0010bd794ee0'
OR categories1.id = '6526afd1-6517-4ccf-9c39-001143651957'
OR categories1.id = '035e2982-034e-4bbe-9552-0011c950e3ce'
OR categories1.id = 'a195a333-a185-4aad-9e6b-00124f3cae45'
OR categories1.id = '3fcd1ce4-3fbc-499c-9784-0012d52878bc'
OR categories1.id = 'de049695-ddf3-488b-909d-00135b144333'
OR categories1.id = '7c3c1046-7c2a-477a-99b6-0013e1000daa'
OR categories1.id = '1a7389f7-1a61-4669-92cf-001466ebd821'
OR categories1.id = 'b8ab03a8-b898-4558-9be8-0014ecd7a298'
OR categories1.id = '56e27d59-56cf-4447-9501-001572c36d0f'
OR categories1.id = 'f519f70a-f506-4336-9e1a-0015f8af3786'
OR categories1.id = '935170bb-933d-4225-9733-00167e9b01fd'
OR categories1.id = '3188ea6c-3174-4114-904c-00170486cc74'
OR categories1.id = 'cfc0641d-cfab-4003-9965-00178a7296eb'
OR categories1.id = '6df7ddce-6de2-4ef2-927e-0018105e6162'
OR categories1.id = '0c2f577f-0c19-4de1-9b97-0018964a2bd9'
OR categories1.id = 'aa66d130-aa50-4cd0-94b0-00191c35f650'
OR categories1.id = '489e4ae1-4887-4bbf-9dc9-0019a221c0c7'
OR categories1.id = 'e6d5c492-e6be-4aae-96e2-001a280d8b3e'
OR categories1.id = '850d3e43-84f5-499d-9ffb-001aadf955b5'
OR categories1.id = '2344b7f4-232c-488c-9914-001b33e5202c'
OR categories1.id = 'c17c31a5-c163-477b-922d-001bb9d0eaa3'
OR categories1.id = '5fb3ab56-5f9a-466a-9b46-001c3fbcb51a'
OR categories1.id = 'fdeb2507-fdd1-4559-945f-001cc5a87f91'
OR categories1.id = '9c229eb8-9c08-4448-9d78-001d4b944a08'
OR categories1.id = '3a5a1869-3a3f-4337-9691-001dd180147f'
OR categories1.id = 'd891921a-d876-4226-9faa-001e576bdef6'
OR categories1.id = '76c90bcb-76ad-4115-98c3-001edd57a96d'
OR categories1.id = '1500857c-14e4-4004-91dc-001f634373e4'
OR categories1.id = 'b337ff2d-b31b-4ef3-9af5-001fe92f3e5b'
OR categories1.id = '516f78de-5152-4de2-940e-00206f1b08d2'
OR categories1.id = 'efa6f28f-ef89-4cd1-9d27-0020f506d349'
OR categories1.id = '8dde6c40-8dc0-4bc0-9640-00217af29dc0'
OR categories1.id = '2c15e5f1-2bf7-4aaf-9f59-002200de6837'
OR categories1.id = 'ca4d5fa2-ca2e-499e-9872-002286ca32ae'
OR categories1.id = '6884d953-6865-488d-918b-00230cb5fd25'
OR categories1.id = '06bc5304-069c-477c-9aa4-002392a1c79c'
OR categories1.id = 'a4f3ccb5-a4d3-466b-93bd-0024188d9213'
OR categories1.id = '432b4666-430a-455a-9cd6-00249e795c8a'
OR categories1.id = 'e162c017-e141-4449-95ef-002524652701'
OR categories1.id = '7f9a39c8-7f78-4338-9f08-0025aa50f178'
OR categories1.id = '1dd1b379-1daf-4227-9821-0026303cbbef'
OR categories1.id = 'bc092d2a-bbe6-4116-913a-0026b6288666'
OR categories1.id = '5a40a6db-5a1d-4005-9a53-00273c1450dd')
AND v_transactions_internal_alive.date >= 20181101
AND v_transactions_internal_alive.date <= 20261031)) AND v_transactions_internal_alive.is_parent = 0 AND v_transactions_internal_alive.tombstone = 0
GROUP BY CAST(SUBSTR(v_transactions_internal_alive.date, 1, 6) AS integer)
ORDER BY v_transactions_internal_alive.date desc, v_transactions_internal_alive.starting_balance_flag, v_transactions_internal_alive.sort_order desc, v_transactions_internal_alive.id;

-- @id actual.report.age_of_money_income
-- @src packages/desktop-client/src/components/reports/spreadsheets/age-of-money-spreadsheet.ts:418-438,500-516
-- @style AQL compiled by the real loot-core compiler + executors (bundled from the pinned source, run on node:sqlite); values inlined as literals by the compiler, no binds
-- @tags analytics,dynamic
-- @note Age of money: the whole income history (FIFO needs every row up to today), excluding on-budget transfers, ordered by the default transaction order.
SELECT v_transactions_internal_alive.id AS id, v_transactions_internal_alive.date AS date, v_transactions_internal_alive.amount AS amount FROM v_transactions_internal_alive
LEFT JOIN accounts accounts1 ON accounts1.id = v_transactions_internal_alive.account AND accounts1.tombstone = 0
LEFT JOIN v_payees payees2 ON payees2.id = v_transactions_internal_alive.payee AND payees2.tombstone = 0
LEFT JOIN accounts accounts3 ON accounts3.id = payees2.transfer_acct AND accounts3.tombstone = 0
WHERE (1
AND v_transactions_internal_alive.date <= 20261030
AND accounts1.offbudget = 0
AND (accounts3.id IS NULL
OR accounts3.offbudget = 1)
AND v_transactions_internal_alive.amount > 0) AND v_transactions_internal_alive.is_parent = 0 AND v_transactions_internal_alive.tombstone = 0
ORDER BY v_transactions_internal_alive.date desc, v_transactions_internal_alive.starting_balance_flag, v_transactions_internal_alive.sort_order desc, v_transactions_internal_alive.id;

-- @id actual.payees.common
-- @src packages/loot-core/src/server/db/index.ts:667-693
-- @style raw SQL string in loot-core; values interpolated with template literals (copied, interpolation resolved)
-- @tags hotpath,analytics
-- @note Payee autocomplete 'frequently used': count and latest date per payee over the last 12 weeks (date literal resolved for 2026-10-30), top 10.
SELECT p.id as id, p.name as name, p.favorite as favorite,
p.category as category, TRUE as common, NULL as transfer_acct,
count(*) as c,
max(t.date) as latest
FROM payees p
LEFT JOIN v_transactions_internal_alive t on t.payee == p.id
WHERE LENGTH(p.name) > 0
AND p.tombstone = 0
AND t.date > 20260807
GROUP BY p.id
ORDER BY c DESC ,p.transfer_acct IS NULL DESC, p.name
COLLATE NOCASE
LIMIT 10;

-- @id actual.payees.orphaned
-- @src packages/loot-core/src/server/db/index.ts:696-712
-- @style raw SQL string in loot-core; values interpolated with template literals (copied, interpolation resolved)
-- @note Orphaned payees (payee manager, after deletes/merges): anti-join of payees to all live transactions plus a NOT EXISTS over json_each of every rule's conditions.
SELECT p.id
FROM payees p
LEFT JOIN payee_mapping pm ON pm.id = p.id
LEFT JOIN v_transactions_internal_alive t ON t.payee = pm.targetId
WHERE p.tombstone = 0
AND p.transfer_acct IS NULL
AND t.id IS NULL
AND NOT EXISTS (
SELECT 1
FROM rules r,
json_each(r.conditions) as cond
WHERE r.tombstone = 0
AND json_extract(cond.value, '$.field') = 'description'
AND json_extract(cond.value, '$.value') = pm.targetId
);

-- @id actual.schedules.discover_window
-- @src packages/loot-core/src/server/schedules/find-schedules.ts:23-40
-- @style AQL compiled by the real loot-core compiler + executors (bundled from the pinned source, run on node:sqlite); values inlined as literals by the compiler, no binds
-- @tags hot-small,dynamic
-- @note Schedule discovery: one account's unscheduled, non-transfer rows within +-2 days of a date (run per candidate date).
SELECT v_transactions_internal_alive.id AS id, v_transactions_internal_alive.is_parent AS is_parent, v_transactions_internal_alive.is_child AS is_child, v_transactions_internal_alive.parent_id AS parent_id, accounts1.id AS account, categories2.id AS category, v_transactions_internal_alive.amount AS amount, payees3.id AS payee, v_transactions_internal_alive.notes AS notes, v_transactions_internal_alive.date AS date, v_transactions_internal_alive.imported_id AS imported_id, v_transactions_internal_alive.error AS error, v_transactions_internal_alive.imported_payee AS imported_payee, v_transactions_internal_alive.starting_balance_flag AS starting_balance_flag, v_transactions_internal_alive.transfer_id AS transfer_id, v_transactions_internal_alive.sort_order AS sort_order, v_transactions_internal_alive.cleared AS cleared, v_transactions_internal_alive.reconciled AS reconciled, v_transactions_internal_alive.tombstone AS tombstone, schedules4.id AS schedule, v_transactions_internal_alive.raw_synced_data AS raw_synced_data FROM v_transactions_internal_alive
LEFT JOIN accounts accounts1 ON accounts1.id = v_transactions_internal_alive.account AND accounts1.tombstone = 0
LEFT JOIN v_categories categories2 ON categories2.id = v_transactions_internal_alive.category AND categories2.tombstone = 0
LEFT JOIN v_payees payees3 ON payees3.id = v_transactions_internal_alive.payee AND payees3.tombstone = 0
LEFT JOIN v_schedules schedules4 ON schedules4.id = v_transactions_internal_alive.schedule AND schedules4.tombstone = 0
LEFT JOIN accounts accounts5 ON accounts5.id = payees3.transfer_acct AND accounts5.tombstone = 0
WHERE (accounts1.id = 'a1c0ffee-0001-4a11-8a11-c4ec0000a001'
AND schedules4.id IS NULL
AND accounts5.id IS NULL
AND (v_transactions_internal_alive.date >= 20260928
AND v_transactions_internal_alive.date <= 20261002)) AND v_transactions_internal_alive.parent_id IS NULL AND v_transactions_internal_alive.tombstone = 0
ORDER BY v_transactions_internal_alive.date desc, v_transactions_internal_alive.starting_balance_flag, v_transactions_internal_alive.sort_order desc, v_transactions_internal_alive.id;
