BEGIN;

-- Introduce the notion of user sets for permissioning.

CREATE FUNCTION purge_user_set(to_purge integer) RETURNS boolean
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

        RETURN true;
    END;
$$ LANGUAGE plpgsql;

CREATE FUNCTION on_user_set_delete() RETURNS "trigger"
AS $$
BEGIN
    IF (TG_RELNAME = 'users') THEN
        PERFORM purge_user_set(OLD.user_id::integer);
    ELSE
        PERFORM purge_user_set(OLD.user_set_id);
    END IF;

    RETURN NEW; -- proceed with the delete
END;
$$ LANGUAGE plpgsql;

-- Include the "from" set with role in the "into" set.
-- Contains the "real" roles in our system
CREATE TABLE user_set_include (
    from_set_id integer NOT NULL,
    into_set_id integer NOT NULL,
    role_id integer NOT NULL,
    CONSTRAINT no_self_includes CHECK (from_set_id <> into_set_id)
);
ALTER TABLE ONLY user_set_include
    ADD CONSTRAINT "user_set_include_pkey"
    PRIMARY KEY (from_set_id, into_set_id);
CREATE UNIQUE INDEX idx_user_set_include_rev
    ON user_set_include (into_set_id,from_set_id);

-- This is the "maintenance" table for the transitive closure on the
-- user_set_include table above.
CREATE SEQUENCE user_set_path_id_seq
    INCREMENT BY 1
    NO MAXVALUE NO MINVALUE CACHE 1;
CREATE TABLE user_set_path (
    user_set_path_id integer NOT NULL DEFAULT nextval('user_set_path_id_seq'),
    from_set_id integer NOT NULL, -- Start
    into_set_id integer NOT NULL, -- End
    role_id integer NOT NULL, -- the role on that "last hop" in the destination set
    vlist integer[] NOT NULL
);
ALTER TABLE ONLY user_set_path
    ADD CONSTRAINT "user_set_path_pkey"
    PRIMARY KEY (user_set_path_id);
CREATE INDEX idx_user_set_path_wholepath
    ON user_set_path (from_set_id,into_set_id);
CREATE INDEX idx_user_set_path_wholepath_rev
    ON user_set_path (into_set_id,from_set_id);

-- GiST indexing of vlist is sucky slow :(
-- Use a simple normalized table lookup 'user_set_path_component' instead.

CREATE TABLE user_set_path_component (
    user_set_path_id integer NOT NULL,
    user_set_id integer NOT NULL
);

-- Update user_set_path_component on every insert into user_set_path.

CREATE FUNCTION on_user_set_path_insert() RETURNS "trigger"
AS $$
DECLARE
    upper_bound int;
BEGIN
    IF (NEW.from_set_id <> NEW.into_set_id) THEN
        -- regular path; consume all vlist elements
        upper_bound := array_upper(NEW.vlist,1);
    ELSE
        -- reflexive path; ignore the last element since it's the same as the
        -- first element
        upper_bound := array_upper(NEW.vlist,1)-1;
    END IF;

    -- Make a row for each vlist entry.
    FOR i IN array_lower(NEW.vlist,1) .. upper_bound LOOP
        INSERT INTO user_set_path_component (user_set_path_id, user_set_id)
        VALUES (NEW.user_set_path_id, NEW.vlist[i]);
    END LOOP;
    RETURN NEW; -- proceed with the insert
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER user_set_path_insert AFTER INSERT ON user_set_path
FOR EACH ROW EXECUTE PROCEDURE on_user_set_path_insert();

-- The transitive closure on user_set_include
CREATE VIEW user_set_include_tc AS
  SELECT DISTINCT from_set_id, into_set_id, role_id
  FROM user_set_path;

-- Map regular ID fields into a user_set_id.  Give each range ~268 million
-- numbers.

-- HANDY WHERE CLAUSES:
-- users: from_set_id <= x'10000000'::int;
-- groups: from_set_id BETWEEN x'10000001'::int AND x'20000000'::int;
-- workspaces: from_set_id BETWEEN x'20000001'::int AND x'30000000'::int;
-- accounts: from_set_id BETWEEN x'30000001'::int AND x'40000000'::int;

ALTER TABLE groups ADD COLUMN user_set_id integer;
UPDATE groups SET user_set_id = group_id + x'10000000'::int;
ALTER TABLE groups ALTER COLUMN user_set_id SET NOT NULL;

ALTER TABLE "Workspace" ADD COLUMN user_set_id integer;
UPDATE "Workspace" SET user_set_id = workspace_id + x'20000000'::int;
ALTER TABLE "Workspace" ALTER COLUMN user_set_id SET NOT NULL;

ALTER TABLE "Account" ADD COLUMN user_set_id integer;
UPDATE "Account" SET user_set_id = account_id + x'30000000'::int;
ALTER TABLE "Account" ALTER COLUMN user_set_id SET NOT NULL;

CREATE TRIGGER workspace_user_set_delete AFTER DELETE ON "Workspace"
FOR EACH ROW EXECUTE PROCEDURE on_user_set_delete();
CREATE TRIGGER account_user_set_delete AFTER DELETE ON "Account"
FOR EACH ROW EXECUTE PROCEDURE on_user_set_delete();
CREATE TRIGGER user_user_set_delete AFTER DELETE ON users
FOR EACH ROW EXECUTE PROCEDURE on_user_set_delete();
CREATE TRIGGER group_user_set_delete AFTER DELETE ON groups
FOR EACH ROW EXECUTE PROCEDURE on_user_set_delete();

CREATE TABLE user_set_plugin (
    user_set_id integer NOT NULL,
    plugin text NOT NULL
);
ALTER TABLE ONLY user_set_plugin
    ADD CONSTRAINT "user_set_plugin_pkey"
    PRIMARY KEY (user_set_id, plugin);
CREATE UNIQUE INDEX user_set_plugin_ukey ON user_set_plugin (plugin, user_set_id);

CREATE TABLE user_set_plugin_pref (
    user_set_id integer NOT NULL,
    plugin text NOT NULL,
    "key" text NOT NULL,
    value text NOT NULL
);
ALTER TABLE ONLY user_set_plugin_pref
    ADD CONSTRAINT user_set_plugin_pref_fk
            FOREIGN KEY (user_set_id, plugin)
            REFERENCES user_set_plugin(user_set_id,plugin) ON DELETE CASCADE;
CREATE INDEX idx_user_set_plugin_pref ON user_set_plugin_pref (user_set_id, plugin);
CREATE INDEX idx_user_set_plugin_pref_key ON user_set_plugin_pref (user_set_id, plugin,"key");

INSERT INTO user_set_plugin
SELECT user_set_id, plugin
FROM "Account"
NATURAL JOIN account_plugin;

INSERT INTO user_set_plugin
SELECT user_set_id, plugin
FROM "Workspace"
NATURAL JOIN workspace_plugin;

INSERT INTO user_set_plugin_pref
SELECT user_set_id, plugin, key, value
FROM "Workspace"
JOIN workspace_plugin_pref USING (workspace_id);

DROP TABLE account_plugin;
DROP TABLE workspace_plugin_pref;
DROP TABLE workspace_plugin;

-- Add some convenience views

-- e.g. WHERE viewer_id = ? AND plugin = 'people'
CREATE VIEW user_use_plugin AS
    SELECT from_set_id AS user_id, into_set_id AS user_set_id, plugin
    FROM user_set_path
    JOIN user_set_plugin ON (into_set_id = user_set_id);

-- We can avoid doing a join by simply checking the value of the from_set_id;
-- if it's not in the range reserved for containers, it must be a user.

CREATE VIEW user_sets_for_user AS
    SELECT from_set_id AS user_id, into_set_id AS user_set_id
    FROM user_set_path
    WHERE from_set_id <= x'10000000'::int;

CREATE VIEW roles_for_user AS
    SELECT from_set_id AS user_id, into_set_id AS user_set_id, role_id
    FROM user_set_path
    WHERE from_set_id <= x'10000000'::int;

-- e.g. WHERE viewer_id = ? AND other_id = ? AND plugin = 'people'
CREATE VIEW users_share_plugin AS
    SELECT v_path.user_id AS viewer_id, o_path.user_id AS other_id, user_set_id, plugin
    FROM user_sets_for_user v_path
    JOIN user_set_plugin plug USING (user_set_id)
    JOIN user_sets_for_user o_path USING (user_set_id);

CREATE VIEW groups_for_user AS
    SELECT user_id, user_set_id, (user_set_id - x'10000000'::int) AS group_id
    FROM user_sets_for_user
    WHERE user_set_id BETWEEN x'10000001'::int AND x'20000000'::int;

CREATE VIEW workspaces_for_user AS
    SELECT user_id, user_set_id, (user_set_id - x'20000000'::int) AS workspace_id
    FROM user_sets_for_user
    WHERE user_set_id BETWEEN x'20000001'::int AND x'30000000'::int;

CREATE VIEW accounts_for_user AS
    SELECT user_id, user_set_id, (user_set_id - x'30000000'::int) AS account_id
    FROM user_sets_for_user
    WHERE user_set_id BETWEEN x'30000001'::int AND x'40000000'::int;

-- either this thing, or something this thing is connected to has this plugin
-- usage:
-- SELECT 1 FROM user_set_plugin_tc WHERE user_set_id = ? AND plugin = ? LIMIT 1
CREATE VIEW user_set_plugin_tc AS
    SELECT user_set_id, plugin FROM user_set_plugin
    UNION ALL
    SELECT from_set_id AS user_set_id, plugin
    FROM user_set_path path
    JOIN user_set_plugin plug ON (path.into_set_id = plug.user_set_id);


UPDATE "System"
   SET value = '95'
 WHERE field = 'socialtext-schema-version';

COMMIT;
