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
    first_row = [0] # plan 0 = the root: asm walks plan index 0
    counter = [0]
    compile(tree, rows, first_row, counter)
    first_row << rows.length # sentinel: end of the last plan's rows
    d = allocate
    d.instance_variable_set(:@rows, rows.freeze)
    d.instance_variable_set(:@first_row, first_row.freeze)
    d.instance_variable_set(:@handle,
                            TeptrisExt.plan_build(rows, first_row))
    d.freeze
  end

  # Pre-order: each plan's rows are one CONTIGUOUS block; nested
  # sub-plans are compiled after the parent's block starts and their
  # indices patch the parent's NESTED rows. first_row must eventually
  # carry plan_count + 1 entries (the sentinel is rows.length).
  def self.compile(tree, rows, first_row, counter)
    idx = counter[0]
    counter[0] += 1
    first_row[idx] = rows.length
    (tree[:children] || []).each do |ch|
      kind = KINDS.fetch(ch[:kind])
      if kind == 3
        sub = counter[0]
        pos = rows.length
        rows << nil # patched with the real sub index below
        sub = compile(ch[:plan], rows, first_row, counter)
        rows[pos] = [ch[:name].to_s, kind, sub]
      else
        rows << [ch[:name].to_s, kind, 0]
      end
    end
    idx
  end
  private_class_method :compile

  def walk(toml)
    TeptrisExt.plan_emit(@handle, toml)
  end
end
