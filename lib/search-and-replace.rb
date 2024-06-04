# frozen_string_literal: true

require 'rainbow'
require 'tempfile'

# A set of files represented as a collection that can each be parsed for a search string or regexp and optionally,
# atomically move a string-replaced version of the file in place.
class SearchAndReplace
  attr_reader :search
  attr_reader :replacement

  def initialize(files, search, search_opts: nil, replacement: nil)
    @files = files
    @search = pattern(search, options: search_opts)
    @search_opts = search_opts
    @replacement = replacement
    @tempfiles = []
  end

  def self.from_config(files, config)
    config.transform_keys!(&:to_sym)
    opts = ((config[:insensitive] && Regexp::IGNORECASE) || 0) | ((config[:extended] && Regexp::EXTENDED) || 0)
    new(files, config[:search], search_opts: opts, replacement: config[:replacement])
  end

  # Determines if string is regexp and converts to object if so
  def pattern(string, options: nil)
    !%r{^/.*/$}.match(string).nil? ? Regexp.new("(?<sar_all>#{string[1..-2]})", options) : string
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
      if line.index(%r{(//|//*|#|<!--)\s*no-search-replace})
        match = nil
      elsif @search_opts & Regexp::IGNORECASE == Regexp::IGNORECASE && @search.is_a?(String)
        match = line.downcase.index(@search.downcase, offset)
      elsif @search.is_a?(String)
        match = line.index(@search, offset)
      else
        match = @search.match(line, offset)
      end

      if match.is_a?(Integer)
        offset = match + 2
      elsif match.is_a?(MatchData)
        offset = match.begin(:sar_all) + 2
      end

      # Don't log a match if there isn't one or if the replacement on a regex would yield no change
      next if match.nil? || (!@replacement.nil? && line.gsub(@search, @replacement) == line)

      occurrences << Occurrence.new(filename, lineno, offset - 1, length_from_match(match), line, @replacement)
    end
    occurrences
  end

  def length_from_match(match)
    if match.is_a?(Integer)
      @search.length
    elsif match.is_a?(MatchData)
      match.match_length(:sar_all)
    end
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
      @occurrences.respond_to?(method)
    end
    # :nocov:
  end

  # Object for recording position of a search hit
  class Occurrence
    attr_accessor :file
    attr_accessor :lineno
    attr_accessor :col
    attr_accessor :length
    attr_accessor :context

    def initialize(file, lineno, col, length, context, replacement)
      @file = file
      @lineno = lineno
      @col = col
      @length = length
      @context = context
      @replacement = replacement
    end

    def to_s
      str = "#{Rainbow(file).cyan}, line #{lineno}, col #{col}:\n    " \
            "#{context.tr("\t", ' ').chomp}\n    " \
            "#{' ' * (col - 1)}#{Rainbow('^' * @length).red}\n"

      if @replacement
        replaced_line = @context.split(//)
        (@col - 1...col - 1 + @length).each do |i|
          replaced_line.delete_at(@col - 1)
        end
        replaced_line.insert(@col - 1, Rainbow(@replacement).green.split(//))
        replaced_line = replaced_line.join('')

        str += "After replacement:\n    " \
               "#{replaced_line.tr("\t", ' ').chomp}\n"
      end
      str
    end
  end
end
