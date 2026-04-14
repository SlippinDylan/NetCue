//
//  MapView.swift
//  NetCue
//
//  Created by SlippinDylan on 2025/12/30.
//

import SwiftUI
import MapKit

/// 地图视图组件
struct MapView: View {
    let latitude: Double
    let longitude: Double

    @State private var position: MapCameraPosition

    init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude

        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            span: MKCoordinateSpan(latitudeDelta: 0.8, longitudeDelta: 0.8)
        )
        _position = State(initialValue: .region(region))
    }

    var body: some View {
        Map(position: $position) {
            Marker("", coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude))
                .tint(.red)
        }
        .mapStyle(.standard)
        .id("\(latitude)-\(longitude)")
    }
}
