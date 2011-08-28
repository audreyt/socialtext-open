BEGIN;

CREATE SEQUENCE gallery_id
    INCREMENT BY 1
    NO MAXVALUE
    NO MINVALUE
    CACHE 1;

CREATE TABLE gallery (
    gallery_id bigint NOT NULL,
    last_update timestamptz DEFAULT now() NOT NULL,
    account_id bigint,
    CONSTRAINT gallery_pk
            PRIMARY KEY (gallery_id),
    CONSTRAINT gallery_account_uniq
            UNIQUE(account_id),
    CONSTRAINT gallery_id_or_account_id
            CHECK(
                (gallery_id = 0 AND account_id IS NULL)
             OR (gallery_id != 0 AND account_id IS NOT NULL)
            ),
    CONSTRAINT gallery_account_fk
            FOREIGN KEY (account_id)
            REFERENCES "Account"(account_id) ON DELETE CASCADE
);

CREATE TABLE gallery_gadget (
    gadget_id bigint NOT NULL,
    gallery_id bigint NOT NULL,
    position INTEGER NOT NULL,
    socialtext BOOLEAN NOT NULL,
    CONSTRAINT gallery_gadget_fk
            FOREIGN KEY (gadget_id)
            REFERENCES gadget(gadget_id) ON DELETE CASCADE,
    CONSTRAINT gallery_gadget_account_fk
            FOREIGN KEY (gallery_id)
            REFERENCES gallery(gallery_id) ON DELETE CASCADE
);
    
ALTER TABLE ONLY gadget
    ADD COLUMN description TEXT,
    ALTER COLUMN src DROP NOT NULL;

-- Update schema version
UPDATE "System"
   SET value = '38'
 WHERE field = 'socialtext-schema-version';

COMMIT;
