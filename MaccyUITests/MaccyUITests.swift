import Carbon
import XCTest

// swiftlint:disable file_length
// swiftlint:disable type_body_length
class MaccyUITests: XCTestCase {
  let app = XCUIApplication()
  let pasteboard = NSPasteboard.general

  let copy1 = UUID().uuidString
  let copy2 = UUID().uuidString
  let copy3 = UUID().uuidString

  // https://hetima.github.io/fucking_nsimage_syntax
  let image1 = NSImage(named: "NSAddTemplate")!
  let image2 = NSImage(named: "NSBluetoothTemplate")!

  let file1 = URL.applicationSupportDirectory.appendingPathComponent("file1.txt")
  let file2 = URL.applicationSupportDirectory.appendingPathComponent("file2.txt")

  let rtf1 = NSAttributedString(string: "foo").rtf(
    from: NSRange(0...2),
    documentAttributes: [:]
  )
  let rtf2 = NSAttributedString(string: "bar").rtf(
    from: NSRange(0...2),
    documentAttributes: [:]
  )

  let html1 = "<a href='#'>foo</a>".data(using: .utf8)
  let html2 = "<a href='#'>bar</a>".data(using: .utf8)

  let imageType = NSPredicate(
    format: "elementType == %lu",
    argumentArray: [XCUIElement.ElementType.image.rawValue]
  )

  var items: XCUIElementQuery {
    app.descendants(matching: .any).matching(identifier: "copy-history-item")
  }

  var itemTitles: [String] {
    items.allElementsBoundByIndex
      .sorted(by: { $0.frame.origin.y < $1.frame.origin.y })
      .compactMap { $0.value as? String }
  }

  private var seedsVariablePromptAtLaunch: Bool {
    name.contains("testVariablePrompt")
  }

  private var keepsPromptPanelOpenDuringTest: Bool {
    name.contains("testNewPromptSheet")
      || name.contains("testPromptManager")
      || name.contains("testVariablePrompt")
      || name.contains("testVisibleQuit")
      || name.contains("testStatusItem")
  }

  override func setUp() {
    super.setUp()
    continueAfterFailure = false

    try? "Hello world".write(to: file1, atomically: true, encoding: .utf8)
    try? "Hello world".write(to: file2, atomically: true, encoding: .utf8)

    app.launchArguments = ["enable-testing"]
    if keepsPromptPanelOpenDuringTest {
      app.launchArguments.append("open-panel-for-testing")
      app.launchArguments.append("keep-panel-open-for-testing")
    }
    if seedsVariablePromptAtLaunch {
      app.launchArguments.append("seed-variable-prompt-for-testing")
    }
    app.launch()

    copyToClipboard(copy2)
    copyToClipboard(copy1)

  }

  override func tearDown() {
    super.tearDown()
    app.terminate()
  }

  func testPopupWithHotkey() throws {
    popUpWithHotkey()
    assertExists(items[copy1])
    assertExists(items[copy2])
  }

  func testCloseWithHotkey() throws {
    popUpWithMouse()
    assertExists(items[copy1])
    simulatePopupHotkey()
    assertNotExists(items[copy1])
  }

  func testPopupWithMenubar() {
    popUpWithMouse()
    assertExists(items[copy1])
    assertExists(items[copy2])
  }

  func testNewPromptSheetStaysVisible() {
    openPromptPickPanelForPromptTests()

    let newPromptButton = app.buttons["新建 Prompt"].firstMatch
    assertExists(newPromptButton)
    newPromptButton.click()

    assertExists(app.staticTexts["新建 Prompt"].firstMatch)
    assertExists(app.textFields["例如：安全代码审查"].firstMatch)
    XCTAssertNotEqual(app.state, .notRunning)
  }

  func testPromptManagerStaysVisible() {
    openPromptPickPanelForPromptTests()

    let managerButton = app.buttons["管理 Prompt"].firstMatch
    assertExists(managerButton)
    managerButton.click()

    assertExists(app.staticTexts["Prompt 管理"].firstMatch)
    assertExists(app.buttons["关闭"].firstMatch)
    let managerSheet = app.sheets.firstMatch
    assertExists(managerSheet)
    XCTAssertGreaterThanOrEqual(managerSheet.frame.height, 600)

    // Regression guard for the former giant blank region: the toolbar must sit
    // at the top of the window and the first row of every column must begin
    // immediately underneath it.
    let managerTitle = app.staticTexts["Prompt 管理"].firstMatch
    let firstScene = app.buttons.matching(NSPredicate(format: "label BEGINSWITH '全部'"))
      .firstMatch
    let listHeader = app.staticTexts.matching(NSPredicate(format: "value BEGINSWITH '全部'"))
      .firstMatch
    assertExists(firstScene)
    assertExists(listHeader)
    assertExists(app.staticTexts["选择一条 Prompt"].firstMatch)
    XCTAssertLessThan(managerTitle.frame.minY - managerSheet.frame.minY, 80)
    XCTAssertLessThan(firstScene.frame.minY - managerTitle.frame.maxY, 120)
    XCTAssertLessThan(listHeader.frame.minY - managerTitle.frame.maxY, 120)
    XCTAssertNotEqual(app.state, .notRunning)
  }

  func testPromptManagerCloseButtonDismissesWithoutEscape() {
    openPromptPickPanelForPromptTests()

    app.buttons["管理 Prompt"].firstMatch.click()
    let closeButton = app.buttons["关闭"].firstMatch
    assertExists(closeButton)
    XCTAssertTrue(closeButton.isHittable)

    closeButton.click()

    assertNotExists(app.staticTexts["Prompt 管理"].firstMatch)
    XCTAssertNotEqual(app.state, .notRunning)
  }

  func testPromptManagerSettingsHasBoundedScrollableLayoutAndReturns() {
    openPromptPickPanelForPromptTests()

    app.buttons["管理 Prompt"].firstMatch.click()
    let settingsButton = app.buttons["设置"].firstMatch
    assertExists(settingsButton)
    settingsButton.click()

    // SwiftUI can expose the sheet root as AXSheet instead of AXOther, so assert
    // the user-visible modal itself rather than coupling the test to one AX role.
    let settings = app.sheets.firstMatch
    assertExists(settings)
    XCTAssertLessThanOrEqual(settings.frame.height, 640)
    XCTAssertGreaterThanOrEqual(settings.frame.height, 580)
    assertExists(app.staticTexts["PromptPick 设置"].firstMatch)
    assertExists(app.buttons["退出 PromptPick"].firstMatch)

    let doneButton = app.buttons["完成"].firstMatch
    assertExists(doneButton)
    XCTAssertTrue(doneButton.isHittable)
    doneButton.click()

    assertExists(app.staticTexts["Prompt 管理"].firstMatch)
    XCTAssertTrue(app.buttons["关闭"].firstMatch.isHittable)
  }

  func testVisibleQuitActionTerminatesApplication() {
    openPromptPickPanelForPromptTests()

    let quitButton = app.buttons["quit-promptpick"].firstMatch
    assertExists(quitButton)
    XCTAssertTrue(quitButton.isHittable)
    quitButton.click()

    XCTAssertTrue(app.wait(for: .notRunning, timeout: 3))
  }

  func testStatusItemRightClickExposesQuitAction() {
    openPromptPickPanelForPromptTests()

    let panelEntry = app.buttons["新建 Prompt"].firstMatch
    assertExists(panelEntry)
    XCTAssertTrue(panelEntry.isHittable)

    let statusItem = app.statusItems.firstMatch
    assertExists(statusItem)
    statusItem.rightClick()

    let quitMenuItem = app.menuItems["退出 PromptPick"].firstMatch
    assertExists(quitMenuItem)
    XCTAssertTrue(quitMenuItem.isHittable)
    assertNotVisible(panelEntry)

    let quitMenuAttachment = XCTAttachment(screenshot: quitMenuItem.screenshot())
    quitMenuAttachment.name = "Frontmost status menu quit action"
    quitMenuAttachment.lifetime = .keepAlways
    add(quitMenuAttachment)

    let openMenuItem = app.menuItems["打开 PromptPick"].firstMatch
    assertExists(openMenuItem)
    openMenuItem.click()

    assertExists(app.buttons["新建 Prompt"].firstMatch)
    XCTAssertTrue(app.buttons["新建 Prompt"].firstMatch.isHittable)
  }

  func testPromptManagerExportJSONSheetIsFrontmostAndCancelable() {
    openPromptPickPanelForPromptTests()

    app.buttons["管理 Prompt"].firstMatch.click()
    let exportButton = app.buttons["导出 JSON"].firstMatch
    assertExists(exportButton)
    exportButton.click()

    assertExists(app.staticTexts["将全部 Prompt 保存为 JSON 文件，可稍后通过“导入 JSON”恢复。"].firstMatch)
    let cancelButton = app.sheets.buttons["取消"].firstMatch
    assertExists(cancelButton)
    XCTAssertTrue(cancelButton.isHittable)
    cancelButton.click()

    assertExists(app.staticTexts["Prompt 管理"].firstMatch)
    XCTAssertTrue(app.buttons["关闭"].firstMatch.isHittable)
  }

  func testPromptManagerImportExplainsJSONAndReturnsAfterCancel() {
    openPromptPickPanelForPromptTests()

    app.buttons["管理 Prompt"].firstMatch.click()
    let importButton = app.buttons["导入 JSON"].firstMatch
    assertExists(importButton)
    importButton.click()

    assertExists(app.staticTexts["请选择由 PromptPick 导出的 JSON 备份文件。重复 Prompt 会自动跳过。"].firstMatch)
    let cancelButton = app.sheets.buttons["取消"].firstMatch
    assertExists(cancelButton)
    XCTAssertTrue(cancelButton.isHittable)
    cancelButton.click()

    assertExists(app.staticTexts["Prompt 管理"].firstMatch)
    XCTAssertTrue(app.buttons["关闭"].firstMatch.isHittable)
  }

  func testVariablePromptSingleClickOpensGuidedFormAndPastes() {
    openPromptPickPanelForPromptTests()

    let promptsTab = app.radioButtons["Prompts"].firstMatch
    assertExists(promptsTab)
    promptsTab.click()

    let allPrompts = app.buttons["全部"].firstMatch
    assertExists(allPrompts)
    allPrompts.click()

    let promptRow = app.buttons["填写安全代码审查"].firstMatch
    assertExists(promptRow)
    promptRow.click()

    assertExists(app.staticTexts["使用「安全代码审查」"].firstMatch)
    assertExists(app.staticTexts["这次内容面向谁？"].firstMatch)
    assertExists(app.staticTexts["要处理哪段代码？"].firstMatch)

    let audience = app.textViews["prompt-variable-input-目标用户"].firstMatch
    let code = app.textViews["prompt-variable-input-代码"].firstMatch
    assertExists(audience)
    assertExists(code)
    audience.click()
    audience.typeText("开发者")
    code.click()
    code.typeText("let value = input")

    let pasteButton = app.buttons["paste-completed-prompt"].firstMatch
    assertExists(pasteButton)
    pasteButton.click()

    assertPasteboardStringEquals("请审查以下代码，面向 开发者：\n\nlet value = input")
    assertNotExists(app.buttons["填写安全代码审查"].firstMatch)
  }

  func testNewCopyIsAdded() {
    popUpWithMouse()
    let copy3 = UUID().uuidString
    copyToClipboard(copy3)
    assertExists(items[copy3])
    app.typeKey(.escape, modifierFlags: [])
    popUpWithMouse()
    assertExists(items[copy2])
  }

  func testSearch() {
    popUpWithMouse()
    search(copy2)
    assertSearchFieldValue(copy2)
    assertExists(app.staticTexts[copy2])
    assertNotExists(items[copy1])
  }

  func testSearchFiles() {
    copyToClipboard(file2)
    copyToClipboard(file1)
    popUpWithMouse()
    search(file2.lastPathComponent)
    assertExists(items[file2.absoluteString.removingPercentEncoding!])
    assertNotExists(items[file1.absoluteString.removingPercentEncoding!])
  }

  func testCopyWithClick() {
    popUpWithMouse()
    scrollIntoViewIfNeeded(items[copy2].firstMatch)
    items[copy2].firstMatch.click()
    assertPasteboardStringEquals(copy2)
  }

  func testCopyWithEnter() {
    popUpWithMouse()
    scrollIntoViewIfNeeded(items[copy2].firstMatch)
    hover(items[copy2].firstMatch)
    app.typeKey(.enter, modifierFlags: [])
    assertPasteboardStringEquals(copy2)
  }

  func testCopyWithCommandShortcut() {
    popUpWithMouse()
    app.typeKey("2", modifierFlags: [.command])
    assertPasteboardStringEquals(copy2)
  }

  func testSearchAndCopyWithCommandShortcut() {
    popUpWithMouse()
    search(copy2)
    app.typeKey("1", modifierFlags: [.command])
    assertPasteboardStringEquals(copy2)
  }

  func testCopyImage() {
    copyToClipboard(image2)
    copyToClipboard(image1)
    popUpWithMouse()
    scrollIntoViewIfNeeded(items.matching(imageType).allElementsBoundByIndex[1])
    hoverAndClick(items.matching(imageType).allElementsBoundByIndex[1])
    assertPasteboardDataCountEquals(image2.tiffRepresentation!.count, forType: .tiff)
  }

  func testCopyFile() {
    copyToClipboard(file2)
    copyToClipboard(file1)
    popUpWithMouse()

    XCTAssertEqual(itemTitles[0...1], [
      file1.absoluteString.removingPercentEncoding!,
      file2.absoluteString.removingPercentEncoding!
    ])
    scrollIntoViewIfNeeded(items[file2.absoluteString.removingPercentEncoding!].firstMatch)
    hoverAndClick(items[file2.absoluteString.removingPercentEncoding!].firstMatch)
    assertPasteboardStringEquals(file2.absoluteString, forType: .fileURL)
  }

  func testCopyRTF() {
    copyToClipboard(rtf2, .rtf)
    popUpWithHotkey()
    closePopupByClickingOutside()
    copyToClipboard(rtf1, .rtf)
    popUpWithHotkey()
    XCTAssertEqual(itemTitles[0...1], ["foo", "bar"])
    scrollIntoViewIfNeeded(app.staticTexts["bar"].firstMatch)
    hoverAndClick(app.staticTexts["bar"].firstMatch)
    XCTAssertEqual(pasteboard.data(forType: .rtf), rtf1)
  }

  func testCopyHTML() {
    copyToClipboard(html2, .html)
    copyToClipboard(html1, .html)
    popUpWithMouse()
    XCTAssertEqual(itemTitles[0...1], ["foo", "bar"])
    scrollIntoViewIfNeeded(items["bar"].firstMatch)
    hoverAndClick(items["bar"].firstMatch)
    assertPasteboardDataEquals(html2, forType: .html)
  }

  func testDownArrow() {
    popUpWithMouse()
    app.typeKey(.downArrow, modifierFlags: [])
    app.typeKey(.enter, modifierFlags: [])
    assertPasteboardStringEquals(copy2)
  }

  func testUpArrow() {
    popUpWithMouse()
    app.typeKey(.downArrow, modifierFlags: [])
    app.typeKey(.upArrow, modifierFlags: [])
    app.typeKey(.enter, modifierFlags: [])
    assertPasteboardStringEquals(copy1)
  }

  func testControlJ() {
    popUpWithMouse()
    app.typeKey("j", modifierFlags: [.control])
    app.typeKey(.enter, modifierFlags: [])
    assertPasteboardStringEquals(copy2)
  }

  func testControlK() {
    popUpWithMouse()
    app.typeKey("j", modifierFlags: [.control])
    app.typeKey("k", modifierFlags: [.control])
    app.typeKey(.enter, modifierFlags: [])
    assertPasteboardStringEquals(copy1)
  }

  func testDeleteEntry() {
    popUpWithMouse()
    app.typeKey(.delete, modifierFlags: [.option])
    assertNotExists(items[copy1])

    app.typeKey(.escape, modifierFlags: [])
    popUpWithMouse()
    assertNotExists(items[copy1])
  }

  func testDeleteEntryDuringSearch() {
    popUpWithMouse()
    search(copy2)
    app.typeKey(.delete, modifierFlags: [.option])
    assertNotExists(items[copy2])

    app.typeKey(.escape, modifierFlags: [])
    popUpWithMouse()
    assertNotExists(items[copy2])
  }

  func testClear() {
    popUpWithMouse()
    scrollIntoViewIfNeeded(items[copy2].firstMatch)
    pin(copy2)
    hoverAndClick(app.staticTexts["Clear"].firstMatch)
    confirmClear()
    popUpWithMouse()
    assertNotExists(items[copy1])
    assertExists(items[copy2])
  }

  func testClearDuringSearch() {
    popUpWithMouse()
    search(copy2)
    hoverAndClick(app.staticTexts["Clear"].firstMatch)
    confirmClear()
    popUpWithMouse()
    assertNotExists(items[copy1])
    assertNotExists(items[copy2])
  }

  func testClearAll() {
    popUpWithMouse()
    scrollIntoViewIfNeeded(items[copy2].firstMatch)
    pin(copy2)
    XCUIElement.perform(withKeyModifiers: [.shift]) {
      hoverAndClick(app.staticTexts["Clear all"].firstMatch)
    }
    confirmClear()
    popUpWithMouse()
    assertNotExists(items[copy1])
    assertNotExists(items[copy2])
  }

  func testPin() {
    popUpWithMouse()
    scrollIntoViewIfNeeded(items[copy2].firstMatch)
    pin(copy2)
    XCTAssertEqual(itemTitles[0...1], [copy2, copy1])

    app.typeKey(.escape, modifierFlags: [])
    popUpWithMouse()
    XCTAssertEqual(itemTitles[0...1], [copy2, copy1])
  }

  func testPinDuringSearch() {
    popUpWithMouse()
    search(copy2)
    scrollIntoViewIfNeeded(items[copy2].firstMatch)
    pin(copy2)
    assertSearchFieldValue("")
    XCTAssertEqual(itemTitles[0...1], [copy2, copy1])
  }

  func testUnpin() {
    popUpWithMouse()
    scrollIntoViewIfNeeded(items[copy2].firstMatch)
    pin(copy2)
    pin(copy2)
    XCTAssertEqual(itemTitles[0...1], [copy1, copy2])
  }

  func testRemoveLastWordFromSearchWithControlW() {
    popUpWithMouse()
    search("foo bar")
    app.typeKey("w", modifierFlags: [.control])
    assertSearchFieldValue("foo ")
  }

  func testPasteToSearch() {
    popUpWithMouse()
    app.typeKey("v", modifierFlags: [.command])
    waitForSearch()
    assertSearchFieldValue(copy1)
    assertExists(items[copy1])
    assertNotExists(items[copy2])
  }

  func testDisablesOnOptionClickingMenubarIcon() {
    XCUIElement.perform(withKeyModifiers: .option) {
      app.statusItems.firstMatch.click()
    }

    let copy3 = UUID().uuidString
    let copy4 = UUID().uuidString
    copyToClipboard(copy3)
    copyToClipboard(copy4)

    popUpWithMouse()
    assertNotExists(items[copy3])
    assertNotExists(items[copy4])

    app.typeKey(.escape, modifierFlags: [])
    XCUIElement.perform(withKeyModifiers: .option) {
      app.statusItems.firstMatch.click()
    }
  }

  func testDisablesOnlyForNextCopyOnOptionShiftClickingMenubarIcon() {
    XCUIElement.perform(withKeyModifiers: [.option, .shift]) {
      app.statusItems.firstMatch.click()
    }

    let copy3 = UUID().uuidString
    let copy4 = UUID().uuidString
    copyToClipboard(copy3)
    copyToClipboard(copy4)

    popUpWithMouse()
    assertNotExists(items[copy3])
    assertExists(items[copy4])
  }

  func testCreatesNewCopyOnEnterWhenSearchResultsAreEmpty() {
    popUpWithMouse()
    search("foo bar")
    app.typeKey(.return, modifierFlags: [])
    XCTAssertEqual(pasteboard.string(forType: .string), "foo bar")
    assertExists(items["foo bar"])
  }

  func testOpenAndClose() throws {
    // Simulate the popup hotkey press (Cmd + Shift + C).
    let cDown = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: true)!
    cDown.flags = [.maskCommand, .maskShift]
    cDown.post(tap: .cghidEventTap)

    waitUntilPoppedUp()

    // Release the 'C' key but keep the popup open.
    let cUp = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: false)!
    cUp.flags = [.maskCommand, .maskShift]
    cUp.post(tap: .cghidEventTap)

    waitUntilPoppedUp()

    // Release the 'Shift' key and assert that the popup remains open - "normal" mode.
    let shiftUp = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_Shift), keyDown: false)!
    shiftUp.flags = [.maskCommand] // Command remains active, Shift released
    shiftUp.post(tap: .cghidEventTap)

    waitUntilPoppedUp()

    // Release the 'CMD' key and assert that the popup remains open - "normal" mode.
    let commandUp = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_Command), keyDown: false)!
    commandUp.flags = []
    commandUp.post(tap: .cghidEventTap)

    waitUntilPoppedUp()

    // Press shortcut again and assert the window closes
    cDown.flags = [.maskCommand, .maskShift]
    cDown.post(tap: .cghidEventTap)

    assertPopupDismissed()
  }

  func testOpenAndSelectSecondItem() throws {
    // Simulate the popup hotkey press (Cmd + Shift + C).
    let cDown = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: true)!
    cDown.flags = [.maskCommand, .maskShift]
    cDown.post(tap: .cghidEventTap)

    waitUntilPoppedUp()

    let cUp = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: false)!
    cUp.flags = [.maskCommand, .maskShift]
    cUp.post(tap: .cghidEventTap)

    // Press C 1 more time while keeping the modifier keys pressed
    cDown.post(tap: .cghidEventTap)

    // Release all modifiers keys and assert that the popup closes.
    let modifiersUp = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_Shift), keyDown: false)!
    modifiersUp.flags = []
    modifiersUp.post(tap: .cghidEventTap)

    assertPopupDismissed()
    assertPasteboardStringEquals(copy2)
  }

  func testOpenAndSelectThirdItem() throws {
    copyToClipboard(copy3)

    // Simulate the popup hotkey press (Cmd + Shift + C).
    let cDown = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: true)!
    cDown.flags = [.maskCommand, .maskShift]
    cDown.post(tap: .cghidEventTap)

    waitUntilPoppedUp()

    let cUp = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: false)!
    cUp.flags = [.maskCommand, .maskShift]
    cUp.post(tap: .cghidEventTap)

    // Press C 2 more times while keeping the modifier keys pressed
    cDown.post(tap: .cghidEventTap)
    cUp.post(tap: .cghidEventTap)
    cDown.post(tap: .cghidEventTap)

    // Release all modifiers keys and assert that the popup closes.
    let modifiersUp = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_Shift), keyDown: false)!
    modifiersUp.flags = []
    modifiersUp.post(tap: .cghidEventTap)

    assertPopupDismissed()
    assertPasteboardStringEquals(copy2)
  }

  func testOpenAndSelectThirdItemRepeatedPress() throws {
    copyToClipboard(copy3)

    // Simulate the popup hotkey press (Cmd + Shift + C).
    let cDown = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: true)!
    cDown.flags = [.maskCommand, .maskShift]
    cDown.post(tap: .cghidEventTap)

    waitUntilPoppedUp()

    // Press C 2 more times while keeping the modifier keys pressed
    cDown.post(tap: .cghidEventTap)
    cDown.post(tap: .cghidEventTap)

    // Release all modifiers keys and assert that the popup closes.
    let modifiersUp = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_Shift), keyDown: false)!
    modifiersUp.flags = []
    modifiersUp.post(tap: .cghidEventTap)

    assertPopupDismissed()
    assertPasteboardStringEquals(copy2)
  }

  func testTogglePopupAndCloseOnClickOutside() {
    popUpWithHotkey()

    closePopupByClickingOutside()
    assertNotExists(items[copy1])

    // Assert that the hotkeys still work
    popUpWithHotkey()

    simulatePopupHotkey()
    assertPopupDismissed()
  }

  private func popUpWithHotkey() {
    simulatePopupHotkey()
    waitUntilPoppedUp()
  }

  private func openPromptPickPanelForPromptTests() {
    let newPromptButton = app.buttons["新建 Prompt"].firstMatch
    if !newPromptButton.exists {
      simulatePopupHotkey()
    }

    if !newPromptButton.waitForExistence(timeout: 3) {
      XCTFail("PromptPick panel did not open")
    }
  }

  // Click outside the popup to close it
  private func closePopupByClickingOutside() {
    let statusBar = app.statusItems.firstMatch
    let coordinate = statusBar.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 10.0))
    coordinate.click()
  }

  private func popUpWithMouse() {
    app.statusItems.firstMatch.click()
    waitUntilPoppedUp()
  }

  private func simulatePopupHotkey() {
    let commandDown = CGEvent(
      keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_Command), keyDown: true)!
    let commandUp = CGEvent(
      keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_Command), keyDown: false)!
    let shiftDown = CGEvent(
      keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_Shift), keyDown: true)!
    let shiftUp = CGEvent(
      keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_Shift), keyDown: false)!
    shiftDown.flags = [.maskCommand]
    shiftUp.flags = [.maskCommand]
    let cDown = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: true)!
    let cUp = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: false)!
    cDown.flags = [.maskCommand, .maskShift]
    cUp.flags = [.maskCommand, .maskShift]
    commandDown.post(tap: .cghidEventTap)
    shiftDown.post(tap: .cghidEventTap)
    cDown.post(tap: .cghidEventTap)
    cUp.post(tap: .cghidEventTap)
    shiftUp.post(tap: .cghidEventTap)
    commandUp.post(tap: .cghidEventTap)
  }

  private func waitUntilPoppedUp() {
    if !app.staticTexts.firstMatch.waitForExistence(timeout: 3) {
      XCTFail("Maccy did not pop up")
    }
  }

  private func assertPopupDismissed() {
    if !app.staticTexts.firstMatch.waitForNonExistence(timeout: 3) {
      XCTFail("Maccy did not dismiss")
    }
  }

  private func copyToClipboard(_ content: String) {
    pasteboard.clearContents()
    pasteboard.setString(content, forType: .string)
    waitTillClipboardCheck()
  }

  private func copyToClipboard(_ content: NSImage) {
    pasteboard.clearContents()
    pasteboard.setData(content.tiffRepresentation, forType: .tiff)
    waitTillClipboardCheck()
  }

  private func copyToClipboard(_ content: URL) {
    pasteboard.clearContents()
    pasteboard.setData(content.dataRepresentation, forType: .fileURL)
    // WTF: The subsequent writes to pasteboard are not
    // visible unless we explicitly read the last one?!
    pasteboard.string(forType: .fileURL)
    waitTillClipboardCheck()
  }

  private func copyToClipboard(_ content: Data?, _ type: NSPasteboard.PasteboardType) {
    pasteboard.clearContents()
    pasteboard.setData(content, forType: type)
    waitTillClipboardCheck()
  }

  // Default interval for Maccy to check clipboard is 1 second
  private func waitTillClipboardCheck() {
    usleep(1_500_000)
  }

  private func pin(_ title: String) {
    hover(items[title].firstMatch)
    app.typeKey("p", modifierFlags: [.option])
    usleep(1_500_000)
  }

  private func hoverAndClick(_ element: XCUIElement) {
    let coordinate = element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
    coordinate.hover()
    usleep(200_000)
    coordinate.click()
  }

  private func scrollIntoViewIfNeeded(_ element: XCUIElement) {
    guard element.exists else {
      return
    }

    let container = app.scrollViews["history-scroll-view"].firstMatch
    guard container.exists else {
      return
    }

    var attempts = 0
    while !container.frame.contains(element.frame) && attempts < 15 {
      // Negative deltaY scrolls down (reveals elements below the viewport).
      let delta: CGFloat = element.frame.midY > container.frame.midY ? -10 : 10
      container.scroll(byDeltaX: 0, deltaY: delta)
      usleep(100_000)
      attempts += 1
    }
  }

  private func hover(_ element: XCUIElement) {
    element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25)).hover()
    usleep(50_000)
    element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).hover()
    usleep(200_000)
  }

  private func search(_ string: String) {
    // NOTE: app.typeText is broken in Sonoma and causes some
    //       Chars to be submitted with a .command mask (e.g. 'p', 'k' or 'j')
    string.forEach {
      app.typeKey("\($0)", modifierFlags: [])
    }
    waitForSearch()
  }

  private func waitForSearch() {
    // NOTE: This is a hack and is flaky.
    // Ideally we should wait for a proper condition to detect that search has settled down.
    usleep(500000)  // wait for search throttle
  }

  private func assertExists(_ element: XCUIElement) {
    expectation(for: NSPredicate(format: "exists = 1"), evaluatedWith: element)
    waitForExpectations(timeout: 3)
  }

  private func assertNotExists(_ element: XCUIElement) {
    expectation(for: NSPredicate(format: "exists = 0"), evaluatedWith: element)
    waitForExpectations(timeout: 3)
  }

  private func assertNotVisible(_ element: XCUIElement) {
    expectation(
      for: NSPredicate(format: "(exists = 0) || (isHittable = 0)"), evaluatedWith: element)
    waitForExpectations(timeout: 3)
  }

  private func assertPasteboardDataEquals(
    _ expected: Data?, forType: NSPasteboard.PasteboardType = .string
  ) {
    let predicate = NSPredicate { (object, _) -> Bool in
      guard let copy = object as? Data else {
        return false
      }

      return self.pasteboard.data(forType: forType) == copy
    }
    expectation(for: predicate, evaluatedWith: expected)
    waitForExpectations(timeout: 3)
  }

  private func assertPasteboardDataCountEquals(
    _ expected: Int, forType: NSPasteboard.PasteboardType = .string
  ) {
    let predicate = NSPredicate { (object, _) -> Bool in
      guard let count = object as? Int else {
        return false
      }

      return self.pasteboard.data(forType: forType)!.count == count
    }
    expectation(for: predicate, evaluatedWith: expected)
    waitForExpectations(timeout: 3)
  }

  private func assertPasteboardStringEquals(_ expected: String?, forType: NSPasteboard.PasteboardType = .string) {
      let predicate = NSPredicate { (object, _) -> Bool in
        guard let copy = object as? String else {
          return false
        }
        return self.pasteboard.string(forType: forType) == copy
      }
      expectation(for: predicate, evaluatedWith: expected)
      waitForExpectations(timeout: 3)
    }

  private func assertSearchFieldValue(_ string: String) {
    XCTAssertEqual(app.textFields.firstMatch.value as? String, string)
  }

  private func confirmClear() {
    let button = app.dialogs.firstMatch.buttons["Clear"].firstMatch
    expectation(for: NSPredicate(format: "isHittable = 1"), evaluatedWith: button)
    waitForExpectations(timeout: 3)
    button.click()
  }
}
// swiftlint:enable type_body_length
// swiftlint:enable file_length
