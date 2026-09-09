package com.obinnaduruaku.omnimusik.sync;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * What a client needs to know about the server before trusting its own sync state.
 *
 * <p>Separate from the playlist listing on purpose: the epoch is a property of the
 * service, not of anyone's playlists, and folding it into the listing would change a
 * wire format that three codebases already agree on.
 *
 * <p>Authenticated like everything else. The value is not a secret, but an
 * unauthenticated endpoint is a decision to defend and this one buys nothing.
 */
@RestController
@RequestMapping("/api/v1/sync")
public class SyncController {

    private final SyncEpochService epochService;

    public SyncController(SyncEpochService epochService) {
        this.epochService = epochService;
    }

    public record SyncEpochDto(String epoch) {}

    @GetMapping("/epoch")
    public SyncEpochDto epoch() {
        return new SyncEpochDto(epochService.current());
    }
}
