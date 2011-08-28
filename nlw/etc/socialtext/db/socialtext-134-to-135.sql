BEGIN;

CREATE FUNCTION not_null(anyarray) RETURNS anyarray AS $$ 
    SELECT ARRAY(SELECT x FROM unnest($1) g(x) WHERE x IS NOT NULL) 
$$ LANGUAGE sql;

UPDATE "System"
   SET value = '135'
 WHERE field = 'socialtext-schema-version';

COMMIT;
