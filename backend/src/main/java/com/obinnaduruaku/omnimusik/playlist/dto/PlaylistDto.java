package com.obinnaduruaku.omnimusik.playlist.dto;

import com.obinnaduruaku.omnimusik.playlist.Playlist;
import com.obinnaduruaku.omnimusik.playlist.PlaylistEntry;

import java.time.Instant;
import java.util.List;
import java.util.UUID;

/**
 * A playlist as it crosses the wire.
 *
 * <p>Timestamps are ISO-8601 strings. Worth stating because Swift's default
 * {@code JSONDecoder} reads a {@code Date} as seconds since the 2001 Apple epoch, so
 * the iOS client must be configured with {@code .iso8601} or every date will decode
 * to some time in 2001 without erroring.
 */
public record PlaylistDto(
        UUID id,
        String name,
        List<PlaylistEntry> entries,
        Instant createdAt,
        Instant updatedAt,
        long version
) {
    public static PlaylistDto from(Playlist playlist) {
        return new PlaylistDto(
                playlist.getId(),
                playlist.getName(),
                playlist.getEntries(),
                playlist.getCreatedAt(),
                playlist.getUpdatedAt(),
                playlist.getVersion()
        );
    }
}
