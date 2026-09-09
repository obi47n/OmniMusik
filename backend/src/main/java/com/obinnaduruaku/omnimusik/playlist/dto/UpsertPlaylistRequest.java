package com.obinnaduruaku.omnimusik.playlist.dto;

import com.obinnaduruaku.omnimusik.playlist.PlaylistEntry;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

import java.util.List;

/**
 * Body for creating or replacing a playlist.
 *
 * <p>{@code expectedVersion} is the version the client last saw. It is null on a
 * create, and required on an update: sending an update without one is how a client
 * accidentally clobbers an edit it never read.
 *
 * <p>Entries are sent whole rather than as a diff. A playlist is small — a few
 * hundred entries at most — and whole-document replacement removes an entire class
 * of partial-application bug in exchange for bytes nobody will notice.
 */
public record UpsertPlaylistRequest(
        @NotBlank @Size(max = 200) String name,
        @Valid List<PlaylistEntry> entries,
        Long expectedVersion
) {
    public List<PlaylistEntry> entriesOrEmpty() {
        return entries == null ? List.of() : entries;
    }
}
