import AppKit
import Defaults
import SwiftUI
import UniformTypeIdentifiers

private enum PromptClipMode: String, CaseIterable, Identifiable {
  case recent = "最近"
  case prompts = "Prompts"

  var id: Self { self }
}

private enum PromptClipCategoryFilter: Hashable {
  case recent
  case all
  case category(UUID)
}

private enum PromptClipSelection: Hashable {
  case prompt(UUID)
  case history(UUID)
}

struct ContentView: View {
  @State private var appState = AppState.shared
  @State private var mode: PromptClipMode = .recent
  @State private var categoryFilter: PromptClipCategoryFilter = .recent
  @State private var query = ""
  @State private var selection: PromptClipSelection?
  @State private var saveHistoryItem: HistoryItemDecorator?
  @State private var editorPrompt: PromptItem?
  @State private var editorPresented = false
  @State private var variablePrompt: PromptItem?
  @State private var pendingVariablePaste: (prompt: PromptItem, content: String)?
  @State private var managerPresented = false
  @State private var toast: String?

  @FocusState private var searchFocused: Bool

  private var library: PromptLibrary { appState.promptLibrary }

  private var recentPrompts: [PromptItem] {
    library.prompts
      .filter { $0.lastUsedAt != nil }
      .sorted(by: recencySort)
  }

  private var visibleRecentPrompts: [PromptItem] {
    if query.isEmpty {
      return Array(recentPrompts.prefix(3))
    }
    return Array(recentPrompts.filter(matches).sorted(by: searchSort).prefix(9))
  }

  private var visibleHistory: [HistoryItemDecorator] {
    appState.history.unpinnedItems.filter { item in
      guard !item.text.isEmpty else { return false }
      guard !library.contains(content: item.text.trimmingCharacters(in: .whitespacesAndNewlines)) else {
        return false
      }
      guard !query.isEmpty else { return true }
      return item.text.localizedCaseInsensitiveContains(query)
        || (item.application?.localizedCaseInsensitiveContains(query) ?? false)
    }
  }

  private var visiblePrompts: [PromptItem] {
    library.prompts
      .filter { prompt in
        switch categoryFilter {
        case .recent:
          return prompt.lastUsedAt != nil
        case .all:
          return true
        case .category(let id):
          return prompt.categoryID == id
        }
      }
      .filter(matches)
      .sorted { lhs, rhs in
        if !query.isEmpty {
          return searchSort(lhs, rhs)
        }
        if categoryFilter == .recent {
          return recencySort(lhs, rhs)
        }
        return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
      }
  }

  private var orderedSelections: [PromptClipSelection] {
    if mode == .recent {
      return visibleRecentPrompts.map { .prompt($0.id) }
        + visibleHistory.map { .history($0.id) }
    }
    return visiblePrompts.map { .prompt($0.id) }
  }

  var body: some View {
    ZStack {
      if #available(macOS 26.0, *) {
        GlassEffectView()
      } else {
        VisualEffectView()
      }

      VStack(spacing: 0) {
        header
        searchField
        if mode == .prompts { categoryBar }
        results
        footer
      }
      .padding(.top, 12)
      .padding(.horizontal, 12)
      .padding(.bottom, 8)

      if let toast {
        VStack {
          Spacer()
          Label(toast, systemImage: "checkmark.circle.fill")
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .frame(height: 38)
            .background(.black.opacity(0.84), in: RoundedRectangle(cornerRadius: 10))
            .padding(.bottom, 54)
        }
        .allowsHitTesting(false)
      }

    }
    .frame(minWidth: 660, minHeight: 560)
    .task {
      library.load()
      try? await appState.history.load()
      restoreSelection()
      searchFocused = true
      appState.popup.height = 720
    }
    .onChange(of: mode) {
      query = ""
      restoreSelection()
    }
    .onChange(of: categoryFilter) {
      restoreSelection()
    }
    .onChange(of: query) {
      if !orderedSelections.contains(where: { $0 == selection }) {
        selection = orderedSelections.first
      }
    }
    .onKeyPress(.downArrow) {
      moveSelection(by: 1)
      return .handled
    }
    .onKeyPress(.upArrow) {
      moveSelection(by: -1)
      return .handled
    }
    .onKeyPress(.return) {
      performPrimaryAction()
      return .handled
    }
    .onKeyPress(phases: .down) { press in
      guard press.modifiers.contains(.command),
            let number = Int(press.characters),
            (1...9).contains(number) else { return .ignored }
      performSelection(at: number - 1)
      return .handled
    }
    .onExitCommand {
      appState.popup.close()
    }
    .sheet(item: $saveHistoryItem) { item in
      SaveHistoryAsPromptSheet(item: item, library: library) { prompt in
        saveHistoryItem = nil
        mode = .prompts
        categoryFilter = .category(prompt.categoryID)
        selection = .prompt(prompt.id)
        showToast("已收藏到「\(library.categoryName(for: prompt))」")
      }
    }
    .sheet(isPresented: $editorPresented) {
      PromptEditorSheet(prompt: editorPrompt, library: library) { prompt in
        editorPresented = false
        mode = .prompts
        categoryFilter = .category(prompt.categoryID)
        selection = .prompt(prompt.id)
        showToast(editorPrompt == nil ? "Prompt 已创建" : "Prompt 已更新")
      }
    }
    .sheet(item: $variablePrompt, onDismiss: finishPendingVariablePaste) { prompt in
      PromptVariableSheet(prompt: prompt) { rendered in
        pendingVariablePaste = (prompt, rendered)
        variablePrompt = nil
      }
    }
    .sheet(isPresented: $managerPresented) {
      PromptManagerView(library: library) { prompt in
        managerPresented = false
        mode = .prompts
        categoryFilter = .category(prompt.categoryID)
        selection = .prompt(prompt.id)
      }
    }
  }

  private var header: some View {
    HStack(spacing: 10) {
      Picker("视图", selection: $mode) {
        Label("最近", systemImage: "clock").tag(PromptClipMode.recent)
        Label("Prompts", systemImage: "sparkles").tag(PromptClipMode.prompts)
      }
      .pickerStyle(.segmented)
      .labelsHidden()
      .controlSize(.large)

      Button {
        editorPrompt = nil
        editorPresented = true
      } label: {
        Image(systemName: "plus")
          .frame(width: 30, height: 30)
      }
      .buttonStyle(.bordered)
      .accessibilityLabel("新建 Prompt")
      .help("新建 Prompt（⌘N）")
      .keyboardShortcut("n", modifiers: .command)

      Button {
        managerPresented = true
      } label: {
        Image(systemName: "gearshape")
          .frame(width: 30, height: 30)
      }
      .buttonStyle(.bordered)
      .accessibilityLabel("管理 Prompt")
      .help("管理 Prompt")
    }
  }

  private var searchField: some View {
    HStack(spacing: 9) {
      Image(systemName: "magnifyingglass")
        .font(.system(size: 17))
        .foregroundStyle(.secondary)
      TextField(mode == .recent ? "搜索最近内容" : "搜索 Prompt", text: $query)
        .textFieldStyle(.plain)
        .font(.system(size: 16))
        .focused($searchFocused)
      if !query.isEmpty {
        Button {
          query = ""
        } label: {
          Image(systemName: "xmark.circle.fill")
            .foregroundStyle(.tertiary)
        }
        .buttonStyle(.plain)
        .help("清除搜索")
      }
    }
    .padding(.horizontal, 12)
    .frame(height: 44)
    .background(.quaternary.opacity(0.7), in: RoundedRectangle(cornerRadius: 9))
    .padding(.top, 10)
  }

  private var categoryBar: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 5) {
        categoryButton("最近使用", filter: .recent)
        categoryButton("全部", filter: .all)
        ForEach(library.categories) { category in
          categoryButton(category.name, filter: .category(category.id))
        }
      }
      .padding(.vertical, 8)
    }
  }

  private func categoryButton(_ title: String, filter: PromptClipCategoryFilter) -> some View {
    Button(title) {
      categoryFilter = filter
    }
    .buttonStyle(.plain)
    .font(.system(size: 12.5, weight: categoryFilter == filter ? .semibold : .regular))
    .foregroundStyle(categoryFilter == filter ? .primary : .secondary)
    .padding(.horizontal, 11)
    .frame(height: 30)
    .background(
      categoryFilter == filter ? Color.primary.opacity(0.09) : Color.clear,
      in: RoundedRectangle(cornerRadius: 7)
    )
  }

  private var results: some View {
    ScrollView {
      LazyVStack(spacing: 2) {
        if mode == .recent {
          recentResults
        } else {
          promptResults
        }
      }
      .padding(.vertical, 5)
    }
    .scrollIndicators(.visible)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  @ViewBuilder
  private var recentResults: some View {
    if !visibleRecentPrompts.isEmpty {
      sectionHeader("最近使用的 Prompt", count: visibleRecentPrompts.count)
      ForEach(visibleRecentPrompts, id: \.id) { prompt in
        promptRow(prompt, shortcut: shortcutNumber(for: .prompt(prompt.id)))
      }
    }

    if !visibleHistory.isEmpty {
      Divider().padding(.vertical, 4)
      sectionHeader("其他剪贴板历史", count: visibleHistory.count)
      ForEach(visibleHistory, id: \.id) { item in
        historyRow(item, shortcut: shortcutNumber(for: .history(item.id)))
      }
    }

    if visibleRecentPrompts.isEmpty && visibleHistory.isEmpty {
      emptyState(
        title: "没有找到最近内容",
        message: query.isEmpty ? "复制内容后会自动出现在这里。" : "试试更短的关键词。"
      )
    }
  }

  @ViewBuilder
  private var promptResults: some View {
    sectionHeader(currentCategoryTitle, count: visiblePrompts.count)
    ForEach(visiblePrompts, id: \.id) { prompt in
      promptRow(prompt, shortcut: shortcutNumber(for: .prompt(prompt.id)))
    }

    if visiblePrompts.isEmpty {
      let historyMatches = visibleHistory.count
      VStack(spacing: 9) {
        emptyState(
          title: query.isEmpty ? "这个场景还没有 Prompt" : "Prompt 中没有找到“\(query)”",
          message: query.isEmpty ? "新建一条，或从最近剪贴板中收藏。" : "换个关键词继续搜索。"
        )
        if !query.isEmpty, historyMatches > 0 {
          Button("剪贴板历史中找到 \(historyMatches) 条，去查看") {
            mode = .recent
          }
          .buttonStyle(.bordered)
        }
      }
    }
  }

  private func sectionHeader(_ title: String, count: Int) -> some View {
    HStack(spacing: 7) {
      Text(title)
      Text("\(count)").foregroundStyle(.tertiary)
      Spacer()
    }
    .font(.system(size: 12.5, weight: .medium))
    .foregroundStyle(.secondary)
    .padding(.horizontal, 10)
    .frame(height: 34)
  }

  private func shortcutNumber(for item: PromptClipSelection) -> Int? {
    guard let index = orderedSelections.firstIndex(of: item) else { return nil }
    return index + 1
  }

  private func promptRow(_ prompt: PromptItem, shortcut: Int?) -> some View {
    let selected = selection == .prompt(prompt.id)
    return Button {
      selection = .prompt(prompt.id)
      if prompt.isVariableTemplate {
        paste(prompt)
      }
    } label: {
      HStack(spacing: 11) {
        Image(systemName: "doc.text")
          .font(.system(size: 18))
          .frame(width: 28)
        VStack(alignment: .leading, spacing: 3) {
          Text(prompt.title)
            .font(.system(size: 15, weight: .semibold))
            .lineLimit(1)
          Text(prompt.isVariableTemplate
               ? "需要填写：\(prompt.variableNames.map(humanReadableVariableName).joined(separator: "、"))"
               : prompt.content.replacingOccurrences(of: "\n", with: " "))
            .font(.system(size: 12.5))
            .foregroundStyle(selected ? .white.opacity(0.82) : .secondary)
            .lineLimit(1)
        }
        Spacer(minLength: 12)
        Text(library.categoryName(for: prompt))
          .font(.system(size: 12))
          .foregroundStyle(selected ? .white.opacity(0.82) : .secondary)
        if prompt.isVariableTemplate {
          Text("填写内容  →")
            .font(.system(size: 11.5, weight: .medium))
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(
              selected ? Color.white.opacity(0.15) : Color.primary.opacity(0.07),
              in: RoundedRectangle(cornerRadius: 5)
            )
        }
        if let shortcut, shortcut <= 9 {
          Text("⌘ \(shortcut)")
            .font(.system(size: 11, design: .rounded))
            .foregroundStyle(selected ? Color.white.opacity(0.72) : Color(nsColor: .tertiaryLabelColor))
        }
      }
      .padding(.horizontal, 11)
      .frame(height: 60)
      .foregroundStyle(selected ? .white : .primary)
      .background(selected ? Color.accentColor : Color.clear, in: RoundedRectangle(cornerRadius: 9))
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("prompt-row-\(prompt.id.uuidString)")
    .accessibilityLabel(prompt.isVariableTemplate ? "填写\(prompt.title)" : prompt.title)
    .accessibilityHint(prompt.isVariableTemplate ? "单击打开本次需要填写的内容" : "双击粘贴 Prompt")
    .simultaneousGesture(TapGesture(count: 2).onEnded {
      if !prompt.isVariableTemplate { paste(prompt) }
    })
  }

  private func historyRow(_ item: HistoryItemDecorator, shortcut: Int?) -> some View {
    let selected = selection == .history(item.id)
    return Button {
      selection = .history(item.id)
    } label: {
      HStack(spacing: 11) {
        AppImageView(appImage: item.applicationImage, size: CGSize(width: 25, height: 25))
          .clipShape(RoundedRectangle(cornerRadius: 6))
        Text(item.text.replacingOccurrences(of: "\n", with: " "))
          .font(.system(size: 14))
          .lineLimit(1)
        Spacer(minLength: 12)
        Text(item.application ?? "剪贴板")
          .font(.system(size: 12))
          .foregroundStyle(selected ? .white.opacity(0.82) : .secondary)
          .lineLimit(1)
        if let shortcut, shortcut <= 9 {
          Text("⌘ \(shortcut)")
            .font(.system(size: 11, design: .rounded))
            .foregroundStyle(selected ? Color.white.opacity(0.72) : Color(nsColor: .tertiaryLabelColor))
        }
        Button {
          saveHistoryItem = item
        } label: {
          Image(systemName: "bookmark")
            .font(.system(size: 16))
            .frame(width: 30, height: 30)
            .background(Color.white.opacity(selected ? 0.14 : 0), in: RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .help("收藏为 Prompt（⌘S）")
      }
      .padding(.horizontal, 11)
      .frame(height: 54)
      .foregroundStyle(selected ? .white : .primary)
      .background(selected ? Color.accentColor : Color.clear, in: RoundedRectangle(cornerRadius: 9))
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("history-row-\(item.id.uuidString)")
    .simultaneousGesture(TapGesture(count: 2).onEnded { paste(item) })
    .contextMenu {
      Button("收藏为 Prompt") {
        selection = .history(item.id)
        saveHistoryItem = item
      }
      Divider()
      Button("删除这条历史", role: .destructive) {
        deleteHistory(item)
      }
    }
  }

  private func emptyState(title: String, message: String) -> some View {
    VStack(spacing: 7) {
      Image(systemName: "magnifyingglass")
        .font(.system(size: 24))
        .foregroundStyle(.tertiary)
      Text(title).font(.system(size: 14, weight: .semibold))
      Text(message).font(.system(size: 12.5)).foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, minHeight: 190)
  }

  private var footer: some View {
    HStack(spacing: 6) {
      if let item = selectedHistoryItem {
        footerButton("粘贴", key: "↩") { paste(item) }
        footerButton("收藏为 Prompt", key: "⌘S", emphasized: true) {
          saveHistoryItem = item
        }
        .keyboardShortcut("s", modifiers: .command)
      } else if let prompt = selectedPrompt {
        footerButton(prompt.isVariableTemplate ? "填写并粘贴" : "粘贴", key: "↩") {
          paste(prompt)
        }
        footerButton("编辑", key: "⌘E") {
          editorPrompt = prompt
          editorPresented = true
        }
        .keyboardShortcut("e", modifiers: .command)
      } else {
        Text("选择一条内容").foregroundStyle(.tertiary)
      }
      Spacer()
      footerButton("退出应用", key: "⌘Q") {
        appState.quit()
      }
      .keyboardShortcut("q", modifiers: .command)
      .accessibilityIdentifier("quit-promptpick")
      Text("Esc 关闭面板")
        .foregroundStyle(.secondary)
    }
    .font(.system(size: 12.5))
    .padding(.horizontal, 4)
    .padding(.top, 7)
    .overlay(alignment: .top) { Divider() }
    .frame(height: 46)
  }

  private func footerButton(
    _ title: String,
    key: String,
    emphasized: Bool = false,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      HStack(spacing: 6) {
        Text(key)
          .font(.system(size: 10.5, weight: .medium))
          .padding(.horizontal, 5)
          .frame(height: 21)
          .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
        Text(title)
      }
      .foregroundStyle(emphasized ? Color.accentColor : Color.secondary)
      .padding(.horizontal, 7)
      .frame(height: 32)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }

  private var selectedPrompt: PromptItem? {
    guard case .prompt(let id) = selection else { return nil }
    let visible = mode == .recent ? visibleRecentPrompts : visiblePrompts
    return visible.first(where: { $0.id == id })
  }

  private var selectedHistoryItem: HistoryItemDecorator? {
    guard mode == .recent, case .history(let id) = selection else { return nil }
    return visibleHistory.first(where: { $0.id == id })
  }

  private var currentCategoryTitle: String {
    switch categoryFilter {
    case .recent: return "最近使用"
    case .all: return "全部"
    case .category(let id): return library.category(withID: id)?.name ?? "场景"
    }
  }

  private func matches(_ prompt: PromptItem) -> Bool {
    guard !query.isEmpty else { return true }
    return prompt.title.localizedCaseInsensitiveContains(query)
      || prompt.content.localizedCaseInsensitiveContains(query)
      || library.categoryName(for: prompt).localizedCaseInsensitiveContains(query)
  }

  private func recencySort(_ lhs: PromptItem, _ rhs: PromptItem) -> Bool {
    let lhsDate = lhs.lastUsedAt ?? .distantPast
    let rhsDate = rhs.lastUsedAt ?? .distantPast
    if lhsDate == rhsDate {
      if lhs.useCount == rhs.useCount {
        return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
      }
      return lhs.useCount > rhs.useCount
    }
    return lhsDate > rhsDate
  }

  private func searchSort(_ lhs: PromptItem, _ rhs: PromptItem) -> Bool {
    let lhsScore = searchScore(lhs)
    let rhsScore = searchScore(rhs)
    if lhsScore != rhsScore { return lhsScore < rhsScore }
    return recencySort(lhs, rhs)
  }

  private func searchScore(_ prompt: PromptItem) -> Int {
    let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !term.isEmpty else { return 0 }
    if prompt.title.localizedCaseInsensitiveCompare(term) == .orderedSame { return 0 }
    if prompt.title.lowercased().hasPrefix(term.lowercased()) { return 1 }
    if prompt.title.localizedCaseInsensitiveContains(term) { return 2 }
    if library.categoryName(for: prompt).localizedCaseInsensitiveContains(term) { return 3 }
    if prompt.content.localizedCaseInsensitiveContains(term) { return 4 }
    return 5
  }

  private func restoreSelection() {
    DispatchQueue.main.async {
      selection = orderedSelections.first
      searchFocused = true
    }
  }

  private func moveSelection(by offset: Int) {
    let items = orderedSelections
    guard !items.isEmpty else { selection = nil; return }
    guard let selection, let index = items.firstIndex(of: selection) else {
      self.selection = items.first
      return
    }
    let nextIndex = min(max(index + offset, 0), items.count - 1)
    self.selection = items[nextIndex]
  }

  private func performPrimaryAction() {
    if let prompt = selectedPrompt {
      paste(prompt)
    } else if let item = selectedHistoryItem {
      paste(item)
    }
  }

  private func performSelection(at index: Int) {
    guard orderedSelections.indices.contains(index) else { return }
    selection = orderedSelections[index]
    performPrimaryAction()
  }

  private func deleteHistory(_ item: HistoryItemDecorator) {
    appState.history.delete(item)
    selection = orderedSelections.first
    showToast("已删除剪贴板历史")
  }

  private func paste(_ item: HistoryItemDecorator) {
    appState.history.select(item, flags: [])
  }

  private func paste(_ prompt: PromptItem) {
    if prompt.isVariableTemplate {
      variablePrompt = prompt
    } else {
      commitPaste(prompt: prompt, content: prompt.content)
    }
  }

  private func commitPaste(prompt: PromptItem, content: String) {
    if !Defaults[.ignoreEvents] {
      Defaults[.ignoreEvents] = true
      Defaults[.ignoreOnlyNextEvent] = true
    }
    Clipboard.shared.copyInMaccy(content)
    library.recordUse(prompt)
    appState.popup.close()
    if Defaults[.pasteByDefault] {
      Clipboard.shared.paste()
    }
  }

  private func finishPendingVariablePaste() {
    guard let pendingVariablePaste else { return }
    self.pendingVariablePaste = nil
    // AppKit makes the parent panel key again while the sheet is finishing its
    // dismissal. Close and paste after that hand-off, otherwise the panel is
    // ordered front again and covers the target input field.
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
      commitPaste(prompt: pendingVariablePaste.prompt, content: pendingVariablePaste.content)
    }
  }

  private func showToast(_ message: String) {
    toast = message
    Task {
      try? await Task.sleep(for: .seconds(2.4))
      if toast == message { toast = nil }
    }
  }

  private func humanReadableVariableName(_ name: String) -> String {
    name.lowercased() == "clipboard" ? "当前剪贴板内容" : name
  }

}

private struct SaveHistoryAsPromptSheet: View {
  let item: HistoryItemDecorator
  let library: PromptLibrary
  let onSaved: (PromptItem) -> Void

  @Environment(\.dismiss) private var dismiss
  @State private var title: String
  @State private var categoryID: UUID?
  @State private var error: String?

  init(item: HistoryItemDecorator, library: PromptLibrary, onSaved: @escaping (PromptItem) -> Void) {
    self.item = item
    self.library = library
    self.onSaved = onSaved
    _title = State(initialValue: Self.suggestTitle(from: item.text))
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      sheetTitle("收藏为 Prompt", subtitle: "像收藏网页一样，立即命名并选择一个场景。")

      labeledField("名称") {
        TextField("Prompt 名称", text: $title)
          .textFieldStyle(.roundedBorder)
      }

      labeledField("场景 · 必填") {
        Picker("场景", selection: $categoryID) {
          Text("选择场景…").tag(nil as UUID?)
          ForEach(library.categories) { category in
            Text(category.name).tag(category.id as UUID?)
          }
        }
        .labelsHidden()
        .frame(maxWidth: .infinity)
      }

      labeledField("Prompt 内容") {
        TextEditor(text: .constant(item.text))
          .font(.system(size: 13))
          .scrollContentBackground(.hidden)
          .padding(7)
          .frame(height: 110)
          .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
          .disabled(true)
      }

      if let error {
        Text(error).font(.system(size: 12)).foregroundStyle(.red)
      }

      HStack {
        Spacer()
        Button("取消") { dismiss() }
          .keyboardShortcut(.cancelAction)
        Button("收藏 Prompt") { save() }
          .buttonStyle(.borderedProminent)
          .keyboardShortcut(.defaultAction)
      }
    }
    .padding(22)
    .frame(width: 500)
  }

  private func save() {
    guard let categoryID else {
      error = "请选择场景，避免 Prompt 进入无人整理的收件箱。"
      return
    }
    guard let prompt = library.createPrompt(
      title: title,
      content: item.text,
      categoryID: categoryID,
      source: "history",
      sourceApp: item.item.application
    ) else {
      error = library.lastError
      return
    }
    onSaved(prompt)
    dismiss()
  }

  private static func suggestTitle(from content: String) -> String {
    let firstLine = content
      .split(whereSeparator: \.isNewline)
      .first
      .map(String.init)?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if firstLine.isEmpty { return "新 Prompt" }
    return firstLine.shortened(to: 32)
  }
}

private struct PromptEditorSheet: View {
  let prompt: PromptItem?
  let library: PromptLibrary
  let onSaved: (PromptItem) -> Void

  @Environment(\.dismiss) private var dismiss
  @State private var title: String
  @State private var content: String
  @State private var categoryID: UUID?
  @State private var error: String?

  init(prompt: PromptItem?, library: PromptLibrary, onSaved: @escaping (PromptItem) -> Void) {
    self.prompt = prompt
    self.library = library
    self.onSaved = onSaved
    _title = State(initialValue: prompt?.title ?? "")
    _content = State(initialValue: prompt?.content ?? "")
    _categoryID = State(initialValue: prompt?.categoryID)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      sheetTitle(
        prompt == nil ? "新建 Prompt" : "编辑 Prompt",
        subtitle: "变量请使用双花括号，例如 {{目标用户}}。"
      )

      HStack(alignment: .top, spacing: 14) {
        labeledField("名称") {
          TextField("例如：安全代码审查", text: $title)
            .textFieldStyle(.roundedBorder)
        }
        .frame(maxWidth: .infinity)

        labeledField("场景 · 必填") {
          Picker("场景", selection: $categoryID) {
            Text("选择场景…").tag(nil as UUID?)
            ForEach(library.categories) { category in
              Text(category.name).tag(category.id as UUID?)
            }
          }
          .labelsHidden()
          .frame(width: 190)
        }
      }

      labeledField("Prompt 内容") {
        TextEditor(text: $content)
          .font(.system(size: 13.5))
          .padding(7)
          .frame(height: 260)
          .overlay {
            RoundedRectangle(cornerRadius: 8)
              .stroke(.separator, lineWidth: 1)
          }
      }

      HStack {
        Text("\(PromptTemplateParser.variableNames(in: content).count) 个变量占位符")
          .font(.system(size: 12))
          .foregroundStyle(.secondary)
        if let error {
          Text(error).font(.system(size: 12)).foregroundStyle(.red)
        }
        Spacer()
        Button("取消") { dismiss() }
          .keyboardShortcut(.cancelAction)
        Button("保存") { save() }
          .buttonStyle(.borderedProminent)
          .keyboardShortcut(.defaultAction)
      }
    }
    .padding(22)
    .frame(width: 700)
  }

  private func save() {
    guard let categoryID else {
      error = "请选择场景。"
      return
    }
    if let prompt {
      guard library.updatePrompt(prompt, title: title, content: content, categoryID: categoryID) else {
        error = library.lastError
        return
      }
      onSaved(prompt)
    } else {
      guard let created = library.createPrompt(
        title: title,
        content: content,
        categoryID: categoryID,
        source: "manual"
      ) else {
        error = library.lastError
        return
      }
      onSaved(created)
    }
    dismiss()
  }
}

private struct PromptVariableSheet: View {
  let prompt: PromptItem
  let onPaste: (String) -> Void

  @Environment(\.dismiss) private var dismiss
  @State private var values: [String: String]
  @State private var attemptedPaste = false
  @FocusState private var focusedVariable: String?

  init(prompt: PromptItem, onPaste: @escaping (String) -> Void) {
    self.prompt = prompt
    self.onPaste = onPaste
    var initial: [String: String] = [:]
    for name in prompt.variableNames {
      if name.lowercased() == "clipboard" {
        initial[name] = NSPasteboard.general.string(forType: .string) ?? ""
      } else {
        initial[name] = ""
      }
    }
    _values = State(initialValue: initial)
  }

  private var rendered: String {
    PromptTemplateParser.render(
      content: prompt.content,
      values: values,
      clipboard: NSPasteboard.general.string(forType: .string)
    )
  }

  private var preview: String {
    let previewValues = Dictionary(uniqueKeysWithValues: prompt.variableNames.map { name in
      let value = values[name, default: ""].trimmingCharacters(in: .whitespacesAndNewlines)
      return (name, value.isEmpty ? "【待填写：\(displayName(for: name))】" : values[name, default: ""])
    })
    return PromptTemplateParser.render(content: prompt.content, values: previewValues)
  }

  private var missingVariables: [String] {
    prompt.variableNames.filter {
      values[$0, default: ""].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
  }

  private var complete: Bool {
    missingVariables.isEmpty
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      sheetTitle(
        "使用「\(prompt.title)」",
        subtitle: "填写下面 \(prompt.variableNames.count) 项，我们会生成完整 Prompt 并粘贴到当前应用。原模板不会被修改。"
      )
      HStack(alignment: .top, spacing: 18) {
        VStack(alignment: .leading, spacing: 9) {
          Label("1  填写本次内容", systemImage: "square.and.pencil")
            .font(.system(size: 13, weight: .semibold))

          ScrollView {
            VStack(spacing: 14) {
              ForEach(prompt.variableNames, id: \.self) { name in
                VStack(alignment: .leading, spacing: 6) {
                  HStack(spacing: 6) {
                    Text(question(for: name))
                      .font(.system(size: 12.5, weight: .medium))
                    Text("必填")
                      .font(.system(size: 10.5, weight: .medium))
                      .foregroundStyle(.secondary)
                      .padding(.horizontal, 5)
                      .frame(height: 18)
                      .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
                  }

                  ZStack(alignment: .topLeading) {
                    if values[name, default: ""].isEmpty {
                      Text(placeholder(for: name))
                        .font(.system(size: 13))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 10)
                        .allowsHitTesting(false)
                    }
                    TextEditor(text: Binding(
                      get: { values[name, default: ""] },
                      set: { values[name] = $0 }
                    ))
                    .font(.system(size: 13))
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .focused($focusedVariable, equals: name)
                    .accessibilityLabel(question(for: name))
                    .accessibilityHint(helperText(for: name))
                    .accessibilityIdentifier("prompt-variable-input-\(name)")
                  }
                  .frame(height: inputHeight(for: name))
                  .background(Color(nsColor: .textBackgroundColor).opacity(0.72), in: RoundedRectangle(cornerRadius: 8))
                  .overlay {
                    RoundedRectangle(cornerRadius: 8)
                      .stroke(fieldBorderColor(for: name), lineWidth: focusedVariable == name ? 1.5 : 1)
                  }

                  Text(helperText(for: name))
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)

                  if attemptedPaste, missingVariables.contains(name) {
                    Label("请先填写这一项", systemImage: "exclamationmark.circle.fill")
                      .font(.system(size: 11.5, weight: .medium))
                      .foregroundStyle(.red)
                  }
                }
              }
            }
          }
          .padding(.vertical, 2)
        }
        .frame(width: 320, height: 350)

        VStack(alignment: .leading, spacing: 7) {
          Label("2  检查最终 Prompt", systemImage: "doc.text.magnifyingglass")
            .font(.system(size: 13, weight: .semibold))
          ScrollView {
            Text(preview)
              .font(.system(size: 13))
              .textSelection(.enabled)
              .frame(maxWidth: .infinity, alignment: .topLeading)
              .padding(10)
          }
          .frame(width: 360, height: 315)
          .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))

          Text(complete ? "内容已完整，可以粘贴。" : "填写左侧内容后，这里会实时生成最终 Prompt。")
            .font(.system(size: 11.5))
            .foregroundStyle(complete ? Color.green : Color.secondary)
        }
      }

      HStack {
        if !complete {
          Text("还需填写 \(missingVariables.count) 项")
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
        }
        Spacer()
        Button("取消") { dismiss() }
          .keyboardShortcut(.cancelAction)
        Button("填好并粘贴") { pasteIfComplete() }
        .buttonStyle(.borderedProminent)
        .keyboardShortcut(.defaultAction)
        .accessibilityIdentifier("paste-completed-prompt")
      }
    }
    .padding(22)
    .frame(width: 760)
    .onAppear {
      focusedVariable = missingVariables.first
    }
  }

  private func displayName(for name: String) -> String {
    name.lowercased() == "clipboard" ? "当前剪贴板内容" : name
  }

  private func question(for name: String) -> String {
    switch name.lowercased() {
    case "clipboard": return "这次要引用哪段剪贴板内容？"
    case "代码", "code": return "要处理哪段代码？"
    case "目标用户", "用户", "audience": return "这次内容面向谁？"
    case "主题", "topic": return "这次要处理什么主题？"
    case "文本", "内容", "材料", "text", "content": return "这次要处理哪段内容？"
    default: return "这次的「\(displayName(for: name))」是什么？"
    }
  }

  private func placeholder(for name: String) -> String {
    switch name.lowercased() {
    case "clipboard": return "已自动带入当前剪贴板，也可以在这里修改"
    case "代码", "code": return "粘贴要处理的代码…"
    case "目标用户", "用户", "audience": return "例如：使用企业后台的产品经理"
    case "主题", "topic": return "例如：AI 产品需求评审"
    case "文本", "内容", "材料", "text", "content": return "粘贴要处理的内容…"
    default: return "填写\(displayName(for: name))…"
    }
  }

  private func helperText(for name: String) -> String {
    if name.lowercased() == "clipboard" {
      return "已从当前剪贴板读取；本次修改不会覆盖原模板。"
    }
    if ["代码", "code", "文本", "内容", "材料", "text", "content"].contains(name.lowercased()) {
      return "可以直接粘贴多行内容，只用于这一次。"
    }
    return "只用于这一次，不会修改已收藏的 Prompt。"
  }

  private func inputHeight(for name: String) -> CGFloat {
    ["代码", "code", "clipboard", "文本", "内容", "材料", "text", "content"].contains(name.lowercased()) ? 138 : 78
  }

  private func fieldBorderColor(for name: String) -> Color {
    if attemptedPaste, missingVariables.contains(name) { return .red }
    if focusedVariable == name { return .accentColor }
    return Color(nsColor: .separatorColor)
  }

  private func pasteIfComplete() {
    guard complete else {
      attemptedPaste = true
      focusedVariable = missingVariables.first
      return
    }
    onPaste(rendered)
  }
}

private struct PromptManagerView: View {
  let library: PromptLibrary
  let onReveal: (PromptItem) -> Void

  @Environment(\.dismiss) private var dismiss
  @State private var categoryID: UUID?
  @State private var selectedPromptID: UUID?
  @State private var editorPrompt: PromptItem?
  @State private var editorPresented = false
  @State private var categoryEditorPresented = false
  @State private var settingsPresented = false
  @State private var categoryToEdit: PromptCategory?
  @State private var error: String?
  @State private var notice: String?
  @State private var isFilePanelPresented = false

  private var prompts: [PromptItem] {
    library.prompts
      .filter { categoryID == nil || $0.categoryID == categoryID }
      .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
  }

  private var selectedPrompt: PromptItem? {
    library.prompt(withID: selectedPromptID) ?? prompts.first
  }

  var body: some View {
    VStack(spacing: 0) {
      HStack {
        Text("Prompt 管理").font(.system(size: 16, weight: .semibold))
        Spacer()
        Button {
          importLibrary()
        } label: {
          Label("导入 JSON", systemImage: "square.and.arrow.down")
        }
        .help("从 PromptPick 导出的 JSON 备份文件中恢复 Prompt")
        .disabled(isFilePanelPresented)
        Button {
          exportLibrary()
        } label: {
          Label("导出 JSON", systemImage: "square.and.arrow.up")
        }
        .help("将全部 Prompt 导出为 JSON 备份文件")
        .disabled(isFilePanelPresented)
        Button {
          settingsPresented = true
        } label: {
          Label("设置", systemImage: "gearshape")
        }
        Button {
          editorPrompt = nil
          editorPresented = true
        } label: {
          Label("新建", systemImage: "plus")
        }
        Button {
          dismiss()
        } label: {
          Label("关闭", systemImage: "xmark")
        }
          .keyboardShortcut(.cancelAction)
      }
      .padding(.horizontal, 16)
      .frame(height: 52)
      .overlay(alignment: .bottom) { Divider() }

      HSplitView {
        VStack(alignment: .leading, spacing: 4) {
          Text("PROMPTS")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.top, 12)
          managerCategoryButton("全部", id: nil, count: library.prompts.count)
          ForEach(library.categories) { category in
            managerCategoryButton(
              category.name,
              id: category.id,
              count: library.prompts.filter { $0.categoryID == category.id }.count
            )
            .contextMenu {
              Button("上移") {
                library.moveCategory(category, by: -1)
              }
              .disabled(library.categories.first?.id == category.id)
              Button("下移") {
                library.moveCategory(category, by: 1)
              }
              .disabled(library.categories.last?.id == category.id)
              Divider()
              Button("重命名") {
                categoryToEdit = category
                categoryEditorPresented = true
              }
              Button("删除", role: .destructive) {
                if !library.deleteCategory(category) { error = library.lastError }
              }
            }
          }
          Button {
            categoryToEdit = nil
            categoryEditorPresented = true
          } label: {
            Label("新建场景", systemImage: "folder.badge.plus")
          }
          .buttonStyle(.plain)
          .font(.system(size: 12.5))
          .padding(10)
          Spacer()
        }
        .frame(minWidth: 160, idealWidth: 180, maxHeight: .infinity, alignment: .top)
        .accessibilityIdentifier("prompt-manager-sidebar")

        VStack(spacing: 0) {
          HStack {
            Text(categoryID.flatMap { library.category(withID: $0)?.name } ?? "全部")
            Spacer()
            Text("\(prompts.count) 条").foregroundStyle(.secondary)
          }
          .font(.system(size: 12.5, weight: .medium))
          .padding(.horizontal, 12)
          .frame(height: 40)
          .overlay(alignment: .bottom) { Divider() }

          ScrollView {
            LazyVStack(spacing: 0) {
              ForEach(prompts) { prompt in
                Button {
                  selectedPromptID = prompt.id
                } label: {
                  VStack(alignment: .leading, spacing: 4) {
                    Text(prompt.title).font(.system(size: 13.5, weight: .semibold)).lineLimit(1)
                    Text(prompt.content.replacingOccurrences(of: "\n", with: " "))
                      .font(.system(size: 11.5))
                      .foregroundStyle(.secondary)
                      .lineLimit(1)
                  }
                  .frame(maxWidth: .infinity, alignment: .leading)
                  .padding(.horizontal, 12)
                  .frame(height: 60)
                  .background(selectedPrompt?.id == prompt.id ? Color.accentColor.opacity(0.14) : .clear)
                }
                .buttonStyle(.plain)
                Divider()
              }
            }
          }
        }
        .frame(minWidth: 250, idealWidth: 300, maxHeight: .infinity, alignment: .top)
        .accessibilityIdentifier("prompt-manager-list")

        Group {
          if let prompt = selectedPrompt {
            VStack(alignment: .leading, spacing: 16) {
              HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                  Text(library.categoryName(for: prompt))
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                  Text(prompt.title).font(.system(size: 23, weight: .semibold))
                }
                Spacer()
                Button("编辑") {
                  editorPrompt = prompt
                  editorPresented = true
                }
              }
              HStack(spacing: 14) {
                Text("使用 \(prompt.useCount) 次")
                Text(prompt.isVariableTemplate ? "\(prompt.variableNames.count) 个变量" : "固定模板")
              }
              .font(.system(size: 12))
              .foregroundStyle(.secondary)
              ScrollView {
                Text(prompt.content)
                  .font(.system(size: 13.5))
                  .textSelection(.enabled)
                  .frame(maxWidth: .infinity, alignment: .topLeading)
                  .padding(14)
              }
              .background(.background, in: RoundedRectangle(cornerRadius: 10))
              HStack {
                Button("删除", role: .destructive) {
                  library.deletePrompt(prompt)
                  selectedPromptID = prompts.first?.id
                }
                Spacer()
                Button("在快速面板中查看") {
                  onReveal(prompt)
                  dismiss()
                }
              }
            }
            .padding(24)
          } else {
            ContentUnavailableView("选择一条 Prompt", systemImage: "doc.text.magnifyingglass")
          }
        }
        .frame(minWidth: 340, idealWidth: 420, maxHeight: .infinity)
        .accessibilityIdentifier("prompt-manager-detail")
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .accessibilityIdentifier("prompt-manager-content")

      if let error {
        Text(error)
          .font(.system(size: 12))
          .foregroundStyle(.red)
          .padding(8)
          .frame(maxWidth: .infinity)
          .background(.red.opacity(0.08))
      }
      if let notice {
        Text(notice)
          .font(.system(size: 12))
          .foregroundStyle(Color.accentColor)
          .padding(8)
          .frame(maxWidth: .infinity)
          .background(Color.accentColor.opacity(0.08))
      }
    }
    .frame(width: 940, height: 610)
    .onAppear {
      library.load()
      selectedPromptID = prompts.first?.id
    }
    .sheet(isPresented: $editorPresented) {
      PromptEditorSheet(prompt: editorPrompt, library: library) { prompt in
        editorPresented = false
        selectedPromptID = prompt.id
      }
    }
    .sheet(isPresented: $categoryEditorPresented) {
      CategoryEditorSheet(category: categoryToEdit, library: library) { category in
        categoryEditorPresented = false
        categoryID = category.id
      }
    }
    .sheet(isPresented: $settingsPresented) {
      PromptClipSettingsSheet()
    }
  }

  private func managerCategoryButton(_ title: String, id: UUID?, count: Int) -> some View {
    Button {
      categoryID = id
      selectedPromptID = nil
    } label: {
      HStack {
        Text(title)
        Spacer()
        Text("\(count)").foregroundStyle(.secondary)
      }
      .padding(.horizontal, 10)
      .frame(height: 32)
      .background(categoryID == id ? Color.accentColor.opacity(0.16) : .clear, in: RoundedRectangle(cornerRadius: 7))
    }
    .buttonStyle(.plain)
  }

  private func exportLibrary() {
    let panel = NSSavePanel()
    panel.title = "导出 Prompt 备份"
    panel.message = "将全部 Prompt 保存为 JSON 文件，可稍后通过“导入 JSON”恢复。"
    panel.prompt = "导出"
    panel.allowedContentTypes = [.json]
    panel.nameFieldStringValue = "PromptPick Backup.json"
    panel.canCreateDirectories = true
    guard let parentWindow = NSApp.keyWindow else {
      error = "无法打开导出窗口，请关闭其他弹窗后重试。"
      return
    }

    isFilePanelPresented = true
    panel.beginSheetModal(for: parentWindow) { response in
      isFilePanelPresented = false
      guard response == .OK, let url = panel.url else { return }
      do {
        try library.exportJSON().write(to: url, options: .atomic)
        error = nil
        notice = "已导出 \(library.prompts.count) 条 Prompt。"
      } catch {
        notice = nil
        self.error = "导出失败：\(error.localizedDescription)"
      }
    }
  }

  private func importLibrary() {
    let panel = NSOpenPanel()
    panel.title = "导入 Prompt 备份"
    panel.message = "请选择由 PromptPick 导出的 JSON 备份文件。重复 Prompt 会自动跳过。"
    panel.prompt = "导入"
    panel.allowedContentTypes = [.json]
    panel.allowsMultipleSelection = false
    panel.canChooseDirectories = false
    guard let parentWindow = NSApp.keyWindow else {
      error = "无法打开导入窗口，请关闭其他弹窗后重试。"
      return
    }

    isFilePanelPresented = true
    panel.beginSheetModal(for: parentWindow) { response in
      isFilePanelPresented = false
      guard response == .OK, let url = panel.url else { return }
      do {
        let imported = try library.importJSON(Data(contentsOf: url))
        selectedPromptID = prompts.first?.id
        error = nil
        notice = "已导入 \(imported) 条 Prompt；重复内容已跳过。"
      } catch {
        notice = nil
        self.error = "导入失败：\(error.localizedDescription)"
      }
    }
  }
}

private struct PromptClipSettingsSheet: View {
  @Environment(\.dismiss) private var dismiss
  @Default(.historyRetentionDays) private var retentionDays
  @Default(.pasteByDefault) private var pasteByDefault
  @Default(.clearOnQuit) private var clearOnQuit
  @State private var confirmClear = false

  var body: some View {
    VStack(spacing: 0) {
      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          sheetTitle("PromptPick 设置", subtitle: "本地优先，权限按需开启。")

          GroupBox("剪贴板历史") {
            VStack(alignment: .leading, spacing: 12) {
              HStack {
                Text("保留时间")
                Spacer()
                Picker("保留时间", selection: $retentionDays) {
                  Text("1 天").tag(1)
                  Text("7 天").tag(7)
                  Text("30 天").tag(30)
                  Text("永久").tag(0)
                }
                .labelsHidden()
                .frame(width: 130)
              }
              Toggle("退出时清空普通剪贴板历史", isOn: $clearOnQuit)
              Button("立即清空普通历史", role: .destructive) {
                confirmClear = true
              }
            }
            .padding(8)
          }

          GroupBox("粘贴与权限") {
            VStack(alignment: .leading, spacing: 8) {
              Toggle("选择后自动粘贴", isOn: $pasteByDefault)
              Text("开启后首次粘贴会请求辅助功能权限；关闭时只写入剪贴板，由你按 ⌘V。")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            }
            .padding(8)
          }

          GroupBox("不记录的 App") {
            ExcludedAppsEditor()
              .padding(8)
          }

          GroupBox("隐私") {
            VStack(alignment: .leading, spacing: 6) {
              Label("剪贴板与 Prompt 正文只保存在本机", systemImage: "lock.shield")
              Label("密码管理器标记的敏感和临时内容默认忽略", systemImage: "eye.slash")
              Text(Storage.shared.storageURL.path)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.tertiary)
                .textSelection(.enabled)
            }
            .padding(8)
          }
        }
        .padding(22)
      }

      Divider()
      HStack {
        Button("退出 PromptPick", role: .destructive) {
          AppState.shared.quit()
        }
        .accessibilityIdentifier("quit-promptpick-from-settings")
        Spacer()
        Button("完成") { dismiss() }
          .buttonStyle(.borderedProminent)
          .keyboardShortcut(.defaultAction)
      }
      .padding(.horizontal, 22)
      .frame(height: 58)
    }
    .frame(width: 560, height: 620)
    .background(Color(nsColor: .windowBackgroundColor))
    .accessibilityIdentifier("promptpick-settings")
    .onChange(of: retentionDays) {
      Task { try? await AppState.shared.history.load() }
    }
    .confirmationDialog("清空普通剪贴板历史？", isPresented: $confirmClear) {
      Button("清空历史", role: .destructive) {
        AppState.shared.history.clear()
        dismiss()
      }
      Button("取消", role: .cancel) {}
    } message: {
      Text("已收藏的 Prompt 不会被删除。")
    }
  }
}

private struct ExcludedAppsEditor: View {
  @Default(.ignoredApps) private var ignoredApps
  @Default(.ignoreAllAppsExceptListed) private var whitelistMode
  @State private var addingApplication = false
  @State private var selectedBundleID: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 9) {
      Toggle("仅记录列表中的 App（白名单模式）", isOn: $whitelistMode)

      ScrollView {
        LazyVStack(spacing: 2) {
          ForEach(ignoredApps, id: \.self) { bundleID in
            Button {
              selectedBundleID = bundleID
            } label: {
              HStack(spacing: 9) {
                applicationIcon(bundleID)
                VStack(alignment: .leading, spacing: 2) {
                  Text(applicationName(bundleID))
                    .font(.system(size: 12.5, weight: .medium))
                  Text(bundleID)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(.secondary)
                }
                Spacer()
              }
              .padding(.horizontal, 8)
              .frame(height: 42)
              .background(
                selectedBundleID == bundleID ? Color.accentColor.opacity(0.14) : Color.clear,
                in: RoundedRectangle(cornerRadius: 7)
              )
            }
            .buttonStyle(.plain)
          }
        }
      }
      .frame(height: ignoredApps.isEmpty ? 36 : 96)
      .overlay {
        RoundedRectangle(cornerRadius: 8)
          .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
      }
      .overlay {
        if ignoredApps.isEmpty {
          Text(whitelistMode ? "尚未选择允许记录的 App" : "尚未排除 App")
            .font(.system(size: 12))
            .foregroundStyle(.tertiary)
        }
      }

      HStack(spacing: 8) {
        Button {
          addingApplication = true
        } label: {
          Label("选择 App", systemImage: "plus")
        }
        Button {
          guard let selectedBundleID else { return }
          ignoredApps.removeAll { $0 == selectedBundleID }
          self.selectedBundleID = nil
        } label: {
          Label("移除", systemImage: "minus")
        }
        .disabled(selectedBundleID == nil)
        Spacer()
        Text(whitelistMode ? "列表外的 App 不记录" : "列表内的 App 不记录")
          .font(.system(size: 11.5))
          .foregroundStyle(.secondary)
      }
    }
    .fileImporter(isPresented: $addingApplication, allowedContentTypes: [.application]) { result in
      guard case .success(let url) = result,
            let bundleID = Bundle(url: url)?.bundleIdentifier,
            !ignoredApps.contains(bundleID) else { return }
      ignoredApps.append(bundleID)
      selectedBundleID = bundleID
    }
  }

  @ViewBuilder
  private func applicationIcon(_ bundleID: String) -> some View {
    if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
      Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
        .resizable()
        .frame(width: 24, height: 24)
    } else {
      Image(systemName: "app.dashed")
        .font(.system(size: 20))
        .frame(width: 24, height: 24)
    }
  }

  private func applicationName(_ bundleID: String) -> String {
    guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
      return "未知 App"
    }
    return NSWorkspace.shared.applicationName(url: url)
  }
}

private struct CategoryEditorSheet: View {
  let category: PromptCategory?
  let library: PromptLibrary
  let onSaved: (PromptCategory) -> Void

  @Environment(\.dismiss) private var dismiss
  @State private var name: String
  @State private var error: String?

  init(category: PromptCategory?, library: PromptLibrary, onSaved: @escaping (PromptCategory) -> Void) {
    self.category = category
    self.library = library
    self.onSaved = onSaved
    _name = State(initialValue: category?.name ?? "")
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      sheetTitle(category == nil ? "新建场景" : "重命名场景", subtitle: "场景只有一级，不创建复杂文件夹树。")
      TextField("场景名称", text: $name).textFieldStyle(.roundedBorder)
      if let error { Text(error).font(.system(size: 12)).foregroundStyle(.red) }
      HStack {
        Spacer()
        Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
        Button("保存") { save() }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
      }
    }
    .padding(22)
    .frame(width: 380)
  }

  private func save() {
    if let category {
      guard library.renameCategory(category, to: name) else {
        error = "名称不能为空，也不能与现有场景重复。"
        return
      }
      onSaved(category)
    } else {
      guard let created = library.createCategory(name: name) else {
        error = "名称不能为空，也不能与现有场景重复。"
        return
      }
      onSaved(created)
    }
    dismiss()
  }
}

private func sheetTitle(_ title: String, subtitle: String) -> some View {
  VStack(alignment: .leading, spacing: 4) {
    Text(title).font(.system(size: 18, weight: .semibold))
    Text(subtitle).font(.system(size: 12.5)).foregroundStyle(.secondary)
  }
}

private func labeledField<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
  VStack(alignment: .leading, spacing: 7) {
    Text(title).font(.system(size: 12.5, weight: .medium)).foregroundStyle(.secondary)
    content()
  }
}

#Preview {
  ContentView()
    .modelContainer(Storage.shared.container)
    .frame(width: 760, height: 720)
}
