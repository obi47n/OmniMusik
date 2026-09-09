package com.obinnaduruaku.omnimusik.sync;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

import java.time.Instant;
import java.util.UUID;

/**
 * This database's identity.
 *
 * <p>Playlist version numbers are only meaningful inside the history that produced
 * them. A client that last synced at version 7 and now sees no playlist at all reads
 * that as a deletion -- correct, so long as the absence really is a deletion. Against
 * a database that was replaced, restored from a backup, or simply restarted while
 * in-memory, the same absence means "these version numbers were never mine", and
 * honouring it deletes work nobody deleted.
 *
 * <p>So the server publishes a value that changes exactly when its history does. One
 * row, written once, read on every sync. A client that sees a value other than the
 * one it stored knows its recorded versions describe a history this server has never
 * had, and re-uploads rather than deleting.
 *
 * <p>Deliberately not a timestamp or a counter: it needs no ordering, only
 * difference, and a random value cannot accidentally collide with a meaningful one
 * after a restore.
 */
@Entity
@Table(name = "sync_epoch")
public class SyncEpoch {

    /** Fixed, because there is exactly one row and a second one would be a bug. */
    public static final long SINGLETON_ID = 1L;

    @Id
    private Long id;

    /**
     * Named {@code epoch_value} rather than {@code value}: the latter is reserved in
     * H2, and Hibernate quotes nothing by default, so the generated select is a
     * syntax error at runtime rather than a mapping error at startup.
     */
    @Column(name = "epoch_value", nullable = false, updatable = false)
    private String value;

    @Column(nullable = false, updatable = false)
    private Instant createdAt;

    protected SyncEpoch() {
        // JPA
    }

    public static SyncEpoch createNew() {
        SyncEpoch epoch = new SyncEpoch();
        epoch.id = SINGLETON_ID;
        epoch.value = UUID.randomUUID().toString();
        epoch.createdAt = Instant.now();
        return epoch;
    }

    public String getValue() {
        return value;
    }

    public Instant getCreatedAt() {
        return createdAt;
    }
}
