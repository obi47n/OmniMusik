package com.obinnaduruaku.omnimusik.playlist;

import com.obinnaduruaku.omnimusik.user.AppUser;
import jakarta.persistence.Column;
import jakarta.persistence.Convert;
import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.Table;
import jakarta.persistence.Version;

import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;

/**
 * A synced playlist.
 *
 * <p>The id is supplied by the client rather than generated here. Playlists are
 * created offline on a device that may not see the network for days, and they need a
 * stable identity from the moment they exist — otherwise the same playlist syncs
 * twice under two ids, or the client has to rewrite every local reference once the
 * server answers. A client-chosen UUID makes the upload idempotent.
 *
 * <p>{@code version} is the concurrency token. Two devices editing the same playlist
 * is the normal case, not an edge case, and last-write-wins would silently discard
 * whichever edit lost the race. See {@link PlaylistService} for how a conflict is
 * reported.
 */
@Entity
@Table(name = "playlist")
public class Playlist {

    @Id
    private UUID id;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "owner_id", nullable = false, updatable = false)
    private AppUser owner;

    @Column(nullable = false)
    private String name;

    @Convert(converter = PlaylistEntryListConverter.class)
    @Column(name = "entries", columnDefinition = "text", nullable = false)
    private List<PlaylistEntry> entries = new ArrayList<>();

    @Column(nullable = false, updatable = false)
    private Instant createdAt;

    @Column(nullable = false)
    private Instant updatedAt;

    @Version
    private long version;

    protected Playlist() {
        // JPA
    }

    public Playlist(UUID id, AppUser owner, String name, List<PlaylistEntry> entries) {
        this.id = id;
        this.owner = owner;
        this.name = name;
        this.entries = entries == null ? new ArrayList<>() : new ArrayList<>(entries);
        this.createdAt = Instant.now();
        this.updatedAt = this.createdAt;
    }

    public UUID getId() {
        return id;
    }

    public AppUser getOwner() {
        return owner;
    }

    public String getName() {
        return name;
    }

    public List<PlaylistEntry> getEntries() {
        return List.copyOf(entries);
    }

    public Instant getCreatedAt() {
        return createdAt;
    }

    public Instant getUpdatedAt() {
        return updatedAt;
    }

    public long getVersion() {
        return version;
    }

    public void replaceContents(String name, List<PlaylistEntry> entries) {
        this.name = name;
        this.entries = entries == null ? new ArrayList<>() : new ArrayList<>(entries);
        this.updatedAt = Instant.now();
    }
}
