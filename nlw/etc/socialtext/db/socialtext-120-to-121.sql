BEGIN;

-- For [Story: Update Signal Annotations to Match New Twitter Spec]
-- Nuke all old annotations in the old format.

UPDATE signal SET anno_blob = '[]';
UPDATE recent_signal SET anno_blob = '[]';

UPDATE "System"
   SET value = '121'
 WHERE field = 'socialtext-schema-version';

COMMIT;
