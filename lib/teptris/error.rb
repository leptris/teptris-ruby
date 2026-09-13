module Teptris
  class Error < StandardError; end

  class ParseError < Error
    attr_reader :line, :column

    def initialize(message, line = 0, column = 0)
      @line = line
      @column = column
      super(message)
    end
  end
end
