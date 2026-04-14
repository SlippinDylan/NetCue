//
//  Scene.swift
//  NetCue
//
//  Created by SlippinDylan on 2025/12/25.
//

import Foundation

struct NetworkScene: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var routerIP: String
    var routerMAC: String
    var controlApps: [String]
    var isEnabled: Bool

    init(id: UUID = UUID(), name: String, routerIP: String, routerMAC: String, controlApps: [String], isEnabled: Bool) {
        self.id = id
        self.name = name
        self.routerIP = routerIP
        self.routerMAC = routerMAC
        self.controlApps = controlApps
        self.isEnabled = isEnabled
    }
}
