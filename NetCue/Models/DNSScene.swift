//
//  DNSScene.swift
//  NetCue
//
//  Created by SlippinDylan on 2025/12/25.
//

import Foundation

struct DNSScene: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var routerIP: String
    var routerMAC: String
    var primaryDNS: String
    var secondaryDNS: String
    var isEnabled: Bool

    init(id: UUID = UUID(), name: String, routerIP: String, routerMAC: String, primaryDNS: String, secondaryDNS: String, isEnabled: Bool) {
        self.id = id
        self.name = name
        self.routerIP = routerIP
        self.routerMAC = routerMAC
        self.primaryDNS = primaryDNS
        self.secondaryDNS = secondaryDNS
        self.isEnabled = isEnabled
    }
}
