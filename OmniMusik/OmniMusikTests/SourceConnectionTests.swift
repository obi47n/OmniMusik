//
//  SourceConnectionTests.swift
//  OmniMusikTests
//
//  Coverage for the source-connection state machine.
//
//  The distinction these tests pin down is the reason the type exists: "not connected
//  yet" and "cannot be connected in this build" look similar and demand opposite
//  interfaces — a button versus an explanation. Collapsing them is how an app ends up
//  offering a Connect button that can never work.
//

import Foundation
import Testing
@testable import OmniMusik

@Suite("Source connections")
@MainActor
struct SourceConnectionTests {

    /// A stand-in for a streaming service, so the state machine can be exercised
    /// without a network, an SDK, or an installed app.
    private final class FakeSource: ConnectableSource {
        let source: TrackSource
        var connectionState: SourceConnectionState
        var failure: Error?
        private(set) var connectCalls = 0

        init(source: TrackSource, state: SourceConnectionState = .disconnected) {
            self.source = source
            self.connectionState = state
        }

        func connect() async throws {
            connectCalls += 1
            if let failure {
                connectionState = .disconnected
                throw failure
            }
            connectionState = .connected(account: "test@example.com")
        }

        func disconnect() async {
            connectionState = .disconnected
        }
    }

    @Test("Only a disconnected source offers to connect")
    func onlyDisconnectedCanConnect() {
        #expect(SourceConnectionState.disconnected.canConnect)
        #expect(!SourceConnectionState.connecting.canConnect)
        #expect(!SourceConnectionState.connected(account: nil).canConnect)
        #expect(!SourceConnectionState.unavailable(reason: "blocked").canConnect)
    }

    @Test("Connecting reaches the connected state and names the account")
    func connectSucceeds() async {
        let fake = FakeSource(source: .appleMusic)
        let center = SourceConnectionCenter(sources: [fake])

        #expect(center.rows.first?.state == .disconnected)
        await center.connect(.appleMusic)

        #expect(center.rows.first?.state == .connected(account: "test@example.com"))
        #expect(center.errorMessage == nil)
    }

    @Test("Backing out of a connection is not reported as an error")
    func cancellationIsNotAnError() async {
        let fake = FakeSource(source: .appleMusic)
        fake.failure = SourceConnectionError.cancelled
        let center = SourceConnectionCenter(sources: [fake])

        await center.connect(.appleMusic)

        #expect(center.errorMessage == nil, "Cancelling is an ordinary outcome, not a failure.")
        #expect(center.rows.first?.state == .disconnected)
    }

    @Test("A real failure surfaces its reason")
    func failureSurfaces() async {
        let fake = FakeSource(source: .appleMusic)
        fake.failure = SourceConnectionError.appNotInstalled(.appleMusic)
        let center = SourceConnectionCenter(sources: [fake])

        await center.connect(.appleMusic)

        let message = try? #require(center.errorMessage)
        #expect(message?.contains("app installed") == true)
    }

    @Test("Disconnecting returns the source to connectable")
    func disconnectReturnsToDisconnected() async {
        let fake = FakeSource(source: .appleMusic, state: .connected(account: "a@b.c"))
        let center = SourceConnectionCenter(sources: [fake])

        await center.disconnect(.appleMusic)
        #expect(center.rows.first?.state == .disconnected)
    }

    @Test("Rows follow the canonical source order, not connection order")
    func rowsAreStablyOrdered() {
        // Registered out of order on purpose: the list must not reshuffle as states
        // change underneath it.
        let center = SourceConnectionCenter(sources: [
            FakeSource(source: .appleMusic),
            FakeSource(source: .local),
        ])
        #expect(center.rows.map(\.source) == TrackSource.allCases.filter { $0 == .local || $0 == .appleMusic })
    }

    @Test("Apple Music explains why it cannot be connected rather than offering a button")
    func appleMusicIsUnavailableWithAReason() {
        let state = AppleMusicSource().connectionState
        #expect(!state.canConnect, "An unconnectable source must not offer a Connect button.")

        guard case .unavailable(let reason) = state else {
            Issue.record("Expected .unavailable, got \(state)")
            return
        }
        #expect(reason.contains("MusicKit"), "The reason should name what is missing.")
    }
}
