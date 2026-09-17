require_relative "spec_helper"

RSpec.describe "launch checklist (leptris/teptris-ruby#3)" do
  it "defines no constants outside the Teptris namespace on require" do
    # Fresh process: requiring teptris alone must not define or rebind
    # any foreign top-level constant (the yeptris Psych lesson).
    out = IO.popen([RbConfig.ruby, "-I#{File.expand_path('../lib', __dir__)}", "-e",
      'require "teptris"; '       'foreign = Object.constants.grep(/Tomlib|Tomlrb|Psych/); '       'print({ teptris: Object.const_defined?(:Teptris), foreign: foreign }.inspect)'],
      &:read)
    expect($?.success?).to be(true)
    # Hash#inspect spelling differs across ruby minors (3.3: {:a=>1},
    # 3.4+: {a: 1}) — parse the subprocess's own output instead
    expect(eval(out)).to eq(teptris: true, foreign: [])
  end

  describe "safe_load" do
    doc = "o = 1979-05-27T07:32:00Z\nl = 1979-05-27T07:32:00\nd = 1979-05-27\nt = 07:32:00\nn = 1\n"

    it "defaults to the native contract" do
      expect(described_class = Teptris::TOML.safe_load(doc)["d"]).to eq(Date.new(1979, 5, 27))
    end

    it "keeps datetimes as canonical strings with datetime_policy: :string" do
      got = Teptris::TOML.safe_load(doc, datetime_policy: :string)
      expect(got["o"]).to eq("1979-05-27T07:32:00Z")
      expect(got["l"]).to eq("1979-05-27T07:32:00")
      expect(got["d"]).to eq("1979-05-27")
      expect(got["t"]).to eq("07:32:00")
    end

    it "raises when a datetime materializes an unpermitted class" do
      expect { Teptris::TOML.safe_load(doc, permitted_classes: [String, Integer]) }
        .to raise_error(Teptris::Error, /not in permitted_classes/)
    end

    it "accepts explicit permitted datetime classes" do
      date_only = "d = 1979-05-27
"
      got = Teptris::TOML.safe_load(date_only,
                                    permitted_classes: [String, Integer, Date])
      expect(got["d"]).to eq(Date.new(1979, 5, 27))
    end

    it "rejects unknown policies" do
      expect { Teptris::TOML.safe_load(doc, datetime_policy: :bogus) }
        .to raise_error(ArgumentError)
    end
  end

  describe "load_schema (descriptor entry point, implemented, teptris#46)" do
    it "rejects non-descriptors" do
      expect { Teptris::TOML.load_schema("a = 1", {}) }
        .to raise_error(ArgumentError, /Teptris::Descriptor/)
    end

    it "materializes planned keys in one pass and skips the rest" do
      d = Teptris::Descriptor.build(
        children: [
          { name: "name", kind: :scalar },
          { name: "hosts", kind: :collection },
          { name: "items", kind: :nested, plan: {
              children: [{ name: "id", kind: :scalar }] } },
        ])
      out = Teptris::TOML.load_schema(
        "name = \"svc\"\njunk = [1, 2, 3]\nhosts = [\"a\", \"b\"]\n" \
        "[[items]]\nid = 1\n[[items]]\nid = 2\n", d)
      expect(out).to eq("name" => "svc", "hosts" => %w[a b],
                        "items" => [{ "id" => 1 }, { "id" => 2 }])
      expect(out).not_to have_key("junk")
    end

    it "reads absent rows as nil" do
      d = Teptris::Descriptor.build(children: [{ name: "gone", kind: :scalar }])
      expect(Teptris::TOML.load_schema("a = 1\n", d)).to eq("gone" => nil)
    end

    it "keeps sub-plan ranges disjoint from later siblings (0.2.29 regression)" do
      d = Teptris::Descriptor.build(
        children: [
          { name: "name", kind: :scalar },
          { name: "items", kind: :nested, plan: {
            children: [{ name: "id", kind: :scalar }] } },
          { name: "meta", kind: :raw },
        ])
      out = Teptris::TOML.load_schema(
        "name = \"svc\"\n[[items]]\nid = 1\n[meta]\nx = \"r\"\n", d)
      expect(out["items"]).to eq([{ "id" => 1 }])
      expect(out["meta"]).to eq("x" => "r")
    end
  end
end
