#!/usr/bin/env ruby
# Ractor-parallel batch loading vs the single-threaded paths.
# Reports wall time for: sequential load, C load_batch, and a Ractor
# worker pool (move-then-copy transfer) across the bench-corpus shapes.
# Run: ruby benchmark/ractor_tier.rb [corpus-dir] [docs-per-shape] [workers]
$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "teptris"
require "etc"

corpus = ARGV[0] || File.expand_path("../../teptris/bench-corpus", __dir__)
per_shape = (ARGV[1] || 40).to_i
workers = (ARGV[2] || ([Ractor.count - 1, 2].max)).to_i

shapes = %w[array_heavy cargo_like datetime_heavy deep_tables mixed
            scalar_float scalar_int scalar_string table_heavy].map do |name|
  path = File.join(corpus, "#{name}.toml")
  File.exist?(path) ? [name, File.read(path)] : nil
end.compact
abort "no corpus under #{corpus}" if shapes.empty?

docs = shapes.flat_map { |name, src| Array.new(per_shape) { [name, src] } }

def bench(label, docs, workers)
  GC.start
  t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  case label
  when "sequential"
    docs.map { |_, src| Teptris::TOML.load(src) }
  when "load_batch"
    Teptris::TOML.load_batch(docs.map(&:last))
  when "ractors"
    pool = Array.new(workers) do
      Ractor.new do
        loop do
          msg = Ractor.receive
          src = msg[1]
          begin
            h = Teptris::TOML.load(src)
          rescue => e
            Ractor.yield [msg[0], e], move: false
            next
          end
          # move: true transfer segfaulted 3.4.11's GC marking
          # (gc_mark_set from newobj_cache_miss under yield(move));
          # the copy path is the stable one
          Ractor.yield [msg[0], h]
        end
      end
    end
    out = Array.new(docs.size)
    docs.each_with_index { |(_, src), i| pool[i % workers].send([i, src]) }
    done = 0
    while done < docs.size
      ready, = Ractor.select(*pool)
      i, v = ready.take
      out[i] = v
      done += 1
    end
    pool.each { |r| r.send(nil) }
    out
  end
  Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0
end

puts format("ruby %s  ractors=%d  docs=%d  cores=%d",
            RUBY_VERSION, workers, docs.size,
            Etc.respond_to?(:nprocessors) ? Etc.nprocessors : "?")
%w[sequential load_batch ractors].each do |label|
  best = Float::INFINITY
  3.times do
    GC.start
    dt = bench(label, docs, workers)
    best = dt if dt < best
  end
  puts format("%-12s %8.1f ms", label, best * 1000)
end
