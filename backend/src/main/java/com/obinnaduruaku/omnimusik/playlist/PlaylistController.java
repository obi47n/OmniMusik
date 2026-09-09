package com.obinnaduruaku.omnimusik.playlist;

import com.obinnaduruaku.omnimusik.playlist.dto.PlaylistDto;
import com.obinnaduruaku.omnimusik.playlist.dto.UpsertPlaylistRequest;
import com.obinnaduruaku.omnimusik.user.AppUser;
import com.obinnaduruaku.omnimusik.user.CurrentUserService;
import jakarta.validation.Valid;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;
import java.util.UUID;

/**
 * Playlist sync endpoints.
 *
 * <p>Create and update are one {@code PUT} keyed by a client-chosen id rather than
 * {@code POST} plus {@code PUT}. The client already knows the identity of what it is
 * uploading, so PUT is both the honest verb and the idempotent one — a retry after a
 * lost response is harmless instead of creating a duplicate.
 */
@RestController
@RequestMapping("/api/v1/playlists")
public class PlaylistController {

    private final PlaylistService playlistService;
    private final CurrentUserService currentUserService;

    public PlaylistController(PlaylistService playlistService, CurrentUserService currentUserService) {
        this.playlistService = playlistService;
        this.currentUserService = currentUserService;
    }

    @GetMapping
    public List<PlaylistDto> list(@AuthenticationPrincipal Jwt jwt) {
        return playlistService.listFor(user(jwt));
    }

    @GetMapping("/{id}")
    public PlaylistDto get(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID id) {
        return playlistService.get(id, user(jwt));
    }

    @PutMapping("/{id}")
    public ResponseEntity<PlaylistDto> upsert(
            @AuthenticationPrincipal Jwt jwt,
            @PathVariable UUID id,
            @Valid @RequestBody UpsertPlaylistRequest request
    ) {
        boolean isNew = request.expectedVersion() == null;
        PlaylistDto result = playlistService.upsert(id, request, user(jwt));
        return ResponseEntity.status(isNew ? HttpStatus.CREATED : HttpStatus.OK).body(result);
    }

    @DeleteMapping("/{id}")
    @org.springframework.web.bind.annotation.ResponseStatus(HttpStatus.NO_CONTENT)
    public void delete(@AuthenticationPrincipal Jwt jwt, @PathVariable UUID id) {
        playlistService.delete(id, user(jwt));
    }

    private AppUser user(Jwt jwt) {
        return currentUserService.resolve(jwt);
    }
}
