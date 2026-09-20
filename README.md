# Concurred

A native macOS chat app for OrcaRouter, OpenRouter, Featherless, and Concurred.
Requires macOS 14 or later and Xcode 16 or later. No third-party Swift packages.

## Run

Open `Concurred.xcodeproj`, select the **Concurred** scheme, and press ⌘R. Or:

```sh
xcodebuild -project Concurred.xcodeproj -scheme Concurred -configuration Release \
  -derivedDataPath build/DerivedData build
open build/DerivedData/Build/Products/Release/Concurred.app
```

The app and tests use the installed Developer ID Application certificate for team
`75D25SJRM5`. Keep this signing identity consistent between builds; do not disable
signing for the app you launch. Unsigned/ad-hoc rebuilds can repeatedly trigger
Keychain access prompts because macOS cannot recognize a stable app identity.
On another developer's Mac, configure that developer's signing team in Xcode.

Open Settings (gear icon or ⌘,), save a provider API key, and choose that provider.
The model picker loads its live catalog and supports search, refresh, and a manually
entered model ID. There are no hardcoded model catalogs. If the catalog is unavailable,
refresh it or enter an ID from the provider's documentation.

| Provider | API base URL |
| --- | --- |
| OrcaRouter | `https://api.orcarouter.ai/v1` |
| OpenRouter | `https://openrouter.ai/api/v1` |
| Featherless | `https://api.featherless.ai/v1` |
| Concurred | `https://concurred.ai/api/v1` |

Model availability, access, and billing are controlled by the selected provider.

## Chat

The home screen presents providers in a two-column card grid. The header and cards
share one alignment, expand with the window, and stay centered vertically. Cards
show provider descriptions, loaded key status and a hover highlight.

The workspace uses a Messages-inspired layout: a resizable conversation sidebar
with conversation portraits, previews, dates and draft indicators; blue outgoing bubbles and gray
replies; and a compact composer. Switch providers from the sidebar footer. The
header keeps the model picker, Alt ID, Network, documentation and Settings visible;
it wraps to two rows in narrow windows. The composer stays at the bottom of the
conversation, including in new chats.

Conversation portraits use the supplied October artwork (10–44), bundled with the
app. Each image numbered 20 and above has four times the selection weight of each
older image. The random conversation ID determines a stable portrait shared by the
sidebar and chat header, including after reopening a saved conversation. Alt ID
shows portrait 44 with Cloak off and portrait 43 with Cloak on; its switch controls
the same setting as the composer.

- Streaming replies with Stop and Retry reply. Retry replaces the last reply using
  the current model and options, without duplicating your question.
- Search, rename, and delete saved conversations; ⌘N creates a new chat.
- Return sends; Shift-Return (including ⌘Shift-Return) inserts a newline; ⌘Return also sends.
  Modified Return is handled explicitly in the native editor. Pasting multiple lines
  inserts plain text without sending; Return during input-method composition does not send.
- Markdown headings, lists, quotes, links, and fenced code. Select across paragraphs
  and code and press ⌘C to copy just the selection as plain text. **Copy** copies the
  whole readable message; **Copy Markdown** preserves the reply source. Outgoing
  messages copy exactly as written. Code blocks also have a dedicated Copy control.
  Right-click a bubble to copy the message. Image references are displayed as links, not downloaded.
- Long replies show a preview with **Show more**; copying always includes the entire
  message. During streaming, very long replies show the latest portion.
- Scrolling upward pauses automatic following. **Jump to latest** returns to the
  newest message. The composer’s **Follow** toggle controls automatic following,
  alongside the visible **Retry** action.
- Switching chats or providers stops the active response and saves its partial text.
  Unsent drafts survive chat switches during the current app session.
- API-key changes apply to open chats and cancel any request using the old key.

## Optional web search and Cloak

**Web search** uses a separately installed and authenticated TinyFish CLI at
`/opt/homebrew/bin/tinyfish` or `/usr/local/bin/tinyfish`. Search failures are shown
before a provider request is made; turn off Web search to send without grounding.
Search times out after 30 seconds and stops when the reply is cancelled.

**Cloak** replaces the real/alt pairs configured in the Alt ID panel and recognized
structured values (emails, common phone/SSN formats, checksum-valid card numbers, and IPv4 addresses).
Automatic detections use explicit placeholders such as `[EMAIL_1]`, preserving a local
map back to the original. Unlabelled bare ten-digit numbers and card-like numbers
with invalid checksums are left alone to reduce corruption of timestamps and quantities. These
substitutions run before both web search and chat requests. Names use given-name-first
order and match both the full name and its first name. For example, with `Harsh` →
`Chloe Stone`, both “Hi Chloe!” and “Hi Chloe Stone!” display as “Hi Harsh!”. Matching
is case-insensitive and respects word boundaries; it also handles possessives, name
spacing and typographic apostrophes. Names inside emails use the email substitution; links containing a name
are masked and restored as whole URLs. Other links and identifiers are left alone.

Replies restore mappings used in the conversation and explicitly configured variants
connected by shorter real/alt pairs. For example, when `Harsh` → `John`,
`Harsh Savergaonkar` → `John Stone`, and a three-part-name pair are configured,
a reply using “Mr. John Stone” restores the two-part name even if the prompt only
used the three-part name. Longest matches take precedence. Incomplete aliases
are held back during streaming until they can be restored safely. Ambiguous short
aliases are left unchanged. Nicknames, surname-only references, initials, translations
and other paraphrases cannot always be reversed reliably; use explicit custom pairs
for additional forms you want to match. Save identity edits before sending.

With Cloak on, **Review Cloak** beside the toggle previews the outgoing conversation
before sending. Apple's on-device `NLTagger` proposes names, places and organizations;
`NSDataDetector` also proposes addresses. Select additional exact phrases to hide,
or enter a missed phrase manually. The replacement map and outgoing text update
locally. **Send reviewed message** uses that exact snapshot; a changed draft is
rejected instead of silently sending different text. Web search receives the last
reviewed user message; its results are added and cloaked afterward. Cancelling the
review changes neither the draft nor the conversation's mappings. Additional hidden
phrases last for the conversation during the app session; use Alt ID custom pairs
for persistent choices. No local generative model or cloud detector rewrites text.

Cloak is best effort: it can miss personal information and is not an anonymity
guarantee. API keys are kept in the macOS Keychain. Alt ID opens without a password
and is saved in `~/Library/Application Support/dev.october.concord/alt-identity.json`,
with access restricted to your macOS account. This identity file is not separately
encrypted by the app. Older identities kept only in Keychain are not automatically
imported; re-enter those details in Alt ID if needed.
**Saved conversations contain the original, uncloaked text on this Mac.**

The Network panel offers User-Agent presets (Chrome on macOS/Windows/Android, Safari on macOS/iPhone, Firefox, curl and
system default), an editable custom value, and an HTTP/SOCKS5 proxy for provider
chat and catalog requests. Its illustrated header gently animates and changes with
direct routing, a custom User-Agent or a proxy. It previews settings, not connection
health; unsaved settings are labeled, and macOS Reduce Motion disables motion.
Choosing a preset displays its Mac, Windows PC, Android phone, iPhone or terminal
illustration and sends a brief decorative beam with moving signal dots toward a
globe. Reselecting the same preset replays it. The selected preset name stays visible.
This changes the User-Agent header only; it does not emulate an OS/browser or send
any test traffic. Choose a preset or edit the value, then save. Invalid enabled-proxy settings block requests rather than
silently connecting directly. TinyFish uses its own connection and does not use
this proxy. Provider redirects are rejected to avoid forwarding credentials or
conversation bodies to another endpoint.

## Storage and errors

Conversations are saved atomically to:

```text
~/Library/Application Support/dev.october.concord/conversations.json
```

The app checkpoints partial responses while streaming. Empty chats and empty
assistant placeholders are not written. Storage failures appear in a persistent
banner with Retry and Show saved chats file actions. An unreadable or corrupt file
is kept intact and blocked from overwrite; repair or restore it, then retry.
Keys are updated in place so a failed Keychain write preserves the previous key.
Launching the app does not read any API keys. Opening a provider loads only its key,
which is cached for the session. Settings can explicitly load a saved key per
provider. Denied access is shown with a Retry button and is never retried automatically.
Existing keys may need approval once when switching from the old unsigned app to
the signed build. See [Apple's code-signing guidance](https://developer.apple.com/library/archive/technotes/tn2206/_index.html)
for how Keychain tracks an app's signing identity across updates.

The bundle identifier and storage directory remain `dev.october.concord`: these are
persistent identifiers, not the displayed app name. Renaming the app leaves saved
chats, identity details, settings and Keychain items in place without a migration.

## Test

```sh
xcodebuild -project Concurred.xcodeproj -scheme Concurred \
  -destination 'platform=macOS' test
```

`ConcurredTests` covers streaming HTTP/SSE handling, cancellation and retry races,
cloaking and web-search privacy, network validation, persistence failures, lazy Keychain
loading and explicit retries, Markdown, and native view rendering. Tests use mock HTTP responses,
mock secrets, and temporary conversation files; they do not send paid model requests.
Native render images are attached to the Xcode test results.

## Layout

```text
Concurred/
  App.swift                  Single main window and Settings scene
  Models/                    Providers, conversations, wire types
  Services/                  Chat transport, SSE parser, Keychain, Cloak, search, network
  State/                     App key/navigation state and conversation persistence
  ViewModels/                Chat lifecycle and model selection
  Views/                     Workspace, model picker, messages, settings and inspectors
ConcurredTests/                Regression and native rendering tests
```

See [AUDIT.md](AUDIT.md) for the findings addressed by the audit and verification scope.
