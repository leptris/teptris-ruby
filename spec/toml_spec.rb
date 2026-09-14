require_relative "spec_helper"

RSpec.describe Teptris::TOML do
  it "loads scalars" do
    expect(described_class.load("a = 1\nb = 1.5\nc = 'x'\nd = true\ne = [1, 2]"))
      .to eq("a" => 1, "b" => 1.5, "c" => "x", "d" => true, "e" => [1, 2])
  end

  it "loads nested tables and arrays of tables in order" do
    doc = described_class.load(<<~TOML)
      root = true
      [a]
      x = 1
      [[aot]]
      n = "first"
      [[aot]]
      n = "second"
    TOML
    expect(doc).to eq("root" => true, "a" => {"x" => 1},
                      "aot" => [{"n" => "first"}, {"n" => "second"}])
  end

  it "maps datetimes per the tomlib contract" do
    doc = described_class.load(<<~TOML)
      o = 1979-05-27T07:32:00Z
      l = 1979-05-27T07:32:00
      d = 1979-05-27
      t = 07:32:00
    TOML
    expect(doc["o"]).to be_a(Time)
    expect(doc["o"].utc).to eq(Time.utc(1979, 5, 27, 7, 32, 0))
    expect(doc["l"]).to be_a(Time)
    expect(doc["d"]).to eq(Date.new(1979, 5, 27))
    expect(doc["t"]).to eq("07:32:00")
  end

  it "keeps utf-8 and escape handling intact" do
    expect(described_class.load(%(s = "\\u00e9\\n"))).to eq("s" => "é\n")
  end

  it "raises ParseError with line and column" do
    expect { described_class.load("a = 1\nb = ?\n") }
      .to raise_error(Teptris::ParseError) do |e|
        expect(e.line).to eq(2)
        expect(e.column).to eq(5)
      end
  end

  it "dumps and roundtrips" do
    obj = {"title" => "teptris", "nested" => {"x" => 1},
           "aot" => [{"n" => 1}, {"n" => 2}], "f" => 1.5}
    expect(described_class.load(described_class.dump(obj))).to eq(obj)
  end

  it "dumps times and dates" do
    obj = {"at" => Time.utc(2026, 9, 13, 8, 0, 0), "on" => Date.new(2026, 9, 13)}
    expect(described_class.dump(obj))
      .to eq("at = 2026-09-13T08:00:00Z\non = 2026-09-13\n")
  end

  it "dumps datetimes across zones, eras, and leap days" do
    obj = {"jan" => Time.new(2026, 1, 2, 3, 4, 5, "-08:00"),
           "pre_epoch" => Time.utc(1969, 12, 31, 23, 59, 59),
           "frac" => Time.new(2026, 9, 13, 10, 30, 15.5, "+05:30"),
           "leap" => Time.utc(2000, 2, 29, 12, 0, 0),
           "local" => Time.local(2026, 6, 15, 1, 2, 3.25)}
    described_class.load(described_class.dump(obj)).each do |k, v|
      expect(v).to be_within(1e-6).of(obj[k])
    end
  end

  it "dumps mixed arrays as inline and homogeneous table arrays as sections" do
    obj = {"mix" => [{"q" => 1}, 2], "nested" => [[1, 2], [3]], "aot" => [{"n" => 1}]}
    toml = described_class.dump(obj)
    expect(toml).to include("mix = [{q = 1}, 2]")
    expect(toml).to include("nested = [[1, 2], [3]]")
    expect(toml).to include("[[aot]]\nn = 1")
    expect(described_class.load(toml)).to eq(obj)
  end

  it "rejects undumpable roots, values, and out-of-range integers" do
    expect { described_class.dump([1]) }.to raise_error(ArgumentError)
    expect { described_class.dump({"x" => Object.new}) }.to raise_error(Teptris::Error)
    expect { described_class.dump({"x" => 2**70}) }.to raise_error(RangeError)
  end

  it "roundtrips the whole bench corpus through the native dump" do
    corpus = File.expand_path("../../teptris/bench-corpus", __dir__)
    Dir[File.join(corpus, "*.toml")].sort.each do |path|
      obj = described_class.load(File.read(path))
      expect(described_class.load(described_class.dump(obj))).to eq(obj)
    end
  end

  describe "TOML 1.1 grammar" do
    it 'parses \e and \xNN escapes' do
      doc = described_class.load(<<~'TOML')
        esc = "A\eB"
        hex = "\x68\x69"
      TOML
      expect(doc["esc"]).to eq("A\x1BB")
      expect(doc["hex"]).to eq("hi")
    end

    it "parses optional seconds in times and datetimes" do
      doc = described_class.load(%{t = 07:32\ndt = 1979-05-27T07:32\noff = 1979-05-27 07:32Z\n})
      expect(doc["t"]).to eq("07:32:00")
      expect(doc["dt"]).to eq(Time.local(1979, 5, 27, 7, 32))
      expect(doc["off"].utc).to eq(Time.utc(1979, 5, 27, 7, 32))
    end

    it "accepts newlines and trailing commas in inline tables" do
      doc = described_class.load(<<~TOML)
        it = {
          a = 1,
          b = 2,
        }
        single = { x = 1, }
      TOML
      expect(doc["it"]).to eq("a" => 1, "b" => 2)
      expect(doc["single"]).to eq("x" => 1)
    end

    it "defines sub-tables within dotted-key tables via headers" do
      doc = described_class.load(<<~TOML)
        [fruit]
        apple.color = "red"
        apple.taste.sweet = true

        [fruit.apple.texture]
        smooth = true

        [[fruit.apple.seeds]]
        size = 2
      TOML
      expect(doc.dig("fruit", "apple", "texture")).to eq("smooth" => true)
      expect(doc.dig("fruit", "apple", "seeds")).to eq(["size" => 2])
    end

    it "still rejects exact dotted-table redefinition" do
      expect { described_class.load(<<~TOML) }
        [fruit]
        apple.color = "red"

        [fruit.apple]
        x = 1
      TOML
        .to raise_error(Teptris::ParseError)
    end
  end

  describe "parity with tomlib", if: defined?(Tomlib) do
    cases = [
      "a = 1\nb = -2\nc = 0xFF\n",
      "s = 'lit'\nt = \"esc\\t\"\n",
      "f = 3.14\ng = 1e6\n",
      "[t]\nx = 1\n[t.u]\ny = [1, 2]\n",
      "[[a]]\nn = 1\n[[a]]\nn = 2\n",
      "d = 1979-05-27\no = 1979-05-27T07:32:00Z\nl = 1979-05-27T07:32:00\nt = 07:32:00\n",
      "k.'quoted key' = 1\n",
    ]
    cases.each_with_index do |toml, i|
      it "matches tomlib on case #{i}" do
        require "tomlib"
        expect(described_class.load(toml)).to eq(Tomlib.load(toml))
      end
    end
  end
end
