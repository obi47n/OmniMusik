package com.obinnaduruaku.omnimusik.error;

import com.obinnaduruaku.omnimusik.playlist.PlaylistConflictException;
import com.obinnaduruaku.omnimusik.playlist.PlaylistNotFoundException;
import com.obinnaduruaku.omnimusik.playlist.dto.PlaylistDto;
import org.springframework.dao.OptimisticLockingFailureException;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;

import java.util.List;

/**
 * Turns domain failures into responses a client can act on.
 *
 * <p>A conflict answers with the server's current playlist attached, so the client
 * has what it needs to merge without a second round trip.
 */
@RestControllerAdvice
public class ApiExceptionHandler {

    public record ApiError(String code, String message, List<String> details) {
        static ApiError of(String code, String message) {
            return new ApiError(code, message, List.of());
        }
    }

    public record ConflictBody(String code, String message, PlaylistDto current) {}

    @ExceptionHandler(PlaylistNotFoundException.class)
    public ResponseEntity<ApiError> handleNotFound(PlaylistNotFoundException e) {
        return ResponseEntity.status(HttpStatus.NOT_FOUND)
                .body(ApiError.of("playlist_not_found", e.getMessage()));
    }

    @ExceptionHandler(PlaylistConflictException.class)
    public ResponseEntity<ConflictBody> handleConflict(PlaylistConflictException e) {
        return ResponseEntity.status(HttpStatus.CONFLICT)
                .body(new ConflictBody("playlist_conflict", e.getMessage(), e.getCurrent()));
    }

    /**
     * Two requests raced inside the same instant, so the explicit version check
     * passed on both. Reported as the same conflict the client already handles.
     */
    @ExceptionHandler(OptimisticLockingFailureException.class)
    public ResponseEntity<ApiError> handleRace(OptimisticLockingFailureException e) {
        return ResponseEntity.status(HttpStatus.CONFLICT)
                .body(ApiError.of("playlist_conflict", "Playlist was modified concurrently. Re-read and retry."));
    }

    @ExceptionHandler(MethodArgumentNotValidException.class)
    public ResponseEntity<ApiError> handleValidation(MethodArgumentNotValidException e) {
        List<String> details = e.getBindingResult().getFieldErrors().stream()
                .map(error -> error.getField() + ": " + error.getDefaultMessage())
                .toList();
        return ResponseEntity.badRequest()
                .body(new ApiError("validation_failed", "The request body is not valid.", details));
    }
}
