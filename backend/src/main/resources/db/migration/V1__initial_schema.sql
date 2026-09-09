-- The schema Hibernate validates against.
--
-- `ddl-auto=validate` in production was always the right call and always needed
-- this file to exist: against an empty database it fails on the first missing
-- table, the app never finishes starting, and the platform restarts it forever. The
-- deployment did exactly that before this migration existed.
--
-- Written by hand rather than generated, because a generated schema is a snapshot of
-- whatever the entities happened to say that day. This one is reviewed, and every
-- later change arrives as its own numbered file rather than as a silent alteration
-- of a live table.

CREATE TABLE app_user (
    id           UUID         NOT NULL,
    -- The identity, deliberately not the email: emails change, and Sign in with
    -- Apple may withhold one entirely, so a unique constraint here rather than there.
    subject      VARCHAR(255) NOT NULL,
    email        VARCHAR(255),
    display_name VARCHAR(255),
    created_at   TIMESTAMP(6) WITH TIME ZONE NOT NULL,
    CONSTRAINT pk_app_user PRIMARY KEY (id),
    CONSTRAINT uq_app_user_subject UNIQUE (subject)
);

CREATE TABLE playlist (
    id         UUID         NOT NULL,
    owner_id   UUID         NOT NULL,
    name       VARCHAR(255) NOT NULL,
    -- Entries are one JSON document, not rows. Order is the point and a child table
    -- is unordered; the reasoning is in DECISIONS.md under the playlist model.
    entries    TEXT         NOT NULL,
    created_at TIMESTAMP(6) WITH TIME ZONE NOT NULL,
    updated_at TIMESTAMP(6) WITH TIME ZONE NOT NULL,
    -- Optimistic locking. A client sends the version it last read and a mismatch is
    -- a 409 carrying the server's copy, so two devices cannot silently overwrite
    -- each other.
    version    BIGINT       NOT NULL,
    CONSTRAINT pk_playlist PRIMARY KEY (id),
    CONSTRAINT fk_playlist_owner FOREIGN KEY (owner_id) REFERENCES app_user (id)
);

-- Every query for playlists is "the ones belonging to this caller", and ownership is
-- also what isolates one account's data from another's.
CREATE INDEX idx_playlist_owner ON playlist (owner_id);

CREATE TABLE sync_epoch (
    id          BIGINT       NOT NULL,
    -- Named epoch_value because `value` is reserved in H2, and Hibernate quotes
    -- nothing by default.
    epoch_value VARCHAR(255) NOT NULL,
    created_at  TIMESTAMP(6) WITH TIME ZONE NOT NULL,
    CONSTRAINT pk_sync_epoch PRIMARY KEY (id)
);
