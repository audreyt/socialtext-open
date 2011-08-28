BEGIN;

SET search_path = public, pg_catalog;

CREATE TABLE "System" (
    field varchar(1024) NOT NULL,
    value varchar(1024) NOT NULL,
    last_update timestamptz DEFAULT CURRENT_TIMESTAMP
);

ALTER TABLE ONLY "System"
    ADD CONSTRAINT system_pkey
            PRIMARY KEY (field);

INSERT INTO "System" (field, value) VALUES ('socialtext-schema-version', 2);

COMMIT;
