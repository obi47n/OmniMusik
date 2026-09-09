package com.obinnaduruaku.omnimusik.sync;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * Reads the epoch, creating it on first use.
 *
 * <p>Created lazily rather than in a startup hook so that it is written in the same
 * transaction as the request that needs it. A startup hook would have to decide what
 * to do when the database is not reachable yet, which is a question worth not asking.
 */
@Service
public class SyncEpochService {

    private final SyncEpochRepository repository;

    public SyncEpochService(SyncEpochRepository repository) {
        this.repository = repository;
    }

    @Transactional
    public String current() {
        return repository.findById(SyncEpoch.SINGLETON_ID)
                .orElseGet(() -> repository.save(SyncEpoch.createNew()))
                .getValue();
    }
}
