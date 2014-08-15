#!/usr/bin/env ruby
require 'rss'
require 'yaml'
require 'digest'
require 'logger'
require 'open-uri'
require 'fileutils'

module Blunderbuss
  class Runner
    def initialize(config = [])
      @history      = []
      @feeds        = config['feeds']
      @path         = config['download_path']
      @history_file = config['history_file']
      @log_file     = config['log_file']

      FileUtils.touch(@log_file)     unless File.exists?(@log_file)
      FileUtils.touch(@history_file) unless File.exists?(@history_file)

      @log = Logger.new(@log_file)
      @log.level = Logger::DEBUG
      @log.debug("Starting Blunderbuss Runner.")
    end

    def load_history
      File.open(@history_file, "r").each_line {|record| @history << record.chomp }
      @log.debug("#{@history.length} history records loaded from #{@history_file}.")
    end

    def in_history?(record)
      if @history.include?(record)
        @log.debug("#{record} exists in history, skipping.")
        return true
      else
        @log.debug("#{record} does not exist in history, continuing.")
        return false
      end
    end

    def add_to_history(record)
      @history << record
      @log.debug("#{record} added to history.")
    end

    def write_history!
      @history.compact!
      @history.sort!
      @history.uniq!

      File.open(@history_file, "w+") do |file|
        @history.each { |record| file.puts(record) }
      end
      @log.debug("Wrote #{@history.length} history records to #{@history_file}.")
    end

    def sanitize_url(link)
      URI.encode(link).gsub("[","%5B").gsub("]","%5D")
    end

    def save_torrent(torrent, filename)
      target = @path + filename + ".torrent"

      unless File.exists?(target)
        File.open(target, 'wb') do |file|
          file.write(torrent.read)
        end
        @log.debug("Wrote torrent: #{target}.")
      else
        @log.warn("Torrent exists, not overwriting: #{target}.")
      end
    end

    def download_torrent(url)
      begin
        torrent = open(url)
        @log.debug("Downloading #{url}.")
      rescue
        @log.error("Error downloading #{url}, skipping.")
        return nil
      end
      return torrent
    end

    def run
      load_history

      @feeds.each do |feed|
        rss = RSS::Parser.parse(feed, false)
        rss.items.each do |item|
          next if item.link.nil?

          link = item.enclosure.url rescue item.link
          url = sanitize_url(link)
          record = Digest::MD5.hexdigest(link)

          @log.debug("Record for #{link} is #{record}.")

          next if in_history?(record)

          torrent = download_torrent(url)

          unless torrent.nil?
            save_torrent(torrent, item.title)
            add_to_history(record)
          end

        end
      end
      write_history!
    end
  end
end


config_file = ENV['HOME'] + "/.blunderbuss.yaml"

config = YAML.load_file(config_file)

Blunderbuss::Runner.new(config).run

# TODO: Daemonize.  Add CLI config. Gemify. Profit...
