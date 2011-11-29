BEGIN;

-- Starfish

UPDATE gadget_instance
   SET class = 'cannot_move cannot_remove'
 WHERE class = 'borderless';

UPDATE "System"
   SET value = '150'
 WHERE field = 'socialtext-schema-version';

COMMIT;
