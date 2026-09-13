require "ffi"

module Teptris
  # Loads the shared libteptris: TEPTRIS_LIB_PATH env, vendored
  # lib/platform/<tag>/, the sibling C checkout's build tree, then the
  # system paths (yeptris-ruby resolution chain).
  module Lib
    extend FFI::Library

    NAMES = %w[libteptris.dylib libteptris.so libteptris.dll].freeze

    def self.candidates
      out = []
      out << ENV["TEPTRIS_LIB_PATH"] if ENV["TEPTRIS_LIB_PATH"]
      out.concat(Dir[File.expand_path("../libteptris.*", __dir__)])
      NAMES.each do |n|
        %w[build build-release build-shared build-bench].each do |b|
          out << File.expand_path("../../teptris/#{b}/src/#{n}", __dir__)
        end
        out << n
      end
      out.compact
    end

    loaded = nil
    candidates.each do |c|
      begin
        ffi_lib c
        loaded = c
        break
      rescue LoadError
        next
      end
    end
    raise Error, "libteptris not found (set TEPTRIS_LIB_PATH)" unless loaded
    LIBRARY_PATH = loaded

    typedef :pointer, :doc
    typedef :pointer, :node

    attach_function :teptris_parse, [:pointer, :size_t, :pointer, :pointer], :int
    attach_function :teptris_document_free, [:doc], :void
    attach_function :teptris_document_error, [:doc], :pointer
    attach_function :teptris_document_root, [:doc], :node
    attach_function :teptris_document_emit, [:doc, :pointer, :pointer], :int
    attach_function :teptris_node_kind, [:node], :int
    attach_function :teptris_node_string, [:node, :pointer], :int
    attach_function :teptris_node_integer, [:node, :pointer], :int
    attach_function :teptris_node_float, [:node, :pointer], :int
    attach_function :teptris_node_boolean, [:node, :pointer], :int
    attach_function :teptris_node_datetime, [:node, :pointer], :int
    attach_function :teptris_node_array_length, [:node], :size_t
    attach_function :teptris_node_array_at, [:node, :size_t], :node
    attach_function :teptris_node_table_length, [:node], :size_t
    attach_function :teptris_node_table_at, [:node, :size_t, :pointer], :node
    attach_function :teptris_document_flatten, [:doc, :pointer, :pointer], :int
    attach_function :teptris_flatten_free, [:pointer], :void

    class ErrorStruct < FFI::Struct
      layout :status, :int, :line, :size_t, :column, :size_t, :message, :string
    end

    class ViewStruct < FFI::Struct
      layout :ptr, :pointer, :len, :size_t
    end

    class DateTimeStruct < FFI::Struct
      layout :year, :int32,
             :month, :uint8, :day, :uint8,
             :hour, :uint8, :minute, :uint8, :second, :uint8,
             :_pad, [:uint8, 3],
             :nanosecond, :uint32, :offset_seconds, :int32
    end
  end

  KIND = {
    string: 0, integer: 1, float: 2, boolean: 3,
    datetime: 4, datetime_local: 5, date_local: 6, time_local: 7,
    array: 8, table: 9
  }.freeze
end
