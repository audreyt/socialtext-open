BEGIN;

-- for [Story: User adds file attachment to Signals]

CREATE SEQUENCE "attachment_id_seq"
    INCREMENT BY 1
    NO MAXVALUE
    NO MINVALUE
    CACHE 1;

CREATE TABLE attachment (
    attachment_id int NOT NULL,
    attachment_uuid text NOT NULL,
    creator_id int NOT NULL,
    created_at timestamptz DEFAULT now() NOT NULL,
    filename text NOT NULL,
    mime_type text NOT NULL, -- TODO: normalize?
    is_image bool NOT NULL,
    is_temporary bool DEFAULT false NOT NULL,
    content_length int NOT NULL
);

ALTER TABLE ONLY attachment
    ADD CONSTRAINT attachment_creator_fk
            FOREIGN KEY (creator_id)
            REFERENCES users(user_id) ON DELETE RESTRICT;

ALTER TABLE ONLY attachment
    ADD CONSTRAINT attachment_pkey PRIMARY KEY (attachment_id);
ALTER TABLE ONLY attachment
    ADD CONSTRAINT attachment_uuid_key UNIQUE (attachment_uuid);

CREATE INDEX idx_attach_created_at ON attachment(created_at);
CREATE INDEX idx_attach_created_at_temp ON attachment(created_at)
    WHERE NOT is_temporary;

CREATE TABLE signal_attachment (
    attachment_id int NOT NULL,
    signal_id bigint NOT NULL
);

ALTER TABLE ONLY signal_attachment
    ADD CONSTRAINT signal_attachment_attachment_fk
            FOREIGN KEY (attachment_id)
            REFERENCES attachment(attachment_id) ON DELETE CASCADE;

ALTER TABLE ONLY signal_attachment
    ADD CONSTRAINT signal_attachment_signal_fk
            FOREIGN KEY (signal_id)
            REFERENCES signal(signal_id) ON DELETE CASCADE;

UPDATE "System"
   SET value = '119'
 WHERE field = 'socialtext-schema-version';

COMMIT;
