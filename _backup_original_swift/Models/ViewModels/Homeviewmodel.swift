
//  Homeviewmodel.swift
//  MyApp
//  Created by Ankit Raj on 12/10/26.
//

import Foundation
import Combine
@MainActor
class HomeViewModel: ObservableObject {
    @Published var todaySteps: Int = 0
    @Published var isActive: Bool = false
    @Published var connectionCode: String = ""
    @Published var connections: [ConnectionResponse] = []
    @Published var showAddConnection = false

    func load() async {
        connectionCode = UserDefaults.standard.string(forKey: "user_name") ?? ""
        do {
            connections = try await APIService.shared.getConnections()
        } catch {
            print("Failed to load connections: \(error)")
        }
    }

    func addConnection(code: String) async {
        do {
            let connection = try await APIService.shared.createConnection(code: code)
            connections.append(connection)
        } catch {
            print("Failed to add connection: \(error)")
        }
    }
}
