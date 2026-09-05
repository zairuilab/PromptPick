import Foundation
import SwiftData

@Model
final class PromptCategory {
  @Attribute(.unique) var id: UUID
  var name: String
  var sortIndex: Int
  var createdAt: Date

  init(id: UUID = UUID(), name: String, sortIndex: Int, createdAt: Date = .now) {
    self.id = id
    self.name = name
    self.sortIndex = sortIndex
    self.createdAt = createdAt
  }
}

@Model
final class PromptItem {
  @Attribute(.unique) var id: UUID
  var title: String
  var content: String
  var categoryID: UUID
  var createdAt: Date
  var updatedAt: Date
  var lastUsedAt: Date?
  var useCount: Int
  var source: String
  var sourceApp: String?

  init(
    id: UUID = UUID(),
    title: String,
    content: String,
    categoryID: UUID,
    createdAt: Date = .now,
    updatedAt: Date = .now,
    lastUsedAt: Date? = nil,
    useCount: Int = 0,
    source: String = "manual",
    sourceApp: String? = nil
  ) {
    self.id = id
    self.title = title
    self.content = content
    self.categoryID = categoryID
    self.createdAt = createdAt
    self.updatedAt = updatedAt
    self.lastUsedAt = lastUsedAt
    self.useCount = useCount
    self.source = source
    self.sourceApp = sourceApp
  }

  var variableNames: [String] {
    PromptTemplateParser.variableNames(in: content)
  }

  var isVariableTemplate: Bool { !variableNames.isEmpty }
}

enum PromptTemplateParser {
  static func variableNames(in content: String) -> [String] {
    guard let expression = try? NSRegularExpression(pattern: #"\{\{\s*([^{}]+?)\s*\}\}"#) else {
      return []
    }

    let range = NSRange(content.startIndex..., in: content)
    var names: [String] = []
    for match in expression.matches(in: content, range: range) {
      guard let nameRange = Range(match.range(at: 1), in: content) else { continue }
      let name = content[nameRange].trimmingCharacters(in: .whitespacesAndNewlines)
      if !name.isEmpty, !names.contains(name) {
        names.append(name)
      }
    }
    return names
  }

  static func render(content: String, values: [String: String], clipboard: String? = nil) -> String {
    var rendered = content
    for name in variableNames(in: content) {
      let value: String
      if name.lowercased() == "clipboard" {
        value = values[name] ?? clipboard ?? ""
      } else {
        value = values[name] ?? ""
      }
      let escapedName = NSRegularExpression.escapedPattern(for: name)
      guard let expression = try? NSRegularExpression(
        pattern: #"\{\{\s*"# + escapedName + #"\s*\}\}"#
      ) else { continue }
      let fullRange = NSRange(rendered.startIndex..., in: rendered)
      rendered = expression.stringByReplacingMatches(
        in: rendered,
        range: fullRange,
        withTemplate: NSRegularExpression.escapedTemplate(for: value)
      )
    }
    return rendered
  }
}

@MainActor
class Storage {
  static let shared = Storage()

  var container: ModelContainer
  var context: ModelContext { container.mainContext }
  var storageURL: URL { url }
  var size: String {
    guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).allValues.first?.value as? Int64, size > 1 else {
      return ""
    }

    return ByteCountFormatter().string(fromByteCount: size)
  }

  private let url: URL

  init() {
    let directory = URL.applicationSupportDirectory.appending(path: "PromptClip", directoryHint: .isDirectory)
    do {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    } catch {
      fatalError("Cannot create PromptPick storage directory: \(error.localizedDescription).")
    }
    url = directory.appending(path: "Storage.sqlite")

    var config = ModelConfiguration(url: url)

    #if DEBUG
    if CommandLine.arguments.contains("enable-testing") {
      config = ModelConfiguration(isStoredInMemoryOnly: true)
    }
    #endif

    do {
      container = try ModelContainer(
        for: HistoryItem.self,
        PromptCategory.self,
        PromptItem.self,
        configurations: config
      )
    } catch let error {
      fatalError("Cannot load database: \(error.localizedDescription).")
    }
  }
}
