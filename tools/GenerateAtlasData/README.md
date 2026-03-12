# GenerateAtlasData

Generates `TextureAtlasData.lua` for DevForge's TextureBrowser module by fetching the latest atlas names from the [wago.tools](https://wago.tools) UiTextureAtlasMember DB2 table.

## Requirements

- .NET 10 SDK (or later)

## Usage

```
cd tools/GenerateAtlasData
dotnet run -- ../../Modules/TextureBrowser/TextureAtlasData.lua
```

Omit the output path to write to stdout instead.

## When to run

After major WoW patches that add or remove texture atlases. The generator pulls the latest data from wago.tools automatically.

## How it works

1. Fetches CSV from `https://wago.tools/db2/UiTextureAtlasMember/csv`
2. Extracts the `CommittedName` column (atlas name strings)
3. Categorizes each name into buckets using prefix/substring pattern rules (first match wins)
4. Outputs a Lua file with categories sorted alphabetically (Miscellaneous last), atlas names sorted alphabetically within each category, 3 per line
