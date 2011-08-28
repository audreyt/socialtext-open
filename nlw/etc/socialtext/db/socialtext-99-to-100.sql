BEGIN;

-- Migrate signal_account table to signal_user_set to enable
-- Signal to Groups

CREATE TABLE signal_user_set (
    signal_id bigint NOT NULL,
    user_set_id int NOT NULL
);

ALTER TABLE ONLY signal_user_set
    ADD CONSTRAINT signal_user_set_pkey
            PRIMARY KEY (signal_id, user_set_id);

ALTER TABLE ONLY signal_user_set
    ADD CONSTRAINT signal_user_set_signal_fk
        FOREIGN KEY (signal_id)
        REFERENCES signal (signal_id) ON DELETE CASCADE;

INSERT INTO signal_user_set (signal_id, user_set_id)
    SELECT signal_id, account_id + x'30000000'::int as user_set_id
      FROM signal_account;

CREATE INDEX ix_signal_user_set
    ON signal_user_set (signal_id);

CREATE UNIQUE INDEX ix_signal_user_set_rev
    ON signal_user_set (user_set_id, signal_id);

-- optimize certain aggregate subselects and for filtering signals
-- related to a particular group/account
CREATE INDEX ix_signal_uset_groups
    ON signal_user_set (signal_id, user_set_id)
    WHERE user_set_id BETWEEN x'10000001'::int AND x'20000000'::int;

CREATE INDEX ix_signal_uset_wksps
    ON signal_user_set (signal_id, user_set_id)
    WHERE user_set_id BETWEEN x'20000001'::int AND x'30000000'::int;

CREATE INDEX ix_signal_uset_accounts
    ON signal_user_set (signal_id, user_set_id)
    WHERE user_set_id > x'30000000'::int;

DROP TABLE signal_account;

-- modify the purge_user_set function to remove the signal_user_set entry
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
        DELETE FROM signal
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

-- same as users_share_plugin, except that the two users can share a user_set
-- that is transitively connected to some plugin (e.g. they share a group,
-- and that group's account has signals enabled)
CREATE VIEW users_share_plugin_tc AS
    SELECT v_path.user_id AS viewer_id, o_path.user_id AS other_id, user_set_id, plugin
    FROM user_sets_for_user v_path
    JOIN user_set_plugin_tc plug USING (user_set_id)
    JOIN user_sets_for_user o_path USING (user_set_id);

UPDATE "System"
   SET value = '100'
 WHERE field = 'socialtext-schema-version';

COMMIT;
