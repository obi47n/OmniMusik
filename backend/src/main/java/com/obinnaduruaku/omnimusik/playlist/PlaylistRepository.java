package com.obinnaduruaku.omnimusik.playlist;

import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

public interface PlaylistRepository extends JpaRepository<Playlist, UUID> {

    /** Most recently updated first, matching the order the clients present. */
    List<Playlist> findByOwnerIdOrderByUpdatedAtDesc(UUID ownerId);

    Optional<Playlist> findByIdAndOwnerId(UUID id, UUID ownerId);
}
