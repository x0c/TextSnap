import AppKit
import Foundation
import MacKitLifecycle
import SwiftUI

@main
struct TextSnapApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var hiddenMenuInserted = false

    init() {
        AutofillHeuristicGuard.install()
    }

    var body: some Scene {
        MenuBarExtra("", isInserted: $hiddenMenuInserted) {
            EmptyView()
        }
    }
}
