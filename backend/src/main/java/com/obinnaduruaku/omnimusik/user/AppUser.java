package com.obinnaduruaku.omnimusik.user;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

import java.time.Instant;
import java.util.UUID;

/**
 * An account, keyed by the identity provider's subject claim.
 *
 * <p>{@code subject} is the identity, not {@code email}. Emails change, and Sign in
 * with Apple may withhold one entirely through Hide My Email, so hanging rows off an
 * address would orphan someone's playlists the day they change it. The email here is
 * a display convenience and is allowed to be null.
 */
@Entity
@Table(name = "app_user")
public class AppUser {

    @Id
    private UUID id;

    @Column(nullable = false, unique = true, updatable = false)
    private String subject;

    private String email;

    private String displayName;

    @Column(nullable = false, updatable = false)
    private Instant createdAt;

    protected AppUser() {
        // JPA
    }

    public AppUser(String subject, String email, String displayName) {
        this.id = UUID.randomUUID();
        this.subject = subject;
        this.email = email;
        this.displayName = displayName;
        this.createdAt = Instant.now();
    }

    public UUID getId() {
        return id;
    }

    public String getSubject() {
        return subject;
    }

    public String getEmail() {
        return email;
    }

    public String getDisplayName() {
        return displayName;
    }

    public Instant getCreatedAt() {
        return createdAt;
    }

    /**
     * Adopts fresh claims from a token.
     *
     * <p>Only writes on an actual difference, so an ordinary authenticated request
     * does not dirty the row and force an UPDATE on every call.
     */
    public boolean adoptClaims(String email, String displayName) {
        boolean changed = false;
        if (email != null && !email.equals(this.email)) {
            this.email = email;
            changed = true;
        }
        if (displayName != null && !displayName.equals(this.displayName)) {
            this.displayName = displayName;
            changed = true;
        }
        return changed;
    }
}
