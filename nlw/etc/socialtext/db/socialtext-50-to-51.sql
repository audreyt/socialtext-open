BEGIN;

ALTER TABLE gadget
    ALTER COLUMN href DROP NOT NULL,
    ALTER COLUMN content_type DROP NOT NULL,
    ADD COLUMN extra_files TEXT;

UPDATE gadget
  SET src = regexp_replace(src, '^file:([^/]*).*?([^/]*).xml$', 'local:\\1:\\2')
WHERE src LIKE 'file:%';

UPDATE "System"
   SET value = '51'
 WHERE field = 'socialtext-schema-version';

COMMIT;
