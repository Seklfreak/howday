import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            CheckInView()
                .tabItem { Label("Today", systemImage: "sun.max") }
            BoardView()
                .tabItem { Label("Friends", systemImage: "person.2") }
            HistoryView()
                .tabItem { Label("History", systemImage: "calendar") }
            FriendsView()
                .tabItem { Label("Add", systemImage: "person.badge.plus") }
        }
    }
}
