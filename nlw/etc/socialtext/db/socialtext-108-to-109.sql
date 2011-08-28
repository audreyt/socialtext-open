BEGIN;

-- modify the purge_user_set function to remove the signal_user_set entry
-- and hide signals.
CREATE OR REPLACE FUNCTION purge_user_set(to_purge integer) RETURNS boolean
AS $$
    BEGIN
        LOCK user_set_include, user_set_path IN SHARE MODE;

        DELETE FROM user_set_include
        WHERE from_set_id = to_purge OR into_set_id = to_purge;

        DELETE FROM user_set_path
        WHERE user_set_path_id IN (
            SELECT user_set_path_id
              FROM user_set_path_component
             WHERE user_set_id = to_purge
        );

        DELETE FROM user_set_plugin_pref
        WHERE user_set_id = to_purge;

        DELETE FROM user_set_plugin
        WHERE user_set_id = to_purge;

        -- Signals that will have zero user-sets after we delete to_purge need
        -- to also get purged.  Otherwise these signals become visible to
        -- everyone.
        UPDATE SIGNAL
        SET hidden = true
        WHERE signal_id IN (
            SELECT signal_id
              FROM signal_user_set sus1
             WHERE sus1.user_set_id = to_purge
               AND NOT EXISTS (
                   SELECT 1
                     FROM signal_user_set sus2
                    WHERE sus1.signal_id = sus2.signal_id
                      AND sus2.user_set_id <> to_purge
               )
         );

        DELETE FROM signal_user_set
        WHERE user_set_id = to_purge;

        RETURN true;
    END;
$$
    LANGUAGE plpgsql;

--- DB migration done
UPDATE "System"
   SET value = '109'
 WHERE field = 'socialtext-schema-version';

COMMIT;
