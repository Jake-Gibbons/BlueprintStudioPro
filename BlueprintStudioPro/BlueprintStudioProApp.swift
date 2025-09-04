import SwiftUI

@main
struct BlueprintStudioProApp: App {
    @StateObject private var floorPlan = FloorPlan()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(floorPlan)
        }
    }
}
