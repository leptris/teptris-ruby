require_relative "spec_helper"
require "tmpdir"

RSpec.describe Teptris::TOML do
  describe ".load_batch" do
    it "returns an Array of eagerly materialized Hashes" do
      out = described_class.load_batch([
        "a = 1\n",
        "b = \"y\"\n",
        "[t]\nk = 1\n",
      ])
      expect(out).to eq([{"a" => 1}, {"b" => "y"}, {"t" => {"k" => 1}}])
    end

    it "preserves the tomlib datetime contract across the batch" do
      out = described_class.load_batch([
        "o = 1979-05-27T07:32:00Z\n",
        "d = 1979-05-27\n",
        "t = 07:32:00\n",
      ])
      expect(out[0]["o"]).to be_a(Time)
      expect(out[0]["o"].utc).to eq(Time.utc(1979, 5, 27, 7, 32, 0))
      expect(out[1]["d"]).to eq(Date.new(1979, 5, 27))
      expect(out[2]["t"]).to eq("07:32:00")
    end

    it "returns [] for an empty batch without raising" do
      expect(described_class.load_batch([])).to eq([])
    end

    it "honours datetime_policy :string uniformly" do
      out = described_class.load_batch(
        ["o = 1979-05-27T07:32:00Z\n", "d = 1979-05-27\n"],
        datetime_policy: :string,
      )
      expect(out[0]["o"]).to eq("1979-05-27T07:32:00Z")
      expect(out[1]["d"]).to eq("1979-05-27")
    end

    it "honours permitted_classes (forbid Time) across the batch" do
      out = described_class.load_batch(
        ["d1 = 1979-05-27\n", "d2 = 1979-05-28\n"],
        safe_load: [String, Integer, Date],
      )
      expect(out[0]["d1"]).to be_a(Date)
      expect(out[1]["d2"]).to be_a(Date)
    end

    it "raises Teptris::Error on a datetime the permitted_classes forbid" do
      expect {
        described_class.load_batch(
          ["o = 1979-05-27T07:32:00Z\n"],
          safe_load: [String, Integer, Date],
        )
      }.to raise_error(Teptris::Error, /not in permitted_classes/)
    end

    it "raises ParseError with line/column on the first failing doc" do
      expect {
        described_class.load_batch(["a = 1\n", "b = ?\n", "c = 3\n"])
      }.to raise_error(Teptris::ParseError) { |e|
        expect(e.line).to eq(1)
        expect(e.column).to eq(5)
      }
    end

    it "raises ArgumentError on a non-Array input" do
      expect { described_class.load_batch("a = 1\n") }
        .to raise_error(ArgumentError, /Array of strings/)
    end

    it "raises ArgumentError on an unknown datetime_policy" do
      expect { described_class.load_batch(["a=1"], datetime_policy: :foo) }
        .to raise_error(ArgumentError, /datetime_policy/)
    end
  end

  describe ".load_lazy_batch" do
    it "returns an Array of Lazy wrappers (one per document)" do
      out = described_class.load_lazy_batch(["a = 1\n", "b = [1, 2]\n"])
      expect(out.size).to eq(2)
      expect(out[0].kind).to eq(:table)
      expect(out[1]["b"][0].value).to eq(1)
    end

    it "shares the batch parse but defers materialization" do
      out = described_class.load_lazy_batch(["a = 1\n", "b = 2\n"])
      expect(out[0]["a"].value).to eq(1)
      expect(out[1]["b"].value).to eq(2)
    end

    it "raises ParseError on the first failing doc" do
      expect {
        described_class.load_lazy_batch(["a = 1\n", "b = ?\n"])
      }.to raise_error(Teptris::ParseError)
    end
  end

  describe ".load_files" do
    around do |ex|
      Dir.mktmpdir("teptris-batch-") do |dir|
        @dir = dir
        @p1 = File.join(dir, "a.toml")
        @p2 = File.join(dir, "b.toml")
        File.write(@p1, "a = 1\n")
        File.write(@p2, "b = 2\n")
        ex.run
      end
    end

    it "reads each path and returns Hashes in order" do
      out = described_class.load_files([@p1, @p2])
      expect(out).to eq([{"a" => 1}, {"b" => 2}])
    end

    it "raises a clear ArgumentError for non-Array input" do
      expect { described_class.load_files(@p1) }
        .to raise_error(ArgumentError, /Array of paths/)
    end
  end
end
