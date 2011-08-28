BEGIN;

-- extended-mode output:
\x

ALTER TABLE "Account"
    ALTER skin_name SET DEFAULT 's3'::varchar;

-- finish up

UPDATE "System"
   SET value = 18
 WHERE field = 'socialtext-schema-version';

COMMIT;
