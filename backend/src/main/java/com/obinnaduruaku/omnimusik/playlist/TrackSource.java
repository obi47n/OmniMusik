package com.obinnaduruaku.omnimusik.playlist;

import com.fasterxml.jackson.annotation.JsonCreator;
import com.fasterxml.jackson.annotation.JsonValue;

/**
 * Where a track's audio lives.
 *
 * <p>The wire values are lowerCamelCase because they have to match the iOS client
 * exactly. Swift's synthesised {@code Codable} conformance encodes a
 * {@code String}-backed enum using its raw value, and OmniMusik's cases are
 * {@code local} and {@code appleMusic}. A Java enum left to Jackson's defaults would
 * serialise as {@code LOCAL} and {@code APPLE_MUSIC}, and the mismatch would only
 * surface as a decode failure on device.
 *
 * <p>This enum has to be extended whenever the client gains a source. Swift's
 * exhaustive switches force every case to be handled there; nothing forces it here,
 * so a new source silently becomes a 400 on sync until this list catches up. That is
 * exactly what happened when Spotify was added.
 */
public enum TrackSource {
    LOCAL("local"),
    APPLE_MUSIC("appleMusic"),
    SPOTIFY("spotify");

    private final String wireValue;

    TrackSource(String wireValue) {
        this.wireValue = wireValue;
    }

    @JsonValue
    public String wireValue() {
        return wireValue;
    }

    @JsonCreator
    public static TrackSource fromWireValue(String value) {
        for (TrackSource source : values()) {
            if (source.wireValue.equals(value)) {
                return source;
            }
        }
        throw new IllegalArgumentException("Unknown track source: " + value);
    }
}
