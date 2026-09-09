package com.obinnaduruaku.omnimusik.playlist;

import jakarta.persistence.AttributeConverter;
import jakarta.persistence.Converter;
import tools.jackson.core.type.TypeReference;
import tools.jackson.databind.json.JsonMapper;

import java.util.List;

/**
 * Persists playlist entries as a JSON document in one column.
 *
 * <p>The same decision as on the client, for the same reasons: order is the point of
 * a playlist and a child-table relationship is unordered, entries are never queried
 * independently, and entries must be able to describe Apple Music tracks that have no
 * row anywhere. Modelling them as a child table would buy indexing nothing uses and
 * would push ordering into a position column that has to be renumbered on every move.
 *
 * <p>The cost is the same too, and worth stating plainly: entries are opaque to SQL,
 * so "which playlists contain this track" would need a scan or a generated index.
 * On Postgres the column could become {@code jsonb} and be indexed with GIN if that
 * query ever appears; the converter keeps the mapping portable to H2 in tests either
 * way.
 *
 * <p>Uses its own mapper rather than Spring's: Hibernate instantiates converters
 * directly, so there is no injection point here. Jackson 3 (Spring Boot 4) moved to
 * the {@code tools.jackson} packages, though annotations kept {@code com.fasterxml}.
 */
@Converter
public class PlaylistEntryListConverter implements AttributeConverter<List<PlaylistEntry>, String> {

    private static final JsonMapper MAPPER = JsonMapper.builder().build();
    private static final TypeReference<List<PlaylistEntry>> TYPE = new TypeReference<>() {};

    @Override
    public String convertToDatabaseColumn(List<PlaylistEntry> entries) {
        try {
            return MAPPER.writeValueAsString(entries == null ? List.of() : entries);
        } catch (RuntimeException e) {
            // Failing the write is correct: silently storing "[]" would delete a
            // person's playlist contents and report success.
            throw new IllegalStateException("Could not serialise playlist entries", e);
        }
    }

    @Override
    public List<PlaylistEntry> convertToEntityAttribute(String json) {
        if (json == null || json.isBlank()) {
            return List.of();
        }
        try {
            return MAPPER.readValue(json, TYPE);
        } catch (RuntimeException e) {
            throw new IllegalStateException("Could not deserialise playlist entries", e);
        }
    }
}
