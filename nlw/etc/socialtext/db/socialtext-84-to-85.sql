BEGIN;

DROP TABLE json_proxy_cache;

UPDATE "System"
   SET value = '85'
 WHERE field = 'socialtext-schema-version';

COMMIT;
