# frozen_string_literal: true

module Teptris
  class Error < StandardError; end

  class ParseError < Error
    attr_reader :line, :column
    # batch context: load_batch/load_slice set this to the 0-based
    # position of the failing document in the batch
    attr_accessor :index

    def initialize(message, line = 0, column = 0)
      @line = line
      @column = column
      super(message)
    end
  end
end
