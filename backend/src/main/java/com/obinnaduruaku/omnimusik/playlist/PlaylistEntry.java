package com.obinnaduruaku.omnimusik.playlist;

import com.fasterxml.jackson.annotation.JsonProperty;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.PositiveOrZero;

import java.util.UUID;

/**
 * One track's place in a playlist.
 *
 * <p>Mirrors the iOS {@code PlaylistEntry} exactly, including the snapshot fields.
 * The server keeps the snapshot for the same reason the client does: an entry whose
 * source cannot be reached must still be able to describe itself. The server has an
 * additional reason — it cannot resolve a local file at all, since those bytes only
 * exist on the device that imported them. Without the snapshot, the web client would
 * show a playlist of blank rows for every local track.
 *
 * <p>{@code sourceID} keeps its Swift capitalisation on the wire. Swift derives
 * coding keys from property names, so the client sends {@code sourceID}; renaming it
 * here to {@code sourceId} would break decoding silently.
 */
public record PlaylistEntry(
        @NotNull UUID id,
        @NotNull TrackSource source,
        @JsonProperty("sourceID") @NotBlank String sourceID,
        @NotBlank String title,
        @NotNull String artist,
        @PositiveOrZero double duration
) {
    /** True when this entry points at the same underlying track as another. */
    public boolean refersToSameTrack(PlaylistEntry other) {
        return source == other.source && sourceID.equals(other.sourceID);
    }
}
