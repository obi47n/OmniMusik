package com.obinnaduruaku.omnimusik.sync;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.request.MockMvcRequestBuilders;
import org.springframework.test.web.servlet.request.RequestPostProcessor;

import static org.hamcrest.Matchers.matchesPattern;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.jwt;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * The epoch a client uses to decide whether its recorded versions mean anything.
 *
 * <p>Stability is the whole contract. A value that changed per request, per user or
 * per restart-with-intact-data would make every client re-upload its entire library
 * on every sync -- so the test that matters is the boring one asserting two calls
 * agree.
 */
@SpringBootTest
@AutoConfigureMockMvc
class SyncEpochApiTests {

    @Autowired
    private MockMvc mvc;

    private static RequestPostProcessor asUser(String subject) {
        return jwt().jwt(builder -> builder
                .subject(subject)
                .claim("email", subject + "@example.com")
                .claim("name", "Test " + subject));
    }

    private String fetchEpoch(String subject) throws Exception {
        return mvc.perform(MockMvcRequestBuilders.get("/api/v1/sync/epoch").with(asUser(subject)))
                .andExpect(status().isOk())
                .andReturn()
                .getResponse()
                .getContentAsString();
    }

    @Test
    @DisplayName("An unauthenticated request is rejected")
    void unauthenticatedIsRejected() throws Exception {
        mvc.perform(MockMvcRequestBuilders.get("/api/v1/sync/epoch"))
                .andExpect(status().isUnauthorized());
    }

    @Test
    @DisplayName("The epoch is a UUID, created on first use")
    void epochIsAUuid() throws Exception {
        mvc.perform(MockMvcRequestBuilders.get("/api/v1/sync/epoch").with(asUser("epoch-shape")))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.epoch").value(matchesPattern(
                        "[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}")));
    }

    /**
     * The one that protects real data. If this value moves while the database has not,
     * every client concludes its version numbers are meaningless and re-uploads.
     */
    @Test
    @DisplayName("The epoch does not change between calls")
    void epochIsStable() throws Exception {
        String first = fetchEpoch("epoch-stable");
        String second = fetchEpoch("epoch-stable");
        org.junit.jupiter.api.Assertions.assertEquals(first, second);
    }

    /**
     * It describes the database, not the caller. A per-user value would be a
     * plausible-looking mistake that only surfaces on a second device.
     */
    @Test
    @DisplayName("Every user sees the same epoch")
    void epochIsNotPerUser() throws Exception {
        String mine = fetchEpoch("epoch-user-one");
        String theirs = fetchEpoch("epoch-user-two");
        org.junit.jupiter.api.Assertions.assertEquals(mine, theirs);
    }
}
