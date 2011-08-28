BEGIN;

-- [Story: Cache "Not found" LDAP lookups]:
--
-- Create a new "missing" column in the "users" table so we can track whether
-- or not the last lookup for a User resulted in our determining that they
-- were "missing" from the LDAP directory.

ALTER TABLE ONLY users ADD COLUMN missing BOOLEAN DEFAULT FALSE NOT NULL;
UPDATE users SET missing=FALSE;

UPDATE "System"
   SET value = '125'
 WHERE field = 'socialtext-schema-version';

COMMIT;
