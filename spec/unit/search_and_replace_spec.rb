# frozen_string_literal: true

require_relative '../spec_helper'
require './lib/search-and-replace'

require 'fileutils'
require 'mixlib/shellout'
require 'rainbow'
require 'tempfile'
require 'yaml'

describe SearchAndReplace do
  let(:files) do
    %W(
      #{__dir__}/fixtures/bad_content.txt
      #{__dir__}/fixtures/good_content.txt
      #{__dir__}/fixtures/ignore_content.txt
    )
  end

  context 'when loading a config' do
    let(:configs) do
      yaml = YAML.safe_load(IO.read("#{__dir__}/fixtures/search-and-replace.yaml"))
      # Convenience naming the different configs
      {
        'foobar' => yaml[0],
        'bad regexp' => yaml[1],
        'insensitive' => yaml[2],
        'insensitive string' => yaml[3],
        'regex foobar' => yaml[4],
        'ignored hash comment' => yaml[5],
        'ignored double slash comment' => yaml[6],
      }
    end

    let(:sar) do
      lambda do |c|
        described_class.from_config(files, c)
      end
    end

    it 'contains all foobar config entries' do
      expect(sar.call(configs['foobar']).search).to be_a(String)
      expect(sar.call(configs['foobar']).search).to eq('foobar')
      expect(sar.call(configs['foobar']).replacement).to eq('fooBAZ')
    end

    it 'contains all bad regexp config entries' do
      expect(sar.call(configs['bad regexp']).search).to be_a(Regexp)
      expect(sar.call(configs['bad regexp']).search).to eq(/(?<sar_all>Bad\s*Regexp)/)
      expect(sar.call(configs['bad regexp']).search.options).to eq(0)
      expect(sar.call(configs['bad regexp']).replacement).to be_nil
    end

    it 'contains all insensitive config entries' do
      expect(sar.call(configs['insensitive']).search).to be_a(Regexp)
      expect(sar.call(configs['insensitive']).search).to eq(/(?<sar_all>InsensitiveREGEXP)/i)
      expect(sar.call(configs['insensitive']).search.options).to eq(Regexp::IGNORECASE)
      expect(sar.call(configs['insensitive']).replacement).to be_nil
    end

    it 'has correct number of occurrences for foobar config' do
      expect(sar.call(configs['foobar']).parse_files[0]).to be_a(SearchAndReplace::FileMatches)
      expect(sar.call(configs['foobar']).parse_files[0].length).to eq(1)
      expect(sar.call(configs['foobar']).parse_files[1]).to be_a(SearchAndReplace::FileMatches)
      expect(sar.call(configs['foobar']).parse_files[1].empty?).to be true
    end

    it 'has correct number of occurrences for bad regexp config' do
      expect(sar.call(configs['bad regexp']).parse_files[0]).to be_a(SearchAndReplace::FileMatches)
      expect(sar.call(configs['bad regexp']).parse_files[0].length).to eq(2)
      expect(sar.call(configs['bad regexp']).parse_files[1]).to be_a(SearchAndReplace::FileMatches)
      expect(sar.call(configs['bad regexp']).parse_files[1].empty?).to be true
    end

    it 'has correct number of occurrences for insensitive config' do
      expect(sar.call(configs['insensitive']).parse_files[0]).to be_a(SearchAndReplace::FileMatches)
      expect(sar.call(configs['insensitive']).parse_files[0].length).to eq(1)
      expect(sar.call(configs['insensitive']).parse_files[1]).to be_a(SearchAndReplace::FileMatches)
      expect(sar.call(configs['insensitive']).parse_files[1].empty?).to be true
    end

    it 'has correct number of occurrences for insensitive string config' do
      expect(sar.call(configs['insensitive string']).parse_files[0]).to be_a(SearchAndReplace::FileMatches)
      expect(sar.call(configs['insensitive string']).parse_files[0].length).to eq(1)
      expect(sar.call(configs['insensitive string']).parse_files[1]).to be_a(SearchAndReplace::FileMatches)
      expect(sar.call(configs['insensitive string']).parse_files[1].empty?).to be true
    end

    it 'does not register an occurrence if replacement would not change line' do
      expect(sar.call(configs['regex foobar']).parse_files[0]).to be_a(SearchAndReplace::FileMatches)
      expect(sar.call(configs['regex foobar']).parse_files[0].length).to eq(0)
    end

    it 'prints an occurrence correctly' do
      expect(sar.call(configs['foobar']).parse_files[0].first.to_s).to eq \
        Rainbow("#{__dir__}/fixtures/bad_content.txt").cyan + ", line 4, col 13:\n    " +
        "Here's one: foobar\n                " +
        Rainbow('^^^^^^').red +
        "\nAfter replacement:\n" +
        "    Here's one: #{Rainbow('fooBAZ').green}\n"
    end

    it 'does not match an ignored hash comment' do
      expect(sar.call(configs['ignored hash comment']).parse_files[2]).to be_a(SearchAndReplace::FileMatches)
      expect(sar.call(configs['ignored hash comment']).parse_files[2].length).to eq(0)
    end

    it 'does not match an ignored double slash comment' do
      expect(sar.call(configs['ignored double slash comment']).parse_files[2]).to be_a(SearchAndReplace::FileMatches)
      expect(sar.call(configs['ignored double slash comment']).parse_files[2].length).to eq(0)
    end
  end

  context 'when run from the command-line' do
    let(:sar) do
      cmd = "#{__dir__}/../../bin/search-and-replace.rb #{args} #{run_files.map(&:path).join(' ')}"
      Mixlib::ShellOut.new(cmd).run_command
    end
    let(:bad_file) { files[0] }
    let(:good_file) { files[1] }
    let(:ignore_file) { files[2] }
    let(:bad_tempfile) { Tempfile.new('rspec-sar') }
    let(:good_tempfile) { Tempfile.new('rspec-sar') }
    let(:ignore_tempfile) { Tempfile.new('rspec-sar') }

    before do
      FileUtils.cp(bad_file, bad_tempfile.path)
      FileUtils.cp(good_file, good_tempfile.path)
      FileUtils.cp(ignore_file, ignore_tempfile.path)
    end

    context 'with a good file' do
      let(:run_files) { [good_tempfile] }
      let(:args) { '-s Something' }

      it 'exits normally' do
        expect(sar.exitstatus).to eq(0)
      end
    end

    context 'with a bad file' do
      let(:run_files) { [bad_tempfile] }
      let(:args) { '-s foobar' }

      it 'exits with error' do
        expect(sar.exitstatus).to eq(1)
      end
    end

    context 'with a bad file and insensitive search' do
      let(:run_files) { [bad_tempfile] }
      let(:args) { '-s "There are SO many" -i' }

      it 'exits with error' do
        expect(sar.exitstatus).to eq(1)
      end
    end

    context 'with a bad file and replacement' do
      let(:run_files) { [bad_tempfile] }
      let(:args) { '-s foobar -r youbar' }

      it 'exits with error' do
        expect(sar.exitstatus).to eq(1)
      end

      it 'replaces string with replacement' do
        expect(sar.exitstatus).to eq(1)
        new_content = IO.read(run_files[0].path)
        expect(new_content.index('foobar')).to be_nil
        expect(new_content.index('youbar')).to be >= 0
      end
    end

    context 'with a bad file and replacement doesn\'t write disabled' do
      let(:run_files) { [bad_tempfile] }
      let(:args) { '-s foobar -r youbar --no-write' }

      it 'exits with error' do
        expect(sar.exitstatus).to eq(1)
      end

      it 'does not replace string with replacement' do
        expect(sar.exitstatus).to eq(1)
        new_content = IO.read(run_files[0].path)
        expect(new_content.index('youbar')).to be_nil
        expect(new_content.index('foobar')).to be >= 0
      end
    end

    context 'with a file with ignored content' do
      let(:run_files) { [ignore_tempfile] }

      context 'in a hash comment' do
        let(:args) { '-s "some special text"' }

        it 'exits with no error' do
          expect(sar.exitstatus).to eq(0)
        end
      end

      context 'in a double slash comment' do
        let(:args) { '-s "some very special text"' }

        it 'exits with no error' do
          expect(sar.exitstatus).to eq(0)
        end
      end
    end
  end
end
