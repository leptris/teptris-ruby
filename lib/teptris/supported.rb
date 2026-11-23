# frozen_string_literal: true

module Teptris
  # The native-layer contract's SSOT (issue #197): the ruby minors
  # the release train builds and packs, per platform. The workflows
  # consume this file — release-matrix's plan job emits their matrix
  # values and runtime lookups from it, and CI's doctrine gate
  # asserts no inlined list drifts from it. Never inline a minor
  # list in a workflow; add it here.
  DEFAULT_MINORS = %w[3.3 3.4 4.0].freeze

  # Platforms whose minor set differs from DEFAULT_MINORS. The
  # windows legacy-DLL ladder (a PE DLL binds its build Ruby's
  # runtime, so mingw32 carries the 3.0-4.0 ladder), the arm64 ucrt
  # pair, and the emulated musl tiers' single-minor policy (qemu
  # training costs minutes; one gem beats none).
  MINORS_BY_PLATFORM = {
    "x64-mingw32" => %w[3.0],
    "x64-mingw-ucrt" => %w[3.1 3.2 3.3 3.4 4.0],
    "aarch64-mingw-ucrt" => %w[3.4 4.0]
  }.freeze

  # The minors for one platform (the lookup every consumer uses).
  def self.minors_for(platform)
    MINORS_BY_PLATFORM.fetch(platform, DEFAULT_MINORS)
  end

  # The union a build CELL compiles: one runner may pack several
  # platform gems (x64-mingw32 + x64-mingw-ucrt share the windows
  # x64 cell), so its compile ladder is the sorted union of their
  # gem-content sets.
  def self.minors_ladder(platforms)
    list = platforms.is_a?(Array) ? platforms : platforms.split
    list.flat_map { |p| minors_for(p) }.uniq.sort
  end

  # The workflow-format map ("plat:min_a_min_b ..." — underscores
  # between minors, the assemble-fat table's shape).
  def self.minors_map(platforms)
    platforms.map { |p| "#{p}:#{minors_for(p).join("_")}" }.join(" ")
  end
end
