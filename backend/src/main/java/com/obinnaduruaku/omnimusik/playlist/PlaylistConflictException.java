package com.obinnaduruaku.omnimusik.playlist;

import com.obinnaduruaku.omnimusik.playlist.dto.PlaylistDto;

/**
 * Thrown when a client's expected version no longer matches the stored one.
 *
 * <p>Carries the server's current state so the response can hand the client
 * everything it needs to merge. Answering a conflict with a bare 409 forces a second
 * round trip to discover what actually changed, and invites the client to just retry
 * blindly with the new version — which is last-write-wins wearing a seatbelt.
 */
public class PlaylistConflictException extends RuntimeException {

    private final transient PlaylistDto current;

    public PlaylistConflictException(PlaylistDto current) {
        super("Playlist was modified by another client");
        this.current = current;
    }

    public PlaylistDto getCurrent() {
        return current;
    }
}
