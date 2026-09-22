require_relative "spec_helper"
require "date"
require "fileutils"

# Dump goldens (closes the board's "goldens vs tomlrb/tomlib dumps"
# line): for every fixture case the emitter's output is pinned to a
# committed golden file AND value-paritized in both directions with
# the reference stack —
#   1. teptris parse of the source input
#   2. teptris roundtrip of its own dump
#   3. tomlib (tomlrb parser) parse of teptris's dump
#   4. teptris parse of tomlib's dump (their serializer, our load)
#   5. byte-stability: the dump equals the committed golden
# Any emitter change shows up as a visible golden diff. Regenerate
# with REGENERATE_DUMPGOLDENS=1 bundle exec rspec
# spec/toml_dump_golden_spec.rb and REVIEW THE DIFF — goldens are a
# contract, not output.
RSpec.describe "dump goldens (teptris <-> tomlib/tomlrb differential)" do
  before(:all) do
    skip "tomlib not available" unless defined?(Tomlib)
  end

  # input TOML (as a human would write it) -> the expected Ruby value
  # both engines must agree on.
  CASES = {
    "strings" => [<<~'TOML',
      s = "tab\there é é \"quoted\" back\\slash"
      lit = 'C:\Users\no\escapes\here'
      ml = """line1
      line2
      """
      mll = '''literal
        kept
      '''
      TOML
      { "s" => "tab\there é é \"quoted\" back\\slash",
        "lit" => 'C:\Users\no\escapes\here',
        "ml" => "line1\nline2\n",
        "mll" => "literal\n  kept\n" }],
    "numbers" => [<<~'TOML',
      int = 9_223_372_036_854_775_807
      neg = -17
      hex = 0xdeadbeef
      oct = 0o755
      bin = 0b11010110
      float = 6.626e-34
      negzero = -0.0
      inf = inf
      ninf = -inf
      TOML
      { "int" => 9_223_372_036_854_775_807, "neg" => -17,
        "hex" => 0xdeadbeef, "oct" => 0o755, "bin" => 0b11010110,
        "float" => 6.626e-34, "negzero" => -0.0,
        "inf" => Float::INFINITY, "ninf" => -Float::INFINITY }],
    "datetimes" => [<<~'TOML',
      odt = 1979-05-27T07:32:00Z
      odt2 = 1979-05-27T00:32:00-07:00
      date = 1979-05-27
      time = 07:32:00
      timef = 00:32:00.999
      TOML
      { "odt" => Time.utc(1979, 5, 27, 7, 32, 0),
        "odt2" => Time.new(1979, 5, 27, 0, 32, 0, "-07:00"),
        "date" => Date.new(1979, 5, 27),
        "time" => "07:32:00",
        "timef" => "00:32:00.999" }],
    # machine-zone parity (NOT golden-pinned: tomlib's dump stamps the
    # machine offset for local Times, and so does teptris — the values
    # round-trip consistently on any single machine)
    "datetimes_local" => [<<~'TOML',
      ldt = 1979-05-27T07:32:00
      TOML
      { "ldt" => Time.local(1979, 5, 27, 7, 32, 0) }],
    "containers" => [<<~'TOML',
      title = "root"

      [tbl]
      x = 1
      nested = { a = 2, b = [3, 4] }

      [tbl.deep]
      y = "z"

      [[aot]]
      n = 1
      tags = ["a", "b"]

      [[aot]]
      n = 2
      tags = []

      [[deep.deeper.deepest]]
      ok = true
      TOML
      { "title" => "root",
        "tbl" => { "x" => 1, "nested" => { "a" => 2, "b" => [3, 4] },
                   "deep" => { "y" => "z" } },
        "aot" => [{ "n" => 1, "tags" => %w[a b] },
                  { "n" => 2, "tags" => [] }],
        "deep" => { "deeper" => { "deepest" => [{ "ok" => true }] } } }],
  }.freeze

  golden_dir = File.expand_path("fixtures/dump_goldens", __dir__)

  # machine-zone cases: parity-checked, never golden-pinned (tomlib's
  # dump embeds the local machine's offset for local Times)
  GOLDEN_SKIP = %w[datetimes_local].freeze

  CASES.each do |name, (input, expected)|
    describe name do
      golden_path = File.join(golden_dir, "#{name}.toml")
      dump = Teptris::TOML.dump(expected)

      it "parses the source input to the expected value" do
        expect(Teptris::TOML.load(input)).to eq(expected)
      end

      it "round-trips its own dump" do
        expect(Teptris::TOML.load(dump)).to eq(expected)
      end

      it "emits output the reference parser (tomlrb via tomlib) agrees with" do
        expect(Tomlib.load(dump)).to eq(expected)
      end

      it "parses the reference serializer's output (tomlib dump)" do
        expect(Teptris::TOML.load(Tomlib.dump(expected))).to eq(expected)
      end

      it "matches the committed golden byte for byte" do
        skip "machine-zone case" if GOLDEN_SKIP.include?(name)
        if ENV["REGENERATE_DUMPGOLDENS"]
          FileUtils.mkdir_p(golden_dir)
          File.write(golden_path, dump)
        end
        unless File.exist?(golden_path)
          skip "no golden yet — run with REGENERATE_DUMPGOLDENS=1 to write, then REVIEW THE DIFF"
        end
        expect(dump).to eq(File.read(golden_path))
      end
    end
  end
end
