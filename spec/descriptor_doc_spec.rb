# frozen_string_literal: true

require "spec_helper"

# teptris-ruby#203: the retained-document plan walk (the engine's
# teptris_plan_walk takes a node; #walk fabricated one from a TOML
# string per call). #walk_doc walks a Teptris::TOML.load_doc handle:
# one parse, many walks (or one parse, several plans over the same
# document). Strings stay on #walk; docs on #walk_doc.
RSpec.describe "Descriptor#walk_doc (retained-document plan walk)" do
  let(:descriptor) do
    Teptris::Descriptor.build(
      children: [
        { name: "name", kind: :scalar },
        { name: "hosts", kind: :collection },
        { name: "items", kind: :nested, plan: {
          children: [{ name: "id", kind: :scalar }]
        } },
        { name: "meta", kind: :raw }
      ]
    )
  end
  let(:toml) do
    "name = \"svc\"\njunk = [1, 2, 3]\nhosts = [\"a\", \"b\"]\n" \
      "[[items]]\nid = 1\n[[items]]\nid = 2\n[meta]\nkeep = true\n"
  end

  it "walks a load_doc document with the same shape as walk" do
    expect(descriptor.walk_doc(Teptris::TOML.load_doc(toml)))
      .to eq(descriptor.walk(toml))
  end

  it "never materializes unplanned keys" do
    out = descriptor.walk_doc(Teptris::TOML.load_doc(toml))
    expect(out).not_to have_key("junk")
    expect(out).to eq("name" => "svc", "hosts" => %w[a b],
                      "items" => [{ "id" => 1 }, { "id" => 2 }],
                      "meta" => { "keep" => true })
  end

  it "reads absent rows as nil" do
    d = Teptris::Descriptor.build(children: [{ name: "gone", kind: :scalar }])
    expect(d.walk_doc(Teptris::TOML.load_doc("a = 1\n")))
      .to eq("gone" => nil)
  end

  it "walks one retained document repeatedly" do
    doc = Teptris::TOML.load_doc(toml)
    first = descriptor.walk_doc(doc)
    second = descriptor.walk_doc(doc)
    expect(second).to eq(first)
  end

  it "walks one document against several plans" do
    doc = Teptris::TOML.load_doc(toml)
    names = Teptris::Descriptor.build(children: [{ name: "name", kind: :scalar }])
    expect(descriptor.walk_doc(doc)).to include("name" => "svc")
    expect(names.walk_doc(doc)).to eq("name" => "svc")
  end

  it "rejects a String (strings belong to #walk)" do
    expect { descriptor.walk_doc(toml) }.to raise_error(TypeError)
  end

  it "rejects a non-document object" do
    expect { descriptor.walk_doc(42) }.to raise_error(TypeError)
  end
end
