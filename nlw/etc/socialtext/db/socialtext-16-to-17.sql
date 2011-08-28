BEGIN;
-- extended-mode output:
\x

--
-- make an "in case of emergency" copy of the User and UserId tables
--

    \o /var/www/socialtext/storage/db-backups/user_detail_migration.txt
    SELECT * FROM "User";
    \o

    \o /var/www/socialtext/storage/db-backups/user_detail_migration2.txt
    SELECT * FROM "UserId";
    \o

--
-- Drop a few things that need to get recreated later due to table/column
-- renames
--

    DROP VIEW user_account;
    DROP FUNCTION auto_vivify_person() CASCADE;

--
-- Give the "UserId" table a new name.
-- I (stash) chose 'users' since 'user' is a Pg reserved word that can't be
-- used without double-quotes.
--

    ALTER TABLE "UserId" RENAME TO users;

    -- will recreate as "users_driver_unique_id" later
    DROP INDEX "UserId___driver_key___driver_key___driver_unique_id";

    -- need to rename both the index and constraint
    ALTER INDEX "UserId_pkey" RENAME TO "users_pkey";
    UPDATE pg_constraint 
       SET conname = 'users_pkey' 
     WHERE conname = 'UserId_pkey';

    -- rename the user_id sequence (yes, Pg docs say to use ALTER TABLE)
    ALTER TABLE "UserId___system_unique_id" 
        RENAME TO "users___user_id";

--
-- Migrate the "User" table into the new users table
--

    -- Add "User" columns to the old "UserId" table to make the new users
    -- table.  Defaults are chosen to work with non-Default users.
    -- We'll re-add indexes to these later.
    ALTER TABLE users
        ADD COLUMN email_address text DEFAULT '' NOT NULL;
    ALTER TABLE users
        ADD COLUMN password text DEFAULT '*none*' NOT NULL;
    ALTER TABLE users
        ADD COLUMN first_name text DEFAULT '' NOT NULL;
    ALTER TABLE users
        ADD COLUMN last_name text DEFAULT '' NOT NULL;
    ALTER TABLE users
        ADD COLUMN cached_at timestamptz DEFAULT '-infinity'::timestamptz NOT NULL;

    UPDATE users
       SET email_address = u.email_address,
           password      = u.password,
           first_name    = u.first_name,
           last_name     = u.last_name,
           cached_at     = 'infinity'::timestamptz
      FROM "User" u
     WHERE u.user_id = driver_unique_id
       AND driver_key = 'Default';

    -- Rectify the "system_unique_id isn't always equal to driver_unique_id"
    -- problem for Default users; the driver_unique_id should only be
    -- different for non-Default users.
    --
    -- This is the reason we drop the
    -- "UserId___driver_key___driver_key___driver_unique_id" index
    -- temporarily; this statement can fail due to the way postgres
    -- "constraint" indexes work.
    UPDATE users
       SET driver_unique_id = system_unique_id
     WHERE driver_key = 'Default';

--
-- clean up the users table schema
--

    -- Rename the system_unique_id column to user_id
    ALTER TABLE users 
        RENAME COLUMN system_unique_id TO user_id;

    -- remove character-length constrains on these three columns:
    ALTER TABLE users
        ALTER COLUMN driver_key TYPE text;
    ALTER TABLE users
        ALTER COLUMN driver_unique_id TYPE text;
    ALTER TABLE users
        ALTER COLUMN driver_username TYPE text;

    -- force username to be NOT NULL
    UPDATE users
        SET driver_username = ''
        WHERE driver_username IS NULL;
    ALTER TABLE users 
        ALTER COLUMN driver_username SET NOT NULL;

    -- rename this ugly constraint (an fk constraint formerly between
    -- Watchlist and UserId)
    UPDATE pg_constraint 
       SET conname = 'watchlist_user_fk' 
     WHERE conname = 'watchlist___userid___user_id___system_unique_id___n___1___1___0';

--
-- Recreate the stuff we said we needed to recreate
--

    -- PL/pgsql functions don't get auto-updated to the new column names
    CREATE FUNCTION auto_vivify_person() RETURNS "trigger"
    AS $$
        BEGIN
            INSERT INTO person (id, last_update) 
                VALUES (NEW.user_id, '-infinity'::timestamptz);
            RETURN NEW;
        END
    $$ LANGUAGE plpgsql;

    -- need to re-attach the trigger to the new table
    CREATE TRIGGER person_ins
        AFTER INSERT ON users
        FOR EACH ROW
        EXECUTE PROCEDURE auto_vivify_person();

    -- rename the system_unique_id field coming out of this view
    CREATE VIEW user_account AS
        SELECT DISTINCT 
            u.user_id, 
            u.driver_key, 
            u.driver_unique_id, 
            u.driver_username, 
            um.created_by_user_id AS creator_id, 
            um.creation_datetime, 
            um.primary_account_id, 
            w.account_id AS secondary_account_id
        FROM users u
        JOIN "UserMetadata" um USING (user_id)
        LEFT JOIN "UserWorkspaceRole" uwr USING (user_id)
        LEFT JOIN "Workspace" w USING (workspace_id);

--
-- non-Default uses will be missing an email_address.  Try to fix this by
-- looking at UserMetadata.email_address_at_import and the username.
--

    -- fill in missing e-mail addresses from import-emails
    UPDATE users
       SET email_address = um.email_address_at_import
      FROM "UserMetadata" um
     WHERE email_address = ''
       AND um.user_id = users.user_id
       AND um.email_address_at_import IS NOT NULL;

    -- fill in emails with usernames that look like emails
    UPDATE users
       SET email_address = driver_username
     WHERE email_address = ''
       AND driver_username LIKE '%@%'
       AND NOT driver_username LIKE '%@%@%';

    -- assign a unique addresses based on user ids
    UPDATE users
       SET email_address = 'migration-missing-email-' || user_id || '@example.com'
     WHERE email_address = '';

--
-- Since email_address_at_import is not UNIQUE, there's a potential for email
-- address conflicts.  Resolve these before adding the (driver_key,
-- email_address) UNIQUE index below.
--
-- Getting into this situation should be impossible for Default users since
-- previously there was a unique constraint on that column.
--

    -- bulk-load everything into this table
    CREATE TEMP TABLE email_conflict_res AS
    SELECT driver_key || '>>' || LOWER(email_address) AS key,
           driver_key, LOWER(email_address) AS email_address, user_id
      FROM users
     WHERE driver_key <> 'Default'; -- not a problem for Default users

    -- make the next step tractable
    CREATE INDEX "temp_conflict_driver_email"
        ON email_conflict_res (key);

    -- we only want to consider addresses that are duplicated
    DELETE FROM email_conflict_res
    WHERE key IN (
        SELECT key
          FROM email_conflict_res
          GROUP BY key
          HAVING count(user_id) = 1
    );

    -- make a record for sysadmin/support to use
    \o /var/www/socialtext/storage/db-backups/user_email_conflicts.txt
    SELECT driver_key, email_address, user_id FROM email_conflict_res;
    \o

    -- speeds up the join during the DELETE
    CREATE INDEX "temp_conflict_user_id"
        ON email_conflict_res (user_id);

    -- Temporarily force the email address to something unique.
    -- Any time ST::User->new() gets run the email address will get updated to
    -- the correct value.  As such, this should not affect things like email
    -- notifications.
    -- This should not affect users logging in via email.
    UPDATE users
       SET email_address = 'migration-duplicated-email-' || user_id || '@example.com'
     WHERE user_id IN (SELECT user_id FROM email_conflict_res);

    DROP TABLE email_conflict_res;

-- recreate former "User" and "UserId" table indexes.
-- considering that we'll be putting more than one driver in this table, we
-- need to make email/username unique *per driver*.

    CREATE UNIQUE INDEX "users_lower_email_address_driver_key"
        ON users (lower(email_address), driver_key);

    CREATE UNIQUE INDEX "users_lower_username_driver_key"
        ON users (lower(driver_username), driver_key);

    CREATE UNIQUE INDEX "users_driver_unique_id"
        ON users (driver_key, driver_unique_id);

--
-- The "User" table and its sequence aren't needed anymore
--

    DROP TABLE "User" CASCADE; -- CASCADE only affects dev-env "x" views
    DROP SEQUENCE "User___user_id";

-- finish up

UPDATE "System"
   SET value = 17
 WHERE field = 'socialtext-schema-version';

COMMIT;
