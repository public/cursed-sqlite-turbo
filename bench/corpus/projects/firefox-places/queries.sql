-- Firefox Places + urlbar (mozilla-firefox/firefox @ be3847db4e2bcc52fa3f078b8b4a1ff167ad158f, MPL-2.0). mozStorage /
-- Sqlite.sys.mjs with :named parameters; JS template strings are resolved to one instantiation each.
-- App-registered SQL functions (SQLFunctions.cpp) are not available in the stock CLI, so:
--   hash(s)  -> a core-SQL fingerprint (length and the last 16 characters with fixed 40-bit weights). data.sql
--              stores the same fingerprint in url_hash/page_url_hash, so url_hash probes keep using the index.
--              It is NULL for strings under 16 characters, which none of the probed URLs are.
--   fixup_url(host) -> iif(substr(host,1,4)='www.', substr(host,5), host)
--   strip_prefix_and_userinfo(url) -> substr(url, instr(url,'://') + 3)
--   AUTOCOMPLETE_MATCH(...) -> LIKE '%token%' over the same url/title/tags arguments
-- Each affected query says so in @modified.

-- @id firefox.autofill.origin_history_bookmark
-- @src browser/components/urlbar/UrlbarProviderAutofill.sys.mjs:157-249
-- @style named :params; originQuery() template with the WHERE of QUERY_ORIGIN_HISTORY_BOOKMARK (lines 305-309), preferHttps, frecency field (ORIGIN_USE_ALT_FRECENCY off)
-- @tags hotpath,dynamic
-- @note Origin autofill on every keystroke: host range scan, four window aggregates partitioned by the www-less host (one over a correlated subquery), top-1 origin, then a url_hash IN probe for the best page.
-- @modified fixup_url(host) (app-registered) replaced by iif(substr(host, 1, 4) = 'www.', substr(host, 5), host), its effect on a bare host (SQLFunctions.cpp:1181); hash() is an app-registered function; replaced by the core-SQL fingerprint that data.sql also stores in url_hash (see header)
-- @param :searchString 'site1'
-- @param :adaptiveAutofillEnabled 0
-- @param :nowMs 1792022400000
-- @param :prefix NULL
-- @param :query_type 1
WITH
autofill_frecency_threshold(value) AS (
  SELECT IFNULL((SELECT value FROM moz_meta WHERE key = 'origin_frecency_threshold'), 2.0)
),
origins(id, prefix, host_prefix, host, fixed, total_fixed_host_frecency, frecency, n_bookmarks, any_recent_typed) AS (
  SELECT id, prefix,
         first_value(prefix) OVER (PARTITION BY host ORDER BY prefix = "https://" DESC, frecency DESC, id DESC),
         host, iif(substr(host, 1, 4) = 'www.', substr(host, 5), host),
         total(frecency) OVER (PARTITION BY iif(substr(host, 1, 4) = 'www.', substr(host, 5), host)),
         frecency,
         total((SELECT total(foreign_count) FROM moz_places WHERE origin_id = o.id)) OVER (PARTITION BY iif(substr(host, 1, 4) = 'www.', substr(host, 5), host)),
         MAX(frecency > 1) OVER (PARTITION BY iif(substr(host, 1, 4) = 'www.', substr(host, 5), host))
  FROM moz_origins o
  WHERE prefix NOT IN ('about:', 'place:')
    AND ((host BETWEEN :searchString AND :searchString || X'FFFF')
      OR (host BETWEEN 'www.' || :searchString AND 'www.' || :searchString || X'FFFF'))
    AND (:adaptiveAutofillEnabled = 0 OR o.block_until_ms IS NULL OR o.block_until_ms <= :nowMs)
),
matched_origin(host_fixed, url) AS (
  SELECT iif(instr(host, :searchString) = 1, host, fixed) || '/', ifnull(:prefix, host_prefix) || host || '/'
  FROM origins
  WHERE (:adaptiveAutofillEnabled = 0 AND n_bookmarks > 0) OR (any_recent_typed AND total_fixed_host_frecency >= (SELECT value FROM autofill_frecency_threshold))
  ORDER BY total_fixed_host_frecency DESC, frecency DESC, n_bookmarks DESC, prefix = "https://" DESC, id DESC
  LIMIT 1
),
matched_place(host_fixed, url, id, title, frecency) AS (
  SELECT o.host_fixed, o.url, h.id, h.title, h.frecency
  FROM matched_origin o
  LEFT JOIN moz_places h ON h.url_hash IN ((length('https://' || o.host_fixed) * 4503599627370496 + unicode(substr('https://' || o.host_fixed, -1, 1)) * 859983745857 + unicode(substr('https://' || o.host_fixed, -2, 1)) * 620455851591 + unicode(substr('https://' || o.host_fixed, -3, 1)) * 380927957327 + unicode(substr('https://' || o.host_fixed, -4, 1)) * 141400063061 + unicode(substr('https://' || o.host_fixed, -5, 1)) * 1001383796573 + unicode(substr('https://' || o.host_fixed, -6, 1)) * 761855902307 + unicode(substr('https://' || o.host_fixed, -7, 1)) * 522328008043 + unicode(substr('https://' || o.host_fixed, -8, 1)) * 282800113777 + unicode(substr('https://' || o.host_fixed, -9, 1)) * 43272219513 + unicode(substr('https://' || o.host_fixed, -10, 1)) * 903255953023 + unicode(substr('https://' || o.host_fixed, -11, 1)) * 663728058759 + unicode(substr('https://' || o.host_fixed, -12, 1)) * 424200164493 + unicode(substr('https://' || o.host_fixed, -13, 1)) * 184672270229 + unicode(substr('https://' || o.host_fixed, -14, 1)) * 1044656003739 + unicode(substr('https://' || o.host_fixed, -15, 1)) * 805128109475 + unicode(substr('https://' || o.host_fixed, -16, 1)) * 565600215209), (length('https://www.' || o.host_fixed) * 4503599627370496 + unicode(substr('https://www.' || o.host_fixed, -1, 1)) * 859983745857 + unicode(substr('https://www.' || o.host_fixed, -2, 1)) * 620455851591 + unicode(substr('https://www.' || o.host_fixed, -3, 1)) * 380927957327 + unicode(substr('https://www.' || o.host_fixed, -4, 1)) * 141400063061 + unicode(substr('https://www.' || o.host_fixed, -5, 1)) * 1001383796573 + unicode(substr('https://www.' || o.host_fixed, -6, 1)) * 761855902307 + unicode(substr('https://www.' || o.host_fixed, -7, 1)) * 522328008043 + unicode(substr('https://www.' || o.host_fixed, -8, 1)) * 282800113777 + unicode(substr('https://www.' || o.host_fixed, -9, 1)) * 43272219513 + unicode(substr('https://www.' || o.host_fixed, -10, 1)) * 903255953023 + unicode(substr('https://www.' || o.host_fixed, -11, 1)) * 663728058759 + unicode(substr('https://www.' || o.host_fixed, -12, 1)) * 424200164493 + unicode(substr('https://www.' || o.host_fixed, -13, 1)) * 184672270229 + unicode(substr('https://www.' || o.host_fixed, -14, 1)) * 1044656003739 + unicode(substr('https://www.' || o.host_fixed, -15, 1)) * 805128109475 + unicode(substr('https://www.' || o.host_fixed, -16, 1)) * 565600215209), (length('http://' || o.host_fixed) * 4503599627370496 + unicode(substr('http://' || o.host_fixed, -1, 1)) * 859983745857 + unicode(substr('http://' || o.host_fixed, -2, 1)) * 620455851591 + unicode(substr('http://' || o.host_fixed, -3, 1)) * 380927957327 + unicode(substr('http://' || o.host_fixed, -4, 1)) * 141400063061 + unicode(substr('http://' || o.host_fixed, -5, 1)) * 1001383796573 + unicode(substr('http://' || o.host_fixed, -6, 1)) * 761855902307 + unicode(substr('http://' || o.host_fixed, -7, 1)) * 522328008043 + unicode(substr('http://' || o.host_fixed, -8, 1)) * 282800113777 + unicode(substr('http://' || o.host_fixed, -9, 1)) * 43272219513 + unicode(substr('http://' || o.host_fixed, -10, 1)) * 903255953023 + unicode(substr('http://' || o.host_fixed, -11, 1)) * 663728058759 + unicode(substr('http://' || o.host_fixed, -12, 1)) * 424200164493 + unicode(substr('http://' || o.host_fixed, -13, 1)) * 184672270229 + unicode(substr('http://' || o.host_fixed, -14, 1)) * 1044656003739 + unicode(substr('http://' || o.host_fixed, -15, 1)) * 805128109475 + unicode(substr('http://' || o.host_fixed, -16, 1)) * 565600215209), (length('http://www.' || o.host_fixed) * 4503599627370496 + unicode(substr('http://www.' || o.host_fixed, -1, 1)) * 859983745857 + unicode(substr('http://www.' || o.host_fixed, -2, 1)) * 620455851591 + unicode(substr('http://www.' || o.host_fixed, -3, 1)) * 380927957327 + unicode(substr('http://www.' || o.host_fixed, -4, 1)) * 141400063061 + unicode(substr('http://www.' || o.host_fixed, -5, 1)) * 1001383796573 + unicode(substr('http://www.' || o.host_fixed, -6, 1)) * 761855902307 + unicode(substr('http://www.' || o.host_fixed, -7, 1)) * 522328008043 + unicode(substr('http://www.' || o.host_fixed, -8, 1)) * 282800113777 + unicode(substr('http://www.' || o.host_fixed, -9, 1)) * 43272219513 + unicode(substr('http://www.' || o.host_fixed, -10, 1)) * 903255953023 + unicode(substr('http://www.' || o.host_fixed, -11, 1)) * 663728058759 + unicode(substr('http://www.' || o.host_fixed, -12, 1)) * 424200164493 + unicode(substr('http://www.' || o.host_fixed, -13, 1)) * 184672270229 + unicode(substr('http://www.' || o.host_fixed, -14, 1)) * 1044656003739 + unicode(substr('http://www.' || o.host_fixed, -15, 1)) * 805128109475 + unicode(substr('http://www.' || o.host_fixed, -16, 1)) * 565600215209))
  ORDER BY h.title IS NOT NULL DESC, h.title || '/' <> o.host_fixed DESC, h.url = o.url DESC, h.frecency DESC, h.id DESC
  LIMIT 1
)
SELECT :query_type AS query_type, :searchString AS search_string, h.host_fixed AS host_fixed, h.url AS url, ifnull(b.title, iif(h.frecency <> 0, h.title, NULL)) AS title
FROM matched_place h
LEFT JOIN moz_bookmarks b ON b.fk = h.id;

-- @id firefox.autofill.origin_prefix_history
-- @src browser/components/urlbar/UrlbarProviderAutofill.sys.mjs:157-249
-- @style named :params; originQuery() with QUERY_ORIGIN_PREFIX_HISTORY's WHERE (lines 323-327) when the user typed a scheme
-- @tags hotpath,dynamic
-- @note Origin autofill after 'https://': prefix BETWEEN filter on the windowed CTE plus the frecency-threshold CTE.
-- @modified fixup_url(host) (app-registered) replaced by iif(substr(host, 1, 4) = 'www.', substr(host, 5), host), its effect on a bare host (SQLFunctions.cpp:1181); hash() is an app-registered function; replaced by the core-SQL fingerprint that data.sql also stores in url_hash (see header)
-- @param :searchString 'mozilla'
-- @param :adaptiveAutofillEnabled 1
-- @param :nowMs 1792022400000
-- @param :prefix 'https://'
-- @param :query_type 1
WITH
autofill_frecency_threshold(value) AS (
  SELECT IFNULL((SELECT value FROM moz_meta WHERE key = 'origin_frecency_threshold'), 2.0)
),
origins(id, prefix, host_prefix, host, fixed, total_fixed_host_frecency, frecency, n_bookmarks, any_recent_typed) AS (
  SELECT id, prefix,
         first_value(prefix) OVER (PARTITION BY host ORDER BY prefix = "https://" DESC, frecency DESC, id DESC),
         host, iif(substr(host, 1, 4) = 'www.', substr(host, 5), host),
         total(frecency) OVER (PARTITION BY iif(substr(host, 1, 4) = 'www.', substr(host, 5), host)),
         frecency,
         total((SELECT total(foreign_count) FROM moz_places WHERE origin_id = o.id)) OVER (PARTITION BY iif(substr(host, 1, 4) = 'www.', substr(host, 5), host)),
         MAX(frecency > 1) OVER (PARTITION BY iif(substr(host, 1, 4) = 'www.', substr(host, 5), host))
  FROM moz_origins o
  WHERE prefix NOT IN ('about:', 'place:')
    AND ((host BETWEEN :searchString AND :searchString || X'FFFF')
      OR (host BETWEEN 'www.' || :searchString AND 'www.' || :searchString || X'FFFF'))
    AND (:adaptiveAutofillEnabled = 0 OR o.block_until_ms IS NULL OR o.block_until_ms <= :nowMs)
),
matched_origin(host_fixed, url) AS (
  SELECT iif(instr(host, :searchString) = 1, host, fixed) || '/', ifnull(:prefix, host_prefix) || host || '/'
  FROM origins
  WHERE prefix BETWEEN :prefix AND :prefix || X'FFFF' AND any_recent_typed AND total_fixed_host_frecency >= (SELECT value FROM autofill_frecency_threshold)
  ORDER BY total_fixed_host_frecency DESC, frecency DESC, n_bookmarks DESC, prefix = "https://" DESC, id DESC
  LIMIT 1
),
matched_place(host_fixed, url, id, title, frecency) AS (
  SELECT o.host_fixed, o.url, h.id, h.title, h.frecency
  FROM matched_origin o
  LEFT JOIN moz_places h ON h.url_hash IN ((length('https://' || o.host_fixed) * 4503599627370496 + unicode(substr('https://' || o.host_fixed, -1, 1)) * 859983745857 + unicode(substr('https://' || o.host_fixed, -2, 1)) * 620455851591 + unicode(substr('https://' || o.host_fixed, -3, 1)) * 380927957327 + unicode(substr('https://' || o.host_fixed, -4, 1)) * 141400063061 + unicode(substr('https://' || o.host_fixed, -5, 1)) * 1001383796573 + unicode(substr('https://' || o.host_fixed, -6, 1)) * 761855902307 + unicode(substr('https://' || o.host_fixed, -7, 1)) * 522328008043 + unicode(substr('https://' || o.host_fixed, -8, 1)) * 282800113777 + unicode(substr('https://' || o.host_fixed, -9, 1)) * 43272219513 + unicode(substr('https://' || o.host_fixed, -10, 1)) * 903255953023 + unicode(substr('https://' || o.host_fixed, -11, 1)) * 663728058759 + unicode(substr('https://' || o.host_fixed, -12, 1)) * 424200164493 + unicode(substr('https://' || o.host_fixed, -13, 1)) * 184672270229 + unicode(substr('https://' || o.host_fixed, -14, 1)) * 1044656003739 + unicode(substr('https://' || o.host_fixed, -15, 1)) * 805128109475 + unicode(substr('https://' || o.host_fixed, -16, 1)) * 565600215209), (length('https://www.' || o.host_fixed) * 4503599627370496 + unicode(substr('https://www.' || o.host_fixed, -1, 1)) * 859983745857 + unicode(substr('https://www.' || o.host_fixed, -2, 1)) * 620455851591 + unicode(substr('https://www.' || o.host_fixed, -3, 1)) * 380927957327 + unicode(substr('https://www.' || o.host_fixed, -4, 1)) * 141400063061 + unicode(substr('https://www.' || o.host_fixed, -5, 1)) * 1001383796573 + unicode(substr('https://www.' || o.host_fixed, -6, 1)) * 761855902307 + unicode(substr('https://www.' || o.host_fixed, -7, 1)) * 522328008043 + unicode(substr('https://www.' || o.host_fixed, -8, 1)) * 282800113777 + unicode(substr('https://www.' || o.host_fixed, -9, 1)) * 43272219513 + unicode(substr('https://www.' || o.host_fixed, -10, 1)) * 903255953023 + unicode(substr('https://www.' || o.host_fixed, -11, 1)) * 663728058759 + unicode(substr('https://www.' || o.host_fixed, -12, 1)) * 424200164493 + unicode(substr('https://www.' || o.host_fixed, -13, 1)) * 184672270229 + unicode(substr('https://www.' || o.host_fixed, -14, 1)) * 1044656003739 + unicode(substr('https://www.' || o.host_fixed, -15, 1)) * 805128109475 + unicode(substr('https://www.' || o.host_fixed, -16, 1)) * 565600215209), (length('http://' || o.host_fixed) * 4503599627370496 + unicode(substr('http://' || o.host_fixed, -1, 1)) * 859983745857 + unicode(substr('http://' || o.host_fixed, -2, 1)) * 620455851591 + unicode(substr('http://' || o.host_fixed, -3, 1)) * 380927957327 + unicode(substr('http://' || o.host_fixed, -4, 1)) * 141400063061 + unicode(substr('http://' || o.host_fixed, -5, 1)) * 1001383796573 + unicode(substr('http://' || o.host_fixed, -6, 1)) * 761855902307 + unicode(substr('http://' || o.host_fixed, -7, 1)) * 522328008043 + unicode(substr('http://' || o.host_fixed, -8, 1)) * 282800113777 + unicode(substr('http://' || o.host_fixed, -9, 1)) * 43272219513 + unicode(substr('http://' || o.host_fixed, -10, 1)) * 903255953023 + unicode(substr('http://' || o.host_fixed, -11, 1)) * 663728058759 + unicode(substr('http://' || o.host_fixed, -12, 1)) * 424200164493 + unicode(substr('http://' || o.host_fixed, -13, 1)) * 184672270229 + unicode(substr('http://' || o.host_fixed, -14, 1)) * 1044656003739 + unicode(substr('http://' || o.host_fixed, -15, 1)) * 805128109475 + unicode(substr('http://' || o.host_fixed, -16, 1)) * 565600215209), (length('http://www.' || o.host_fixed) * 4503599627370496 + unicode(substr('http://www.' || o.host_fixed, -1, 1)) * 859983745857 + unicode(substr('http://www.' || o.host_fixed, -2, 1)) * 620455851591 + unicode(substr('http://www.' || o.host_fixed, -3, 1)) * 380927957327 + unicode(substr('http://www.' || o.host_fixed, -4, 1)) * 141400063061 + unicode(substr('http://www.' || o.host_fixed, -5, 1)) * 1001383796573 + unicode(substr('http://www.' || o.host_fixed, -6, 1)) * 761855902307 + unicode(substr('http://www.' || o.host_fixed, -7, 1)) * 522328008043 + unicode(substr('http://www.' || o.host_fixed, -8, 1)) * 282800113777 + unicode(substr('http://www.' || o.host_fixed, -9, 1)) * 43272219513 + unicode(substr('http://www.' || o.host_fixed, -10, 1)) * 903255953023 + unicode(substr('http://www.' || o.host_fixed, -11, 1)) * 663728058759 + unicode(substr('http://www.' || o.host_fixed, -12, 1)) * 424200164493 + unicode(substr('http://www.' || o.host_fixed, -13, 1)) * 184672270229 + unicode(substr('http://www.' || o.host_fixed, -14, 1)) * 1044656003739 + unicode(substr('http://www.' || o.host_fixed, -15, 1)) * 805128109475 + unicode(substr('http://www.' || o.host_fixed, -16, 1)) * 565600215209))
  ORDER BY h.title IS NOT NULL DESC, h.title || '/' <> o.host_fixed DESC, h.url = o.url DESC, h.frecency DESC, h.id DESC
  LIMIT 1
)
SELECT :query_type AS query_type, :searchString AS search_string, h.host_fixed AS host_fixed, h.url AS url, iif(h.frecency <> 0, h.title, NULL) AS title
FROM matched_place h
;

-- @id firefox.autofill.origin_bookmark
-- @src browser/components/urlbar/UrlbarProviderAutofill.sys.mjs:157-249
-- @style named :params; originQuery() with QUERY_ORIGIN_BOOKMARK's WHERE (line 329), history disabled, no preferHttps
-- @tags dynamic
-- @note Bookmark-only origin autofill: same windowed CTE, n_bookmarks filter, LEFT JOIN moz_bookmarks for the title.
-- @modified fixup_url(host) (app-registered) replaced by iif(substr(host, 1, 4) = 'www.', substr(host, 5), host), its effect on a bare host (SQLFunctions.cpp:1181); hash() is an app-registered function; replaced by the core-SQL fingerprint that data.sql also stores in url_hash (see header)
-- @param :searchString 'git'
-- @param :adaptiveAutofillEnabled 0
-- @param :nowMs 1792022400000
-- @param :prefix NULL
-- @param :query_type 1
WITH
autofill_frecency_threshold(value) AS (
  SELECT IFNULL((SELECT value FROM moz_meta WHERE key = 'origin_frecency_threshold'), 2.0)
),
origins(id, prefix, host_prefix, host, fixed, total_fixed_host_frecency, frecency, n_bookmarks, any_recent_typed) AS (
  SELECT id, prefix,
         first_value(prefix) OVER (PARTITION BY host ORDER BY frecency DESC, prefix = "https://" DESC, id DESC),
         host, iif(substr(host, 1, 4) = 'www.', substr(host, 5), host),
         total(frecency) OVER (PARTITION BY iif(substr(host, 1, 4) = 'www.', substr(host, 5), host)),
         frecency,
         total((SELECT total(foreign_count) FROM moz_places WHERE origin_id = o.id)) OVER (PARTITION BY iif(substr(host, 1, 4) = 'www.', substr(host, 5), host)),
         0
  FROM moz_origins o
  WHERE prefix NOT IN ('about:', 'place:')
    AND ((host BETWEEN :searchString AND :searchString || X'FFFF')
      OR (host BETWEEN 'www.' || :searchString AND 'www.' || :searchString || X'FFFF'))
    AND (:adaptiveAutofillEnabled = 0 OR o.block_until_ms IS NULL OR o.block_until_ms <= :nowMs)
),
matched_origin(host_fixed, url) AS (
  SELECT iif(instr(host, :searchString) = 1, host, fixed) || '/', ifnull(:prefix, host_prefix) || host || '/'
  FROM origins
  WHERE n_bookmarks > 0
  ORDER BY total_fixed_host_frecency DESC, frecency DESC, n_bookmarks DESC, prefix = "https://" DESC, id DESC
  LIMIT 1
),
matched_place(host_fixed, url, id, title, frecency) AS (
  SELECT o.host_fixed, o.url, h.id, h.title, h.frecency
  FROM matched_origin o
  LEFT JOIN moz_places h ON h.url_hash IN ((length('https://' || o.host_fixed) * 4503599627370496 + unicode(substr('https://' || o.host_fixed, -1, 1)) * 859983745857 + unicode(substr('https://' || o.host_fixed, -2, 1)) * 620455851591 + unicode(substr('https://' || o.host_fixed, -3, 1)) * 380927957327 + unicode(substr('https://' || o.host_fixed, -4, 1)) * 141400063061 + unicode(substr('https://' || o.host_fixed, -5, 1)) * 1001383796573 + unicode(substr('https://' || o.host_fixed, -6, 1)) * 761855902307 + unicode(substr('https://' || o.host_fixed, -7, 1)) * 522328008043 + unicode(substr('https://' || o.host_fixed, -8, 1)) * 282800113777 + unicode(substr('https://' || o.host_fixed, -9, 1)) * 43272219513 + unicode(substr('https://' || o.host_fixed, -10, 1)) * 903255953023 + unicode(substr('https://' || o.host_fixed, -11, 1)) * 663728058759 + unicode(substr('https://' || o.host_fixed, -12, 1)) * 424200164493 + unicode(substr('https://' || o.host_fixed, -13, 1)) * 184672270229 + unicode(substr('https://' || o.host_fixed, -14, 1)) * 1044656003739 + unicode(substr('https://' || o.host_fixed, -15, 1)) * 805128109475 + unicode(substr('https://' || o.host_fixed, -16, 1)) * 565600215209), (length('https://www.' || o.host_fixed) * 4503599627370496 + unicode(substr('https://www.' || o.host_fixed, -1, 1)) * 859983745857 + unicode(substr('https://www.' || o.host_fixed, -2, 1)) * 620455851591 + unicode(substr('https://www.' || o.host_fixed, -3, 1)) * 380927957327 + unicode(substr('https://www.' || o.host_fixed, -4, 1)) * 141400063061 + unicode(substr('https://www.' || o.host_fixed, -5, 1)) * 1001383796573 + unicode(substr('https://www.' || o.host_fixed, -6, 1)) * 761855902307 + unicode(substr('https://www.' || o.host_fixed, -7, 1)) * 522328008043 + unicode(substr('https://www.' || o.host_fixed, -8, 1)) * 282800113777 + unicode(substr('https://www.' || o.host_fixed, -9, 1)) * 43272219513 + unicode(substr('https://www.' || o.host_fixed, -10, 1)) * 903255953023 + unicode(substr('https://www.' || o.host_fixed, -11, 1)) * 663728058759 + unicode(substr('https://www.' || o.host_fixed, -12, 1)) * 424200164493 + unicode(substr('https://www.' || o.host_fixed, -13, 1)) * 184672270229 + unicode(substr('https://www.' || o.host_fixed, -14, 1)) * 1044656003739 + unicode(substr('https://www.' || o.host_fixed, -15, 1)) * 805128109475 + unicode(substr('https://www.' || o.host_fixed, -16, 1)) * 565600215209), (length('http://' || o.host_fixed) * 4503599627370496 + unicode(substr('http://' || o.host_fixed, -1, 1)) * 859983745857 + unicode(substr('http://' || o.host_fixed, -2, 1)) * 620455851591 + unicode(substr('http://' || o.host_fixed, -3, 1)) * 380927957327 + unicode(substr('http://' || o.host_fixed, -4, 1)) * 141400063061 + unicode(substr('http://' || o.host_fixed, -5, 1)) * 1001383796573 + unicode(substr('http://' || o.host_fixed, -6, 1)) * 761855902307 + unicode(substr('http://' || o.host_fixed, -7, 1)) * 522328008043 + unicode(substr('http://' || o.host_fixed, -8, 1)) * 282800113777 + unicode(substr('http://' || o.host_fixed, -9, 1)) * 43272219513 + unicode(substr('http://' || o.host_fixed, -10, 1)) * 903255953023 + unicode(substr('http://' || o.host_fixed, -11, 1)) * 663728058759 + unicode(substr('http://' || o.host_fixed, -12, 1)) * 424200164493 + unicode(substr('http://' || o.host_fixed, -13, 1)) * 184672270229 + unicode(substr('http://' || o.host_fixed, -14, 1)) * 1044656003739 + unicode(substr('http://' || o.host_fixed, -15, 1)) * 805128109475 + unicode(substr('http://' || o.host_fixed, -16, 1)) * 565600215209), (length('http://www.' || o.host_fixed) * 4503599627370496 + unicode(substr('http://www.' || o.host_fixed, -1, 1)) * 859983745857 + unicode(substr('http://www.' || o.host_fixed, -2, 1)) * 620455851591 + unicode(substr('http://www.' || o.host_fixed, -3, 1)) * 380927957327 + unicode(substr('http://www.' || o.host_fixed, -4, 1)) * 141400063061 + unicode(substr('http://www.' || o.host_fixed, -5, 1)) * 1001383796573 + unicode(substr('http://www.' || o.host_fixed, -6, 1)) * 761855902307 + unicode(substr('http://www.' || o.host_fixed, -7, 1)) * 522328008043 + unicode(substr('http://www.' || o.host_fixed, -8, 1)) * 282800113777 + unicode(substr('http://www.' || o.host_fixed, -9, 1)) * 43272219513 + unicode(substr('http://www.' || o.host_fixed, -10, 1)) * 903255953023 + unicode(substr('http://www.' || o.host_fixed, -11, 1)) * 663728058759 + unicode(substr('http://www.' || o.host_fixed, -12, 1)) * 424200164493 + unicode(substr('http://www.' || o.host_fixed, -13, 1)) * 184672270229 + unicode(substr('http://www.' || o.host_fixed, -14, 1)) * 1044656003739 + unicode(substr('http://www.' || o.host_fixed, -15, 1)) * 805128109475 + unicode(substr('http://www.' || o.host_fixed, -16, 1)) * 565600215209))
  ORDER BY h.title IS NOT NULL DESC, h.title || '/' <> o.host_fixed DESC, h.url = o.url DESC, h.frecency DESC, h.id DESC
  LIMIT 1
)
SELECT :query_type AS query_type, :searchString AS search_string, h.host_fixed AS host_fixed, h.url AS url, ifnull(b.title, iif(h.frecency <> 0, h.title, NULL)) AS title
FROM matched_place h
LEFT JOIN moz_bookmarks b ON b.fk = h.id;

-- @id firefox.autofill.url_history_bookmark
-- @src browser/components/urlbar/UrlbarProviderAutofill.sys.mjs:252-301
-- @style named :params; urlQuery() with QUERY_URL_HISTORY_BOOKMARK's fragments (lines 335-345)
-- @tags hotpath,dynamic
-- @note URL autofill once the input has a path: rev_host index probes for host and www.host, UNION ALL with NOCASE BETWEEN on a computed column, top-1.
-- @modified strip_prefix_and_userinfo() (app-registered) replaced by substr(x, instr(x, '://') + 3) (the data has no userinfo); :strippedURL is never schemed, so the call on it is a no-op either way
-- @param :revHost 'moc.buhtig.'
-- @param :strippedURL 'github.com/en-US/docs/'
-- @param :searchString 'github.com/en-US/docs/'
-- @param :adaptiveAutofillEnabled 0
-- @param :pageFrecencyThreshold 100
-- @param :query_type 2
WITH matched_url(url, title, frecency, n_bookmarks, visited, stripped_url, is_exact_match, id) AS (
  SELECT url, title, frecency, foreign_count AS n_bookmarks, visit_count > 0 AS visited,
         substr(url, instr(url, '://') + 3) AS stripped_url,
         substr(url, instr(url, '://') + 3) = substr(:strippedURL, instr(:strippedURL, '://') + 3) AS is_exact_match, id
  FROM moz_places
  WHERE rev_host = :revHost
        AND ((:adaptiveAutofillEnabled = 0 AND n_bookmarks > 0) OR frecency > :pageFrecencyThreshold) AND stripped_url COLLATE NOCASE BETWEEN :strippedURL AND :strippedURL || X'FFFF'
  UNION ALL
  SELECT url, title, frecency, foreign_count AS n_bookmarks, visit_count > 0 AS visited,
         substr(url, instr(url, '://') + 3) AS stripped_url,
         substr(url, instr(url, '://') + 3) = 'www.' || substr(:strippedURL, instr(:strippedURL, '://') + 3) AS is_exact_match, id
  FROM moz_places
  WHERE rev_host = :revHost || 'www.'
        AND ((:adaptiveAutofillEnabled = 0 AND n_bookmarks > 0) OR frecency > :pageFrecencyThreshold) AND stripped_url COLLATE NOCASE BETWEEN 'www.' || :strippedURL AND 'www.' || :strippedURL || X'FFFF'
  ORDER BY is_exact_match DESC, frecency DESC, id DESC
  LIMIT 1
)
SELECT :query_type AS query_type, :searchString AS search_string, :strippedURL AS stripped_url, matched_url.url AS url, ifnull(b.title, matched_url.title) AS title
FROM matched_url
LEFT JOIN moz_bookmarks b ON b.fk = matched_url.id;

-- @id firefox.autofill.url_prefix_history
-- @src browser/components/urlbar/UrlbarProviderAutofill.sys.mjs:252-301
-- @style named :params; urlQuery() with QUERY_URL_PREFIX_HISTORY's fragments (lines 371-381)
-- @tags hotpath,dynamic
-- @note URL autofill with a typed scheme: url COLLATE NOCASE BETWEEN prefix||strippedURL ranges under each rev_host.
-- @modified strip_prefix_and_userinfo() (app-registered) replaced by substr(x, instr(x, '://') + 3) (the data has no userinfo); :strippedURL is never schemed, so the call on it is a no-op either way
-- @param :revHost 'gro.allizom.'
-- @param :strippedURL 'mozilla.org/d'
-- @param :searchString 'https://mozilla.org/d'
-- @param :prefix 'https://'
-- @param :pageFrecencyThreshold 100
-- @param :query_type 2
WITH matched_url(url, title, frecency, n_bookmarks, visited, stripped_url, is_exact_match, id) AS (
  SELECT url, title, frecency, foreign_count AS n_bookmarks, visit_count > 0 AS visited,
         substr(url, instr(url, '://') + 3) AS stripped_url,
         substr(url, instr(url, '://') + 3) = substr(:strippedURL, instr(:strippedURL, '://') + 3) AS is_exact_match, id
  FROM moz_places
  WHERE rev_host = :revHost
        AND (visited OR n_bookmarks = 0) AND frecency > :pageFrecencyThreshold AND url COLLATE NOCASE BETWEEN :prefix || :strippedURL AND :prefix || :strippedURL || X'FFFF'
  UNION ALL
  SELECT url, title, frecency, foreign_count AS n_bookmarks, visit_count > 0 AS visited,
         substr(url, instr(url, '://') + 3) AS stripped_url,
         substr(url, instr(url, '://') + 3) = 'www.' || substr(:strippedURL, instr(:strippedURL, '://') + 3) AS is_exact_match, id
  FROM moz_places
  WHERE rev_host = :revHost || 'www.'
        AND (visited OR n_bookmarks = 0) AND frecency > :pageFrecencyThreshold AND url COLLATE NOCASE BETWEEN :prefix || 'www.' || :strippedURL AND :prefix || 'www.' || :strippedURL || X'FFFF'
  ORDER BY is_exact_match DESC, frecency DESC, id DESC
  LIMIT 1
)
SELECT :query_type AS query_type, :searchString AS search_string, :strippedURL AS stripped_url, matched_url.url AS url, matched_url.title AS title
FROM matched_url
;

-- @id firefox.urlbar.places_default
-- @src browser/components/urlbar/UrlbarProviderPlaces.sys.mjs:27-73
-- @style named :params; defaultQuery() with no extra conditions (#suggestionPrefQuery, line 1257-1326), PAGES_FRECENCY_FIELD = frecency
-- @tags hotpath,dynamic
-- @note The main history/bookmark suggestion query per keystroke: walk moz_places by frecency, three correlated bookmark/tag subqueries in the result set feeding a CASE match predicate, LEFT JOIN open tabs, LIMIT.
-- @modified AUTOCOMPLETE_MATCH(:searchString, url, title, tags, ..., :matchBehavior, :searchBehavior) (app-registered) replaced by case-insensitive LIKE '%token%' over the same url/title/tags arguments, i.e. one token with MATCH_ANYWHERE and default behaviour
-- @param :parent 4
-- @param :userContextId 0
-- @param :switchTabsEnabled 1
-- @param :searchString 'docs'
-- @param :maxResults 10
SELECT h.url, h.title, ( SELECT dateAdded FROM moz_bookmarks WHERE fk = h.id ) AS bookmarkDate,
       ( SELECT title FROM moz_bookmarks WHERE fk = h.id AND title NOTNULL ORDER BY lastModified DESC LIMIT 1 ) AS btitle,
       ( SELECT GROUP_CONCAT(t.title ORDER BY t.title) FROM moz_bookmarks b JOIN moz_bookmarks t ON t.id = +b.parent AND t.parent = :parent WHERE b.fk = h.id ) AS tags, h.id, t.open_count, frecency AS frecency, t.userContextId, h.last_visit_date, NULLIF(t.groupId, '') groupId
FROM moz_places h
LEFT JOIN moz_openpages_temp t ON t.url = h.url AND (t.userContextId = :userContextId OR (t.userContextId <> -1 AND :userContextId IS NULL))
WHERE ((:switchTabsEnabled AND t.open_count > 0) OR frecency <> 0)
  AND CASE WHEN bookmarkDate
        THEN (h.url LIKE '%' || :searchString || '%' OR IFNULL(btitle, h.title) LIKE '%' || :searchString || '%' OR tags LIKE '%' || :searchString || '%')
        ELSE (h.url LIKE '%' || :searchString || '%' OR h.title LIKE '%' || :searchString || '%')
      END
  
ORDER BY frecency DESC, h.id DESC
LIMIT :maxResults;

-- @id firefox.urlbar.places_site_search
-- @src browser/components/urlbar/UrlbarProviderPlaces.sys.mjs:42-73
-- @style named :params; defaultQuery() with the #filterOnHost conditions for restyleSearches off (lines 1257-1305)
-- @tags hotpath,dynamic
-- @note Site-specific search: rev_host filter plus a NOT EXISTS over a correlated LIMIT-10 CTE of recent visits joined back to redirect targets.
-- @modified AUTOCOMPLETE_MATCH(:searchString, url, title, tags, ..., :matchBehavior, :searchBehavior) (app-registered) replaced by case-insensitive LIKE '%token%' over the same url/title/tags arguments, i.e. one token with MATCH_ANYWHERE and default behaviour; get_unreversed_host(:host || '.') || '.' is a function of a parameter only, so :revHost carries its result
-- @param :parent 4
-- @param :userContextId 0
-- @param :switchTabsEnabled 1
-- @param :searchString 'item'
-- @param :maxResults 10
-- @param :revHost 'gro.allizom.repoleved.'
SELECT h.url, h.title, ( SELECT dateAdded FROM moz_bookmarks WHERE fk = h.id ) AS bookmarkDate,
       ( SELECT title FROM moz_bookmarks WHERE fk = h.id AND title NOTNULL ORDER BY lastModified DESC LIMIT 1 ) AS btitle,
       ( SELECT GROUP_CONCAT(t.title ORDER BY t.title) FROM moz_bookmarks b JOIN moz_bookmarks t ON t.id = +b.parent AND t.parent = :parent WHERE b.fk = h.id ) AS tags, h.id, t.open_count, frecency AS frecency, t.userContextId, h.last_visit_date, NULLIF(t.groupId, '') groupId
FROM moz_places h
LEFT JOIN moz_openpages_temp t ON t.url = h.url AND (t.userContextId = :userContextId OR (t.userContextId <> -1 AND :userContextId IS NULL))
WHERE ((:switchTabsEnabled AND t.open_count > 0) OR frecency <> 0)
  AND CASE WHEN bookmarkDate
        THEN (h.url LIKE '%' || :searchString || '%' OR IFNULL(btitle, h.title) LIKE '%' || :searchString || '%' OR tags LIKE '%' || :searchString || '%')
        ELSE (h.url LIKE '%' || :searchString || '%' OR h.title LIKE '%' || :searchString || '%')
      END
  AND h.rev_host = :revHost AND NOT EXISTS (
    WITH visits(id) AS (SELECT id FROM moz_historyvisits WHERE place_id = h.id ORDER BY visit_date DESC LIMIT 10)
    SELECT 1 FROM visits src JOIN moz_historyvisits dest ON src.id = dest.from_visit WHERE dest.visit_type IN (5,6)
  ) AND (h.foreign_count > 0 OR h.title NOTNULL)
ORDER BY frecency DESC, h.id DESC
LIMIT :maxResults;

-- @id firefox.urlbar.switchtab
-- @src browser/components/urlbar/UrlbarProviderPlaces.sys.mjs:75-87
-- @style named :params
-- @tags hotpath
-- @note Open tabs not in history: anti-join from moz_openpages_temp to moz_places via url_hash, ordered by ROWID DESC.
-- @modified hash() is an app-registered function; replaced by the core-SQL fingerprint that data.sql also stores in url_hash (see header); AUTOCOMPLETE_MATCH(:searchString, t.url, t.url, ...) replaced by t.url LIKE '%token%'
-- @param :userContextId 0
-- @param :searchString 'tab'
-- @param :maxResults 10
SELECT t.url, t.url AS title, 0 AS bookmarkDate, NULL AS btitle, NULL AS tags, NULL AS id, t.open_count, NULL AS frecency,
       t.userContextId, NULL AS last_visit_date, NULLIF(t.groupId, '') groupId
FROM moz_openpages_temp t
LEFT JOIN moz_places h ON h.url_hash = (length(t.url) * 4503599627370496 + unicode(substr(t.url, -1, 1)) * 859983745857 + unicode(substr(t.url, -2, 1)) * 620455851591 + unicode(substr(t.url, -3, 1)) * 380927957327 + unicode(substr(t.url, -4, 1)) * 141400063061 + unicode(substr(t.url, -5, 1)) * 1001383796573 + unicode(substr(t.url, -6, 1)) * 761855902307 + unicode(substr(t.url, -7, 1)) * 522328008043 + unicode(substr(t.url, -8, 1)) * 282800113777 + unicode(substr(t.url, -9, 1)) * 43272219513 + unicode(substr(t.url, -10, 1)) * 903255953023 + unicode(substr(t.url, -11, 1)) * 663728058759 + unicode(substr(t.url, -12, 1)) * 424200164493 + unicode(substr(t.url, -13, 1)) * 184672270229 + unicode(substr(t.url, -14, 1)) * 1044656003739 + unicode(substr(t.url, -15, 1)) * 805128109475 + unicode(substr(t.url, -16, 1)) * 565600215209) AND h.url = t.url
WHERE h.id IS NULL
  AND (t.userContextId = :userContextId OR (t.userContextId <> -1 AND :userContextId IS NULL))
  AND t.url LIKE '%' || :searchString || '%'
ORDER BY t.ROWID DESC
LIMIT :maxResults;

-- @id firefox.urlbar.input_history
-- @src browser/components/urlbar/UrlbarProviderInputHistory.sys.mjs:30-66
-- @style named :params
-- @tags hotpath
-- @note Adaptive history: GROUP BY over an input range in a derived table, joined to places, four correlated bookmark subqueries, ranked.
-- @modified AUTOCOMPLETE_MATCH(NULL, ...) (app-registered) only applies the behaviour filter when the search string is NULL; replaced by the default behaviour's history/bookmark/open-page test
-- @param :parent 4
-- @param :search_string 'si'
-- @param :userContextId 0
-- @param :maxResults 10
SELECT h.url, h.title,
       EXISTS(SELECT 1 FROM moz_bookmarks WHERE fk = h.id) AS bookmarked,
       ( SELECT title FROM moz_bookmarks WHERE fk = h.id AND title NOTNULL ORDER BY lastModified DESC LIMIT 1 ) AS bookmark_title,
       ( SELECT dateAdded FROM moz_bookmarks WHERE fk = h.id ORDER BY dateAdded DESC LIMIT 1 ) AS bookmarkDate,
       ( SELECT GROUP_CONCAT(t.title ORDER BY t.title) FROM moz_bookmarks b JOIN moz_bookmarks t ON t.id = +b.parent AND t.parent = :parent WHERE b.fk = h.id ) AS tags,
       t.open_count, t.userContextId, h.last_visit_date
FROM (
  SELECT ROUND(MAX(use_count) * (1 + (input = :search_string)), 1) AS rank, place_id
  FROM moz_inputhistory
  WHERE input BETWEEN :search_string AND :search_string || X'FFFF'
  GROUP BY place_id
) AS i
JOIN moz_places h ON h.id = i.place_id
LEFT JOIN moz_openpages_temp t ON t.url = h.url AND (t.userContextId = :userContextId OR (t.userContextId <> -1 AND :userContextId IS NULL))
WHERE (bookmarked OR h.visit_count > 0 OR t.open_count > 0)
ORDER BY rank DESC, frecency DESC
LIMIT :maxResults;

-- @id firefox.urlbar.history_url_heuristic
-- @src browser/components/urlbar/UrlbarProviderHistoryUrlHeuristic.sys.mjs:76-100
-- @style named :params
-- @tags hot-small,hotpath
-- @note Heuristic result for a typed URL: four url_hash probes plus url IN, LEFT JOIN bookmarks, five-key ordering.
-- @modified hash() is an app-registered function; replaced by the core-SQL fingerprint that data.sql also stores in url_hash (see header)
-- @param :strippedURL 'github.com/'
-- @param :inputedURL 'github.com/'
SELECT url, IIF(last_visit_date NOTNULL, h.title, b.title) AS _title, frecency
FROM moz_places h
LEFT JOIN moz_bookmarks b ON b.fk = h.id
WHERE url_hash IN ((length('https://' || :strippedURL) * 4503599627370496 + unicode(substr('https://' || :strippedURL, -1, 1)) * 859983745857 + unicode(substr('https://' || :strippedURL, -2, 1)) * 620455851591 + unicode(substr('https://' || :strippedURL, -3, 1)) * 380927957327 + unicode(substr('https://' || :strippedURL, -4, 1)) * 141400063061 + unicode(substr('https://' || :strippedURL, -5, 1)) * 1001383796573 + unicode(substr('https://' || :strippedURL, -6, 1)) * 761855902307 + unicode(substr('https://' || :strippedURL, -7, 1)) * 522328008043 + unicode(substr('https://' || :strippedURL, -8, 1)) * 282800113777 + unicode(substr('https://' || :strippedURL, -9, 1)) * 43272219513 + unicode(substr('https://' || :strippedURL, -10, 1)) * 903255953023 + unicode(substr('https://' || :strippedURL, -11, 1)) * 663728058759 + unicode(substr('https://' || :strippedURL, -12, 1)) * 424200164493 + unicode(substr('https://' || :strippedURL, -13, 1)) * 184672270229 + unicode(substr('https://' || :strippedURL, -14, 1)) * 1044656003739 + unicode(substr('https://' || :strippedURL, -15, 1)) * 805128109475 + unicode(substr('https://' || :strippedURL, -16, 1)) * 565600215209), (length('https://www.' || :strippedURL) * 4503599627370496 + unicode(substr('https://www.' || :strippedURL, -1, 1)) * 859983745857 + unicode(substr('https://www.' || :strippedURL, -2, 1)) * 620455851591 + unicode(substr('https://www.' || :strippedURL, -3, 1)) * 380927957327 + unicode(substr('https://www.' || :strippedURL, -4, 1)) * 141400063061 + unicode(substr('https://www.' || :strippedURL, -5, 1)) * 1001383796573 + unicode(substr('https://www.' || :strippedURL, -6, 1)) * 761855902307 + unicode(substr('https://www.' || :strippedURL, -7, 1)) * 522328008043 + unicode(substr('https://www.' || :strippedURL, -8, 1)) * 282800113777 + unicode(substr('https://www.' || :strippedURL, -9, 1)) * 43272219513 + unicode(substr('https://www.' || :strippedURL, -10, 1)) * 903255953023 + unicode(substr('https://www.' || :strippedURL, -11, 1)) * 663728058759 + unicode(substr('https://www.' || :strippedURL, -12, 1)) * 424200164493 + unicode(substr('https://www.' || :strippedURL, -13, 1)) * 184672270229 + unicode(substr('https://www.' || :strippedURL, -14, 1)) * 1044656003739 + unicode(substr('https://www.' || :strippedURL, -15, 1)) * 805128109475 + unicode(substr('https://www.' || :strippedURL, -16, 1)) * 565600215209), (length('http://' || :strippedURL) * 4503599627370496 + unicode(substr('http://' || :strippedURL, -1, 1)) * 859983745857 + unicode(substr('http://' || :strippedURL, -2, 1)) * 620455851591 + unicode(substr('http://' || :strippedURL, -3, 1)) * 380927957327 + unicode(substr('http://' || :strippedURL, -4, 1)) * 141400063061 + unicode(substr('http://' || :strippedURL, -5, 1)) * 1001383796573 + unicode(substr('http://' || :strippedURL, -6, 1)) * 761855902307 + unicode(substr('http://' || :strippedURL, -7, 1)) * 522328008043 + unicode(substr('http://' || :strippedURL, -8, 1)) * 282800113777 + unicode(substr('http://' || :strippedURL, -9, 1)) * 43272219513 + unicode(substr('http://' || :strippedURL, -10, 1)) * 903255953023 + unicode(substr('http://' || :strippedURL, -11, 1)) * 663728058759 + unicode(substr('http://' || :strippedURL, -12, 1)) * 424200164493 + unicode(substr('http://' || :strippedURL, -13, 1)) * 184672270229 + unicode(substr('http://' || :strippedURL, -14, 1)) * 1044656003739 + unicode(substr('http://' || :strippedURL, -15, 1)) * 805128109475 + unicode(substr('http://' || :strippedURL, -16, 1)) * 565600215209), (length('http://www.' || :strippedURL) * 4503599627370496 + unicode(substr('http://www.' || :strippedURL, -1, 1)) * 859983745857 + unicode(substr('http://www.' || :strippedURL, -2, 1)) * 620455851591 + unicode(substr('http://www.' || :strippedURL, -3, 1)) * 380927957327 + unicode(substr('http://www.' || :strippedURL, -4, 1)) * 141400063061 + unicode(substr('http://www.' || :strippedURL, -5, 1)) * 1001383796573 + unicode(substr('http://www.' || :strippedURL, -6, 1)) * 761855902307 + unicode(substr('http://www.' || :strippedURL, -7, 1)) * 522328008043 + unicode(substr('http://www.' || :strippedURL, -8, 1)) * 282800113777 + unicode(substr('http://www.' || :strippedURL, -9, 1)) * 43272219513 + unicode(substr('http://www.' || :strippedURL, -10, 1)) * 903255953023 + unicode(substr('http://www.' || :strippedURL, -11, 1)) * 663728058759 + unicode(substr('http://www.' || :strippedURL, -12, 1)) * 424200164493 + unicode(substr('http://www.' || :strippedURL, -13, 1)) * 184672270229 + unicode(substr('http://www.' || :strippedURL, -14, 1)) * 1044656003739 + unicode(substr('http://www.' || :strippedURL, -15, 1)) * 805128109475 + unicode(substr('http://www.' || :strippedURL, -16, 1)) * 565600215209))
  AND url IN ('https://' || :strippedURL, 'https://www.' || :strippedURL, 'http://' || :strippedURL, 'http://www.' || :strippedURL)
  AND frecency <> 0
ORDER BY _title NOTNULL DESC, _title || '/' <> :strippedURL DESC, h.url = :inputedURL DESC, h.frecency DESC, h.id DESC;

-- @id firefox.urlbar.topsites_redirect_chain
-- @src browser/components/urlbar/UrlbarProviderTopSites.sys.mjs:427-447
-- @style named :params
-- @note Last visit of a top site including redirect chains: recursive CTE over moz_historyvisits.from_visit with UNION (dedup) and an aggregate.
-- @modified hash() is an app-registered function; replaced by the core-SQL fingerprint that data.sql also stores in url_hash (see header)
-- @param :url 'https://www.mozilla.org/'
-- @param :redirectPermanent 5
-- @param :redirectTemporary 6
WITH RECURSIVE redirect_chain(visit_id, visit_date) AS (
  SELECT v.id, v.visit_date FROM moz_places h JOIN moz_historyvisits v ON v.place_id = h.id
  WHERE h.url_hash = (length(:url) * 4503599627370496 + unicode(substr(:url, -1, 1)) * 859983745857 + unicode(substr(:url, -2, 1)) * 620455851591 + unicode(substr(:url, -3, 1)) * 380927957327 + unicode(substr(:url, -4, 1)) * 141400063061 + unicode(substr(:url, -5, 1)) * 1001383796573 + unicode(substr(:url, -6, 1)) * 761855902307 + unicode(substr(:url, -7, 1)) * 522328008043 + unicode(substr(:url, -8, 1)) * 282800113777 + unicode(substr(:url, -9, 1)) * 43272219513 + unicode(substr(:url, -10, 1)) * 903255953023 + unicode(substr(:url, -11, 1)) * 663728058759 + unicode(substr(:url, -12, 1)) * 424200164493 + unicode(substr(:url, -13, 1)) * 184672270229 + unicode(substr(:url, -14, 1)) * 1044656003739 + unicode(substr(:url, -15, 1)) * 805128109475 + unicode(substr(:url, -16, 1)) * 565600215209) AND h.url = :url
  UNION
  SELECT v.id, v.visit_date FROM moz_historyvisits v JOIN redirect_chain c ON v.from_visit = c.visit_id
  WHERE v.visit_type IN (:redirectPermanent, :redirectTemporary)
)
SELECT MAX(visit_date) / 1000 AS lastVisit FROM redirect_chain;

-- @id firefox.bookmarks.fetch_by_guid
-- @src toolkit/components/places/Bookmarks.sys.mjs:2472-2485
-- @style named :params
-- @tags hot-small,hotpath
-- @note Bookmarks.fetch(guid): guid unique index, two LEFT JOINs, correlated child count.
-- @param :guid 'bkmk00000042'
SELECT b.guid, IFNULL(p.guid, '') AS parentGuid, b.position AS 'index', b.dateAdded, b.lastModified, b.type, IFNULL(b.title, '') AS title, h.url AS url, b.id AS _id, b.parent AS _parentId,
       (SELECT count(*) FROM moz_bookmarks WHERE parent = b.id) AS _childCount,
       p.parent AS _grandParentId, b.syncStatus AS _syncStatus
FROM moz_bookmarks b
LEFT JOIN moz_bookmarks p ON p.id = b.parent
LEFT JOIN moz_places h ON h.id = b.fk
WHERE b.guid = :guid;

-- @id firefox.bookmarks.fetch_by_parent_guid
-- @src toolkit/components/places/Bookmarks.sys.mjs:2716-2737
-- @style named :params
-- @tags hotpath
-- @note Folder listing for the library/sidebar: children by parent guid ordered by position, correlated child count per row.
-- @param :parentGuid 'menu________'
SELECT b.guid, IFNULL(p.guid, '') AS parentGuid, b.position AS 'index', b.dateAdded, b.lastModified, b.type, IFNULL(b.title, '') AS title, h.url AS url, b.id AS _id, b.parent AS _parentId,
       (SELECT count(*) FROM moz_bookmarks WHERE parent = b.id) AS _childCount,
       NULL AS _grandParentId, NULL AS _syncStatus
FROM moz_bookmarks b
LEFT JOIN moz_bookmarks p ON p.id = b.parent
LEFT JOIN moz_places h ON h.id = b.fk
WHERE p.guid = :parentGuid
ORDER BY b.position ASC;

-- @id firefox.bookmarks.fetch_by_url
-- @src toolkit/components/places/Bookmarks.sys.mjs:2674-2700
-- @style named :params
-- @tags hot-small,hotpath
-- @note Is this page bookmarked (star button, on every navigation): url_hash probe, 3-way join, correlated 3-way tag group_concat.
-- @modified hash() is an app-registered function; replaced by the core-SQL fingerprint that data.sql also stores in url_hash (see header)
-- @param :url 'https://www.github.com/'
-- @param :tagsFolderId 4
SELECT b.guid, IFNULL(p.guid, '') AS parentGuid, b.position AS 'index', b.dateAdded, b.lastModified, b.type, IFNULL(b.title, '') AS title, h.url AS url, b.id AS _id, b.parent AS _parentId, NULL AS _childCount,
       p.parent AS _grandParentId, b.syncStatus AS _syncStatus,
       (SELECT group_concat(pp.title ORDER BY pp.title)
        FROM moz_bookmarks bb JOIN moz_bookmarks pp ON bb.parent = pp.id JOIN moz_bookmarks gg ON pp.parent = gg.id
        WHERE bb.fk = h.id AND gg.guid = 'tags________') AS _tags
FROM moz_bookmarks b
JOIN moz_bookmarks p ON p.id = b.parent
JOIN moz_places h ON h.id = b.fk
WHERE h.url_hash = (length(:url) * 4503599627370496 + unicode(substr(:url, -1, 1)) * 859983745857 + unicode(substr(:url, -2, 1)) * 620455851591 + unicode(substr(:url, -3, 1)) * 380927957327 + unicode(substr(:url, -4, 1)) * 141400063061 + unicode(substr(:url, -5, 1)) * 1001383796573 + unicode(substr(:url, -6, 1)) * 761855902307 + unicode(substr(:url, -7, 1)) * 522328008043 + unicode(substr(:url, -8, 1)) * 282800113777 + unicode(substr(:url, -9, 1)) * 43272219513 + unicode(substr(:url, -10, 1)) * 903255953023 + unicode(substr(:url, -11, 1)) * 663728058759 + unicode(substr(:url, -12, 1)) * 424200164493 + unicode(substr(:url, -13, 1)) * 184672270229 + unicode(substr(:url, -14, 1)) * 1044656003739 + unicode(substr(:url, -15, 1)) * 805128109475 + unicode(substr(:url, -16, 1)) * 565600215209) AND h.url = :url
AND _grandParentId <> :tagsFolderId
ORDER BY b.lastModified DESC;

-- @id firefox.bookmarks.fetch_by_urls
-- @src toolkit/components/places/Bookmarks.sys.mjs:2617-2650
-- @style named :params; :urls bound as an array
-- @tags dynamic
-- @note Batch bookmark lookup for many URLs: CTE of (url, hash) joined on both columns, tags subquery, ordered by url.
-- @modified carray(:urls) (a SQLite extension Places binds an array to) replaced by json_each over a JSON array; hash() is an app-registered function; replaced by the core-SQL fingerprint that data.sql also stores in url_hash (see header)
-- @param :urls '["https://www.mozilla.org/","https://github.com/","https://www.github.com/","https://site14.com/","https://en.wikipedia.org/"]'
-- @param :tagsFolderId 4
WITH urls(url, url_hash) AS (
  SELECT value, (length(value) * 4503599627370496 + unicode(substr(value, -1, 1)) * 859983745857 + unicode(substr(value, -2, 1)) * 620455851591 + unicode(substr(value, -3, 1)) * 380927957327 + unicode(substr(value, -4, 1)) * 141400063061 + unicode(substr(value, -5, 1)) * 1001383796573 + unicode(substr(value, -6, 1)) * 761855902307 + unicode(substr(value, -7, 1)) * 522328008043 + unicode(substr(value, -8, 1)) * 282800113777 + unicode(substr(value, -9, 1)) * 43272219513 + unicode(substr(value, -10, 1)) * 903255953023 + unicode(substr(value, -11, 1)) * 663728058759 + unicode(substr(value, -12, 1)) * 424200164493 + unicode(substr(value, -13, 1)) * 184672270229 + unicode(substr(value, -14, 1)) * 1044656003739 + unicode(substr(value, -15, 1)) * 805128109475 + unicode(substr(value, -16, 1)) * 565600215209) FROM json_each(:urls)
)
SELECT b.guid, IFNULL(p.guid, '') AS parentGuid, b.position AS 'index', b.dateAdded, b.lastModified, b.type, IFNULL(b.title, '') AS title, h.url AS url, b.id AS _id, b.parent AS _parentId, NULL AS _childCount,
       p.parent AS _grandParentId, b.syncStatus AS _syncStatus,
       (SELECT group_concat(pp.title ORDER BY pp.title)
        FROM moz_bookmarks bb JOIN moz_bookmarks pp ON bb.parent = pp.id JOIN moz_bookmarks gg ON pp.parent = gg.id
        WHERE bb.fk = h.id AND gg.guid = 'tags________') AS _tags
FROM moz_bookmarks b
JOIN moz_bookmarks p ON p.id = b.parent
JOIN moz_places h ON h.id = b.fk
JOIN urls ON urls.url = h.url AND urls.url_hash = h.url_hash
WHERE _grandParentId <> :tagsFolderId
ORDER BY h.url, b.lastModified DESC;

-- @id firefox.bookmarks.fetch_by_tags
-- @src toolkit/components/places/Bookmarks.sys.mjs:2539-2575
-- @style positional ? list for the tags (one per tag), tags guid interpolated
-- @tags dynamic
-- @note Bookmarks carrying all of two tags: IN-subquery with a 3-way join, lower() IN-list, GROUP BY ... HAVING count(*) = n, plus a correlated tag list.
-- @param ?1 'work'
-- @param ?2 'read-later-9'
SELECT b.guid, IFNULL(p.guid, '') AS parentGuid, b.position AS 'index', b.dateAdded, b.lastModified, b.type, IFNULL(b.title, '') AS title, h.url AS url, b.id AS _id, b.parent AS _parentId, NULL AS _childCount,
       p.parent AS _grandParentId, b.syncStatus AS _syncStatus,
       (SELECT group_concat(pp.title ORDER BY pp.title)
        FROM moz_bookmarks bb JOIN moz_bookmarks pp ON pp.id = bb.parent JOIN moz_bookmarks gg ON gg.id = pp.parent
        WHERE bb.fk = h.id AND gg.guid = 'tags________') AS _tags
FROM moz_bookmarks b
JOIN moz_bookmarks p ON p.id = b.parent
JOIN moz_bookmarks g ON g.id = p.parent
JOIN moz_places h ON h.id = b.fk
WHERE g.guid <> 'tags________'
AND b.fk IN (
  SELECT b2.fk FROM moz_bookmarks b2
  JOIN moz_bookmarks p2 ON p2.id = b2.parent
  JOIN moz_bookmarks g2 ON g2.id = p2.parent
  WHERE g2.guid = 'tags________'
  AND lower(p2.title) IN (?1,?2)
  GROUP BY b2.fk HAVING count(*) = 2
)
ORDER BY b.lastModified DESC;

-- @id firefox.bookmarks.fetch_recent
-- @src toolkit/components/places/Bookmarks.sys.mjs:2749-2775
-- @style named :params
-- @tags hotpath
-- @note Recent bookmarks (library, new tab): 3-way join excluding tags and place: queries, top-N by dateAdded.
-- @modified url_hash NOT BETWEEN hash('place', 'prefix_lo') AND hash('place', 'prefix_hi') (a scheme-prefix hash range; app-registered) replaced by the equivalent substr(url, 1, 6) <> 'place:'
-- @param :tagsFolderId 4
-- @param :type 1
-- @param :numberOfItems 10
SELECT b.guid, IFNULL(p.guid, '') AS parentGuid, b.position AS 'index', b.dateAdded, b.lastModified, b.type, IFNULL(b.title, '') AS title, h.url AS url, b.id AS _id, b.parent AS _parentId, NULL AS _childCount, NULL AS _grandParentId, NULL AS _syncStatus
FROM moz_bookmarks b
JOIN moz_bookmarks p ON p.id = b.parent
JOIN moz_places h ON h.id = b.fk
WHERE p.parent <> :tagsFolderId
AND b.type = :type
AND substr(url, 1, 6) <> 'place:'
ORDER BY b.dateAdded DESC, b.ROWID DESC
LIMIT :numberOfItems;

-- @id firefox.bookmarks.query_by_title
-- @src toolkit/components/places/Bookmarks.sys.mjs:2404-2450
-- @style named :params; queryString built from the info fields (title instance)
-- @tags dynamic
-- @note Bookmarks.search({title}): self LEFT JOIN for the parent, excludes tag folders, title equality scan.
-- @param :tags_folder 4
-- @param :title 'Bookmark 42'
SELECT b.guid, IFNULL(p.guid, '') AS parentGuid, b.position AS 'index', b.dateAdded, b.lastModified, b.type,
       IFNULL(b.title, '') AS title, h.url AS url, b.parent, p.parent,
       NULL AS _id, NULL AS _childCount, NULL AS _grandParentId, NULL AS _parentId, NULL AS _syncStatus
FROM moz_bookmarks b
LEFT JOIN moz_bookmarks p ON p.id = b.parent
LEFT JOIN moz_places h ON h.id = b.fk
WHERE b.parent <> :tags_folder AND p.parent <> :tags_folder AND b.title = :title;

-- @id firefox.bookmarks.move_descendants_check
-- @src toolkit/components/places/Bookmarks.sys.mjs:814-826
-- @style named :params
-- @note Moving a folder: recursive CTE seeded with VALUES collecting all descendant folders, then IN descendants.
-- @param :id 2
-- @param :type 2
WITH RECURSIVE
descendants(did) AS (
  VALUES(:id)
  UNION ALL
  SELECT id FROM moz_bookmarks JOIN descendants ON parent = did WHERE type = :type
)
SELECT guid FROM moz_bookmarks WHERE id IN descendants;

-- @id firefox.bookmarks.set_ancestors_last_modified
-- @src toolkit/components/places/Bookmarks.sys.mjs:3167-3178
-- @style named :params
-- @note Recursive walk up the folder tree driving an UPDATE ... WHERE id IN cte.
-- @param :guid 'fold00000100'
-- @param :type 2
-- @param :time 1792022400000000
WITH RECURSIVE
ancestors(aid) AS (
  SELECT id FROM moz_bookmarks WHERE guid = :guid
  UNION ALL
  SELECT parent FROM moz_bookmarks JOIN ancestors ON id = aid WHERE type = :type
)
UPDATE moz_bookmarks SET lastModified = :time
WHERE id IN ancestors;

-- @id firefox.bookmarks.remove_folder_contents
-- @src toolkit/components/places/Bookmarks.sys.mjs:3221-3242
-- @style named :params
-- @note Folder removal: recursive descendants CTE with CROSS JOIN to keep hierarchy order, joined to parents and places.
-- @param :folderGuid 'toolbar_____'
WITH RECURSIVE
descendants(did) AS (
  SELECT b.id FROM moz_bookmarks b JOIN moz_bookmarks p ON b.parent = p.id WHERE p.guid = :folderGuid
  UNION ALL
  SELECT id FROM moz_bookmarks JOIN descendants ON parent = did
)
SELECT b.id AS _id, b.parent AS _parentId, b.position AS 'index', b.type, url, b.guid, p.guid AS parentGuid, b.dateAdded,
       b.lastModified, IFNULL(b.title, '') AS title, p.parent AS _grandParentId, NULL AS _childCount, b.syncStatus AS _syncStatus
FROM descendants
CROSS JOIN moz_bookmarks b ON did = b.id
JOIN moz_bookmarks p ON p.id = b.parent
LEFT JOIN moz_places h ON b.fk = h.id;

-- @id firefox.bookmarks.full_paths
-- @src toolkit/components/places/Bookmarks.sys.mjs:3437-3449
-- @style named :params; :guidArray bound as an array
-- @note Breadcrumb paths for several bookmarks: recursive CTE walking parents, seeded from an array.
-- @modified guid IN carray(:guidArray) (SQLite carray extension) replaced by guid IN (SELECT value FROM json_each(:guidArray))
-- @param :guidArray '["bkmk00000042","bkmk00000777","fold00000100","bkmk00002999"]'
-- @param :rootGuid 'root________'
WITH RECURSIVE parents(start_guid, guid, _id, _parent, title) AS
  (SELECT guid AS start_guid, guid, id AS _id, parent AS _parent, IFNULL(title, '') AS title
   FROM moz_bookmarks
   WHERE guid IN (SELECT value FROM json_each(:guidArray))
   UNION ALL
   SELECT p.start_guid, b.guid, b.id AS _id, b.parent AS _parent, IFNULL(b.title, '') AS title
   FROM moz_bookmarks b
   INNER JOIN parents p ON b.id = p._parent)
SELECT * FROM parents WHERE guid != :rootGuid;

-- @id firefox.utils.bookmarks_tree
-- @src toolkit/components/places/PlacesUtils.sys.mjs:1809-1845
-- @style named :params; tags guid and ICONDATA_FLAGS_RICH (1) interpolated
-- @note promiseBookmarksTree (backups, sync): recursive descendants CTE plus a grouped tagged CTE, per-row icon subquery (3-way join, url_hash probe) and anno subquery, ordered by level.
-- @modified hash() is an app-registered function; replaced by the core-SQL fingerprint that data.sql also stores in url_hash (see header)
-- @param :item_guid 'root________'
-- @param :tags_folder 4
-- @param :charset_anno 'URIProperties/characterSet'
WITH RECURSIVE
descendants(fk, level, type, id, guid, parent, parentGuid, position, title, dateAdded, lastModified) AS (
  SELECT b1.fk, 0, b1.type, b1.id, b1.guid, b1.parent, (SELECT guid FROM moz_bookmarks WHERE id = b1.parent),
         b1.position, b1.title, b1.dateAdded, b1.lastModified
  FROM moz_bookmarks b1 WHERE b1.guid=:item_guid
  UNION ALL
  SELECT b2.fk, level + 1, b2.type, b2.id, b2.guid, b2.parent, descendants.guid, b2.position, b2.title, b2.dateAdded, b2.lastModified
  FROM moz_bookmarks b2
  JOIN descendants ON b2.parent = descendants.id AND b2.id <> :tags_folder),
tagged(place_id, tags) AS (
  SELECT b.fk, group_concat(p.title ORDER BY p.title)
  FROM moz_bookmarks b JOIN moz_bookmarks p ON p.id = b.parent JOIN moz_bookmarks g ON g.id = p.parent
  WHERE g.guid = 'tags________'
  GROUP BY b.fk
)
SELECT d.level, d.id, d.guid, d.parent, d.parentGuid, d.type, d.position AS [index], IFNULL(d.title, '') AS title, d.dateAdded,
       d.lastModified, h.url,
       (SELECT icon_url FROM moz_icons i JOIN moz_icons_to_pages ON icon_id = i.id JOIN moz_pages_w_icons pi ON page_id = pi.id
        WHERE pi.page_url_hash = (length(h.url) * 4503599627370496 + unicode(substr(h.url, -1, 1)) * 859983745857 + unicode(substr(h.url, -2, 1)) * 620455851591 + unicode(substr(h.url, -3, 1)) * 380927957327 + unicode(substr(h.url, -4, 1)) * 141400063061 + unicode(substr(h.url, -5, 1)) * 1001383796573 + unicode(substr(h.url, -6, 1)) * 761855902307 + unicode(substr(h.url, -7, 1)) * 522328008043 + unicode(substr(h.url, -8, 1)) * 282800113777 + unicode(substr(h.url, -9, 1)) * 43272219513 + unicode(substr(h.url, -10, 1)) * 903255953023 + unicode(substr(h.url, -11, 1)) * 663728058759 + unicode(substr(h.url, -12, 1)) * 424200164493 + unicode(substr(h.url, -13, 1)) * 184672270229 + unicode(substr(h.url, -14, 1)) * 1044656003739 + unicode(substr(h.url, -15, 1)) * 805128109475 + unicode(substr(h.url, -16, 1)) * 565600215209) AND pi.page_url = h.url
        ORDER BY (flags & 1) ASC, width DESC LIMIT 1) AS iconUri,
       (SELECT tags FROM tagged WHERE place_id = h.id) AS tags,
       (SELECT a.content FROM moz_annos a JOIN moz_anno_attributes n ON a.anno_attribute_id = n.id
        WHERE place_id = h.id AND n.name = :charset_anno) AS charset
FROM descendants d
LEFT JOIN moz_bookmarks b3 ON b3.id = d.parent
LEFT JOIN moz_places h ON h.id = d.fk
ORDER BY d.level, d.parent, d.position;

-- @id firefox.history.fetch_page_info
-- @src toolkit/components/places/History.cpp:1676-1684
-- @style named :params (mozStorage BindByName)
-- @tags hot-small,hotpath
-- @note Per-navigation page lookup: url_hash probe with a correlated last-visit id and a bookmarked EXISTS.
-- @modified hash() is an app-registered function; replaced by the core-SQL fingerprint that data.sql also stores in url_hash (see header)
-- @param :page_url 'https://github.com/'
SELECT guid, id, title, hidden, typed, frecency, visit_count, last_visit_date,
       (SELECT id FROM moz_historyvisits WHERE place_id = h.id AND visit_date = h.last_visit_date) AS last_visit_id,
       EXISTS(SELECT 1 FROM moz_bookmarks WHERE fk = h.id) AS bookmarked
FROM moz_places h
WHERE url_hash = (length(:page_url) * 4503599627370496 + unicode(substr(:page_url, -1, 1)) * 859983745857 + unicode(substr(:page_url, -2, 1)) * 620455851591 + unicode(substr(:page_url, -3, 1)) * 380927957327 + unicode(substr(:page_url, -4, 1)) * 141400063061 + unicode(substr(:page_url, -5, 1)) * 1001383796573 + unicode(substr(:page_url, -6, 1)) * 761855902307 + unicode(substr(:page_url, -7, 1)) * 522328008043 + unicode(substr(:page_url, -8, 1)) * 282800113777 + unicode(substr(:page_url, -9, 1)) * 43272219513 + unicode(substr(:page_url, -10, 1)) * 903255953023 + unicode(substr(:page_url, -11, 1)) * 663728058759 + unicode(substr(:page_url, -12, 1)) * 424200164493 + unicode(substr(:page_url, -13, 1)) * 184672270229 + unicode(substr(:page_url, -14, 1)) * 1044656003739 + unicode(substr(:page_url, -15, 1)) * 805128109475 + unicode(substr(:page_url, -16, 1)) * 565600215209) AND url = :page_url;

-- @id firefox.history.insert_visit
-- @src toolkit/components/places/History.cpp:1188-1192
-- @style named :params
-- @tags hot-small,hotpath
-- @note Visit insert on every navigation (the AFTER INSERT trigger is TEMP and app-function based, see schema.sql).
-- @param :from_visit 0
-- @param :page_id 6
-- @param :visit_date 1792022400000000
-- @param :visit_type 1
-- @param :source 0
-- @param :triggeringPlaceId NULL
-- @param :userContextId 0
INSERT INTO moz_historyvisits (from_visit, place_id, visit_date, visit_type, session, source, triggeringPlaceId, userContextId)
VALUES (:from_visit, :page_id, :visit_date, :visit_type, 0, :source, :triggeringPlaceId, :userContextId);

-- @id firefox.history.remove_by_filter_pages
-- @src toolkit/components/places/History.sys.mjs:1320-1353
-- @style named :params; fragments built from the filter (subhost wildcard + date range instance)
-- @tags dynamic
-- @note History.removeByFilter({host: '.example.org', beginDate, endDate}): rev_host BETWEEN range with a correlated EXISTS date probe.
-- @param :revHost 'gro.elpmaxe'
-- @param :begin 1789430400000000
-- @param :end 1792022400000000
SELECT h.id, url, url_hash, rev_host, guid, title, frecency, foreign_count
FROM moz_places h WHERE
(h.rev_host between :revHost || "." and :revHost || "/") AND (EXISTS
  (SELECT id FROM moz_historyvisits v WHERE v.place_id = h.id AND
   v.visit_date >= :begin AND v.visit_date <= :end
   LIMIT 1));

-- @id firefox.history.firefox_view_recent
-- @src toolkit/components/places/PlacesQuery.sys.mjs:150-168
-- @style SQL built from cachedHistoryOptions: daysOld = Infinity (no WHERE), SORT_BY.LAST_VISITED (GROUP BY url), limit interpolated
-- @tags hotpath,dynamic
-- @note Firefox View history tab: visits joined to places, GROUP BY url with MAX(visit_date), top-N by recency.
SELECT MAX(visit_date) as visit_date, h.visit_count as visit_count, title, url, guid
FROM moz_historyvisits v
JOIN moz_places h
ON v.place_id = h.id
AND hidden = 0
GROUP BY url
ORDER BY visit_date DESC
LIMIT 50;

-- @id firefox.utils.metadata_get
-- @src toolkit/components/places/PlacesUtils.sys.mjs:2249-2251
-- @style named :params
-- @tags hot-small
-- @note PlacesUtils.metadata.get: WITHOUT ROWID key lookup.
-- @param :key 'origin_frecency_threshold'
SELECT value FROM moz_meta WHERE key = :key;

-- @id firefox.urlbar.open_tabs_list
-- @src browser/components/urlbar/UrlbarProviderOpenTabs.sys.mjs:147-148
-- @style no parameters
-- @note Open-tab cache dump: ordered scan of the open pages table.
SELECT url, userContextId, NULLIF(groupId, '') groupId, open_count FROM moz_openpages_temp ORDER BY url, userContextId, groupId;

-- @id firefox.frecency.recalc_origins
-- @src toolkit/components/places/PlacesFrecencyRecalculator.sys.mjs:342-367
-- @style SQL with interpolated cutoff days (90) and chunk size (50)
-- @note Origin frecency recalculation: UPDATE with a correlated AVG * COUNT(DISTINCT date()) over places JOIN visits, IN top-N subquery, RETURNING.
-- @modified strftime('%s','now','localtime','start of day','-90 day','utc') uses the wall clock and local time zone; pinned to the data's 'now' (2026-10-14, UTC) so results are reproducible
UPDATE moz_origins
SET frecency = IFNULL((
  SELECT CAST(AVG(h.frecency) * COUNT(DISTINCT date(v.visit_date / 1000000, 'unixepoch')) AS INTEGER)
  FROM moz_places h
  JOIN moz_historyvisits v ON v.place_id = h.id
  WHERE h.origin_id = moz_origins.id
    AND v.visit_type = 2
    AND v.visit_date > strftime('%s','2026-10-14','start of day','-90 day') * 1000000
), 1.0),
recalc_frecency = 0
WHERE id IN (
  SELECT id FROM moz_origins WHERE recalc_frecency = 1 ORDER BY frecency DESC LIMIT 50
)
RETURNING id;

-- @id firefox.frecency.origin_threshold
-- @src toolkit/components/places/PlacesFrecencyRecalculator.sys.mjs:379-391
-- @style named :params
-- @note Autofill threshold: NTILE window over all origins, MAX of the first bucket.
-- @param :buckets 4
WITH ntiled AS (
  SELECT host, frecency, NTILE(:buckets) OVER (ORDER BY frecency ASC) AS ntile
  FROM moz_origins
  WHERE frecency > 1)
SELECT MAX(frecency)
FROM ntiled
WHERE ntile = 1;

-- @id firefox.expiration.find_orphan_uris
-- @src toolkit/components/places/PlacesExpiration.sys.mjs:210-218
-- @style named :params
-- @tags batch
-- @note Expiration step: INSERT ... SELECT of pages with no visits and no bookmarks via an anti-join, LIMIT.
-- @param :limit_uris 300
INSERT INTO expiration_notify (p_id, url, guid, visit_date)
SELECT h.id, h.url, h.guid, h.last_visit_date
FROM moz_places h
LEFT JOIN moz_historyvisits v ON h.id = v.place_id
WHERE h.last_visit_date IS NULL
  AND h.foreign_count = 0
  AND v.id IS NULL
  AND frecency <> -1
LIMIT :limit_uris;

-- @id firefox.expiration.orphan_favicon_pages
-- @src toolkit/components/places/PlacesExpiration.sys.mjs:318-323
-- @style no parameters
-- @note Favicon page GC: NOT IN over every moz_places url_hash OR a correlated NOT EXISTS.
DELETE FROM moz_pages_w_icons
WHERE page_url_hash NOT IN (
  SELECT url_hash FROM moz_places
) OR NOT EXISTS (
  SELECT 1 FROM moz_icons_to_pages WHERE page_id = moz_pages_w_icons.id
);

-- @id firefox.expiration.orphan_favicons
-- @src toolkit/components/places/PlacesExpiration.sys.mjs:334-338
-- @style no parameters
-- @note Icon GC: IN over an EXCEPT compound.
DELETE FROM moz_icons WHERE id IN (
  SELECT id FROM moz_icons WHERE root = 0
  EXCEPT
  SELECT icon_id FROM moz_icons_to_pages
);

-- @id firefox.expiration.orphan_annos
-- @src toolkit/components/places/PlacesExpiration.sys.mjs:349-354
-- @style named :params
-- @note Annotation GC: anti-join with LIMIT inside an IN subquery.
-- @param :limit_annos 100
DELETE FROM moz_annos WHERE id in (
  SELECT a.id FROM moz_annos a
  LEFT JOIN moz_places h ON a.place_id = h.id
  WHERE h.id IS NULL
  LIMIT :limit_annos
);
