BEGIN;

-- add the 'title' column to the field_class table.
-- update the stock fields with stock titles
-- set title to name where NULL
-- make title NOT NULL

ALTER TABLE profile_field ADD COLUMN title text;

UPDATE profile_field SET title='AIM™'         WHERE name='aol_sn'       ;
UPDATE profile_field SET title='GTalk'        WHERE name='gtalk_sn'     ;
UPDATE profile_field SET title='Home phone'   WHERE name='home_phone'   ;
UPDATE profile_field SET title='Mobile phone' WHERE name='mobile_phone' ;
UPDATE profile_field SET title='Sametime®'    WHERE name='sametime_sn'  ;
UPDATE profile_field SET title='Skype™'       WHERE name='skype_sn'     ;
UPDATE profile_field SET title='Twitter'      WHERE name='twitter_sn'   ;
UPDATE profile_field SET title='Work phone'   WHERE name='work_phone'   ;
UPDATE profile_field SET title='Yahoo!™'      WHERE name='yahoo_sn'     ;
UPDATE profile_field SET title='Blog'         WHERE name='blog'         ;
UPDATE profile_field SET title='Company'      WHERE name='company'      ;
UPDATE profile_field SET title='Facebook™'    WHERE name='facebook_url' ;
UPDATE profile_field SET title='Linkedin®'    WHERE name='linkedin_url' ;
UPDATE profile_field SET title='Location'     WHERE name='location'     ;
UPDATE profile_field SET title='Personal'     WHERE name='personal_url' ;
UPDATE profile_field SET title='Position'     WHERE name='position'     ;
UPDATE profile_field SET title='Assistant'    WHERE name='assistant'    ;
UPDATE profile_field SET title='Manager'      WHERE name='supervisor'   ;

UPDATE profile_field SET title=name WHERE title IS NULL;

ALTER TABLE profile_field ALTER COLUMN title SET NOT NULL;

UPDATE "System"
   SET value = 24
 WHERE field = 'socialtext-schema-version';

COMMIT;
