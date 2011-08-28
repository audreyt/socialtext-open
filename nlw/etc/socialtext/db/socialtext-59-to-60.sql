BEGIN;

ALTER TABLE container_type
  ADD COLUMN purge_all_on_update BOOLEAN DEFAULT FALSE;

ALTER TABLE gadget_instance
    ADD COLUMN class TEXT;

UPDATE "System"
   SET value = '60'
 WHERE field = 'socialtext-schema-version';

COMMIT;
