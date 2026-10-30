//
//  ConnectionsStore.swift
//  Consnow
//
//  iOS counterpart of ConnectionsRepositoryImpl: friends list + each friend's
//  latest steps / lock status, cached on disk so the list still shows offline.
//

import Foundation
import Combine

/// Last known state of one friend.
nonisolated struct PeerSnapshot: Codable, Equatable {
    var steps: PeerStepsResponse?
    var activity: ActivityResponse?
    var notSharing = false
    var fetchedAt: Date
}

final class ConnectionsStore: ObservableObject {
    static let shared = ConnectionsStore()

    @Published private(set) var connections: [ConnectionDto] = []
    /// Keyed by the friend's user id (peer.id).
    @Published private(set) var snapshots: [String: PeerSnapshot] = [:]
    @Published private(set) var isOffline = false
    @Published private(set) var hasLoaded = false

    private let defaults = UserDefaults.standard
    private let connectionsKey = "connections_cache_v1"
    private let snapshotsKey = "peer_snapshots_cache_v1"

    private init() {
        if let data = defaults.data(forKey: connectionsKey),
           let cached = try? JSONDecoder().decode([ConnectionDto].self, from: data) {
            connections = cached
            hasLoaded = true
        }
        if let data = defaults.data(forKey: snapshotsKey),
           let cached = try? JSONDecoder().decode([String: PeerSnapshot].self, from: data) {
            snapshots = cached
        }
    }

    // MARK: - Loading

    /// GET /connections, then every friend's steps + lock status.
    func refresh() async {
        do {
            let list = try await APIClient.shared.send("GET", "connections", as: [ConnectionDto].self)
            connections = sorted(list)
            isOffline = false
            hasLoaded = true
            save()
            for connection in connections {
                await refreshPeer(connection.peer.id, persist: false)
            }
            save()
        } catch APIError.offline {
            isOffline = true
            hasLoaded = true
        } catch {
            hasLoaded = true
        }
    }

    /// GET /steps/user/:id + GET /activity/peer/:id for one friend.
    func refreshPeer(_ peerId: String, persist: Bool = true) async {
        async let stepsResult = fetchSteps(peerId)
        async let activityResult = fetchActivity(peerId)
        let (steps, activity) = await (stepsResult, activityResult)

        var snapshot = snapshots[peerId] ?? PeerSnapshot(fetchedAt: .distantPast)
        if steps.ok {
            snapshot.steps = steps.value
            snapshot.notSharing = steps.notSharing
        }
        if let activity { snapshot.activity = activity }
        if steps.ok || activity != nil {
            snapshot.fetchedAt = Date()
            isOffline = false
        }
        snapshots[peerId] = snapshot
        if persist { save() }
    }

    // MARK: - Adding

    /// POST /connections with a friend's 6-character code.
    @discardableResult
    func add(code raw: String) async throws -> ConnectionDto {
        let code = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard code.count == 6 else {
            throw APIError.server(status: 400, message: "Connection codes are 6 characters.")
        }
        if code == TokenManager.shared.user?.connectionCode {
            throw APIError.server(status: 400, message: "That's your own code. Ask your friend for theirs.")
        }

        let connection = try await APIClient.shared.send(
            "POST", "connections",
            body: CreateConnectionRequest(connectionCode: code),
            as: ConnectionDto.self
        )
        if !connections.contains(where: { $0.id == connection.id }) {
            connections = sorted(connections + [connection])
        }
        save()
        await refreshPeer(connection.peer.id)
        return connection
    }

    // MARK: - Cache

    func clear() {
        connections = []
        snapshots = [:]
        isOffline = false
        hasLoaded = false
        defaults.removeObject(forKey: connectionsKey)
        defaults.removeObject(forKey: snapshotsKey)
    }

    private func save() {
        if let data = try? JSONEncoder().encode(connections) {
            defaults.set(data, forKey: connectionsKey)
        }
        if let data = try? JSONEncoder().encode(snapshots) {
            defaults.set(data, forKey: snapshotsKey)
        }
    }

    private func sorted(_ list: [ConnectionDto]) -> [ConnectionDto] {
        list.sorted { $0.peer.name.localizedCaseInsensitiveCompare($1.peer.name) == .orderedAscending }
    }

    // MARK: - Fetch helpers

    private func fetchSteps(_ peerId: String) async -> (value: PeerStepsResponse?, notSharing: Bool, ok: Bool) {
        do {
            let response = try await APIClient.shared.send(
                "GET", "steps/user/\(peerId)",
                query: [URLQueryItem(name: "date", value: DateUtil.localDay())],
                as: PeerStepsResponse.self
            )
            return (response, false, true)
        } catch APIError.server(let status, _) where status == 403 {
            return (nil, true, true)   // friend turned sharing off
        } catch {
            return (nil, false, false)
        }
    }

    private func fetchActivity(_ peerId: String) async -> ActivityResponse? {
        try? await APIClient.shared.send("GET", "activity/peer/\(peerId)", as: ActivityResponse.self)
    }
}
