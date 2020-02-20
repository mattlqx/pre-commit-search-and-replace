# frozen_string_literal: true

require 'tempfile'

# A set of files represented as a collection that can each be parsed for a search string or regexp and optionally,
# atomically move a string-replaced version of the file in place.
class SearchAndReplace
  attr_reader :search
  attr_reader :replacement

  def initialize(files, search, search_opts: nil, replacement: nil)
    @files = files
    @search = pattern(search, options: search_opts)
    @replacement = replacement
    @tempfiles = []
  end

  def self.from_config(files, config)
    opts = ((config['insensitive'] && Regexp::IGNORECASE) || 0) | ((config['extended'] && Regexp::EXTENDED) || 0)
    new(files, config['search'], search_opts: opts, replacement: config['replacement'])
  end

  # Determines if string is regexp and converts to object if so
  def pattern(string, options: nil)
    !%r{^/.*/$}.match(string).nil? ? Regexp.new(string[1..-2], options) : string
  end

  def parse_files
    @files.map { |f| parse_file(f) }
  end

  # Searches a file for pattern and returns occurrence objects for each and the path to the tempfile if
  # replacement is specified
  def parse_file(filename) # rubocop:disable Metrics/AbcSize
    all_occurrences = []
    file = IO.open(IO.sysopen(filename, 'r'))
    tempfile = Tempfile.new('pre-commit-search') unless @replacement.nil?
    until file.eof?
      line = file.gets
      occurrences = search_line(filename, file.lineno, line)
      all_occurrences += occurrences
      tempfile&.write(occurrences.empty? ? line : line.gsub(@search, @replacement))
    end
    unless tempfile.nil?
      tempfile.close
      @tempfiles << tempfile # Hold on to a reference so it's not garbage collected yet
    end
    file.close
    FileMatches.new(self, filename, all_occurrences, tempfile&.path)
  end

  # Searches a line for pattern and writes string replaced line to newfile if specified
  def search_line(filename, lineno, line)
    occurrences = []
    offset = 0
    match = false
    until match.nil?
      match = line.index(@search, offset)
      offset = match + 2 if match.is_a?(Integer)
      # Don't log a match if there isn't one or if the replacement on a regex would yield no change
      next if !match.is_a?(Integer) || (!@replacement.nil? && line.gsub(@search, @replacement) == line)
      occurrences << Occurrence.new(filename, lineno, match + 1, line)
    end
    occurrences
  end

  # A collection of occurrences in a file
  class FileMatches
    attr_reader :filename
    attr_reader :search
    attr_accessor :occurrences
    attr_accessor :replacement_file_path

    def initialize(sar, filename, occurrences = [], replacement_file_path = nil)
      @occurrences = occurrences
      @replacement_file_path = replacement_file_path
      @search = sar
      @filename = filename
    end

    # :nocov:
    def to_s
      "file: #{filename}, search: '#{search.search}', replacement: '#{search.replacement || 'nil'}', " \
      "count: #{occurences.length}"
    end

    def method_missing(method, *args)
      if @occurrences.respond_to?(method)
        @occurrences.send(method, *args)
      else
        super
      end
    end

    def respond_to_missing?(method, *_args)
      @occurrences.respond_to?(method) || respond_to?(method)
    end
    # :nocov:
  end

  # Object for recording position of a search hit
  class Occurrence
    attr_accessor :file
    attr_accessor :lineno
    attr_accessor :col
    attr_accessor :context

    def initialize(file, lineno, col, context)
      @file = file
      @lineno = lineno
      @col = col
      @context = context
    end

    def to_s
      "#{file}, line #{lineno}, col #{col}:\n" \
      "    #{context.tr("\t", ' ').chomp}\n" \
      "    #{' ' * (col - 1)}^"
    end
  end
end
