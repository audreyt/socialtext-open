BEGIN;

-- Story: Custom skin is applied to Socialtext Desktop

ALTER TABLE "Account"
    ADD COLUMN desktop_logo_uri varchar(250) DEFAULT '/static/desktop/images/sd-logo.png';
ALTER TABLE "Account"
    ADD COLUMN desktop_header_gradient_top varchar(7) DEFAULT '#4C739B';
ALTER TABLE "Account"
    ADD COLUMN desktop_header_gradient_bottom varchar(7) DEFAULT '#506481';
ALTER TABLE "Account"
    ADD COLUMN desktop_bg_color varchar(7) DEFAULT '#FFFFFF';
ALTER TABLE "Account"
    ADD COLUMN desktop_2nd_bg_color varchar(7) DEFAULT '#F2F2F2';
ALTER TABLE "Account"
    ADD COLUMN desktop_text_color varchar(7) DEFAULT '#000000';
ALTER TABLE "Account"
    ADD COLUMN desktop_link_color varchar(7) DEFAULT '#0081F8';
ALTER TABLE "Account"
    ADD COLUMN desktop_highlight_color varchar(7) DEFAULT '#FFFDD3';

UPDATE "System"
   SET value = '50'
 WHERE field = 'socialtext-schema-version';

COMMIT;
