import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "scroll")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(AppInfo.name)
                .font(.largeTitle.weight(.semibold))
            Text(AppInfo.tagline)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(40)
        .frame(minWidth: 420, minHeight: 280)
    }
}

/// Static identity of the app, kept in one place so the bootstrap view and the
/// tests read the same values.
enum AppInfo {
    static let name = "Pergamenum"
    static let tagline = "Bootstrap - under active development"
}

#Preview {
    ContentView()
}
