import SwiftUI

enum MainTab: Hashable {
    case today, board, history
}

struct MainTabView: View {
    @State private var selection: MainTab = .today

    var body: some View {
        TabView(selection: $selection) {
            CheckInView()
                .tabItem { Label("Today", systemImage: "sun.max") }
                .tag(MainTab.today)
            BoardView(tabSelection: $selection)
                .tabItem { Label("Friends", systemImage: "person.2") }
                .tag(MainTab.board)
            HistoryView()
                .tabItem { Label("History", systemImage: "calendar") }
                .tag(MainTab.history)
        }
    }
}
