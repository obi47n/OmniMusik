package com.obinnaduruaku.omnimusik.playlist;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.request.MockMvcRequestBuilders;
import org.springframework.test.web.servlet.request.RequestPostProcessor;

import java.util.UUID;

import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.jwt;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * End-to-end coverage of the sync endpoints.
 *
 * <p>The conflict cases are the point of this suite. Two devices editing one playlist
 * is the normal case for this app, and a regression there would not surface as an
 * error -- it would surface as somebody's reordering quietly disappearing.
 */
@SpringBootTest
@AutoConfigureMockMvc
class PlaylistApiTests {

    @Autowired
    private MockMvc mvc;

    private static RequestPostProcessor asUser(String subject) {
        return jwt().jwt(builder -> builder
                .subject(subject)
                .claim("email", subject + "@example.com")
                .claim("name", "Test " + subject));
    }

    private static String body(String name, Long expectedVersion, String entriesJson) {
        String version = expectedVersion == null ? "null" : expectedVersion.toString();
        return "{\"name\":\"" + name + "\",\"expectedVersion\":" + version
                + ",\"entries\":" + entriesJson + "}";
    }

    private static final String LOCAL_ENTRY =
            "[{\"id\":\"11111111-1111-1111-1111-111111111111\",\"source\":\"local\","
            + "\"sourceID\":\"a.mp3\",\"title\":\"Local One\",\"artist\":\"Someone\",\"duration\":120.5}]";

    private static final String MIXED_ENTRIES =
            "[{\"id\":\"11111111-1111-1111-1111-111111111111\",\"source\":\"local\","
            + "\"sourceID\":\"a.mp3\",\"title\":\"Local One\",\"artist\":\"Someone\",\"duration\":120.5},"
            + "{\"id\":\"22222222-2222-2222-2222-222222222222\",\"source\":\"appleMusic\","
            + "\"sourceID\":\"1440857781\",\"title\":\"Streamed\",\"artist\":\"Another\",\"duration\":200.0}]";

    @Test
    @DisplayName("An unauthenticated request is rejected")
    void unauthenticatedIsRejected() throws Exception {
        mvc.perform(MockMvcRequestBuilders.get("/api/v1/playlists"))
                .andExpect(status().isUnauthorized());
    }

    @Test
    @DisplayName("A first upload creates the playlist under the client's own id")
    void createUsesClientSuppliedId() throws Exception {
        UUID id = UUID.randomUUID();

        mvc.perform(MockMvcRequestBuilders.put("/api/v1/playlists/{id}", id)
                        .with(asUser("create-user"))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(body("Late Night", null, LOCAL_ENTRY)))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.id").value(id.toString()))
                .andExpect(jsonPath("$.name").value("Late Night"))
                .andExpect(jsonPath("$.version").value(0));

        mvc.perform(MockMvcRequestBuilders.get("/api/v1/playlists")
                        .with(asUser("create-user")))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$[0].id").value(id.toString()));
    }

    @Test
    @DisplayName("Cross-source entries round trip with the client's wire values intact")
    void crossSourceEntriesRoundTrip() throws Exception {
        UUID id = UUID.randomUUID();

        mvc.perform(MockMvcRequestBuilders.put("/api/v1/playlists/{id}", id)
                        .with(asUser("mixed-user"))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(body("Mixed", null, MIXED_ENTRIES)))
                .andExpect(status().isCreated());

        // The exact strings matter: Swift encodes the enum by raw value and derives
        // the key name from the property, so "appleMusic" and "sourceID" are part of
        // the contract, not cosmetic.
        mvc.perform(MockMvcRequestBuilders.get("/api/v1/playlists/{id}", id)
                        .with(asUser("mixed-user")))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.entries[0].source").value("local"))
                .andExpect(jsonPath("$.entries[0].sourceID").value("a.mp3"))
                .andExpect(jsonPath("$.entries[1].source").value("appleMusic"))
                .andExpect(jsonPath("$.entries[1].sourceID").value("1440857781"))
                .andExpect(jsonPath("$.entries[1].duration").value(200.0));
    }

    @Test
    @DisplayName("Order is preserved, because order is the point of a playlist")
    void orderIsPreserved() throws Exception {
        UUID id = UUID.randomUUID();
        mvc.perform(MockMvcRequestBuilders.put("/api/v1/playlists/{id}", id)
                        .with(asUser("order-user"))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(body("Ordered", null, MIXED_ENTRIES)))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.entries[0].title").value("Local One"))
                .andExpect(jsonPath("$.entries[1].title").value("Streamed"));
    }

    @Test
    @DisplayName("An update with the version the client last read succeeds and bumps it")
    void updateWithCurrentVersionSucceeds() throws Exception {
        UUID id = UUID.randomUUID();
        mvc.perform(MockMvcRequestBuilders.put("/api/v1/playlists/{id}", id)
                        .with(asUser("update-user"))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(body("First", null, LOCAL_ENTRY)))
                .andExpect(status().isCreated());

        mvc.perform(MockMvcRequestBuilders.put("/api/v1/playlists/{id}", id)
                        .with(asUser("update-user"))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(body("Renamed", 0L, LOCAL_ENTRY)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.name").value("Renamed"))
                .andExpect(jsonPath("$.version").value(1));
    }

    @Test
    @DisplayName("A stale version is refused, and the response carries the current state to merge from")
    void staleVersionConflicts() throws Exception {
        UUID id = UUID.randomUUID();
        mvc.perform(MockMvcRequestBuilders.put("/api/v1/playlists/{id}", id)
                        .with(asUser("conflict-user"))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(body("Original", null, LOCAL_ENTRY)))
                .andExpect(status().isCreated());

        // Another device gets there first.
        mvc.perform(MockMvcRequestBuilders.put("/api/v1/playlists/{id}", id)
                        .with(asUser("conflict-user"))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(body("From Phone", 0L, MIXED_ENTRIES)))
                .andExpect(status().isOk());

        // This client still believes it is on version 0.
        mvc.perform(MockMvcRequestBuilders.put("/api/v1/playlists/{id}", id)
                        .with(asUser("conflict-user"))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(body("From Web", 0L, LOCAL_ENTRY)))
                .andExpect(status().isConflict())
                .andExpect(jsonPath("$.code").value("playlist_conflict"))
                .andExpect(jsonPath("$.current.name").value("From Phone"))
                .andExpect(jsonPath("$.current.version").value(1));
    }

    @Test
    @DisplayName("Updating an existing playlist without a version is a conflict, not a silent overwrite")
    void missingVersionOnExistingConflicts() throws Exception {
        UUID id = UUID.randomUUID();
        mvc.perform(MockMvcRequestBuilders.put("/api/v1/playlists/{id}", id)
                        .with(asUser("noversion-user"))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(body("Original", null, LOCAL_ENTRY)))
                .andExpect(status().isCreated());

        mvc.perform(MockMvcRequestBuilders.put("/api/v1/playlists/{id}", id)
                        .with(asUser("noversion-user"))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(body("Clobber", null, LOCAL_ENTRY)))
                .andExpect(status().isConflict());
    }

    @Test
    @DisplayName("Another user's playlist reads as absent rather than forbidden")
    void otherUsersPlaylistIsInvisible() throws Exception {
        UUID id = UUID.randomUUID();
        mvc.perform(MockMvcRequestBuilders.put("/api/v1/playlists/{id}", id)
                        .with(asUser("owner-user"))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(body("Private", null, LOCAL_ENTRY)))
                .andExpect(status().isCreated());

        // 404 rather than 403: a 403 would confirm the id exists, which makes the
        // endpoint an oracle for enumerating other people's data.
        mvc.perform(MockMvcRequestBuilders.get("/api/v1/playlists/{id}", id)
                        .with(asUser("intruder-user")))
                .andExpect(status().isNotFound());

        mvc.perform(MockMvcRequestBuilders.put("/api/v1/playlists/{id}", id)
                        .with(asUser("intruder-user"))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(body("Hijack", 0L, LOCAL_ENTRY)))
                .andExpect(status().isNotFound());

        mvc.perform(MockMvcRequestBuilders.get("/api/v1/playlists")
                        .with(asUser("intruder-user")))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.length()").value(0));
    }

    @Test
    @DisplayName("A playlist can be deleted, and is then gone")
    void deleteRemovesPlaylist() throws Exception {
        UUID id = UUID.randomUUID();
        mvc.perform(MockMvcRequestBuilders.put("/api/v1/playlists/{id}", id)
                        .with(asUser("delete-user"))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(body("Doomed", null, LOCAL_ENTRY)))
                .andExpect(status().isCreated());

        mvc.perform(MockMvcRequestBuilders.delete("/api/v1/playlists/{id}", id)
                        .with(asUser("delete-user")))
                .andExpect(status().isNoContent());

        mvc.perform(MockMvcRequestBuilders.get("/api/v1/playlists/{id}", id)
                        .with(asUser("delete-user")))
                .andExpect(status().isNotFound());
    }

    @Test
    @DisplayName("A blank name is rejected with field-level detail")
    void blankNameIsRejected() throws Exception {
        mvc.perform(MockMvcRequestBuilders.put("/api/v1/playlists/{id}", UUID.randomUUID())
                        .with(asUser("validation-user"))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(body("", null, LOCAL_ENTRY)))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code").value("validation_failed"));
    }

    @Test
    @DisplayName("The account is provisioned on first authenticated request")
    void meProvisionsOnFirstCall() throws Exception {
        mvc.perform(MockMvcRequestBuilders.get("/api/v1/me")
                        .with(asUser("brand-new-user")))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.subject").value("brand-new-user"))
                .andExpect(jsonPath("$.email").value("brand-new-user@example.com"))
                .andExpect(jsonPath("$.id").isNotEmpty());
    }
}
