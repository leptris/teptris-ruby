#!/usr/bin/env ruby
# Ractor-parallel batch loading vs the single-threaded paths.
# Reports wall time for: sequential load, C load_batch, and a Ractor
# worker pool (move-then-copy transfer) across the bench-corpus shapes.
# Run: ruby benchmark/ractor_tier.rb [corpus-dir] [docs-per-shape] [workers]
$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "teptris"
require "etc"
require "timeout"

corpus = ARGV[0] || File.expand_path("../../teptris/bench-corpus", __dir__)
per_shape = (ARGV[1] || 40).to_i
workers = (ARGV[2] || [Ractor.count - 1, 2].max).to_i

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
  when "threads4"
    # load_batch(threads: 4): one GVL release per slice, shared key
    # cache per slice, zero-copy thread passing
    Teptris::TOML.load_batch(docs.map(&:last), threads: 4)
  when "ractors"
    # dead workers must not wedge the collector: tagged results,
    # sentinel shutdown, closed-port tolerance, and a hard timeout
    # that reports HUNG as a verdict instead of hanging the lane.
    # Ruby 4.0 removed Ractor.yield/take/receive - workers talk
    # through Ractor::Port there; 3.4 keeps the yield/take pool.
    Timeout.timeout(120) do
      if Ractor.const_defined?(:Port)
        dbg = ENV["TEPTRIS_RACTOR_DEBUG"]
        trace = ->(phase) { warn(format("[dbg] %s %s", phase, Time.now.strftime("%S.%L"))) if dbg }
        outp = Ractor::Port.new
        inp = Array.new(workers) { Ractor::Port.new }
        trace.call("ports created")
        pool = inp.map do |ip|
          Ractor.new(ip, outp) do |my_in, my_out|
            warn("[dbg] worker up") if ENV["TEPTRIS_RACTOR_DEBUG"]
            loop do
              msg = my_in.receive
              break if msg == :done

              i, src = msg
              begin
                my_out << [i, Teptris::TOML.load(src)]
              rescue StandardError => e
                warn("[dbg] worker load failed: \#{e.class}") if ENV["TEPTRIS_RACTOR_DEBUG"]
                my_out << [i, e]
              end
            end
            warn("[dbg] worker done") if ENV["TEPTRIS_RACTOR_DEBUG"]
          rescue Ractor::PortClosed
            warn("[dbg] worker saw PortClosed") if ENV["TEPTRIS_RACTOR_DEBUG"]
          end
        end
        trace.call("workers \#{workers} up")
        out = Array.new(docs.size)
        docs.each_with_index do |(_, src), i|
          inp[i % workers] << [i, src]
        end
        trace.call("docs sent: \#{docs.size}")
        done = 0
        while done < docs.size
          # oi/ov, NOT i/v: the names would become Timeout-scope locals
          # here and poison the 3.4 else-branch worker block's own
          # `i, src = msg`, which then captures them (Ractor isolation
          # violation: 'can not isolate a Proc (i)').
          oi, ov = outp.receive
          out[oi] = ov
          done += 1
          warn("[dbg] received \#{done}/\#{docs.size} (doc \#{oi} \#{ov.class})") if dbg && (done % 40).zero?
        end
        trace.call("all received")
        inp.each do |ip|
          ip << :done
        rescue StandardError
          nil
        end
      else
        pool = Array.new(workers) do
          Ractor.new do
            loop do
              msg = Ractor.receive
              break if msg == :done

              i, src = msg
              begin
                Ractor.yield [i, Teptris::TOML.load(src)]
              rescue StandardError => e
                Ractor.yield [i, e]
              end
            end
          end
        end
        out = Array.new(docs.size)
        docs.each_with_index do |(_, src), i|
          pool[i % workers].send([i, src])
        end
        done = 0
        alive = pool.dup
        while done < docs.size && !alive.empty?
          ready, = begin
            Ractor.select(*alive)
          rescue Ractor::ClosedError
            break
          end
          begin
            i, v = ready.take
            out[i] = v
            done += 1
          rescue Ractor::ClosedError
            alive.delete(ready)
          end
        end
        pool.each do |r|
          r.send(:done)
        rescue StandardError
          nil
        end
      end
      raise "HUNG collected #{done}/#{docs.size}" unless done == docs.size

      out
    end
  end
  Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0
end

puts format("ruby %s  ractors=%d  docs=%d  cores=%d",
            RUBY_VERSION, workers, docs.size,
            Etc.respond_to?(:nprocessors) ? Etc.nprocessors : "?")
%w[sequential load_batch threads4 ractors].each do |label|
  best = Float::INFINITY
  3.times do
    GC.start
    dt = bench(label, docs, workers)
    best = dt if dt < best
  end
  puts format("%-12s %8.1f ms", label, best * 1000)
rescue Timeout::Error
  puts format("%-12s %8s", label, "HUNG")
rescue RuntimeError => e
  puts format("%-12s %8s", label, e.message[0, 40])
end
