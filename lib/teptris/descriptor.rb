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
    # Pre-order plan numbering (root = plan 0) with each plan's rows
    # assigned a DISJOINT reserved range. Interleaved appending leaks
    # siblings that follow a :nested child into the sub-plan's range —
    # the 0.2.29 bug (every array-of-tables element grew stray nil
    # rows).
    plans = []
    index_of = {}
    collect = lambda do |t|
      unless index_of.key?(t.object_id)
        index_of[t.object_id] = plans.length
        plans << t
      end
      (t[:children] || []).each do |ch|
        collect.call(ch[:plan]) if KINDS.fetch(ch[:kind]) == 3
      end
    end
    collect.call(tree)

    first_row = [0]
    plans.each { |t| first_row << first_row[-1] + (t[:children] || []).length }
    rows = Array.new(first_row[-1])
    plans.each_with_index do |t, i|
      (t[:children] || []).each_with_index do |ch, j|
        kind = KINDS.fetch(ch[:kind])
        sub = kind == 3 ? index_of[ch[:plan].object_id] : 0
        rows[first_row[i] + j] = [ch[:name].to_s, kind, sub]
      end
    end

    d = allocate
    d.instance_variable_set(:@rows, rows.freeze)
    d.instance_variable_set(:@first_row, first_row.freeze)
    d.instance_variable_set(:@handle,
                            TeptrisExt.plan_build(rows, first_row))
    d.freeze
  end

  def walk(toml)
    TeptrisExt.plan_emit(@handle, toml)
  end
end
