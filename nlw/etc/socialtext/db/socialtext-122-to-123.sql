BEGIN;

-- for webhooks

ALTER TABLE webhook ADD COLUMN group_id bigint;

CREATE INDEX webhook__class_group_ix
	    ON webhook ("class", group_id);

ALTER TABLE ONLY webhook
    ADD CONSTRAINT webhook_group_id_fk
            FOREIGN KEY (group_id)
            REFERENCES groups(group_id) ON DELETE CASCADE;

UPDATE webhook SET class = 'page.tag'
    WHERE class = 'pagetag';
UPDATE webhook SET class = 'signal.create'
    WHERE class = 'signal';

UPDATE "System"
   SET value = '123'
 WHERE field = 'socialtext-schema-version';

COMMIT;
