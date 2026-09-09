package com.obinnaduruaku.omnimusik.playlist;

import com.obinnaduruaku.omnimusik.playlist.dto.PlaylistDto;
import com.obinnaduruaku.omnimusik.playlist.dto.UpsertPlaylistRequest;
import com.obinnaduruaku.omnimusik.user.AppUser;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;
import java.util.UUID;

/**
 * Playlist reads and writes, with the sync rules.
 *
 * <p>The interesting part is {@link #upsert}. Two devices editing one playlist is
 * the normal case for this app, not an edge case: a set built on the phone is exactly
 * the thing someone then reorders on the web. Last-write-wins would silently discard
 * whichever edit lost, and the person would never learn which.
 *
 * <p>So writes are version-checked. The client sends the version it last read; if the
 * stored version has moved on, the write is refused and the server's current state
 * comes back with the conflict so the client can merge rather than guess. The
 * {@code @Version} column additionally protects against two requests racing inside
 * the same instant, which the explicit check alone cannot see.
 */
@Service
public class PlaylistService {

    private final PlaylistRepository playlists;

    public PlaylistService(PlaylistRepository playlists) {
        this.playlists = playlists;
    }

    @Transactional(readOnly = true)
    public List<PlaylistDto> listFor(AppUser owner) {
        return playlists.findByOwnerIdOrderByUpdatedAtDesc(owner.getId())
                .stream()
                .map(PlaylistDto::from)
                .toList();
    }

    @Transactional(readOnly = true)
    public PlaylistDto get(UUID id, AppUser owner) {
        return PlaylistDto.from(require(id, owner));
    }

    /**
     * Creates the playlist if this id is new, otherwise replaces its contents.
     *
     * <p>Idempotent by id so a client that uploaded successfully but lost the
     * response can safely retry. Retrying a create against a server that already has
     * the row is the single most common sync failure, and making it an update rather
     * than a duplicate-key error removes it entirely.
     */
    @Transactional
    public PlaylistDto upsert(UUID id, UpsertPlaylistRequest request, AppUser owner) {
        return playlists.findById(id)
                .map(existing -> {
                    if (!existing.getOwner().getId().equals(owner.getId())) {
                        // Someone else's id. Reported as absent rather than
                        // forbidden, for the reason in PlaylistNotFoundException.
                        throw new PlaylistNotFoundException();
                    }
                    Long expected = request.expectedVersion();
                    if (expected == null || expected != existing.getVersion()) {
                        throw new PlaylistConflictException(PlaylistDto.from(existing));
                    }
                    existing.replaceContents(request.name(), request.entriesOrEmpty());
                    // saveAndFlush, not save: @Version is incremented by the flush,
                    // which otherwise happens at commit -- after this DTO is built.
                    // Returning the pre-flush version would hand the client a number
                    // that is already stale, so its very next write would conflict.
                    return PlaylistDto.from(playlists.saveAndFlush(existing));
                })
                .orElseGet(() -> {
                    Playlist created = new Playlist(id, owner, request.name(), request.entriesOrEmpty());
                    return PlaylistDto.from(playlists.saveAndFlush(created));
                });
    }

    @Transactional
    public void delete(UUID id, AppUser owner) {
        playlists.delete(require(id, owner));
    }

    private Playlist require(UUID id, AppUser owner) {
        return playlists.findByIdAndOwnerId(id, owner.getId())
                .orElseThrow(PlaylistNotFoundException::new);
    }
}
