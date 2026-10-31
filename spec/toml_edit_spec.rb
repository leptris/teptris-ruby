# frozen_string_literal: true

require "spec_helper"

RSpec.describe Teptris::TOML do
  describe ".edit" do
    it "preserves everything but the value" do
      src = "# c\nversion = \"1.2.3\"  # t\n[serve]\nport = 8080\n"
      expect(described_class.edit(src, "serve.port", "9090")).to eq(
        "# c\nversion = \"1.2.3\"  # t\n[serve]\nport = 9090\n"
      )
    end

    it "splices multiline and inline targets and keeps CRLF" do
      expect(described_class.edit("m = \"\"\"\nline\n\"\"\"\nz = 1\n", "m", "\"n\"")).to eq(
        "m = \"n\"\nz = 1\n"
      )
      expect(described_class.edit("t = {a = 1}\n", "t", "{a = 2}")).to eq("t = {a = 2}\n")
      expect(described_class.edit("# c\r\nport = 8080\r\n", "port", "9090")).to eq(
        "# c\r\nport = 9090\r\n"
      )
    end

    it "raises on an absent key" do
      expect { described_class.edit("a = 1\n", "b", "2") }.to raise_error(Teptris::Error)
    end

    it "raises on a malformed replacement" do
      expect { described_class.edit("a = 1\n", "a", "@@@") }.to raise_error(Teptris::Error)
    end
  end
end
