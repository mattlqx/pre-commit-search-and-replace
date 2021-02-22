#!/usr/bin/env ruby
# frozen_string_literal: true

require 'optparse'
require 'yaml'

require_relative '../lib/search-and-replace'

command_opts = {}
op = OptionParser.new do |opts|
  opts.banner = "Usage: #{$PROGRAM_NAME} <args> <files>"

  opts.on('-c', '--config PATH', 'YAML config for multiple search and, optionally, replace operations') do |v|
    command_opts['config'] = v
  end
  opts.on('-s', '--search STRING', 'Search string or regexp (required if not using config)') do |v|
    command_opts['search'] = v
  end
  opts.on('-r', '--replacement STRING', 'Replacement string') do |v|
    command_opts['replacement'] = v
  end
  opts.on('-i', '--[no-]insensitive', 'Case-insensitive search') do |v|
    command_opts['insensitive'] = v
  end
  opts.on('-e', '--[no-]extended', 'Extended regexp search') do |v|
    command_opts['extended'] = v
  end
end
op.parse!
command_opts['config'] ||= '.pre-commit-search-and-replace.yaml'

if ARGV.length.zero?
  $stderr.write("No files to search supplied as arguments!\n")
  puts "\n#{op.help}"
  exit(1)
end

ARGV.reject! { |f| File.absolute_path(f) == File.absolute_path(command_opts['config']) }

configs = if command_opts['search']
            [command_opts]
          else
            begin
              YAML.safe_load(IO.read(command_opts['config']))
            rescue Errno::ENOENT
              $stderr.write("Unable to open #{command_opts['config']} and no search argument specified.\n")
              puts "\n#{op.help}"
              exit(1)
            end
          end
files_fixed = []
exit_status = 0

# Process each entry in the config against all arguments (filenames)
configs.each_with_index do |entry, i|
  puts "Config entry #{i + 1} is missing required search string." && exit(1) if entry['search'].nil?
  sar = SearchAndReplace.from_config(ARGV, entry)
  sar.parse_files.each do |result|
    next if result.empty?

    puts "==== Found #{result.length} occurrences of \"#{entry['description'] || entry['search']}\" in " \
         "#{result.first.file}:\n\n"
    puts result.occurrences.map(&:to_s).join("\n")
    exit_status = 1
    next if entry['replacement'].nil?

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

files_fixed.uniq.each { |dest| puts "Fixed #{dest}" }
exit(exit_status)
