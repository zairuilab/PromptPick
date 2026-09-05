import Defaults
import KeyboardShortcuts
import Sparkle
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
  var panel: FloatingPanel<ContentView>!

  @objc
  private lazy var statusItem: NSStatusItem = {
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    statusItem.autosaveName = "PromptPickStatusItem"
    statusItem.isVisible = true
    statusItem.button?.action = #selector(performStatusItemClick)
    statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
    let menuBarImage = NSImage(named: .maccyStatusBar)
      ?? NSImage(systemSymbolName: "clipboard.fill", accessibilityDescription: "PromptPick")
    menuBarImage?.isTemplate = true
    menuBarImage?.size = NSSize(width: 16, height: 16)
    statusItem.button?.image = menuBarImage
    statusItem.button?.toolTip = "PromptPick"
    statusItem.button?.imagePosition = .imageLeft
    statusItem.button?.target = self
    return statusItem
  }()

  private var isStatusItemDisabled: Bool {
    Defaults[.ignoreEvents] || Defaults[.enabledPasteboardTypes].isEmpty
  }

  private var statusItemVisibilityObserver: NSKeyValueObservation?

  func applicationWillFinishLaunching(_ notification: Notification) { // swiftlint:disable:this function_body_length
    // Older dogfood builds allowed the only status item to be removed from the
    // menu bar. Clear AppKit's persisted hidden state before creating the new,
    // non-removable PromptPick item so the app always has an entry point.
    UserDefaults.standard.set(true, forKey: "NSStatusItem VisibleCC Item-1")
    UserDefaults.standard.synchronize()

    #if DEBUG
    if CommandLine.arguments.contains("enable-testing") {
      SPUUpdater(hostBundle: Bundle.main,
                 applicationBundle: Bundle.main,
                 userDriver: SPUStandardUserDriver(hostBundle: Bundle.main, delegate: nil),
                 delegate: nil)
      .automaticallyChecksForUpdates = false
      // Start from a clean slate for the isolated testing preferences.
      UserDefaults.standard.removePersistentDomain(forName: Defaults.Keys.testingSuiteName)
    }
    #endif

    // Bridge FloatingPanel via AppDelegate.
    AppState.shared.appDelegate = self

    Clipboard.shared.onNewCopy { History.shared.add($0) }
    Clipboard.shared.start()

    Task {
      for await _ in Defaults.updates(.clipboardCheckInterval, initial: false) {
        Clipboard.shared.restart()
      }
    }

    statusItemVisibilityObserver = observe(\.statusItem.isVisible, options: .new) { _, change in
      if let newValue = change.newValue, Defaults[.showInStatusBar] != newValue {
        Defaults[.showInStatusBar] = newValue
      }
    }

    Task {
      for await value in Defaults.updates(.showInStatusBar) {
        statusItem.isVisible = value
      }
    }

    synchronizeMenuIconText()
    Task {
      for await value in Defaults.updates(.showRecentCopyInMenuBar) {
        if value {
          statusItem.button?.title = AppState.shared.menuIconText
        } else {
          statusItem.button?.title = ""
        }
      }
    }

    Task {
      for await _ in Defaults.updates(.ignoreEvents) {
        statusItem.button?.appearsDisabled = isStatusItemDisabled
      }
    }

    Task {
      for await _ in Defaults.updates(.enabledPasteboardTypes) {
        statusItem.button?.appearsDisabled = isStatusItemDisabled
      }
    }
  }

  func applicationDidFinishLaunching(_ aNotification: Notification) {
    migrateUserDefaults()
    disableUnusedGlobalHotkeys()

    #if DEBUG
    seedVariablePromptForTestingIfNeeded()
    #endif

    panel = FloatingPanel(
      contentRect: NSRect(origin: .zero, size: Defaults[.windowSize]),
      identifier: Bundle.main.bundleIdentifier ?? "org.p0deje.Maccy",
      statusBarButton: statusItem.button,
      onClose: { AppState.shared.popup.reset() }
    ) {
      ContentView()
    }

    #if DEBUG
    if CommandLine.arguments.contains("open-panel-for-testing") {
      DispatchQueue.main.async {
        self.panel.open(height: AppState.shared.popup.height)
      }
    }
    #endif
  }

  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    panel.toggle(height: AppState.shared.popup.height)
    return true
  }

  func applicationWillTerminate(_ notification: Notification) {
    if Defaults[.clearOnQuit] {
      AppState.shared.history.clear()
    }
  }

  #if DEBUG
  @MainActor
  private func seedVariablePromptForTestingIfNeeded() {
    guard CommandLine.arguments.contains("seed-variable-prompt-for-testing") else { return }

    let library = AppState.shared.promptLibrary
    library.load()
    guard !library.prompts.contains(where: { $0.title == "安全代码审查" }),
          let category = library.categories.first(where: { $0.name == "代码审查" }) else { return }
    _ = library.createPrompt(
      title: "安全代码审查",
      content: "请审查以下代码，面向 {{目标用户}}：\n\n{{代码}}",
      categoryID: category.id,
      source: "ui-test"
    )
  }
  #endif

  private func ensureMigration(key: String, _ action: () -> Void) {
    if Defaults[.migrations][key] != true {
      action()
      Defaults[.migrations][key] = true
    }
  }

  private func migrateUserDefaults() {
    ensureMigration(key: "2024-07-01-version-2") {
      // Start 2.x from scratch.
      Defaults.reset(.migrations)

      // Inverse hide* configuration keys.
      Defaults[.showFooter] = !UserDefaults.standard.bool(forKey: "hideFooter")
      Defaults[.showSearch] = !UserDefaults.standard.bool(forKey: "hideSearch")
      Defaults[.showTitle] = !UserDefaults.standard.bool(forKey: "hideTitle")
      UserDefaults.standard.removeObject(forKey: "hideFooter")
      UserDefaults.standard.removeObject(forKey: "hideSearch")
      UserDefaults.standard.removeObject(forKey: "hideTitle")

      Defaults[.migrations]["2024-07-01-version-2"] = true
    }

    ensureMigration(key: "2025-07-04-add-jpeg-heic") {
      var types = Defaults[.enabledPasteboardTypes]
      if !types.intersection(StorageType.images.types).isEmpty {
        types.formUnion(StorageType.images.types)
      }
      Defaults[.enabledPasteboardTypes] = types
    }

    // The following defaults are not used in Maccy 2.x
    // and should be removed in 3.x.
    // - LaunchAtLogin__hasMigrated
    // - avoidTakingFocus
    // - saratovSeparator
    // - maxMenuItemLength
    // - maxMenuItems
  }

  @objc
  private func performStatusItemClick() {
    if let event = NSApp.currentEvent {
      if event.type == .rightMouseUp {
        showStatusItemMenu(for: event)
        return
      }

      let modifierFlags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

      if modifierFlags.contains(.option) {
        Defaults[.ignoreEvents].toggle()

        if modifierFlags.contains(.shift) {
          Defaults[.ignoreOnlyNextEvent] = Defaults[.ignoreEvents]
        }

        return
      }
    }

    panel.toggle(height: AppState.shared.popup.height, at: .statusItem)
  }

  private func showStatusItemMenu(for event: NSEvent) {
    guard let button = statusItem.button else { return }

    let menu = NSMenu()
    menu.autoenablesItems = false
    menu.addItem(withTitle: "打开 PromptPick", action: #selector(openFromStatusItemMenu), keyEquivalent: "")
    menu.addItem(withTitle: "暂停记录", action: #selector(toggleRecordingFromStatusItemMenu), keyEquivalent: "")
    menu.items.last?.state = Defaults[.ignoreEvents] ? .on : .off
    menu.addItem(.separator())
    menu.addItem(withTitle: "退出 PromptPick", action: #selector(quitFromStatusItemMenu), keyEquivalent: "q")
    menu.items.forEach { $0.target = self }

    // The quick panel deliberately lives at screen-saver level so it can appear
    // above fullscreen apps. A standard NSMenu sits lower in the window stack,
    // so leaving the panel open makes the menu look as if it opened behind it.
    // Keep these two transient surfaces mutually exclusive, like native macOS
    // status-item apps: dismiss the panel first, flush that visual state, then
    // let AppKit present the menu from the status item.
    if panel.isPresented {
      panel.close()
      NSApp.updateWindows()
    }

    NSMenu.popUpContextMenu(menu, with: event, for: button)
  }

  @objc
  private func openFromStatusItemMenu() {
    DispatchQueue.main.async {
      self.panel.open(height: AppState.shared.popup.height, at: .statusItem)
    }
  }

  @objc
  private func toggleRecordingFromStatusItemMenu() {
    Defaults[.ignoreEvents].toggle()
  }

  @objc
  private func quitFromStatusItemMenu() {
    NSApp.terminate(self)
  }

  private func synchronizeMenuIconText() {
    _ = withObservationTracking {
      AppState.shared.menuIconText
    } onChange: {
      DispatchQueue.main.async {
        if Defaults[.showRecentCopyInMenuBar] {
          self.statusItem.button?.title = AppState.shared.menuIconText
        }
        self.synchronizeMenuIconText()
      }
    }
  }

  private func disableUnusedGlobalHotkeys() {
    let names: [KeyboardShortcuts.Name] = [.delete, .pin, .togglePreview]
    KeyboardShortcuts.disable(names)

    NotificationCenter.default.addObserver(
      forName: Notification.Name("KeyboardShortcuts_shortcutByNameDidChange"),
      object: nil,
      queue: nil
    ) { notification in
      if let name = notification.userInfo?["name"] as? KeyboardShortcuts.Name, names.contains(name) {
        KeyboardShortcuts.disable(name)
      }
    }
  }
}
