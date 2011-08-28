BEGIN;

-- by using "text_pattern_ops" we can make efficient LIKE queries in utf8
-- see http://www.postgresql.org/docs/faqs.FAQ.html#item4.6

CREATE INDEX users_lower_email ON users (lower(email_address) text_pattern_ops);
CREATE INDEX users_lower_username ON users (lower(driver_username) text_pattern_ops);
CREATE INDEX users_lower_first_name ON users (lower(first_name) text_pattern_ops);
CREATE INDEX users_lower_last_name ON users (lower(last_name) text_pattern_ops);

UPDATE "System"
   SET value = '48'
 WHERE field = 'socialtext-schema-version';

COMMIT;
