# App audit — September 19, 2026

The audit covered every application source file, the Xcode project, persistence,
provider transport, search/cloaking, and the native SwiftUI screens.

## Findings addressed

| Area | Finding | Implemented change |
| --- | --- | --- |
| Reply lifecycle | Stop enabled Send before the old task finished; late deltas could modify a new reply. | Request identity guards and synchronous finalization before a new request. |
| Navigation | Leaving a chat kept its request alive. Shared multiwindow navigation could also create concurrent editors. | Cancel on disappearance; one main workspace window. |
| Deletion | A late response recreated a deleted conversation. | Store updates require an existing conversation. |
| Recovery | Failures left no way to retry without repeating the question. | Retry replaces only the last reply. |
| Credentials | Open chats continued using the old API key after Settings changed it. | Observe key changes, stop old requests, rebuild the client. |
| Keychain | Delete-then-add could lose the old key, and errors appeared as successful saves. | Update in place; throwing reads/writes; cached state changes only after success. |
| Storage | Read/write errors were discarded; corrupt data could be overwritten. | Visible errors, protected failed loads, atomic saves and explicit retry. |
| Streaming storage | Only the initial question and finished response were saved. Empty placeholders were persisted. | Periodic partial-response checkpoints; exclude empty assistant placeholders. |
| Drafts | Switching chats discarded unsent text. | Session-scoped drafts held by the conversation store. |
| Empty chats | New Chat could create duplicates when an older empty chat existed. | Reuse any empty conversation for that provider. |
| SSE | Line-by-line decoding ignored event framing, malformed chunks, and disconnected responses. | Bounded UTF-8 parser with CR/LF, comments, multiline events, explicit errors, and completion checks. |
| HTTP | Sessions were not invalidated, error bodies were unbounded, and redirects could move sensitive requests. | Ephemeral sessions with cleanup, bounded error reads, response validation, redirect rejection. |
| Model selection | Stale fallback models, duplicate IDs, and huge menus obscured catalog failures. | Live unique catalog, searchable picker, refresh, visible errors, manual IDs. |
| Search privacy | Search received the original prompt before Cloak ran. | Apply Cloak before both search and provider requests, including returned grounding text. |
| Search lifecycle | A detached process ignored cancellation, had no deadline, and could block on stderr. | Cancellable process with timeout and output limit; explicit search errors. |
| Cloak correctness | Substitutions cascaded through injected values, modified parts of words, and could reverse ambiguously. | One-pass range replacements, word boundaries, stable per-session mappings, unique generated substitutions, identity validation. |
| Privacy copy | UI claimed personal data stayed only in Keychain and that cloaking guaranteed privacy. | Explain best-effort detection and original-text chat storage. |
| Network | Invalid enabled-proxy settings silently connected directly. | Validate host/port/header values at save and request time; fail closed. |
| Network UI | Scope was misleading and save feedback was missing. | User-Agent presets plus a custom value, validation, save feedback, and explicit provider-only proxy scope. |
| Long messages | Text was silently truncated at 8,000 characters. | Explicit expandable previews; complete copy; visible streaming-tail notice. |
| Markdown | Ordered lists always started at 1 and longer/tilde fences parsed incorrectly. | Preserve list starts and fence boundaries; copy individual code blocks. |
| Links | Markdown could expose arbitrary local/custom-scheme links. | Limit actionable links to HTTP, HTTPS and mailto. |
| UI | Hidden save failures, whitespace keys, immediate deletion, narrow composer, unlabeled icon controls. | Inline status/errors, trimmed keys, delete confirmation, minimum chat width, accessible labels and keyboard shortcuts. |
| Obsolete code | Closed-provider paths, compatibility decoder, unused file logger, outdated setup docs. | Remove obsolete paths and rewrite documentation around the implemented product. |

## Follow-up adjustments

Restored the User-Agent preset menu at the user's request. Alt ID now uses an
owner-only local JSON file and does not access Keychain, so opening or saving it
does not require a Keychain password prompt. API keys continue using Keychain.
No legacy identity import or fallback is added; old Keychain entries are untouched.

## Messages-style UI pass

Updated the provider picker, resizable sidebar, conversation header and composer.
The sidebar shows avatars, message previews, dates and unsent drafts. Outgoing
bubbles use a consistent blue with white text; incoming replies adapt to light and
dark appearances. Copy controls stay visible below bubbles, and right-click copy
remains available. Alt ID and Network (with the restored User-Agent presets) are
direct buttons alongside the model picker, documentation and Settings. The header
wraps in narrow windows instead of hiding tools in an overflow menu. Sidebar
spacing is tighter, and the oversized empty-chat greeting is removed. The composer
stays at the bottom in both new and existing chats, matching the Messages layout.

Scrolling upward pauses automatic following and reveals Jump to latest. Follow
and Retry are visible below the composer when a conversation has messages. Empty
conversations no longer react to transcript scrolling or show Jump to latest. Native
List virtualization is retained. A three-dot response indicator respects Reduce
Motion. Error banners include Retry when possible. Native render checks cover both
appearances, the minimum 820×560 window size, 480-point chat panes and empty/full
conversations in a large 1440×900 workspace.

## Validation

All 81 regression tests pass, covering local identity storage and permissions, HTTP without contacting providers, request
races, web-search/cloaking boundaries, subprocess cancellation and stderr handling,
file failures, Markdown and native view rendering. Debug and optimized Release
builds pass with Xcode 26.0.1 on macOS 26 (Apple silicon). No Swift compiler warnings
remain; Xcode emits only its informational App Intents metadata warning because
the app does not use App Intents.

Native render checks use isolated in-memory credentials and temporary chat files.
Home, Settings, chat, and message layouts are inspected at constrained sizes. Provider
billing, external service uptime, actual account entitlements, and a real proxy
server are outside these deterministic checks. Image references remain explicit
links; the README no longer claims inline image loading that the app did not implement.

## Branding and Keychain prompts

Renamed the app, executable, Xcode project, scheme and tests to Concurred. The supplied
snowflake image is packaged as the macOS AppIcon at all required sizes and as the
home-screen logo. Persistent bundle/storage identifiers remain unchanged.

Previous runs disabled code signing and loaded every provider key at startup. Builds
now use the installed Developer ID Application identity, with a stable designated
requirement across Debug and Release. App startup performs no secret reads; only the
selected provider's key is loaded, with cached results for the session. A denied read
requires an explicit retry. Settings offers per-provider loading instead of reading
every saved key. API keys stay in Keychain; no ACLs are weakened or keys exported.

Follow-up inspection of existing provider items found two stale restrictions: their
trusted-app entries referenced the old unsigned Concord build, and their signing
partitions retained that build's exact code hash. The three provider items' trusted
apps were repaired to point to signed Concurred. A separate signed verification
process satisfying Concurred's designated requirement still received `errSecAuthFailed`
with password UI disabled. macOS also refused the signing-partition update without
authorization. The permission repair is therefore incomplete until the user grants
Always Allow to Concurred; stable code signing alone does not repair these old items.
No API-key values were printed or exported, and the temporary read-verification
executable was removed.

## Cloak name restoration

Exact-only reverse substitutions missed responses that shortened an alt full name.
Cloak now retains typed name mappings and derives first-name forms in both directions.
`Harsh` → `Chloe Stone` restores both `Chloe Stone` and `Chloe` to `Harsh`; a configured
full real name also masks first-name-only prompts. Explicit outgoing pairs take
priority over inferred aliases, and ambiguous incoming aliases are not guessed.
The Name field uses given-name-first order; recognized titles are skipped, while
hyphenated first names stay intact instead of relying on Foundation's unreliable
full-name ordering inference. Name aliases respect word boundaries, casing,
possessives, whitespace and straight/typographic apostrophes. Emails and URLs are
handled as whole values instead of inserting name fragments into them.

Streaming buffers incomplete alias suffixes, including splits within words and
between first/family names; completion and cancellation flush the final restored
text. Mappings remain stable after identity edits. Validation rejects alt values
that contain the configured real first name. Tests cover the reported example,
streaming and persistence, subsequent outgoing history, Cloak toggles, collisions,
compound names, explicit custom forms, links and long literals. Arbitrary nicknames,
translations and semantic references remain outside deterministic substitution.


## Input, clipboard and Cloak follow-up (2026-09-20)

- Replaced the SwiftUI composer field with a native plain-text editor. Shift-Return
  and Command-Shift-Return insert a newline at the cursor; Return/Command-Return
  send. IME composition and pasted multiline text never trigger Send. Removed the
  competing window-level Send shortcut; repeated Return cannot send twice.
- Message bubbles use one selectable native attributed-text view per visible row.
  Selection spans paragraphs/code, Command-C exports plain text, Copy exports the
  full readable message, and Copy Markdown preserves the original reply source.
- Cloak activates explicitly configured variants connected through shorter pairs.
  The user's three-part-name → two-part-name reply example is covered, including
  every streamed character boundary; percentages and surrounding text are preserved.
- Replaced automatic random fake numbers/emails with typed placeholders and exact
  restoration. Credit-card detection checks the checksum; bare ten-digit numbers
  require phone context. This reduces corruption of amounts and timestamps, at the
  cost of requiring explicit review for ambiguous identifiers.
- Review Cloak uses Apple's local Natural Language entity recognition and address
  detection to suggest exact phrases. Additional replacements are selected by the
  user; a live outgoing preview and local map show what will be sent. Sending uses
  the reviewed snapshot for chat/search. Cancellation leaves the active vault alone;
  stale drafts are rejected. No generative rewrite or cloud PII detector was added.
- Tests cover actual modifier events, IME, selection/clipboard types, multiline
  content, configured name variants, placeholder round-trips, local suggestions,
  review cancellation/staleness and request/response boundaries. Render checks
  include the new review and a multiline composer at the minimum chat-pane width.

Detection remains best effort, not a guarantee of anonymity. Automatic local entity
suggestions vary with language and OS models. Ordinary sends still work directly;
Review Cloak is an explicit optional step. Additional hidden phrases stay only in
this conversation's in-memory map; saved chats continue to contain original text.

The provider home screen was restored to an adaptive card grid at the user's request, with the Concurred name/logo, provider descriptions, cached key status and hover feedback. The existing home render check covers the minimum window and a larger dark-mode window.


## Conversation portraits and home layout

Bundled the 35 user-supplied October portraits (10.webp–44.webp), preserving the
artwork as PNG assets. A stable weighted choice from the random conversation UUID
keeps portraits consistent across list updates and restarts without changing chat
storage. Images 20–44 each receive four times the weight of images 10–19. The
selected conversation uses the same portrait in its header; the provider picker
retains provider icons. Alt ID displays image 44 when Cloak is off and image 43
when on, with a switch bound to the composer's setting.

The home cards now share their header's width and alignment, grow with the window,
and center together vertically. Removed the duplicated unloaded “Open” badge and
improved action-label contrast. Render checks cover minimum and large windows in
light/dark mode, chat portraits, and both Alt ID states. Regression checks cover
portrait stability through serialization, the weighting distribution and all
bundled images decoding successfully.


The Network inspector now has an illustrated header with subtle floating motion,
state-dependent portraits, a route badge, and explicit unsaved-preview text. Proxy
fields transition on toggle. Animations respect macOS Reduce Motion. The header
reports configuration only; no network test or protection claim is implied. Native
render checks cover direct/default, custom User-Agent, and SOCKS5 states at the
minimum inspector width. Existing proxy validation remains unchanged.


The User-Agent section now names the selected preset and shows a native device
illustration: Mac, Windows PC, Android phone, iPhone, terminal or custom client. A
short widening beam and traveling signal dots animate on selection/reselection;
Reduce Motion retains a static illustration. Added Chrome on Android to the preset
catalog. The animation does not generate traffic or claim device emulation. Render
checks cover every preset at narrow inspector width and intermediate Android/Windows
signal frames.
