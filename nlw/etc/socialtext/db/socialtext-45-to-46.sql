BEGIN;

-- reserved for Story: User lookaheads UI

UPDATE "System"
   SET value = '46'
 WHERE field = 'socialtext-schema-version';

COMMIT;
