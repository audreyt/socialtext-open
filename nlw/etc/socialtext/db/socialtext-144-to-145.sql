BEGIN;

-- Add a counter for 
ALTER TABLE page ADD COLUMN like_count bigint DEFAULT 0;

-- Index for ordering list views by likes
CREATE INDEX page_likes_count_idx
    ON page(like_count);

-- Removed unnecessary page update

CREATE FUNCTION update_like_count() RETURNS trigger AS $update_like_count$
    BEGIN
        IF (TG_OP = 'INSERT') THEN
            IF NEW.page_id IS NOT NULL AND NEW.revision_id IS NULL THEN
                UPDATE page
                   SET like_count = like_count + 1
                 WHERE page.workspace_id = NEW.workspace_id
                   AND page.page_id = NEW.page_id;
            END IF;
            RETURN NEW;
        ELSIF (TG_OP = 'DELETE') THEN
            IF OLD.page_id IS NOT NULL AND OLD.revision_id IS NULL THEN
                UPDATE page
                   SET like_count = like_count - 1
                 WHERE page.workspace_id = OLD.workspace_id
                   AND page.page_id = OLD.page_id;
            END IF;
            RETURN OLD;
        END IF;
        RETURN NULL;
    END;
$update_like_count$ LANGUAGE plpgsql;

CREATE TRIGGER update_like_count BEFORE INSERT OR DELETE ON user_like
    FOR EACH ROW EXECUTE PROCEDURE update_like_count();

UPDATE "System"
   SET value = '145'
 WHERE field = 'socialtext-schema-version';

COMMIT;
