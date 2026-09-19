2026-Sep-15 r1.6.4
  Fixed: clicking an autocomplete suggestion left the code editor unfocused
    - Clicking (unlike Enter/Tab) blurs the EditBox first, so keystrokes
      right after a click-accept fell through to the game's own keybinds
      instead of continuing to type. Focus is now restored after accepting.
    - That same blur had armed a deferred cleanup timer that would fire a
      moment later and wipe out the fill-mode/signature-help state just
      set up for a click-accepted function -- now cancelled when accepting

2026-Sep-14 r1.6.3
  Fixed: autocomplete suggestions didn't highlight on mouse hover
    - The list only ever showed the keyboard-navigated (Up/Down) selection;
      hovering now also moves that selection, matching the highlight-then-
      accept convention used elsewhere in the addon (Macro/Snippet lists)

2026-Sep-14 r1.6.2
  Fixed: clicking an autocomplete suggestion still didn't insert it
    - r1.6.1 fixed missing click registration, but a second bug remained:
      clicking the row blurs the EditBox first (standard WoW behavior),
      which fired OnEditFocusLost synchronously and cleared the
      suggestion list before the row's own click finished, so
      AcceptSuggestion always found nothing left to accept. The cleanup
      is now deferred slightly so the click completes first.

2026-Sep-14 r1.6.1
  Fixed: clicking an autocomplete suggestion closed the list without
    inserting anything
    - The suggestion row buttons never called RegisterForClicks, so
      OnClick wasn't firing -- every other clickable list row in this
      addon (Snippets, Macros, dropdown menus) does this; the new
      suggestion rows were the one that missed it. Clicking now behaves
      the same as pressing Enter on the highlighted item.

2026-Sep-14 r1.6.0
  New: Signature help + parameter auto-fill for autocomplete
    - Typing inside a call's parens now shows a live signature hint with
      the current parameter highlighted, sourced from the same live API
      data as completion (APIBrowserData)
    - Accepting a function completion now inserts its real parameter
      names (when known) instead of empty parens, with the first one
      pre-highlighted -- type to replace it, Tab to move to the next
    - Correctly identifies the *enclosing* call when a call is nested
      inside another (e.g. completing inside `foo(bar(1,2), |)`)
    - Functions with no known argument data (anything from the API
      browser's _G-scan fallback) keep the existing bare "()" behavior --
      no popup, no fill mode, nothing to hint
    - Added APIBrowserData:GetEntryByFullName and a shared
      DF.Util:TokenizeLua for this and future editor tooling

2026-Sep-14 r1.5.1
  Fixed: accepting an autocomplete suggestion could duplicate/misplace
    prior characters
    - Root cause: FAIAP's syntax highlighter caches decoded text and only
      refreshes it on its own ~0.2s idle timer -- an independent race
      against autocomplete's own debounce, so reading text and cursor
      position separately could combine a stale full text with a fresh
      cursor position. Both are now read from a single consistent snapshot
      (CodeEditBox:GetTextAndCursor)
  Improved: function completions now insert "()" with the cursor placed
    between the parens, ready for arguments (events/tables insert just
    the bare name, matching how they're actually used)

2026-Sep-14 r1.5.0
  New: Autocomplete against the live WoW API in editable code editors
    - Type a dotted/colon chain (e.g. "C_Item.") to see a ranked, capped
      suggestion list sourced from APIBrowserData's live API index
    - Up/Down to navigate, Enter/Tab to accept, Escape to dismiss
    - Available in the Snippet Editor's code editor and Frame Builder's
      code pane; scoped to WoW API members only (not local variables or
      other snippets' functions)
    - Added CodeEditBox:JumpToOffset/GetTextBeforeCursor, correctly
      accounting for FAIAP's syntax-highlighting color codes so positions
      stay accurate once highlighting has run

2026-Sep-14 r1.4.2
  Fixed: Inspector could crash selecting some unit frames (e.g. EllesmereUI)
    - Util:IsFullscreenFrame compared a frame's GetWidth/GetHeight result
      directly, which can be a WoW 12.0 secret number on some frames -- a
      pcall around the call doesn't protect against the *returned value*
      itself throwing on comparison; now checked via SecretGuard first

2026-Sep-14 r1.4.1
  Fixed: Macro Editor's macro list had no search/filter box
    - Added a "Filter macros..." search box above the list, matching Snippets/CVars/Events
  Fixed: Inspector's Registered Events / Scripts sections could crash on a secret boolean
    - IsEventRegistered/HasScript results now go through SecretGuard:SafeGet instead of a
      bare pcall (the crash is on testing the *returned* value, not the call itself)
  Fixed: Table Viewer's "load more" pagination could miss circular references
    - reused a stale/empty ancestor-tracking table instead of a snapshot of the real one,
      so a cycle reachable only through a later page wasn't always caught

2026-Sep-14 r1.4.0
  New: Frame Builder's code pane is now editable, with two-way sync
    - Hand-edit generated code directly; a debounced parser (built on the
      vendored FAIAP Lua tokenizer) reads recognized statements back into
      the property panel, elements list, and live preview
    - Hand-written script handler bodies (OnShow/OnEvent/etc.) and any
      trailing custom code are preserved verbatim across future visual-side
      edits instead of being overwritten by the canned placeholder
    - If the code doesn't parse (e.g. the frame header is missing/garbled),
      a status line says so and the visual model is left untouched

2026-Sep-14 r1.3.0
  Changed: Frame Builder is now embedded in the Snippet Editor instead of a popup
    - "Frame Builder" creates a dedicated snippet shown as a Code | Preview split
      with a right-hand property pane (root settings, toolbox, elements, properties)
    - The preview is a real embedded canvas now, not a floating overlay -- no more
      strata fights with the editor window
    - A snippet's element layout (builderState) now persists across tabs/reloads,
      instead of being thrown away after the old popup's "Insert as Snippet"

2026-Sep-14 r1.2.0
  New: Frame Builder multi-element form designer (phase 1)
    - Toolbox to add Button/CheckBox/EditBox/Label/Slider child elements onto the
      frame being built, with a live canvas preview alongside the code preview
    - Click an element on the canvas or in the sidebar list to select it; a
      dynamic property panel edits its X/Y position and type-specific fields
    - Generated code covers the whole composed element tree, not just the root
      frame; element variable names stay stable even after mid-list deletes
    - Drag-to-position and event/script binding are planned for a later phase

2026-Sep-14 r1.1.0
  Removed: WeakAuras converter (WAImporter module)
    - Dropped WA export decode/codegen and the Editor's "WA Import" button
  Fixed: SendChatMessage replaced with C_ChatInfo.SendChatMessage in Console
    - Console now uses the non-deprecated chat API for /say, /yell, /whisper

2026-Aug-12 r1.0.17
  Fixed: Interface version corrected to 120100 for patch 12.1.0 — the previous value
         made the addon show as incompatible in the addon manager
    - Addon scaffold and WeakAuras importer templates emit "## Interface: 120100"

2026-Aug-11 r1.0.16
  Improved: Interface version bumped to 120100 for patch 12.1.0
    - Addon scaffold and WeakAuras importer templates now emit "## Interface: 120100"

2026-Mar-30 r1.0.13
  Fixed: BugGrabber integration for current versions using EventRegistry API
    - BugGrabber dropped CallbackHandler-1.0 in favor of Blizzard EventRegistry
    - DevForge now supports both EventRegistry and legacy CallbackHandler paths
    - Fires BugGrabber.DisplayRegistered to suppress duplicate chat output

2026-Mar-12 r1.0.12
  Improved: TextureBrowser functionality and versioning updates

2026-Feb-25 r1.0.11
  New: Sound Browser module
    - Browse SoundKit IDs by category (auto-read from SOUNDKIT global, grouped by prefix)
    - FileID range explorer with async playability scanning
    - Live capture tab hooks PlaySound, PlaySoundFile, and PlayMusic calls
    - Play/stop controls with single-active-sound management and auto-reset polling
    - Favorites and recent lists persisted to SavedVariables
    - Context menu: Copy ID, Copy PlaySound/PlaySoundFile/PlayMusic code, Insert to editor
    - Search across all sources (kits, file IDs, live captures, favorites)
  Improved: API Browser detail view
    - Security labels (callable vs protected) instead of raw internal values
    - Default values shown on arguments and fields
    - Mixin type annotations on arguments (e.g. ItemLocationMixin)
    - InnerType shown for table returns (e.g. table<number>)
    - MayReturnNothing flag with explanation
    - Event LiteralName shown as copyable RegisterEvent string
    - Synchronous event timing indicator
    - Enumeration range info (count, min, max)
    - Per-field documentation on structures and enum values
    - Namespace environment and documentation
    - Insert Call now uses documented default values for argument placeholders
  Fixed: API Browser Documentation field crash when value was a table instead of string

2026-Feb-3 r1.0.0 Initial stable public release