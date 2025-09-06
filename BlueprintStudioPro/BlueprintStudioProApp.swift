import SwiftUI

@main
struct BlueprintStudioProApp: App {
    @StateObject private var floorPlan = Floorplan()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(floorPlan)
        }
    }
}
