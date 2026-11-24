# frozen_string_literal: true

require "json"

# Schema validation against the JSON Schema 2020-12 practical
# subset (engine SCHEMAS.md). Compile once, validate many: the
# compiled schema is an immutable, arena-backed handle held by the
# native extension (freed with the wrapper by GC).
#
#   schema = Teptris::Schema.compile('{"properties":{"port":{"type":"integer"}}}')
#   schema.validate("port = \"x\"\n")
#   # => [{path: "port", schema_path: "#/properties.port",
#   #       message: "expected a matching type, found string"}]
#   schema.valid?("port = 8080\n") # => true
#
# Compile failures raise Teptris::Error carrying the engine's diag
# JSON - unsupported constructs are named, never silently ignored.
# Documents that do not parse raise Teptris::ParseError with
# line/column.
class Teptris::Schema
  # The violation shape: where in the document (+path+), where in
  # the schema (+schema_path+), and why (+message+).
  class Violation
    attr_reader :path, :schema_path, :message

    def initialize(path, schema_path, message)
      @path = path
      @schema_path = schema_path
      @message = message
    end

    def to_h
      { path: path, schema_path: schema_path, message: message }
    end

    # Value semantics: two violations of the same fact are the same
    # violation, wherever they came from (validate vs validate_doc).
    def ==(other)
      other.is_a?(Violation) && other.to_h == to_h
    end
    alias eql? ==

    def hash
      to_h.hash
    end
  end

  class << self
    def compile(schema_json)
      new(TeptrisExt.schema_compile(schema_json))
    end
  end

  def initialize(handle)
    @handle = handle
  end

  # Validate raw TOML; an empty array = valid. Raises
  # Teptris::ParseError when the document does not parse.
  def validate(toml)
    violations(TeptrisExt.schema_validate(@handle, toml))
  end

  # True when the document parses with no violations.
  def valid?(toml)
    validate(toml).empty?
  end

  # Validate a RETAINED document (Teptris::TOML.load_doc): one parse,
  # many validations — the engine's teptris_schema_validate_doc face.
  # Raw TOML strings belong to #validate. Same violations as
  # #validate.
  def validate_doc(doc)
    violations(TeptrisExt.schema_validate_doc(@handle, doc))
  end

  # The retained-document twin of #valid?.
  def valid_doc?(doc)
    validate_doc(doc).empty?
  end

  def inspect
    "#<#{self.class.name}>"
  end

  private

  # The engine reports violations as a JSON array of
  # {"path", "schemaPath", "message"} objects; the wrapper owns the
  # materialized shape.
  def violations(raw_json)
    JSON.parse(raw_json).map do |v|
      Violation.new(v["path"], v["schemaPath"], v["message"])
    end
  end
end
