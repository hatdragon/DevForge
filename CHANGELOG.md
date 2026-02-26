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