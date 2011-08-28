BEGIN;

CREATE OR REPLACE FUNCTION user_set_is_user(id bigint) RETURNS BOOLEAN as $$
BEGIN
    IF id <= x'10000000'::int THEN
        RETURN TRUE;
    ELSE
        RETURN FALSE;
    END IF;
END
$$
language plpgsql;

CREATE OR REPLACE FUNCTION user_set_is_group(id bigint) RETURNS BOOLEAN as $$
BEGIN
    IF id > x'10000000'::int AND id <= x'20000000'::int THEN
        RETURN TRUE;
    ELSE
        RETURN FALSE;
    END IF;
END
$$
language plpgsql;

CREATE OR REPLACE FUNCTION user_set_is_workspace(id bigint) RETURNS BOOLEAN as $$
BEGIN
    IF id > x'20000000'::int AND id <= x'30000000'::int THEN
        RETURN TRUE;
    ELSE
        RETURN FALSE;
    END IF;
END
$$
language plpgsql;

CREATE OR REPLACE FUNCTION user_set_is_account(id bigint) RETURNS BOOLEAN as $$
BEGIN
    IF id > x'30000000'::int THEN
        RETURN TRUE;
    ELSE
        RETURN FALSE;
    END IF;
END
$$
language plpgsql;

CREATE OR REPLACE FUNCTION shares_account(user1 bigint, user2 bigint) returns BOOLEAN AS $$
DECLARE
    myrec RECORD;
BEGIN
    SELECT into_set_id INTO myrec
    FROM
        user_set_path
    WHERE
        from_set_id = user1
    AND
        into_set_id > x'30000000'::int
    AND
        into_set_id in (
            SELECT DISTINCT into_set_id
            FROM user_set_path
            WHERE from_set_id = user2
              AND into_set_id > x'30000000'::int)
    LIMIT 1;
    RETURN FOUND;
END
$$
language plpgsql;

UPDATE "System"
   SET value = '140'
 WHERE field = 'socialtext-schema-version';

COMMIT;
