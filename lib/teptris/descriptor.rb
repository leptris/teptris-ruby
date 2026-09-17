# frozen_string_literal: true

# Tree-shaped schema-descriptor materialization (teptris#46, mirroring
# leptris v1): compile a plan tree once, then materialize a whole TOML
# subtree against it in ONE native pass — unplanned keys are never
# materialized.
#
#   descriptor = Teptris::Descriptor.build(
#     children: [
#       { name: "name", kind: :scalar },
#       { name: "port", kind: :scalar },
#       { name: "hosts", kind: :collection },
#       { name: "items", kind: :nested, plan: {
#           children: [{ name: "id", kind: :scalar }] } },
#       { name: "everything_else", kind: :raw },
#     ])
#   descriptor.walk(toml_string)  # => { "name" => "svc", ... }
#
# Row kinds: :scalar (any TOML value), :collection (array of scalars),
# :nested (recurse via +plan:+; also spans arrays of tables), :raw
# (the untouched native subtree). Rows absent from the document read
# as nil.
class Teptris::Descriptor
  KINDS = { scalar: 1, collection: 2, nested: 3, raw: 4 }.freeze
  private_constant :KINDS

  attr_reader :rows, :first_row

  def self.build(tree)
    rows = []
    first_row = [0]
    counter = [1]
    compile(tree, rows, first_row, counter)
    d = allocate
    d.instance_variable_set(:@rows, rows.freeze)
    d.instance_variable_set(:@first_row, first_row.freeze)
    d.instance_variable_set(:@handle,
                            TeptrisExt.plan_build(rows, first_row))
    d.freeze
  end

  def self.compile(tree, rows, first_row, counter)
    idx = counter[0]
    counter[0] += 1
    first_row[idx] = rows.length
    (tree[:children] || []).each do |ch|
      kind = KINDS.fetch(ch[:kind])
      sub = 0
      sub = compile(ch[:plan], rows, first_row, counter) if kind == 3
      rows << [ch[:name].to_s, kind, sub]
    end
    idx
  end
  private_class_method :compile

  def walk(toml)
    TeptrisExt.plan_emit(@handle, toml)
  end
end
