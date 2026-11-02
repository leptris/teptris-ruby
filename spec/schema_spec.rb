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
      expect do
        described_class.compile('{"unevaluatedProperties":false}')
      end.to raise_error(Teptris::Error, /unevaluatedProperties/)
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
      expect(schema.valid?("k = 1.0\n")).to be(false)
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
