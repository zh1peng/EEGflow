# Prep Job JSON (EEGflow)

Top-level fields:
- `steps` (required): array of step objects
- `Options` (optional): e.g., `{ "validate_only": false }`

Each step object:
- `id`   string
- `name` string
- `op`   string (must match a prep op name)
- `args` object (parameters; can be empty)

Minimal example:

```json
{
  "steps": [
    { "id":"S001", "name":"Load", "op":"load_set",
      "args": { "filename":"", "filepath":"" } },
    { "id":"S002", "name":"Filter", "op":"filter",
      "args": { "LowCutoff":0.5, "HighCutoff":30 } },
    { "id":"S003", "name":"BadChannels", "op":"remove_bad_channels",
      "args": { "Action":"remove" } },
    { "id":"S004", "name":"Save", "op":"save_set",
      "args": { "filename":"", "filepath":"" } }
  ],
  "Options": { "validate_only": false }
}
```

Housekeeping fields (auto-injected by `prep.setup_io`):
- `filename`/`filepath` for `load_set/load_mff` and `save_set`
- `LogFile` for most steps
- `LogPath` for `remove_bad_channels` and `remove_bad_ICs`

Keep these out of JSON unless you have a special reason to override them.
