package com.obinnaduruaku.omnimusik.playlist;

/**
 * Thrown for a playlist that does not exist, and for one that belongs to somebody
 * else.
 *
 * <p>Deliberately the same exception for both. Answering 403 for another user's
 * playlist would confirm that the id exists, which turns the endpoint into an
 * oracle for enumerating other people's data.
 */
public class PlaylistNotFoundException extends RuntimeException {
    public PlaylistNotFoundException() {
        super("Playlist not found");
    }
}
