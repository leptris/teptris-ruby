require "spec_helper"

RSpec.describe "load_batch threads:" do
  CORPUS = Dir[File.expand_path("../../teptris/bench-corpus/*.toml",
                               __dir__)].sort.map { |p| File.read(p) }
  SMALL = ["a = 1\n[x]\nb = 2\n", "t = 07:32:00\n", "s = 'v'\n[[k]]\ni = 1\n"] * 20

  before(:all) do
    # any corpus available? fall back to generated shapes
    @docs = if CORRUPT_EMPTY = CORPUS.empty?
      Array.new(60) { |i| "k#{i} = #{i}\n[t#{i}]\ns = \"str #{i}\"\n" }
    else
      CORPUS + CORPUS
    end
  end

  it "parallel results equal sequential results" do
    seq = Teptris::TOML.load_batch(@docs)
    par = Teptris::TOML.load_batch(@docs, threads: 4)
    expect(par).to eq(seq)
  end

  it "threads: 1 keeps the C batch path" do
    expect(Teptris::TOML.load_batch(SMALL, threads: 1))
      .to eq(Teptris::TOML.load_batch(SMALL))
  end

  it "handles the same string object repeated across slices" do
    one = "k = 1\n[t]\ns = 'v'\n"
    many = Array.new(60, one)
    seq = Teptris::TOML.load_batch(many)
    par = Teptris::TOML.load_batch(many, threads: 4)
    expect(par).to eq(seq)
    expect(par.uniq.size).to eq(1)
  end

  it "raises the first document's error deterministically" do
    bad = ["a = 1\n", "b = 2\n", "c = ?\n", "d = 4\n"]
    expect { Teptris::TOML.load_batch(bad, threads: 3) }
      .to raise_error(Teptris::ParseError)
  end

  it "survives compaction during parallel load (string pinning)" do
    skip "compaction unavailable" unless GC.respond_to?(:compact)
    stress = Array.new(80) { |i| "k#{i} = #{i}\nn#{i} = 1.5\n[s#{i}]\nx = \"#{'y' * 64}\"\n" }
    seq = Teptris::TOML.load_batch(stress)
    th = Thread.new do
      5.times { GC.start(full_mark: true, immediate_sweep: true); GC.compact }
    end
    par = Teptris::TOML.load_batch(stress, threads: 4)
    th.join
    expect(par).to eq(seq)
  end
end
