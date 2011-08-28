BEGIN;

/* Any time a User record gets updated, update the "last_profile_update"
 * column to reflect that the User record *has* changed.
 */
CREATE OR REPLACE FUNCTION mark_user_as_updated_when_user_changes() RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        NEW.last_profile_update := current_timestamp;
    ELSE
        IF NEW.last_profile_update = OLD.last_profile_update THEN
            NEW.last_profile_update := current_timestamp;
        END IF;
    END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER users_mark_as_updated_when_changed
    BEFORE INSERT OR UPDATE ON users
    FOR EACH ROW EXECUTE PROCEDURE mark_user_as_updated_when_user_changes();

/* Any time a Profile Field for a User gets updated, update the
 * "last_profile_update" column back on the User record, to denote that there
 * has been a change.
 */
CREATE OR REPLACE FUNCTION mark_user_as_updated_when_profile_changes() RETURNS TRIGGER AS $$
BEGIN

  IF TG_OP = 'INSERT' OR TG_OP = 'UPDATE' THEN
    UPDATE users
       SET last_profile_update = current_timestamp
     WHERE user_id = NEW.user_id;
    RETURN NEW;
  ELSIF TG_OP = 'DELETE' THEN
    UPDATE users
       SET last_profile_update = current_timestamp
     WHERE user_id = OLD.user_id;
    RETURN OLD;
  END IF;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER profile_attr_mark_user_updated_when_changed
    BEFORE INSERT OR UPDATE OR DELETE ON profile_attribute
    FOR EACH ROW EXECUTE PROCEDURE mark_user_as_updated_when_profile_changes();

CREATE TRIGGER profile_rel_mark_user_updated_when_changed
    BEFORE INSERT OR UPDATE OR DELETE ON profile_relationship
    FOR EACH ROW EXECUTE PROCEDURE mark_user_as_updated_when_profile_changes();

CREATE TRIGGER profile_photo_mark_user_updated_when_changed
    BEFORE INSERT OR UPDATE OR DELETE ON profile_photo
    FOR EACH ROW EXECUTE PROCEDURE mark_user_as_updated_when_profile_changes();

UPDATE "System"
   SET value = '133'
 WHERE field = 'socialtext-schema-version';

COMMIT;
