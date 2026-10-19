# CLAUDE.md — teptris-ruby

## Mission

Be the best TOML parser and builder ever made — in C, Ruby, Rust, and
JS — measured, not claimed. This binding's bar, and the family
ledger/plan, live in the engine's
[BEST-EVER.md](https://github.com/leptris/teptris/blob/main/BEST-EVER.md).
"At parity" or "unmeasured" is an open gap.

## Operating laws (this binding)

- Version = `{engine version}.{binding iteration}` (current: 0.3.4.1 =
  engine 0.3.4, iteration 1). The engine pin is
  `LIBTEPTRIS_VERSION` in the `Rakefile` — **a version bump moves the
  pin in the same PR**.
- Releases: dispatch `release.yml` with EMPTY `next_version` (tags the
  current VERSION), batched train, RubyGems OIDC.
- Every release is gated by a published-gem smoke: install from
  rubygems, `Teptris::TOML.load`, the 601-deep plan probe
  (`TeptrisExt.plan_build(rows, first_row)` with `[name, kind, sub]`
  triples must reject with `Teptris::Error`), and zero bytes on
  stdout/stderr.
- API shape mirrors `tomlib` (`Teptris::TOML.load/safe_load/dump`);
  the native extension IS the binding — no fallback, ever.
- Bench doctrine: vs the best native competitor (tomlrb head-to-head
  is an open ledger gap), best-of-≥40, numbers carry date+host.
- All changes through PRs (rebase-merge); specs + armhf/qemu lanes
  gate the merge.
