# Concord

A clean, minimal macOS app (SwiftUI) that lets you chat through the model-routing
gateway of your choice — in the spirit of Claude Cowork / OpenWork.

Pick a provider on the home screen, paste your API keys in Settings, and chat.

## Providers

| Provider    | Status     | Base URL                        | Key       |
| ----------- | ---------- | ------------------------------- | --------- |
| OrcaRouter  | ✅ Available | `https://api.orcarouter.ai/v1`  | `sk-orca-…` |
| OpenRouter  | ✅ Available | `https://openrouter.ai/api/v1`  | `sk-or-…` |
| Featherless | ✅ Available | `https://api.featherless.ai/v1` | `rc_…`    |
| Concurred   | ✅ Available | `https://concurred.ai/api/v1`   | `ck_…`    |

All four providers are OpenAI-compatible (streaming chat + live model catalog) and
share one `ChatClient`, configured per-provider in `Provider.swift`. Every provider
has an API-key field in **Settings** (stored in the macOS Keychain).

### Chat features

- **Rich rendering** of assistant replies: Markdown (headings, lists, quotes, bold/
  italic/inline-code, links), fenced **code blocks** with a Copy button, and inline
  **images** (`![alt](url)`, including `data:` base64 URIs). No external dependencies —
  see `Views/MarkdownView.swift`.
- **Per-chat model picker** with the live catalog plus an **Enter model ID…** option
  (top of the menu) to type any slug the provider serves.
- **Saved conversations** with a sidebar (new / rename / delete / switch), persisted
  to `~/Library/Application Support/dev.october.concord/conversations.json`.

## Run it

**In Xcode** (recommended):

```
open Concord.xcodeproj
```

Then select the **Concord** scheme and press ⌘R. On first run Xcode signs it with
"Sign to Run Locally" automatically.

**From the command line:**

```
xcodebuild -project Concord.xcodeproj -scheme Concord -configuration Debug build
open ~/Library/Developer/Xcode/DerivedData/Concord-*/Build/Products/Debug/Concord.app
```

- Requires macOS 14+ and Xcode 16+ (built & verified against Xcode 26 / macOS 26, Swift 5 language mode).

## Using OrcaRouter

1. Get an API key at [orcarouter.ai](https://www.orcarouter.ai) (keys start with `sk-orca-`).
2. Open **Settings** (gear icon, or ⌘,) and paste it under **OrcaRouter → Save**.
3. Back on the home screen, click the **OrcaRouter** card.
4. Pick a model (the live catalog loads from `/v1/models`; a fallback list is used
   if it can't be reached) and send a message. Responses stream in.

OrcaRouter is OpenAI-compatible, so this uses `POST https://api.orcarouter.ai/v1/chat/completions`
with `Authorization: Bearer <key>`.

## Project layout

```
Concord.xcodeproj            # uses Xcode's synchronized file-system groups
Concord/
  App.swift                  # @main App + Settings scene (⌘,)
  Models/
    Provider.swift           # the 4 providers + status (available/closed)
    ChatModels.swift         # ChatMessage + OpenAI-compatible wire types
  Services/
    SecretStore.swift        # Keychain-backed API-key storage
    OrcaRouterClient.swift    # OrcaRouter client (streaming + model list)
  State/
    AppStore.swift           # navigation + key state (@Observable)
  ViewModels/
    ChatViewModel.swift      # one chat session
  Views/
    ContentView.swift        # home grid + provider cards
    ChatScreen.swift         # chat UI, bubbles, empty/missing-key states
    SettingsForm.swift       # per-provider API-key editor
  Assets.xcassets            # accent color
```

## Adding a provider in v2

Each closed provider becomes available by:

1. Flipping its `status` to `.available` in `Provider.swift`.
2. Adding a client alongside `OrcaRouterClient` (OpenRouter, Featherless and
   Concurred all expose OpenAI-compatible `/chat/completions` endpoints, so the
   existing client is largely reusable — parameterize the base URL, or introduce a
   small `ChatClient` protocol).
3. Pointing `ChatViewModel` at the right client for the selected provider.
