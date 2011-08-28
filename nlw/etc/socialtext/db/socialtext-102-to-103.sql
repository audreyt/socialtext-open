BEGIN;

--- Create identical looking tables to hold "recent Signals", for performance
--- reasons; we'll keep track of "recent" Signals in this set of tables *as
--- well as* in the original tables (this data is *just* a copy of the
--- original data, its *NOT* a replacement for it).
---
--- When querying recent Signals, we can hit these smaller tables for better
--- performance (as there's less data in it).
---
--- SQL TRIGGERs are added to the *original* Signals tables, to ensure that
--- any changes made to those tables are reflected in these "recent" tables.


--- Create the "recent_signal" table, and indices matching the original
--- "signal" table.
CREATE TABLE recent_signal (
    signal_id bigint NOT NULL,
    "at" timestamptz DEFAULT now(),
    user_id bigint NOT NULL,
    body text NOT NULL,
    in_reply_to_id bigint,
    recipient_id bigint,
    hidden boolean DEFAULT false
);

INSERT INTO recent_signal
SELECT signal_id, at, user_id, body, in_reply_to_id, recipient_id, hidden
  FROM signal
 WHERE at >= 'today'::timestamptz - '4 weeks'::interval;

CREATE INDEX ix_recent_signal_at ON recent_signal ("at");
CREATE INDEX ix_recent_signal_at_user ON recent_signal ("at", user_id);
CREATE INDEX ix_recent_signal_recipient_at ON recent_signal (recipient_id, "at");
CREATE INDEX ix_recent_signal_reply ON recent_signal (in_reply_to_id);
CREATE INDEX ix_recent_signal_user_at ON recent_signal (user_id, "at");
CREATE INDEX recent_signal_hidden ON recent_signal (hidden);

ALTER TABLE ONLY recent_signal
    ADD CONSTRAINT recent_signal_pkey
        PRIMARY KEY (signal_id);

--- Add triggers to the original "signal" table to automatically propogate
--- changes into the "recent_signal" table

--- INSERT signal
CREATE FUNCTION insert_recent_signal() RETURNS "trigger"
    AS $$
    BEGIN
        INSERT INTO recent_signal (
            signal_id, "at", user_id, body,
            in_reply_to_id, recipient_id, hidden
        )
        VALUES (
            NEW.signal_id, NEW."at", NEW.user_id, NEW.body,
            NEW.in_reply_to_id, NEW.recipient_id, NEW.hidden
        );
        RETURN NULL;    -- trigger return val is ignored
    END
    $$
LANGUAGE plpgsql;

CREATE TRIGGER signal_insert_recent
    AFTER INSERT ON signal
    FOR EACH ROW
    EXECUTE PROCEDURE insert_recent_signal();

--- UPDATE signal
CREATE FUNCTION update_recent_signal() RETURNS "trigger"
    AS $$
    BEGIN
        UPDATE recent_signal
           SET "at"           = NEW."at",
               user_id        = NEW.user_id,
               body           = NEW.body,
               in_reply_to_id = NEW.in_reply_to_id,
               recipient_id   = NEW.recipient_id,
               hidden         = NEW.hidden
         WHERE signal_id      = NEW.signal_id;
        RETURN NULL;    -- trigger return val is ignored
    END
    $$
LANGUAGE plpgsql;

CREATE TRIGGER signal_update_recent
    AFTER UPDATE ON signal
    FOR EACH ROW
    EXECUTE PROCEDURE update_recent_signal();

--- DELETE signal
CREATE FUNCTION delete_recent_signal() RETURNS "trigger"
    AS $$
    BEGIN
        DELETE FROM recent_signal
         WHERE recent_signal.signal_id = OLD.signal_id;
        RETURN NULL;    -- trigger return val is ignored
    END
    $$
LANGUAGE plpgsql;

CREATE TRIGGER signal_delete_recent
    AFTER DELETE ON signal
    FOR EACH ROW
    EXECUTE PROCEDURE delete_recent_signal();

--- Create the "recent_signal_user_set" table, and indices matching the
--- original "signal_user_set" table.
---
--- This table *also* has referential integrity to the "recent_signal" table,
--- so that as items are deleted from "recent_signal" it cascades into this
--- table automatically.
CREATE TABLE recent_signal_user_set (
    signal_id bigint NOT NULL,
    user_set_id integer NOT NULL
);

INSERT INTO recent_signal_user_set
SELECT signal_id, user_set_id
  FROM signal_user_set
 WHERE signal_id IN (SELECT signal_id FROM recent_signal);

CREATE INDEX ix_recent_signal_user_set
    ON recent_signal_user_set (signal_id);

CREATE UNIQUE INDEX ix_recent_signal_user_set_rev
    ON recent_signal_user_set (user_set_id, signal_id);

CREATE INDEX ix_recent_signal_uset_accounts
    ON recent_signal_user_set (signal_id, user_set_id)
    WHERE (user_set_id > (B'00110000000000000000000000000000'::"bit")::integer);

CREATE INDEX ix_recent_signal_uset_groups
    ON recent_signal_user_set (signal_id, user_set_id)
    WHERE ((user_set_id >= (B'00010000000000000000000000000001'::"bit")::integer) AND (user_set_id <= (B'00100000000000000000000000000000'::"bit")::integer));

CREATE INDEX ix_recent_signal_uset_wksps
    ON recent_signal_user_set (signal_id, user_set_id)
    WHERE ((user_set_id >= (B'00100000000000000000000000000001'::"bit")::integer) AND (user_set_id <= (B'00110000000000000000000000000000'::"bit")::integer));

ALTER TABLE ONLY recent_signal_user_set
    ADD CONSTRAINT recent_signal_user_set_signal_fk
        FOREIGN KEY (signal_id)
        REFERENCES recent_signal(signal_id) ON DELETE CASCADE;

--- INSERT signal_user_set
CREATE FUNCTION insert_recent_signal_user_set() RETURNS "trigger"
    AS $$
    BEGIN
        INSERT INTO recent_signal_user_set (signal_id, user_set_id)
        VALUES (NEW.signal_id, NEW.user_set_id);
        RETURN NULL;    -- trigger return val is ignored
    END
    $$
LANGUAGE plpgsql;

CREATE TRIGGER signal_uset_insert_recent
    AFTER INSERT ON signal_user_set
    FOR EACH ROW
    EXECUTE PROCEDURE insert_recent_signal_user_set();

--- UPDATE signal_user_set
CREATE FUNCTION update_recent_signal_user_set() RETURNS "trigger"
    AS $$
    BEGIN
        UPDATE recent_signal_user_set
           SET user_set_id = NEW.user_set_id
         WHERE signal_id   = OLD.signal_id
           AND user_set_id = OLD.user_set_id;
        RETURN NULL;    -- trigger return val is ignored
    END
    $$
LANGUAGE plpgsql;

CREATE TRIGGER signal_uset_update_recent
    AFTER UPDATE ON signal_user_set
    FOR EACH ROW
    EXECUTE PROCEDURE update_recent_signal_user_set();

--- DELETE signal_user_set
CREATE FUNCTION delete_recent_signal_user_set() RETURNS "trigger"
    AS $$
    BEGIN
        DELETE FROM recent_signal_user_set
         WHERE recent_signal_user_set.signal_id   = OLD.signal_id
           AND recent_signal_user_set.user_set_id = OLD.user_set_id;
        RETURN NULL;    -- trigger return val is ignored
    END
    $$
LANGUAGE plpgsql;

CREATE TRIGGER signal_uset_delete_recent
    AFTER DELETE ON signal_user_set
    FOR EACH ROW
    EXECUTE PROCEDURE delete_recent_signal_user_set();

--- DB migration done
UPDATE "System"
   SET value = '103'
 WHERE field = 'socialtext-schema-version';

COMMIT;
