# frozen_string_literal: true

require "spec_helper"
require "json"

RSpec.describe Teptris::Schema do
  let(:manifest_schema) do
    JSON.generate(
      type: "object",
      properties: {
        "name" => { type: "string", minLength: 1 },
        "port" => { type: "integer", minimum: 1 },
        "mode" => { enum: %w[fast safe] }
      },
      required: %w[name port]
    )
  end

  describe ".compile" do
    it "compiles and validates" do
      schema = described_class.compile(manifest_schema)
      expect(schema.validate("name = \"srv\"\nport = 8080\n")).to be_empty
      expect(schema.valid?("name = \"srv\"\nport = 8080\n")).to be(true)
    end

    it "reports every violation with path, schema_path and message" do
      schema = described_class.compile(manifest_schema)
      bad = schema.validate("name = \"\"\nport = 0\n")
      expect(bad.length).to eq(2)
      expect(bad[0].path).to eq("name")
      expect(bad[0].schema_path).to eq("#/properties.name")
      expect(bad[0].message).to include("minLength")
      expect(bad[1].path).to eq("port")
      expect(bad.map(&:to_h)).to all(include(:path, :schema_path, :message))
    end

    it "reports a missing required property at the root path" do
      schema = described_class.compile(manifest_schema)
      bad = schema.validate("port = 1\n")
      expect(bad.length).to eq(1)
      expect(bad[0].path).to eq("")
      expect(bad[0].message).to include("name")
    end

    it "raises Teptris::Error with the engine diag on unsupported constructs" do
      # unevaluatedProperties is enforced since engine 0.3.22
      schema = described_class.compile('{"unevaluatedProperties":false}')
      expect(schema.validate("a = 1\n").length).to eq(1)
      expect do
        described_class.compile('{"$ref":"https://x.example/s.json"}')
      end.to raise_error(Teptris::Error, /remote/)
    end

    it "raises on broken JSON" do
      expect { described_class.compile('{"type":}') }
        .to raise_error(Teptris::Error, /error/)
    end
  end

  describe "the four policies" do
    it "keeps integer TOML-native (enum is type-strict)" do
      schema = described_class.compile('{"properties":{"k":{"enum":[1]}}}')
      expect(schema.valid?("k = 1\n")).to be(true)
      # 2020-12 numeric identity since engine 0.3.23
      expect(schema.valid?("k = 1.0\n")).to be(true)
      expect(schema.valid?("k = 1.5\n")).to be(false)
    end

    it "validates datetimes as strings with formats" do
      schema = described_class.compile(
        '{"properties":{"k":{"type":"string","format":"date-time"}}}'
      )
      expect(schema.valid?("k = 2026-01-02T03:04:05Z\n")).to be(true)
      expect(schema.valid?("k = \"soon\"\n")).to be(false)
    end

    it "treats nan as a float failing every ordered comparison" do
      schema = described_class.compile('{"properties":{"k":{"minimum":0}}}')
      expect(schema.valid?("k = nan\n")).to be(false)
      expect(schema.valid?("k = inf\n")).to be(true)
    end

    it "reads bare null in a type array as absence" do
      schema = described_class.compile(
        '{"properties":{"k":{"type":["string",null]}}}'
      )
      expect(schema.valid?("k = \"s\"\n")).to be(true)
      expect(schema.valid?("j = 1\n")).to be(true)
      expect(schema.valid?("k = 1\n")).to be(false)
    end
  end

  describe "recursive $ref" do
    it "memoizes and reports nested paths" do
      schema = described_class.compile(
        '{"properties":{"v":{"type":"integer"},' \
        '"kids":{"type":"array","items":{"$ref":"#"}}},"required":["v"]}'
      )
      expect(schema.valid?("v = 0\n[[kids]]\nv = 1\n[[kids.kids]]\nv = 2\n"))
        .to be(true)
      bad = schema.validate("v = 0\n[[kids]]\nv = \"x\"\n")
      expect(bad.length).to eq(1)
      expect(bad[0].path).to eq("kids.0.v")
    end
  end

  describe "unknown keywords" do
    it "treats them as extensions (2020-12)" do
      schema = described_class.compile(
        '{"x-vendor":true,"properties":{"k":{"type":"integer"}}}'
      )
      expect(schema.valid?("k = 1\n")).to be(true)
      expect(schema.valid?("k = \"s\"\n")).to be(false)
    end
  end

  describe "parse failures" do
    it "raises Teptris::ParseError with line/column" do
      schema = described_class.compile("{}")
      begin
        schema.validate("a = = 1\n")
        raise "expected ParseError"
      rescue Teptris::ParseError => e
        expect(e.message).not_to be_empty
        expect(e.line).to be >= 1
      end
    end
  end
end

RSpec.describe "the taplo parity surface (engine 0.3.21)" do
  subject(:compile) { ->(json) { Teptris::Schema.compile(json) } }
  it "enforces draft-07 dependencies in both forms" do
    deps = Teptris::Schema.compile(
      '{"dependencies":{"credit_card":["billing_address"]}}'
    )
    expect(deps.validate("a = 1\ncredit_card = 1\n").length).to eq(1)
    expect(deps.valid?("credit_card = 1\nbilling_address = 'x'\n")).to be(true)

    schema_form = Teptris::Schema.compile(
      '{"dependencies":{"credit_card":{"required":["billing_address"]}}}'
    )
    expect(schema_form.validate("credit_card = 1\n").length).to eq(1)
  end

  it "reads tuple items and additionalItems" do
    tuple = Teptris::Schema.compile(
      '{"properties":{"t":{"items":[{"type":"string"}],"additionalItems":false}}}'
    )
    expect(tuple.valid?("t = ['x']\n")).to be(true)
    expect(tuple.validate("t = ['x', 1]\n").length).to eq(1)
  end

  it "keeps multipleOf exact across decimals" do
    mult = Teptris::Schema.compile('{"properties":{"k":{"multipleOf":0.1}}}')
    expect(mult.valid?("k = 0.3\n")).to be(true)
    expect(mult.valid?("k = 0.35\n")).to be(false)
  end

  it "enforces the formats taplo cannot" do
    uuid = Teptris::Schema.compile('{"properties":{"k":{"format":"uuid"}}}')
    expect(uuid.valid?("k = '123e4567-e89b-12d3-a456-426614174000'\n"))
      .to be(true)
    expect(uuid.valid?("k = 'nope'\n")).to be(false)
    req = Teptris::Schema.compile('{"properties":{"k":{"format":"semver-requirement"}}}')
    expect(req.valid?("k = '^1.2'\n")).to be(true)
    expect(req.valid?("k = 'not a req'\n")).to be(false)
  end
end

describe "the SOTA surface (engine 0.3.22)" do
  it "enforces unevaluatedProperties with the cousin rule" do
    cousin = Teptris::Schema.compile(
      '{"allOf":[{"properties":{"a":{}}},{"unevaluatedProperties":false}]}'
    )
    expect(cousin.validate("a = 1\n").length).to eq(1)

    adjacent = Teptris::Schema.compile(
      '{"properties":{"a":{}},"unevaluatedProperties":false}'
    )
    expect(adjacent.valid?("a = 1\n")).to be(true)
    expect(adjacent.valid?("a = 1\nb = 2\n")).to be(false)
  end

  it "resolves dynamic refs to the innermost anchor" do
    tree = Teptris::Schema.compile(
      '{"$dynamicAnchor":"node","type":"object","properties":' \
      '{"value":{"type":"integer"},"children":{"type":"array",' \
      '"items":{"$dynamicRef":"#node"}}}}'
    )
    expect(tree.valid?("value = 1\n[[children]]\nvalue = 2\n")).to be(true)
    expect(tree.valid?("value = 1\n[[children]]\nvalue = 'x'\n")).to be(false)
  end

  it "asserts contentSchema against the decoded content" do
    schema = <<~JSON.tr("\n", "")
      {"properties":{"k":{"contentEncoding":"base64",
        "contentMediaType":"application/json",
        "contentSchema":{"type":"object","required":["n"]}}}}
    JSON
    content = Teptris::Schema.compile(schema)
    expect(content.valid?("k = 'eyJuIjogMX0='\n")).to be(true)
    expect(content.valid?("k = 'W10='\n")).to be(false)
  end

  it "satisfies the TOML-native local formats by kind" do
    local = Teptris::Schema.compile(
      '{"properties":{"k":{"format":"time-local"}}}'
    )
    expect(local.valid?("k = 07:32:00\n")).to be(true)
    expect(local.valid?("k = '07:32:00Z'\n")).to be(false)
  end
end

describe "vendored metaschemas (engine 0.3.23)" do
  it "resolves the official metaschema in memory" do
    schema = Teptris::Schema.compile(
      '{"$ref":"https://json-schema.org/draft/2020-12/schema"}'
    )
    expect(schema.validate("type = \"string\"\n")).to be_empty
    expect(schema.validate("type = 123\n").length).to eq(1)
  end

  it "takes the legacy draft-07 empty-fragment URL" do
    schema = Teptris::Schema.compile(
      '{"$ref":"http://json-schema.org/draft-07/schema#"}'
    )
    expect(schema.validate("description = \"d\"\n")).to be_empty
  end

  it "reports the engine version" do
    expect(Teptris::TOML.engine_version).to eq("0.3.24")
  end
end

  describe "unicode property escapes (engine 0.3.24)" do
    it "matches letters across scripts" do
      schema = Teptris::Schema.compile(
        '{"properties":{"k":{"pattern":"^\\\\p{Letter}+$"}}}'
      )
      expect(schema.validate("k = \"π\"\n")).to be_empty
      expect(schema.validate("k = '123'\n").length).to eq(1)
    end

    it "negates with \\P" do
      schema = Teptris::Schema.compile(
        '{"properties":{"k":{"pattern":"^\\\\P{Letter}+$"}}}'
      )
      expect(schema.validate("k = '123'\n")).to be_empty
    end

    it "reports the engine version" do
      expect(Teptris::TOML.engine_version).to eq("0.3.24")
    end
  end
