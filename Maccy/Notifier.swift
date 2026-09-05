import AppKit

class Notifier {
  // Clipboard content must never appear in system notifications or on the lock screen.
  // Keep only the optional local sound feedback inherited from the clipboard engine.
  static func notify(body: String?, sound: NSSound?) {
    _ = body
    sound?.play()
  }
}
