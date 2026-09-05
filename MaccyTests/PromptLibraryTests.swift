import SwiftData
import XCTest
@testable import Maccy

final class PromptTemplateParserTests: XCTestCase {
  func testVariableNamesAreTrimmedAndDeduplicated() {
    let content = "审查 {{ 代码 }}，面向 {{目标用户}}，再次检查 {{代码}}。"
    XCTAssertEqual(PromptTemplateParser.variableNames(in: content), ["代码", "目标用户"])
  }

  func testTemplateRenderingSupportsClipboard() {
    let content = "为 {{目标用户}} 总结：{{clipboard}}"
    let rendered = PromptTemplateParser.render(
      content: content,
      values: ["目标用户": "产品经理"],
      clipboard: "这是一段材料"
    )
    XCTAssertEqual(rendered, "为 产品经理 总结：这是一段材料")
  }

  func testEditedClipboardVariableOverridesSystemClipboard() {
    let content = "总结：{{clipboard}}"
    let rendered = PromptTemplateParser.render(
      content: content,
      values: ["clipboard": "用户在表单中修改的内容"],
      clipboard: "系统剪贴板原值"
    )
    XCTAssertEqual(rendered, "总结：用户在表单中修改的内容")
  }
}

@MainActor
final class PromptLibraryTests: XCTestCase {
  private var containers: [ModelContainer] = []

  private func makeLibrary() throws -> PromptLibrary {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(
      for: HistoryItem.self,
      PromptCategory.self,
      PromptItem.self,
      configurations: config
    )
    containers.append(container)
    let library = PromptLibrary(context: container.mainContext)
    library.load()
    return library
  }

  func testDefaultCategoriesAndDuplicateProtection() throws {
    let library = try makeLibrary()
    XCTAssertEqual(library.categories.map(\.name), ["代码审查", "产品分析", "内容写作"])

    let categoryID = try XCTUnwrap(library.categories.first?.id)
    XCTAssertNotNil(library.createPrompt(
      title: "安全审查",
      content: "检查以下代码",
      categoryID: categoryID,
      source: "manual"
    ))
    XCTAssertNil(library.createPrompt(
      title: "重复内容",
      content: "检查以下代码",
      categoryID: categoryID,
      source: "manual"
    ))
    XCTAssertEqual(library.prompts.count, 1)
  }

  func testJSONRoundTrip() throws {
    let source = try makeLibrary()
    let categoryID = try XCTUnwrap(source.categories.first?.id)
    _ = source.createPrompt(
      title: "安全审查",
      content: "检查 {{代码}}",
      categoryID: categoryID,
      source: "manual"
    )

    let data = try source.exportJSON()
    let destination = try makeLibrary()
    XCTAssertEqual(try destination.importJSON(data), 1)
    XCTAssertEqual(destination.prompts.first?.title, "安全审查")
    XCTAssertEqual(destination.prompts.first?.variableNames, ["代码"])
  }

  func testCreatedPromptIDsRemainDistinctAfterUse() throws {
    let library = try makeLibrary()
    let categoryID = try XCTUnwrap(library.categories.first?.id)
    let first = try XCTUnwrap(library.createPrompt(
      title: "First",
      content: "first content",
      categoryID: categoryID,
      source: "test"
    ))
    let second = try XCTUnwrap(library.createPrompt(
      title: "Second",
      content: "second content",
      categoryID: categoryID,
      source: "test"
    ))

    XCTAssertNotEqual(first.id, second.id)
    library.recordUse(first)
    library.recordUse(second)
    XCTAssertEqual(Set(library.prompts.map(\.id)).count, 2)
  }
}
