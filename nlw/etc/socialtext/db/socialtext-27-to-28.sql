BEGIN;

-- Extracted gadget information from the gadget XML
CREATE TABLE gadget (
    gadget_id BIGINT NOT NULL,
    src TEXT NOT NULL,

    -- plugin the widget is installed from
    plugin TEXT,

    -- Iframe src, this is either a ReST URL or an HREF set in the gadget XML
    href TEXT NOT NULL,

    -- Field used for knowing whether to reinstall the gadget from XML
    last_update timestamptz NOT NULL DEFAULT now(),

    -- url/html/html-inline
    content_type TEXT NOT NULL,

    -- list of feature javascript to include
    features TEXT[],

    -- list of href/authz pairs for preloading REST URLs
    preloads TEXT[][],

    -- gadget HTML+JS+CSS
    content TEXT,

    -- Supported ModulePrefs
    title TEXT,
    thumbnail TEXT,
    scrolling BOOLEAN DEFAULT FALSE,
    height INTEGER
);

CREATE SEQUENCE gadget_id
    INCREMENT BY 1
    NO MAXVALUE
    NO MINVALUE
    CACHE 1;

ALTER TABLE ONLY gadget
    ADD CONSTRAINT gadget_pk
        PRIMARY KEY (gadget_id),
    ADD CONSTRAINT gadget_src
        UNIQUE (src);

CREATE INDEX ix_gadget__src
    ON gadget(src);

-- gadget localization table
CREATE TABLE gadget_message (
    gadget_id BIGINT NOT NULL,
    lang TEXT NOT NULL,
    country TEXT DEFAULT '',
    key TEXT NOT NULL,
    value TEXT NOT NULL
);

ALTER TABLE ONLY gadget_message
    ADD CONSTRAINT gadget_message_pk
        PRIMARY KEY (gadget_id, lang, country, key),
    ADD CONSTRAINT gadget_message_gadget_fk
        FOREIGN KEY (gadget_id)
        REFERENCES gadget(gadget_id) ON DELETE CASCADE;

-- Container configuration
-- This table allows admins to add new container layouts
CREATE TABLE container_type (
    container_type TEXT NOT NULL,
    path_args TEXT[],
    links_template TEXT,
    hello_template TEXT,
    layout_template TEXT
);

ALTER TABLE ONLY container_type
    ADD CONSTRAINT container_type_pk
        PRIMARY KEY (container_type);

-- Mapping of a container type and its default gadgets
CREATE TABLE default_gadget (
    default_gadget_id BIGINT NOT NULL,
    container_type TEXT NOT NULL,
    src TEXT NOT NULL,

    "col" INTEGER NOT NULL,
    "row" INTEGER NOT NULL,
    
    -- determines whether the gadget is moveable
    fixed BOOLEAN DEFAULT FALSE,

    -- default preferences
    default_prefs TEXT [][]
);

CREATE SEQUENCE
    default_gadget_id
    INCREMENT BY 1
    NO MAXVALUE
    NO MINVALUE
    CACHE 1;

ALTER TABLE ONLY default_gadget
    ADD CONSTRAINT default_gadget_pk
        PRIMARY KEY (default_gadget_id),
    ADD CONSTRAINT container_type_fk
        FOREIGN KEY (container_type)
        REFERENCES container_type(container_type) ON DELETE CASCADE;

CREATE INDEX ix_default_gadget__container_type
    ON default_gadget(container_type);

-- Container that holds gadget
CREATE TABLE container (
    container_id BIGINT NOT NULL,
    container_type TEXT NOT NULL,
    user_id BIGINT,
    workspace_id BIGINT,
    account_id BIGINT
);

CREATE SEQUENCE container_id
    INCREMENT BY 1
    NO MAXVALUE
    NO MINVALUE
    CACHE 1;

ALTER TABLE ONLY container
    ADD CONSTRAINT container_pk
        PRIMARY KEY (container_id),
    ADD CONSTRAINT container_type_fk
        FOREIGN KEY (container_type)
        REFERENCES container_type(container_type) ON DELETE CASCADE,
    ADD CONSTRAINT container_account_id_fk
        FOREIGN KEY (account_id)
        REFERENCES "Account"(account_id) ON DELETE CASCADE,
    ADD CONSTRAINT container_workspace_id_fk
        FOREIGN KEY (workspace_id)
        REFERENCES "Workspace"(workspace_id) ON DELETE CASCADE,
    ADD CONSTRAINT container_user_id_fk
        FOREIGN KEY (user_id)
        REFERENCES users(user_id) ON DELETE CASCADE,
    ADD CONSTRAINT container_scope_ptr
        CHECK ((user_id IS NOT NULL != workspace_id IS NOT NULL != account_id IS NOT NULL));

-- Instance of a gadget in a container
CREATE TABLE gadget_instance (
    gadget_instance_id BIGINT NOT NULL,
    container_id BIGINT NOT NULL,
    default_gadget_id BIGINT,
    gadget_id BIGINT NOT NULL,

    "col" INTEGER NOT NULL,
    "row" INTEGER NOT NULL,

    minimized BOOLEAN DEFAULT FALSE
);

CREATE SEQUENCE gadget_instance_id
    INCREMENT BY 1
    NO MAXVALUE
    NO MINVALUE
    CACHE 1;

ALTER TABLE ONLY gadget_instance
    ADD CONSTRAINT gadget_instace_pk
        PRIMARY KEY (gadget_instance_id),
    ADD CONSTRAINT default_gadget_id_fk
        FOREIGN KEY (default_gadget_id)
        REFERENCES default_gadget(default_gadget_id)
        ON DELETE CASCADE,
    ADD CONSTRAINT gadget_instance_container_fk
        FOREIGN KEY (container_id)
        REFERENCES container(container_id) ON DELETE CASCADE,
    ADD CONSTRAINT gadget_instance_gadget_fk
        FOREIGN KEY (gadget_id)
        REFERENCES gadget(gadget_id) ON DELETE CASCADE;

CREATE INDEX ix_gadget_instance__container_id
    ON gadget_instance(container_id);

-- List of valid user preferences for a given gadget
CREATE TABLE gadget_user_pref (
    user_pref_id BIGINT NOT NULL,
    gadget_id BIGINT NOT NULL,
    name TEXT NOT NULL,
    datatype TEXT,
    display_name TEXT,
    default_value TEXT,
    options TEXT[][], -- when datatype == enum
    required BOOLEAN DEFAULT FALSE
);

CREATE SEQUENCE gadget_user_pref_id
    INCREMENT BY 1
    NO MAXVALUE
    NO MINVALUE
    CACHE 1;

ALTER TABLE ONLY gadget_user_pref
    ADD CONSTRAINT gadget_user_pref_pk
        PRIMARY KEY (user_pref_id),
    ADD CONSTRAINT gadget_user_pref_gadget_fk
        FOREIGN KEY (gadget_id)
        REFERENCES gadget(gadget_id) ON DELETE CASCADE;

CREATE INDEX ix_gadget_user_pref_gadget_id
    ON gadget_user_pref(gadget_id);

-- Table to store actual user pref settings for a gadget instance
CREATE TABLE gadget_instance_user_pref (
    gadget_instance_id BIGINT NOT NULL,
    user_pref_id BIGINT NOT NULL,
    value TEXT
);

ALTER TABLE ONLY gadget_instance_user_pref
    ADD CONSTRAINT gadget_instance_user_pref_pk
        PRIMARY KEY (gadget_instance_id, user_pref_id),
    ADD CONSTRAINT gadget_instance_user_pref_gadget_instance_fk
        FOREIGN KEY (gadget_instance_id)
        REFERENCES gadget_instance(gadget_instance_id) ON DELETE CASCADE,
    ADD CONSTRAINT gadget_instance_user_pref_user_pref_fk
        FOREIGN KEY (user_pref_id)
        REFERENCES gadget_user_pref(user_pref_id) ON DELETE CASCADE;

CREATE INDEX ix_gadget_instance_user_pref__user_pref_id
    ON gadget_instance_user_pref(user_pref_id);

CREATE INDEX ix_container_user_id
    ON container (user_id);
CREATE INDEX ix_container_workspace_id
    ON container (workspace_id);
CREATE INDEX ix_container_account_id
    ON container (account_id);
CREATE INDEX ix_container_container_type
    ON container (container_type);
CREATE INDEX ix_container_user_id_type
    ON container (container_type, user_id);


-- Update schema version
UPDATE "System"
   SET value = '28'
 WHERE field = 'socialtext-schema-version';

COMMIT;
