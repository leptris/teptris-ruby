#!/usr/bin/env ruby
# load_batch / load_lazy_batch speedup over per-doc load, three
# many-small shapes. Reported on the lang-tier lane so per-release
# numbers can be tracked.
#
# Perf shape (ubuntu-latest, ruby 3.3, 2026-09-21):
#   * eager load_batch is **not faster** than per-doc load for tiny /
#     medium docs (Ruby method dispatch + JIT amortize the per-doc
#     path; the C batch adds scratch alloc + tight Ruby allocation
#     pressure). Eager load_batch wins for LARGE docs and is a
#     convenience (per-doc error report, shared opts parsing) in
#     every shape.
#   * load_lazy_batch is a real speedup when materialization is
#     deferred — parse-only across the batch, no per-doc Hash
#     construction.
$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "teptris"

# shape 1: tiny — one row each (unitsml-style)
TINY = Array.new(2000) { |i|
  <<~TOML
    id = #{i}
    name = "row-#{i}"
    tags = [1, 2, 3]
  TOML
}

# shape 2: medium — nested tables + arrays of tables
MED = Array.new(500) { |i|
  <<~TOML
    id = #{i}
    title = "row #{i}"
    [meta]
    score = 1.5
    flag = true
    tags = ["a", "b", "c", "d", "e"]
    [[meta.children]]
    name = "first"
    age = 1
    [[meta.children]]
    name = "second"
    age = 2
  TOML
}

# shape 3: large — array-heavy, like scalar_float
LARGE = Array.new(100) { |i|
  body = (1..200).map { |j| "v#{j} = #{j}.#{i}" }.join("\n")
  "[block]\n#{body}\n"
}

def bench(label, &b)
  reps = 6
  best = Float::INFINITY
  reps.times do
    t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    b.call
    dt = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0
    best = dt if dt < best
  end
  printf("%-44s best-of-%d: %7.2f ms\n", label, reps, best * 1000.0)
  best
end

[ ["tiny (2000x, 1-line each)",  TINY],
  ["medium (500x, 8-line aot)",  MED],
  ["large (100x, 200-line array)", LARGE] ].each do |name, corpus|
  total_bytes = corpus.sum(&:bytesize)
  puts "#{name}  total=#{total_bytes/1024} KB"
  per = bench("  load (per-doc)")         { corpus.each { |s| Teptris::TOML.load(s) } }
  bat = bench("  load_batch (one call)")  { Teptris::TOML.load_batch(corpus) }
  laz = bench("  load_lazy_batch (parse-only)") do
    arr = Teptris::TOML.load_lazy_batch(corpus); arr.size
  end
  printf("  eager-batch vs per-doc: %.2fx   lazy-batch vs per-doc: %.2fx\n\n",
         bat / per, laz / per)
end
