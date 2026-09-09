package com.obinnaduruaku.omnimusik.user;

import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * Resolves the caller's row, creating it on first sight.
 *
 * <p>Provisioning happens here rather than through a sign-up endpoint. The identity
 * provider already owns registration; by the time a request carries a verified token
 * the account exists, and asking the client to call a separate "create me" endpoint
 * first only adds a step that can be skipped and a state that can be missed.
 */
@Service
public class CurrentUserService {

    private final AppUserRepository users;

    public CurrentUserService(AppUserRepository users) {
        this.users = users;
    }

    @Transactional
    public AppUser resolve(Jwt jwt) {
        String subject = jwt.getSubject();
        String email = jwt.getClaimAsString("email");
        String displayName = firstNonBlank(jwt.getClaimAsString("name"), jwt.getClaimAsString("given_name"));

        return users.findBySubject(subject)
                .map(existing -> {
                    if (existing.adoptClaims(email, displayName)) {
                        users.save(existing);
                    }
                    return existing;
                })
                .orElseGet(() -> users.save(new AppUser(subject, email, displayName)));
    }

    private static String firstNonBlank(String a, String b) {
        if (a != null && !a.isBlank()) {
            return a;
        }
        return (b != null && !b.isBlank()) ? b : null;
    }
}
