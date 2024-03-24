#!/usr/bin/env ruby
# frozen_string_literal: true

require 'optparse'
require 'rainbow'
require 'yaml'

require_relative '../lib/search-and-replace'

command_opts = {
  :color => true,
  :write => true,
  :config => '.pre-commit-search-and-replace.yaml'
}
op = OptionParser.new do |opts|
  opts.banner = "Usage: #{$PROGRAM_NAME} <args> <files>"

  opts.on('-c', '--config PATH',
          'YAML config for multiple search and, optionally, replace operations. ' \
          'default .pre-commit-search-and-replace.yaml')
  opts.on('-s', '--search STRING', 'Search string or regexp (required if not using config)')
  opts.on('-r', '--replacement STRING', 'Replacement string')
  opts.on('-i', '--[no-]insensitive', 'Case-insensitive search')
  opts.on('-e', '--[no-]extended', 'Extended regexp search')
  opts.on('-C', '--[no-]color', 'Output coloring, default true')
  opts.on('-w', '--[no-]write', 'Write replacements to file, default true')
end
op.parse!(into: command_opts)
Rainbow.enabled = command_opts[:color]

if ARGV.length.zero?
  $stderr.write("No files to search supplied as arguments!\n")
  puts "\n#{op.help}"
  exit(1)
end

ARGV.reject! { |f| File.absolute_path(f) == File.absolute_path(command_opts[:config]) }

configs = if command_opts[:search]
            [command_opts]
          else
            begin
              YAML.safe_load(IO.read(command_opts[:config]))
            rescue Errno::ENOENT
              $stderr.write("Unable to open #{command_opts[:config]} and no search argument specified.\n")
              puts "\n#{op.help}"
              exit(1)
            end
          end
files_fixed = []
exit_status = 0

# Process each entry in the config against all arguments (filenames)
configs.each_with_index do |entry, i|
  entry.transform_keys!(&:to_sym)
  puts "Config entry #{i + 1} is missing required search string." && exit(1) if entry[:search].nil?
  sar = SearchAndReplace.from_config(ARGV, entry)
  sar.parse_files.each do |result|
    next if result.empty?

    puts "==== Found #{Rainbow(result.length).red} occurrences of " \
         "\"#{Rainbow(entry[:description] || entry[:search]).yellow}\" in " \
         "#{Rainbow(result.first.file).cyan}:\n\n"
    puts result.occurrences.map(&:to_s).join("\n")
    exit_status = 1
    next if entry[:replacement].nil?

    if command_opts[:write]
      files_fixed << result.first.file

      src = result.replacement_file_path
      dest = result.first.file

      unless RUBY_PLATFORM =~ /mswin|mingw|windows/
        stat = File.stat(dest)
        FileUtils.chown(stat.uid, stat.gid, src)
        FileUtils.chmod(stat.mode, src)
      end
      FileUtils.mv(src, dest)
    end
  end
end

files_fixed.uniq.each { |dest| puts Rainbow("Fixed #{dest}").green }
exit(exit_status)
