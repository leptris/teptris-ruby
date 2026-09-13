# teptris descriptor ABI (v1, reserved)

Fused schema-descriptor materialization: the same descriptor shape as
leptris/yeptris#238, so a framework compiles descriptors once per
model and runs them on every engine. This entry point is reserved
(`Teptris::TOML.load_schema`); the fused native pass lands with the
co-designed ABI, versioned and lockstep with the binding
(`{c-semver}.{binding-patch}`).

## Descriptor (flat, positional, C-friendly array of node plans)

```
{ wire_name,            # str
  kind,                 # :scalar | :collection | :nested | :callback
  type_tag,             # :int | :float | :bool | :string | :date | ...
  child_plan_index,     # for :nested / :collection
  flags }               # optional/merge/rename controls
```

## Contract (mirrors the yeptris #238 requirements)

1. **Escape hatch**: `kind: :callback` returns the raw value plus the
   node position; Ruby finishes just those fields. The bulk fuses.
2. **The descriptor is an ABI, not a schema language** — two-names-
   one-slot merges, value maps, renames and raw capture are the
   caller's compiled plan's job, not XSD/JSON-Schema.
3. **Versioned + lockstep**, whole-document results only — never per
   value across the FFI boundary.
4. TOML's tree is hash-shaped: the KV value path (the flat drain
   buffer, `teptris_document_flatten`) is the shared materialization
   substrate for the whole KV family; the descriptor pass shapes it
   into typed results without materializing the intermediate Hash.
