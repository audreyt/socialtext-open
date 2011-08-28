BEGIN;

-- This shouldn't do anything in actual migrations from lolcat, but is
-- required if we are upgrading from older megasharks
DELETE FROM gadget WHERE src = 'local:widgets:activities.xml';

-- Point all activities widgets to the new location
UPDATE gadget
   SET src = 'local:widgets:activities.xml'
 WHERE src = 'local:widgets:activities';

UPDATE "System"
   SET value = '139'
 WHERE field = 'socialtext-schema-version';

COMMIT;
