-- Small statements on the TPC-H SF0.1 database (bench/small/run.sh), each named <class>:<what>, for the parity bar
-- (turbo within 1.02x of stock on small queries). Classes as in bench/classes.tsv.
-- name: point:orders-pk
SELECT o_totalprice, o_orderdate FROM orders WHERE o_orderkey = 12353;
-- name: point:customer-pk
SELECT c_name, c_acctbal FROM customer WHERE c_custkey = 4242;
-- name: point:join-pk
SELECT o_orderdate, c_name FROM orders, customer WHERE o_orderkey = 12353 AND c_custkey = o_custkey;
-- name: point:partsupp-composite
SELECT ps_availqty, ps_supplycost FROM partsupp WHERE ps_partkey = 777 AND ps_suppkey = 278;
-- name: range:lineitem-of-order
SELECT l_linenumber, l_quantity, l_extendedprice FROM lineitem WHERE l_orderkey = 12353;
-- name: range:orders-of-customer
SELECT o_orderkey, o_totalprice FROM orders WHERE o_custkey = 1234;
-- name: range:count-week
SELECT count(*) FROM orders WHERE o_orderdate BETWEEN '1995-01-01' AND '1995-01-07';
-- name: agg:sum-100-orders
SELECT sum(l_extendedprice) FROM lineitem WHERE l_orderkey BETWEEN 1000 AND 1100;
-- name: agg:group-nation
SELECT n_regionkey, count(*) FROM nation GROUP BY n_regionkey;
-- name: topn:customer-latest
SELECT o_orderkey FROM orders WHERE o_custkey = 1234 ORDER BY o_orderdate DESC LIMIT 3;
-- name: topn:latest-orders
SELECT o_orderkey, o_orderdate FROM orders ORDER BY o_orderdate DESC LIMIT 10;
-- name: distinct:shipmodes
SELECT DISTINCT l_shipmode FROM lineitem WHERE l_orderkey BETWEEN 1000 AND 1100;
-- name: subquery:exists
SELECT EXISTS (SELECT 1 FROM orders WHERE o_custkey = 1234);
-- name: subquery:correlated-count
SELECT c_name, (SELECT count(*) FROM orders WHERE o_custkey = c_custkey) FROM customer WHERE c_custkey BETWEEN 100 AND 110;
-- name: scan-expr:like-200-parts
SELECT count(*) FROM part WHERE p_partkey BETWEEN 1 AND 200 AND p_name LIKE '%green%';
-- name: scan-expr:nation-filter
SELECT n_name FROM nation WHERE n_regionkey = 2;
-- name: short:constants
SELECT 1, 'a', 2.5;
-- name: short:functions
SELECT abs(-5) + length('hello'), upper('x'), substr('abcdef', 2, 3);
