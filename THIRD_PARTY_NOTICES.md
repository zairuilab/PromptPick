# Third-Party Dependency Inventory

This inventory reflects the exact Swift package versions pinned for the
PromptPick MVP. It was verified against the license files in the resolved local
checkouts. Corresponding license texts are preserved in `THIRD_PARTY_LICENSES/`.

| Dependency | Version | License | Source |
|---|---:|---|---|
| Maccy | commit `02dd0a3` | MIT | https://github.com/p0deje/Maccy |
| Defaults | 8.2.0 | MIT | https://github.com/sindresorhus/Defaults |
| fuse-swift | 1.4.0 | MIT | https://github.com/krisk/fuse-swift |
| KeyboardShortcuts | 2.0.2 | MIT | https://github.com/sindresorhus/KeyboardShortcuts |
| LaunchAtLogin-Modern | 1.1.0 | MIT | https://github.com/sindresorhus/LaunchAtLogin-Modern |
| Sauce | 2.4.1 | MIT | https://github.com/Clipy/Sauce |
| Settings | 3.1.1 | MIT | https://github.com/sindresorhus/Settings |
| Sparkle | 2.6.4 | MIT-style permissive | https://github.com/sparkle-project/Sparkle |
| swift-log | 1.6.4 | Apache-2.0 | https://github.com/apple/swift-log |
| SwiftHEXColors | 1.4.1 | MIT | https://github.com/thii/SwiftHEXColors |

PromptPick currently disables the upstream Maccy update feed. Sparkle remains
linked as inherited infrastructure but has no PromptPick feed configured.

The dependency names and licenses remain the property of their respective
copyright holders. This inventory is provided for attribution and license
compliance; it does not imply endorsement of PromptPick.
