BEGIN;

-- for {bz: 4027}

ALTER TABLE ONLY signal_attachment
    ADD CONSTRAINT sigattach_ukey UNIQUE (attachment_id, signal_id);
ALTER TABLE ONLY signal_attachment
    ADD CONSTRAINT sigattach_ukey2 UNIQUE (signal_id, attachment_id);

UPDATE "System"
   SET value = '122'
 WHERE field = 'socialtext-schema-version';

COMMIT;
