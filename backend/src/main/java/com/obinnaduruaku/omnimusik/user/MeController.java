package com.obinnaduruaku.omnimusik.user;

import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.time.Instant;
import java.util.UUID;

/**
 * The caller's own account.
 *
 * <p>Doubles as the provisioning trigger and as a cheap way for a client to confirm
 * its token is actually accepted, which is otherwise only discoverable by attempting
 * a real request.
 */
@RestController
@RequestMapping("/api/v1/me")
public class MeController {

    private final CurrentUserService currentUserService;

    public MeController(CurrentUserService currentUserService) {
        this.currentUserService = currentUserService;
    }

    public record MeDto(UUID id, String subject, String email, String displayName, Instant createdAt) {}

    @GetMapping
    public MeDto me(@AuthenticationPrincipal Jwt jwt) {
        AppUser user = currentUserService.resolve(jwt);
        return new MeDto(
                user.getId(),
                user.getSubject(),
                user.getEmail(),
                user.getDisplayName(),
                user.getCreatedAt()
        );
    }
}
