import AppKit
import Defaults
import Foundation
import Settings
import SwiftData
import SwiftUI

@Observable
final class PromptLibrary {
  private struct ExportDocument: Codable {
    let version: Int
    let exportedAt: Date
    let categories: [ExportCategory]
    let prompts: [ExportPrompt]
  }

  private struct ExportCategory: Codable {
    let id: UUID
    let name: String
    let sortIndex: Int
  }

  private struct ExportPrompt: Codable {
    let id: UUID
    let title: String
    let content: String
    let categoryID: UUID
    let createdAt: Date
    let updatedAt: Date
    let lastUsedAt: Date?
    let useCount: Int
    let source: String
    let sourceApp: String?
  }

  private(set) var prompts: [PromptItem] = []
  private(set) var categories: [PromptCategory] = []
  private(set) var lastError: String?

  @ObservationIgnored
  private var context: ModelContext?

  init() {}

  init(context: ModelContext) {
    self.context = context
  }

  @MainActor
  func load() {
    let context = resolvedContext
    do {
      categories = try context.fetch(
        FetchDescriptor<PromptCategory>(sortBy: [SortDescriptor(\.sortIndex), SortDescriptor(\.name)])
      )
      if categories.isEmpty {
        seedDefaultCategories()
      }
      prompts = try context.fetch(
        FetchDescriptor<PromptItem>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
      )
      lastError = nil
    } catch {
      lastError = "无法读取 Prompt 数据：\(error.localizedDescription)"
    }
  }

  @discardableResult
  @MainActor
  func createCategory(name: String) -> PromptCategory? {
    let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalized.isEmpty else { return nil }
    if let existing = categories.first(where: { $0.name.localizedCaseInsensitiveCompare(normalized) == .orderedSame }) {
      return existing
    }

    let context = resolvedContext
    let category = PromptCategory(name: normalized, sortIndex: categories.count)
    context.insert(category)
    saveAndReload()
    return category
  }

  @MainActor
  func renameCategory(_ category: PromptCategory, to name: String) -> Bool {
    let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalized.isEmpty else { return false }
    guard !categories.contains(where: {
      $0.id != category.id && $0.name.localizedCaseInsensitiveCompare(normalized) == .orderedSame
    }) else { return false }
    category.name = normalized
    saveAndReload()
    return true
  }

  @MainActor
  func deleteCategory(_ category: PromptCategory) -> Bool {
    guard !prompts.contains(where: { $0.categoryID == category.id }) else {
      lastError = "请先移动或删除该场景下的 Prompt。"
      return false
    }
    let context = resolvedContext
    context.delete(category)
    saveAndReload()
    return true
  }

  @MainActor
  func moveCategory(_ category: PromptCategory, by offset: Int) {
    guard let currentIndex = categories.firstIndex(where: { $0.id == category.id }) else { return }
    let targetIndex = min(max(currentIndex + offset, 0), categories.count - 1)
    guard currentIndex != targetIndex else { return }
    categories.swapAt(currentIndex, targetIndex)
    for (index, category) in categories.enumerated() {
      category.sortIndex = index
    }
    saveAndReload()
  }

  func prompt(withID id: UUID?) -> PromptItem? {
    guard let id else { return nil }
    return prompts.first(where: { $0.id == id })
  }

  func category(withID id: UUID) -> PromptCategory? {
    categories.first(where: { $0.id == id })
  }

  func categoryName(for prompt: PromptItem) -> String {
    category(withID: prompt.categoryID)?.name ?? "未分类"
  }

  func contains(content: String) -> Bool {
    prompts.contains(where: { $0.content == content })
  }

  @discardableResult
  @MainActor
  func createPrompt(
    title: String,
    content: String,
    categoryID: UUID,
    source: String,
    sourceApp: String? = nil
  ) -> PromptItem? {
    let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
    let normalizedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalizedTitle.isEmpty, !normalizedContent.isEmpty, category(withID: categoryID) != nil else {
      lastError = "名称、内容和场景都必须填写。"
      return nil
    }
    guard !contains(content: normalizedContent) else {
      lastError = "这条内容已经在 Prompt 库中。"
      return nil
    }

    let context = resolvedContext
    let prompt = PromptItem(
      title: normalizedTitle,
      content: normalizedContent,
      categoryID: categoryID,
      source: source,
      sourceApp: sourceApp
    )
    context.insert(prompt)
    saveAndReload()
    return prompt
  }

  @MainActor
  func updatePrompt(_ prompt: PromptItem, title: String, content: String, categoryID: UUID) -> Bool {
    let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
    let normalizedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalizedTitle.isEmpty, !normalizedContent.isEmpty, category(withID: categoryID) != nil else {
      lastError = "名称、内容和场景都必须填写。"
      return false
    }
    guard !prompts.contains(where: { $0.id != prompt.id && $0.content == normalizedContent }) else {
      lastError = "另一条 Prompt 已经使用相同内容。"
      return false
    }
    prompt.title = normalizedTitle
    prompt.content = normalizedContent
    prompt.categoryID = categoryID
    prompt.updatedAt = .now
    saveAndReload()
    return true
  }

  @MainActor
  func deletePrompt(_ prompt: PromptItem) {
    let context = resolvedContext
    context.delete(prompt)
    saveAndReload()
  }

  @MainActor
  func recordUse(_ prompt: PromptItem) {
    prompt.lastUsedAt = .now
    prompt.useCount += 1
    saveAndReload()
  }

  func exportJSON() throws -> Data {
    let document = ExportDocument(
      version: 1,
      exportedAt: .now,
      categories: categories.map {
        ExportCategory(id: $0.id, name: $0.name, sortIndex: $0.sortIndex)
      },
      prompts: prompts.map {
        ExportPrompt(
          id: $0.id,
          title: $0.title,
          content: $0.content,
          categoryID: $0.categoryID,
          createdAt: $0.createdAt,
          updatedAt: $0.updatedAt,
          lastUsedAt: $0.lastUsedAt,
          useCount: $0.useCount,
          source: $0.source,
          sourceApp: $0.sourceApp
        )
      }
    )
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return try encoder.encode(document)
  }

  @discardableResult
  @MainActor
  func importJSON(_ data: Data) throws -> Int {
    let context = resolvedContext
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let document = try decoder.decode(ExportDocument.self, from: data)
    guard document.version == 1 else {
      throw CocoaError(.fileReadCorruptFile, userInfo: [
        NSLocalizedDescriptionKey: "不支持的 PromptPick 备份版本。"
      ])
    }

    var categoryIDMap: [UUID: UUID] = [:]
    for incoming in document.categories.sorted(by: { $0.sortIndex < $1.sortIndex }) {
      if let existing = categories.first(where: {
        $0.name.localizedCaseInsensitiveCompare(incoming.name) == .orderedSame
      }) {
        categoryIDMap[incoming.id] = existing.id
      } else {
        let category = PromptCategory(name: incoming.name, sortIndex: categories.count)
        context.insert(category)
        categories.append(category)
        categoryIDMap[incoming.id] = category.id
      }
    }

    var imported = 0
    for incoming in document.prompts {
      guard !prompts.contains(where: { $0.content == incoming.content }) else { continue }
      guard let mappedCategoryID = categoryIDMap[incoming.categoryID] ?? categories.first?.id else { continue }
      context.insert(PromptItem(
        id: incoming.id,
        title: incoming.title,
        content: incoming.content,
        categoryID: mappedCategoryID,
        createdAt: incoming.createdAt,
        updatedAt: incoming.updatedAt,
        lastUsedAt: incoming.lastUsedAt,
        useCount: incoming.useCount,
        source: "import",
        sourceApp: incoming.sourceApp
      ))
      imported += 1
    }
    try context.save()
    load()
    return imported
  }

  @MainActor
  private func seedDefaultCategories() {
    let context = resolvedContext
    ["代码审查", "产品分析", "内容写作"].enumerated().forEach { index, name in
      context.insert(PromptCategory(name: name, sortIndex: index))
    }
    try? context.save()
    categories = (try? context.fetch(
      FetchDescriptor<PromptCategory>(sortBy: [SortDescriptor(\.sortIndex)])
    )) ?? []
  }

  @MainActor
  private func saveAndReload() {
    let context = resolvedContext
    do {
      try context.save()
      lastError = nil
      load()
    } catch {
      lastError = "保存失败：\(error.localizedDescription)"
    }
  }

  @MainActor
  private var resolvedContext: ModelContext {
    if let context { return context }
    let context = Storage.shared.context
    self.context = context
    return context
  }
}

@Observable
class AppState: Sendable {
  static let shared = AppState(history: History.shared, footer: Footer())

  let multiSelectionEnabled = false

  var appDelegate: AppDelegate?
  var popup: Popup
  var history: History
  var promptLibrary: PromptLibrary
  var footer: Footer
  var navigator: NavigationManager
  var preview: SlideoutController

  var searchVisible: Bool {
    if !Defaults[.showSearch] { return false }
    switch Defaults[.searchVisibility] {
    case .always: return true
    case .duringSearch: return !history.searchQuery.isEmpty
    }
  }

  var menuIconText: String {
    var title = history.unpinnedItems.first?.text.shortened(to: 100)
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    title.unicodeScalars.removeAll(where: CharacterSet.newlines.contains)
    return title.shortened(to: 20)
  }

  private let about = About()
  private var settingsWindowController: SettingsWindowController?

  init(history: History, footer: Footer) {
    self.history = history
    promptLibrary = PromptLibrary()
    self.footer = footer
    popup = Popup()
    navigator = NavigationManager(history: history, footer: footer)
    preview = SlideoutController(
      onContentResize: { contentWidth in
        Defaults[.windowSize].width = contentWidth
      },
      onSlideoutResize: { previewWidth in
        Defaults[.previewWidth] = previewWidth
      })
    preview.contentWidth = Defaults[.windowSize].width
    preview.slideoutWidth = Defaults[.previewWidth]
  }

  @MainActor
  func select(flags modifierFlags: NSEvent.ModifierFlags) {
    if !navigator.selection.isEmpty {
      if navigator.isMultiSelectInProgress {
        navigator.isManualMultiSelect = false
        history.startPasteStack(selection: &navigator.selection, flags: modifierFlags)
      } else {
        history.select(navigator.selection.first, flags: modifierFlags)
      }
    } else if let item = footer.selectedItem {
      // TODO: Use item.suppressConfirmation, but it's not updated!
      if item.confirmation != nil, Defaults[.suppressClearAlert] == false {
        item.showConfirmation = true
      } else {
        item.action()
      }
    } else {
      Clipboard.shared.copyInMaccy(history.searchQuery)
      history.searchQuery = ""
    }
  }

  @MainActor
  func togglePin() {
    withTransaction(Transaction()) {
      navigator.selection.forEach { _, item in
        history.togglePin(item)
      }
    }
  }

  @MainActor
  func removePasteStack() {
    history.interruptPasteStack()
    navigator.highlightFirst()
  }

  @MainActor
  func deleteSelection() {
    guard let leadItem = navigator.leadHistoryItem else { return }
    let nextUnselectedItem = history.visibleItems.nearest(to: leadItem) { !$0.isSelected }

    withTransaction(Transaction()) {
      navigator.selection.forEach { _, item in
        history.delete(item)
      }
      navigator.select(item: nextUnselectedItem)
    }
  }

  func openAbout() {
    about.openAbout(nil)
  }

  @MainActor
  func openPreferences() { // swiftlint:disable:this function_body_length
    if settingsWindowController == nil {
      settingsWindowController = SettingsWindowController(
        panes: [
          Settings.Pane(
            identifier: Settings.PaneIdentifier.general,
            title: NSLocalizedString("Title", tableName: "GeneralSettings", comment: ""),
            toolbarIcon: NSImage.gearshape!
          ) {
            GeneralSettingsPane()
          },
          Settings.Pane(
            identifier: Settings.PaneIdentifier.storage,
            title: NSLocalizedString("Title", tableName: "StorageSettings", comment: ""),
            toolbarIcon: NSImage.externaldrive!
          ) {
            StorageSettingsPane()
          },
          Settings.Pane(
            identifier: Settings.PaneIdentifier.appearance,
            title: NSLocalizedString("Title", tableName: "AppearanceSettings", comment: ""),
            toolbarIcon: NSImage.paintpalette!
          ) {
            AppearanceSettingsPane()
          },
          Settings.Pane(
            identifier: Settings.PaneIdentifier.pins,
            title: NSLocalizedString("Title", tableName: "PinsSettings", comment: ""),
            toolbarIcon: NSImage.pincircle!
          ) {
            PinsSettingsPane()
              .environment(self)
              .modelContainer(Storage.shared.container)
          },
          Settings.Pane(
            identifier: Settings.PaneIdentifier.ignore,
            title: NSLocalizedString("Title", tableName: "IgnoreSettings", comment: ""),
            toolbarIcon: NSImage.nosign!
          ) {
            IgnoreSettingsPane()
          },
          Settings.Pane(
            identifier: Settings.PaneIdentifier.advanced,
            title: NSLocalizedString("Title", tableName: "AdvancedSettings", comment: ""),
            toolbarIcon: NSImage.gearshape2!
          ) {
            AdvancedSettingsPane()
          }
        ]
      )
    }
    settingsWindowController?.show()
    settingsWindowController?.window?.orderFrontRegardless()
  }

  func quit() {
    NSApp.terminate(self)
  }
}
