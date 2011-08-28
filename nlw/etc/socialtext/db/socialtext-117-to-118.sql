BEGIN;

CREATE TABLE temporary_gallery_gadget
    AS SELECT DISTINCT * FROM gallery_gadget;

DROP TABLE gallery_gadget;

ALTER TABLE ONLY temporary_gallery_gadget RENAME TO gallery_gadget;

ALTER TABLE ONLY gallery_gadget
    ALTER gadget_id SET NOT NULL,
    ALTER gallery_id SET NOT NULL,
    ALTER "position" SET NOT NULL,
    ALTER removed SET DEFAULT false,
    ALTER socialtext SET DEFAULT false,
    ALTER "global" SET DEFAULT false,
    ADD CONSTRAINT gallery_gadget_uniq
        UNIQUE (gallery_id, gadget_id),
    ADD CONSTRAINT gallery_gadget_account_fk
            FOREIGN KEY (gallery_id)
            REFERENCES gallery(gallery_id) ON DELETE CASCADE,
    ADD CONSTRAINT gallery_gadget_fk
            FOREIGN KEY (gadget_id)
            REFERENCES gadget(gadget_id) ON DELETE CASCADE;

CREATE INDEX gallery_gadget_gadget_id_idx
	    ON gallery_gadget (gadget_id);

UPDATE "System"
   SET value = '118'
 WHERE field = 'socialtext-schema-version';

COMMIT;
