# DevForge Architecture

> 76 files, ~26,000 lines of Lua.
> Bundled libraries: LibStub, LibDeflate, LibSerialize (for WA import decoding).
> No Ace3 or external frameworks.

---

## High-Level Architecture

```mermaid
graph TB
    subgraph Entry["Entry Points"]
        SLASH["/devforge  /df  /dl  /lua  /apii"]
        COMP["Addon Compartment Button"]
        LOADED["ADDON_LOADED Event"]
    end

    subgraph Libs["Bundled Libraries"]
        LSTUB["LibStub"]
        LDEFLATE["LibDeflate"]
        LSERIALIZE["LibSerialize"]
    end

    subgraph Core["Core Layer"]
        INIT["Init.lua<br/>Slash commands, Toggle, Show"]
        CONST["Constants.lua<br/>Colors, Fonts, Layout"]
        SG["SecretGuard.lua<br/>issecretvalue / canaccessvalue"]
        UTIL["Util.lua<br/>PrettyPrint, DeepCopy, Debounce"]
        EB["EventBus.lua<br/>Internal pub/sub"]
        MS["ModuleSystem.lua<br/>Register, Activate, Lazy-load"]
        IB["IntegrationBus.lua<br/>Cross-module actions"]
    end

    subgraph SV["SavedVariables"]
        SCHEMA["Schema.lua<br/>Defaults, Migration"]
        DB[(DevForgeDB)]
    end

    subgraph UI["UI Framework"]
        THEME["Theme.lua<br/>Backdrop helpers, Fonts"]
        MW["MainWindow.lua<br/>HIGH strata, Resize grip"]
        AB["ActivityBar.lua<br/>Vertical icon strip"]
        SBR["Sidebar.lua<br/>Module list panel"]
        BP["BottomPanel.lua<br/>Shared Output / Problems"]
        subgraph Widgets
            BTN[Button]
            SP[ScrollPane]
            SB[SearchBox]
            CEB[CodeEditBox]
            TV[TreeView]
            PG[PropertyGrid]
            SPL[SplitPane]
            DD[DropDown]
            CPD[CopyDialog]
        end
    end

    subgraph Modules["Modules (Lazy-loaded)"]
        ERR["ErrorHandler<br/>Lua error capture"]
        CON["Console<br/>REPL + History"]
        INS["Inspector<br/>Pick + Tree + Props"]
        API["API Browser<br/>Blizzard Docs"]
        TBV["TableViewer<br/>Deep inspect tables"]
        CVR["CVarViewer<br/>CVar browser"]
        SNP["Editor<br/>Snippet CRUD + Templates"]
        WAI["WAImporter<br/>WA decode + codegen"]
        EVT["Events<br/>Monitor + Index"]
        PERF["Performance<br/>Addon profiling"]
        MAC["MacroEditor<br/>Macro CRUD"]
        TEX["Textures<br/>Browser + Preview"]
    end

    SLASH --> INIT
    COMP --> INIT
    LOADED --> SCHEMA
    SCHEMA --> DB
    INIT --> MS
    MS --> |first tab click| Modules
    MS --> |MODULE_ACTIVATED| EB
    EB --> SBR
    INIT --> MW
    MW --> AB
    MW --> SBR
    MW --> BP
    MW --> |content area| Modules
    Modules --> Widgets
    Modules --> UTIL
    Modules --> SG
    Modules --> DB
    IB --> EB
    WAI --> Libs
```

---

## Load Order & Boot Sequence

```mermaid
sequenceDiagram
    participant WoW as WoW Client
    participant TOC as TOC Loader
    participant Init as Init.lua
    participant Schema as Schema.lua
    participant MS as ModuleSystem
    participant MW as MainWindow
    participant Mod as Module (lazy)

    WoW->>TOC: Load DevForge.toc
    TOC->>TOC: LibStub, LibDeflate, LibSerialize
    TOC->>TOC: Constants.lua (colors, layout)
    TOC->>Init: Init.lua (frame, slash cmds)
    TOC->>TOC: SecretGuard, Util, EventBus, ModuleSystem
    TOC->>Schema: Schema.lua (registers PLAYER_LOGOUT)
    TOC->>TOC: Theme, Widgets, ActivityBar, Sidebar, BottomPanel, MainWindow
    TOC->>TOC: IntegrationBus.lua
    TOC->>TOC: All Module files (Register only, no UI)

    Note over TOC: All files loaded. WoW fires ADDON_LOADED.

    WoW->>Init: ADDON_LOADED "DevForge"
    Init->>Schema: Schema.Init()
    Schema->>Schema: Apply defaults to DevForgeDB
    Schema->>Schema: Run migrations
    Init->>Init: ErrorHandler.Init() (hook seterrorhandler)
    Init->>Init: EventBus.Fire(DF_ADDON_LOADED)

    Note over Init: Addon is ready. No UI created yet.

    WoW->>Init: User types /devforge
    Init->>MW: DF.CreateMainWindow()
    MW->>MW: Create HIGH frame, title bar, activity bar, sidebar, bottom panel
    MW->>MS: ModuleSystem.Activate(Console)

    MS->>Mod: factory() first-time creation
    Mod->>Mod: Create frames, wire widgets
    MS->>Mod: OnFirstActivate()
    MS->>Mod: OnActivate()
    MS->>Init: EventBus.Fire(MODULE_ACTIVATED)
```

---

## Module Lifecycle

```mermaid
stateDiagram-v2
    [*] --> Registered : ModuleSystem.Register(name, factory, tabLabel)
    Registered --> Creating : First tab click / DF.Show(name)
    Creating --> Active : factory() returns instance
    Active --> Active : OnActivate() on each tab switch in
    Active --> Inactive : OnDeactivate() on tab switch away
    Inactive --> Active : OnActivate() on return

    note right of Registered
        Factory function stored.
        No frames created.
        No memory used.
    end note

    note right of Creating
        factory() called once.
        OnFirstActivate() fires.
        Instance cached forever.
    end note
```

### Module Registry

| Internal Name    | Tab Label    | Slash Command         | Files |
|------------------|--------------|-----------------------|-------|
| `ErrorHandler`   | Errors       | `/df errors`, `/dl`   | 4     |
| `Console`        | Console      | `/df console`, `/lua` | 5     |
| `Inspector`      | Inspector    | `/df inspect`, `/df pick` | 6  |
| `APIBrowser`     | API Browser  | `/df api`, `/apii`    | 5     |
| `TableViewer`    | Tables       | (via IntegrationBus)  | 2     |
| `CVarViewer`     | CVars        | (via sidebar)         | 2     |
| `SnippetEditor`  | Editor       | `/df editor`          | 7     |
| `WAImporter`     | WA Import    | (via Editor scaffold) | 3     |
| `EventMonitor`   | Events       | `/df events`          | 4     |
| `Performance`    | Perf         | `/df perf`            | 3     |
| `MacroEditor`    | Macros       | `/df macros`          | 3     |
| `TextureBrowser` | Textures     | `/df textures`        | 5     |

---

## Console Execution Flow

```mermaid
flowchart TD
    INPUT["User types code + Enter"]
    HIST["ConsoleHistory:Add(code)"]
    HOOK["Hook global print()"]

    EXPR{"loadstring('return ' .. code)"}
    STMT{"loadstring(code)"}
    PCALL["pcall(fn)"]

    RESTORE["ALWAYS restore print()"]
    FORMAT["FormatResults()"]
    OUTPUT["BottomPanel shared output"]

    INPUT --> HIST --> HOOK
    HOOK --> EXPR
    EXPR -->|parse OK| PCALL
    EXPR -->|parse fail| STMT
    STMT -->|parse OK| PCALL
    STMT -->|parse fail| FORMAT

    PCALL -->|success| RESTORE
    PCALL -->|error| RESTORE
    RESTORE --> FORMAT --> OUTPUT

    style RESTORE fill:#2d5a2d,stroke:#4a4
```

### Print Capture Safety

```
origPrint = print
print = capture_function
    DoExecute()      -- wrapped in pcall
print = origPrint    -- ALWAYS runs, even on internal error
```

---

## Inspector Data Flow

```mermaid
flowchart LR
    subgraph Pick["Picker Mode"]
        SCREEN["Fullscreen TOOLTIP frame"]
        MOUSE["OnUpdate: GetMouseFocus()"]
        HL["InspectorHighlight<br/>Blue overlay + label"]
        CLICK["Left-click: select"]
    end

    subgraph Tree["Tree Panel"]
        WALK["Walk GetParent() to root"]
        BUILD["GetChildren() + GetRegions()"]
        TREEVIEW["TreeView widget"]
    end

    subgraph Props["Property Panel"]
        SEC["SecretGuard:SafeGet()"]
        SECT["Build sections:<br/>Identity, Geometry,<br/>Strata, Anchors,<br/>Events, Scripts"]
        GRID["PropertyGrid widget"]
    end

    subgraph Overlay["Grid Overlay"]
        GUIDEL["Guide lines at frame edges"]
        DIMS["Dimension labels"]
        PIXGRID["Screen pixel grid"]
    end

    SCREEN --> MOUSE --> HL
    HL --> CLICK
    CLICK --> WALK --> BUILD --> TREEVIEW
    TREEVIEW -->|node click| SEC --> SECT --> GRID
    TREEVIEW -->|node click| HL
    TREEVIEW -->|node click| Overlay
```

### Secret Value Handling

```mermaid
flowchart TD
    READ["frame:GetSomeProperty()"]
    PCALL{"pcall()"}
    SECRET{"issecretvalue(result)?"}
    ACCESS{"canaccessvalue(fn)?"}

    OK["Return value"]
    ERR["Return [error]"]
    REDACT["Return [secret] in red"]
    DENIED["Return access denied"]

    READ --> ACCESS
    ACCESS -->|yes| PCALL
    ACCESS -->|no| DENIED
    PCALL -->|error| ERR
    PCALL -->|ok| SECRET
    SECRET -->|yes| REDACT
    SECRET -->|no| OK

    style REDACT fill:#5a1a1a,stroke:#a44
    style DENIED fill:#5a1a1a,stroke:#a44
```

---

## API Browser Data Pipeline

```mermaid
flowchart TD
    LOAD["C_AddOns.LoadAddOn<br/>'Blizzard_APIDocumentation'"]
    OBJ["C_AddOns.LoadAddOn<br/>'Blizzard_ObjectAPI'"]
    QUERY["APIDocumentation:GetAllSystems()"]
    MERGE["Merge ObjectAPI systems"]

    INDEX["Build flat index<br/>name, fullName, system, type, doc"]
    SORT["Sort by fullName"]

    TREE["BuildTreeNodes()<br/>Namespace > Functions/Events/Tables"]
    SEARCH["APIBrowserSearch:Find(query)<br/>Substring match name + desc"]
    DETAIL["APIBrowserDetail:ShowEntry()<br/>Signature, params, returns"]

    LOAD --> QUERY
    OBJ --> MERGE
    QUERY --> MERGE --> INDEX --> SORT
    SORT --> TREE
    SORT --> SEARCH
    TREE --> DETAIL
    SEARCH --> DETAIL
```

---

## WAImporter Pipeline

```mermaid
flowchart TD
    subgraph Decode["WADecode.lua"]
        INPUT["WA export string"]
        BASE64["LibDeflate:DecodeForPrint()"]
        DECOMP["LibDeflate:DecompressDeflate()"]
        DESER["LibSerialize:Deserialize()"]
        ANALYZE["AnalyzeAura()<br/>Normalize triggers, config,<br/>authorOptions, textures,<br/>conditions, custom code"]
    end

    subgraph CodeGen["WACodeGen.lua"]
        TOC["GenerateTOC()<br/>.toc manifest"]
        INIT["GenerateInit()<br/>SavedVars, load guards,<br/>per-aura frame code"]
        OPTS["GenerateOptions()<br/>Settings API controls"]
    end

    subgraph AuraTypes["Per-Aura Code Generation"]
        ICON["GenIconAura<br/>Frame + Texture + Cooldown"]
        BAR["GenAuraBarAura<br/>StatusBar + timer OnUpdate"]
        TEXT["GenTextAura<br/>FontString + dynamic text"]
        TEXTURE["GenTextureAura<br/>Frame + Texture + rotation"]
    end

    subgraph Shared["Shared Emitters"]
        ENV["EmitAuraEnv<br/>aura_env.config + DB overlay"]
        STUBS["EmitWAStubs<br/>WA API compatibility shim"]
        CUSTOM["EmitCustomCode<br/>init/onShow/onHide"]
        TRIG["GenTriggerCode<br/>aura2/status/custom/event"]
        ONUPD["EmitCustomTriggerOnUpdate<br/>Throttled polling + cursor follow"]
        COND["BuildConditionLines<br/>Color/fontSize conditions"]
        TEXCALL["TextureCall<br/>Atlas vs path + WA texture subs"]
    end

    subgraph Options["Options Generation"]
        SLIDER["EmitRangeOption<br/>Settings.CreateSlider"]
        TOGGLE["EmitToggleOption<br/>Settings.CreateCheckbox"]
        SELECT["EmitSelectOption<br/>Settings.CreateDropdown"]
        COLOR["EmitColorEditor<br/>Standalone floating panel"]
        DESC["EmitDescriptionOption<br/>Section headers"]
    end

    INPUT --> BASE64 --> DECOMP --> DESER --> ANALYZE
    ANALYZE --> TOC
    ANALYZE --> INIT
    ANALYZE --> OPTS

    INIT --> AuraTypes
    AuraTypes --> Shared

    OPTS --> Options

    style Decode fill:#1e2a3a,stroke:#4a6a8a
    style CodeGen fill:#1e2a3a,stroke:#4a6a8a
```

### WAImporter aura_env & Config Flow

```
WA authorOptions (decoded)
    |
    v
ExtractAuthorOptions()       -- normalize to {type, key, name, default, ...}
ExtractConfig()              -- raw config key/value pairs (incl. table values)
    |
    v
CollectConfigDefaults()      -- merge authorOptions defaults + raw config fallback
    |
    v
GenerateInit():
    db.config.key = default   -- per-key if-nil initialization in SavedVariables
    aura_env.config = {...}   -- baked defaults inside each aura's do-block
    db.config overlay         -- for k,v in pairs(db.config) do aura_env.config[k] = v end
    |
    v
GenerateOptions():
    Settings API controls     -- range/toggle/select bind to db.config[key]
    Color editor panel        -- standalone BackdropTemplate frame with swatches
    ns.RefreshConfig()        -- no-op stub; config changes require /reload
```

### WA Texture Substitution

| WA Bundled Texture      | Substitution                          |
|-------------------------|---------------------------------------|
| `Circle_Smooth2`        | `Interface\COMMON\Indicator-Gray`     |
| `Circle_Smooth`         | `Interface\COMMON\Indicator-Gray`     |
| `Square_White`          | `Interface\BUTTONS\WHITE8X8`          |
| (unknown WA texture)    | `INV_Misc_QuestionMark` + TODO comment|

---

## Event Monitor Architecture

```mermaid
flowchart TD
    subgraph Capture["Capture Engine"]
        CF["captureFrame (hidden Frame)"]
        REG["RegisterEvent() x 40+ events"]
        HANDLER["OnEvent: push to ring buffer"]
    end

    subgraph Log["EventMonitorLog"]
        RING["Ring buffer (max 2000)"]
        FILTER["EventMonitorFilter<br/>Blacklist + Whitelist"]
        FMT["FormatEntry(): timestamp + event + args"]
    end

    subgraph Live["Live Log View"]
        SBOX["SearchBox: filter by name"]
        OUT["ConsoleOutput: scrolling text"]
    end

    subgraph Browse["Browse / Reference View"]
        IDX["EventIndex<br/>~230 events, 28 categories"]
        BTREE["TreeView: category > events"]
        BDETAIL["Detail panel:<br/>description, payload, usage"]
        MONITOR["Monitor This button"]
    end

    CF --> HANDLER --> FILTER --> RING
    RING --> FMT --> OUT
    SBOX --> OUT

    IDX --> BTREE --> BDETAIL
    MONITOR -->|"add event to captureFrame"| REG

    TOGGLE{{"Browse / Live Log toggle"}}
    TOGGLE --> Live
    TOGGLE --> Browse
```

---

## Snippet Editor Data Model

```mermaid
erDiagram
    DevForgeDB ||--o{ Snippet : "snippets[]"
    DevForgeDB {
        string lastSnippetId
    }
    Snippet {
        string id PK "s_{GetTime()}_{counter}"
        string name "User-editable"
        string code "Lua source"
        number modified "GetTime() timestamp"
    }
```

```mermaid
flowchart LR
    subgraph Store["SnippetStore (data layer)"]
        CREATE["Create(name)"]
        SAVE["Save(id, name, code)"]
        DELETE["Delete(id)"]
        DUP["Duplicate(id)"]
        GETALL["GetAll() sorted by modified"]
    end

    subgraph Templates["Template System"]
        TDATA["TemplateData<br/>Built-in addon templates"]
        TBROWSE["TemplateBrowser<br/>Category tree + preview"]
        FBUILDER["FrameBuilder<br/>Visual frame code gen"]
        SCAFFOLD["AddonScaffold<br/>Full addon project gen"]
    end

    subgraph UI["SnippetEditor UI"]
        LIST["SnippetList<br/>Left panel"]
        NAME["Name EditBox"]
        CODE["CodeEditBox<br/>Multi-line"]
        OUTPUT["Bottom panel output"]
        RUN["Run button"]
    end

    LIST -->|click| SAVE
    LIST -->|click| UI
    RUN --> SAVE
    RUN -->|ConsoleExec:Execute()| OUTPUT
    CREATE --> LIST
    DELETE --> LIST
    DUP --> LIST
    TBROWSE -->|"insert template"| CODE
    FBUILDER -->|"insert frame code"| CODE
    SCAFFOLD -->|"generate project"| CPD["CopyDialog"]
```

---

## UI Frame Hierarchy

```mermaid
graph TD
    UI["UIParent"]
    MW["DevForgeMainWindow<br/>HIGH strata, BackdropTemplate"]
    TITLE["Title Bar<br/>Drag to move"]
    CLOSE["Close Button"]
    RESIZE["Resize Grip<br/>Bottom-right"]
    ACTBAR["ActivityBar<br/>Vertical icon strip (left edge)"]
    SIDEBAR["Sidebar<br/>Module list panel"]
    BOTTOM["BottomPanel<br/>Output + Problems tabs"]
    CONTENT["Content Area"]

    UI --> MW
    MW --> TITLE
    MW --> CLOSE
    MW --> RESIZE
    MW --> ACTBAR
    MW --> SIDEBAR
    MW --> BOTTOM
    MW --> CONTENT

    ACTBAR --> A1["Console"]
    ACTBAR --> A2["Inspector"]
    ACTBAR --> A3["API Browser"]
    ACTBAR --> A4["Tables"]
    ACTBAR --> A5["CVars"]
    ACTBAR --> A6["Editor"]
    ACTBAR --> A7["Events"]
    ACTBAR --> A8["Perf"]
    ACTBAR --> A9["Macros"]
    ACTBAR --> A10["Textures"]
    ACTBAR --> A11["Errors"]

    CONTENT --> |"active module.frame"| MOD["Module Frame<br/>(SetAllPoints content)"]

    style MW fill:#1e1e24,stroke:#666
    style CONTENT fill:#1e1e24,stroke:#444
```

---

## Widget Composition Patterns

```mermaid
graph TD
    subgraph ScrollPane
        SF["ScrollFrame"]
        SC["Content Frame"]
        SB["Scrollbar Track"]
        TH["Draggable Thumb"]
        SF --> SC
        SB --> TH
    end

    subgraph TreeView
        SP2["ScrollPane (internal)"]
        ROWS["Pooled row buttons"]
        FLAT["flatList[] (visible nodes)"]
        EXP["expanded{} (id -> bool)"]
    end

    subgraph SplitPane
        P1["Panel 1 (left/top)"]
        SPLITTER["Splitter bar<br/>Drag to resize"]
        P2["Panel 2 (right/bottom)"]
    end

    subgraph PropertyGrid
        SP3["ScrollPane (internal)"]
        HROWS["Header rows"]
        PROWS["Property rows<br/>key | value"]
    end

    subgraph CopyDialog
        OVERLAY["Fullscreen backdrop"]
        DIALOG["Dialog frame<br/>FULLSCREEN_DIALOG strata"]
        CODE["CodeEditBox (read-only)"]
        COPYBTN["Copy + Close buttons"]
    end
```

---

## EventBus & IntegrationBus Message Flow

```mermaid
flowchart LR
    subgraph Publishers
        INIT["Init.lua"]
        MS["ModuleSystem"]
        MW["MainWindow"]
        MODS["Modules"]
    end

    subgraph EventBus["EventBus"]
        ADDON["DF_ADDON_LOADED"]
        LOGOUT["DF_PLAYER_LOGOUT"]
        MODACT["MODULE_ACTIVATED"]
        RESIZE["WINDOW_RESIZED"]
    end

    subgraph IntegrationBus["IntegrationBus"]
        INSERT["DF_INSERT_TO_EDITOR"]
        VIEWTBL["DF_VIEW_TABLE"]
        VIEWERR["DF_VIEW_ERROR"]
    end

    subgraph Subscribers
        SCHEMA["Schema.lua"]
        SIDEBAR["Sidebar.lua"]
        EDITOR["SnippetEditor"]
        CONSOLE["Console"]
        TBLVIEW["TableViewer"]
    end

    INIT -->|fire| ADDON
    INIT -->|fire| LOGOUT
    MS -->|fire| MODACT
    MW -->|fire| RESIZE
    MODS -->|fire| INSERT
    MODS -->|fire| VIEWTBL

    LOGOUT -->|on| SCHEMA
    MODACT -->|on| SIDEBAR
    INSERT -->|on| EDITOR
    INSERT -->|on| CONSOLE
    VIEWTBL -->|on| TBLVIEW
```

---

## SavedVariables Lifecycle

```mermaid
sequenceDiagram
    participant WoW as WoW Client
    participant Schema as Schema.lua
    participant DB as DevForgeDB
    participant Modules as Modules

    WoW->>Schema: ADDON_LOADED
    Schema->>DB: Read persisted table
    Schema->>DB: Apply DEFAULTS for missing keys
    Schema->>DB: Run version migrations

    loop During Play
        Modules->>DB: Read/write consoleHistory
        Modules->>DB: Read/write snippets
        Modules->>DB: Read/write window pos/size
        Modules->>DB: Read/write sidebar/bottom state
    end

    WoW->>Schema: PLAYER_LOGOUT
    Schema->>DB: Trim consoleHistory to 200
    WoW->>WoW: Serialize DevForgeDB to disk
```

---

## Slash Command Router

```mermaid
flowchart TD
    CMD["/df <args>"]
    PARSE["strtrim + lower"]

    EMPTY{"empty?"}
    TOGGLE["DF:Toggle()"]

    KNOWN{"known command?"}
    CONSOLE["Show Console"]
    INSPECT["Show Inspector + Picker"]
    APIB["Show API Browser"]
    EDITOR["Show Editor"]
    EVENTS["Show Events"]
    TEXTURES["Show Textures"]
    ERRORS["Show ErrorHandler"]
    PERF["Show Performance"]
    MACROS["Show MacroEditor"]
    GRID["Show Inspector + Toggle Grid"]
    RESET["Reset Window Position"]

    DUMP{"starts with 'dump '?"}
    EXEC_DUMP["Execute expression<br/>Pretty-print to BottomPanel"]

    FALLBACK["Execute as Lua<br/>in Console"]

    CMD --> PARSE --> EMPTY
    EMPTY -->|yes| TOGGLE
    EMPTY -->|no| KNOWN

    KNOWN -->|console| CONSOLE
    KNOWN -->|inspect / pick| INSPECT
    KNOWN -->|api| APIB
    KNOWN -->|editor| EDITOR
    KNOWN -->|events| EVENTS
    KNOWN -->|textures| TEXTURES
    KNOWN -->|errors| ERRORS
    KNOWN -->|perf| PERF
    KNOWN -->|macros| MACROS
    KNOWN -->|grid| GRID
    KNOWN -->|reset| RESET
    KNOWN -->|no match| DUMP

    DUMP -->|yes| EXEC_DUMP
    DUMP -->|no| FALLBACK
```

### Additional Slash Aliases

| Command   | Target              |
|-----------|---------------------|
| `/dl`     | Show ErrorHandler   |
| `/apii`   | Show API Browser    |
| `/lua`    | Show Console (optional inline code) |

---

## Error Handling Strategy

```
Layer             Guard                        Behavior
---------------------------------------------------------------------------
WoW API calls     pcall() everywhere           Return nil + error string
Secret values     issecretvalue() + pcall       Display [secret] in red
Frame properties  SecretGuard:SafeGet()         Graceful [error] display
Event callbacks   EventBus pcall per handler    Log to DF.ErrorLog, continue
User code exec    loadstring + pcall            Show error in Console output
Print hijacking   Outer pcall + always-restore  Never leaves print broken
Module creation   pcall(factory)                Print error, skip module
Addon loading     pcall(LoadAddOn)              Show fallback message
Grid drawing      Loop cap (4000 lines)         Prevent infinite loops
Resize handlers   Width > 0 guards              Skip layout on zero-size
Font creation     _G lookup before CreateFont   Survives /reload
Lua errors        seterrorhandler hook           Capture to ErrorHandler module
```

### ErrorHandler Module

```mermaid
flowchart TD
    subgraph Capture["Error Capture"]
        HOOK["seterrorhandler() hook"]
        FILTER["Deduplicate + timestamp"]
        STORE["Error list (ring buffer)"]
    end

    subgraph UI["ErrorHandler UI"]
        LIST["ErrorList<br/>Scrollable error entries"]
        DETAIL["ErrorDetail<br/>Stack trace + locals"]
        MONITOR["ErrorMonitor<br/>Background error count badge"]
    end

    HOOK --> FILTER --> STORE
    STORE --> LIST
    LIST -->|click| DETAIL
    STORE --> MONITOR
```

---

## File Map

```
DevForge/                          (76 files, ~26,000 lines)
  DevForge.toc                     TOC manifest + load order

  Libs/                            Bundled libraries (3 files)
    LibStub/
      LibStub.lua                  Standard WoW library loader
    LibDeflate/
      LibDeflate.lua               Compression (for WA import)
    LibSerialize/
      LibSerialize.lua             Serialization (for WA import)

  Core/                            Foundation (7 files)
    Constants.lua                  Colors, fonts, layout dimensions
    Init.lua                       Boot, slash commands, addon compartment
    SecretGuard.lua                12.x secret value wrappers
    Util.lua                       String helpers, PrettyPrint, Debounce
    EventBus.lua                   Internal pub/sub with error logging
    ModuleSystem.lua               Lazy module registry + tab activation
    IntegrationBus.lua             Cross-module actions (insert, view table)

  SavedVariables/                  Persistence (1 file)
    Schema.lua                     Defaults, migrations, logout trim

  UI/                              Framework (15 files)
    Theme.lua                      Backdrop helpers, font cache
    ActivityBar.lua                Vertical icon strip (left edge)
    Sidebar.lua                    Module list / navigation panel
    BottomPanel.lua                Shared Output + Problems tabs
    MainWindow.lua                 HIGH frame, drag, resize, ESC close
    Widgets/
      Button.lua                   Dark styled button
      ScrollPane.lua               ScrollFrame + thumb scrollbar
      SearchBox.lua                EditBox + placeholder + debounce
      CodeEditBox.lua              Multi-line code input with Tab=4spaces
      TreeView.lua                 Virtual-scroll expandable tree
      PropertyGrid.lua             Two-column sectioned key/value
      SplitPane.lua                Resizable horizontal/vertical split
      DropDown.lua                 Context menu (no UIDropDownMenu)
      CopyDialog.lua               Fullscreen copy-to-clipboard dialog

  Modules/ErrorHandler/            Error capture (4 files)
    ErrorHandler.lua               Orchestrator, seterrorhandler hook
    ErrorList.lua                  Scrollable error entry list
    ErrorDetail.lua                Stack trace + context display
    ErrorMonitor.lua               Background error count badge

  Modules/Console/                 Lua REPL (5 files)
    ConsoleHistory.lua             Ring buffer, Up/Down, persistence
    ConsoleExec.lua                loadstring + pcall, print capture
    ConsoleOutput.lua              Scrollable colored output
    ConsoleInput.lua               Input line with prompt
    Console.lua                    Orchestrator

  Modules/Inspector/               Frame Inspector (6 files)
    InspectorHighlight.lua         Blue overlay rectangle
    InspectorPicker.lua            Fullscreen pick via GetMouseFocus
    InspectorTree.lua              Parent/child hierarchy builder
    InspectorProps.lua             Property sections (6 groups)
    InspectorGrid.lua              Pixel grid + frame guide lines
    Inspector.lua                  Orchestrator

  Modules/APIBrowser/              API Reference (5 files)
    APIBrowserData.lua             Load Blizzard docs + ObjectAPI
    APIBrowserSearch.lua           Substring search across all entries
    APIBrowserList.lua             Namespace tree + search box
    APIBrowserDetail.lua           Signature, params, returns display
    APIBrowser.lua                 Orchestrator

  Modules/TableViewer/             Deep table inspector (2 files)
    TableDump.lua                  Recursive table serialization
    TableViewer.lua                Tree-based table browser

  Modules/CVarViewer/              CVar browser (2 files)
    CVarData.lua                   CVar metadata + categories
    CVarViewer.lua                 Searchable CVar list + detail

  Modules/SnippetEditor/           Code Snippets (7 files)
    SnippetStore.lua               CRUD for persistent snippets
    SnippetList.lua                Scrollable snippet name list
    TemplateData.lua               Built-in addon code templates
    TemplateBrowser.lua            Category tree + template preview
    FrameBuilder.lua               Visual frame code generator
    AddonScaffold.lua              Full addon project generator
    SnippetEditor.lua              Orchestrator with Run/Save/Delete

  Modules/WAImporter/              WeakAuras converter (3 files)
    WADecode.lua                   Decode + analyze WA export strings
    WACodeGen.lua                  Generate standalone addon from analysis
    WAImporter.lua                 Import dialog UI

  Modules/EventMonitor/            Event Tools (4 files)
    EventMonitorLog.lua            Ring buffer + blacklist/whitelist
    EventIndex.lua                 230 events, 28 categories, search
    EventMonitorFilter.lua         Filter configuration UI
    EventMonitor.lua               Live log + Browse reference

  Modules/Performance/             Addon profiling (3 files)
    PerfData.lua                   GetAddOnCPUUsage / memory collection
    PerfTable.lua                  Sortable addon performance table
    PerfMonitor.lua                Orchestrator

  Modules/MacroEditor/             Macro management (3 files)
    MacroStore.lua                 Macro CRUD via WoW macro API
    MacroList.lua                  Scrollable macro list
    MacroEditor.lua                Orchestrator with icon picker

  Modules/TextureBrowser/          Asset Browser (5 files)
    TextureAtlasData.lua           Atlas name database (~469 KB)
    TextureIconData.lua            Icon path database
    TextureRuntime.lua             Runtime texture lookup helpers
    TextureIndex.lua               Categorized texture paths + atlas
    TextureBrowser.lua             Grid preview with size toggle
```
