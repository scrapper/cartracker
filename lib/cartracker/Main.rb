#!/usr/bin/env ruby -w
# encoding: UTF-8
#
# = Main.rb -- CarTracker - Capture and analyze your EV telemetry.
#
# Copyright (c) 2019 by Chris Schlaeger <cs@taskjuggler.org>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of version 2 of the GNU General Public License as
# published by the Free Software Foundation.
#
require 'fileutils'
require 'perobs'

require 'cartracker/Log'
require 'cartracker/AudiConnector'

module CarTracker

  class Main

    def main(argv)
      app_dir = File.join(Dir.home, '.cartracker')
      create_directory(app_dir, 'Application directory')

      # Open a log file to record warning and error messages
      log_file_name = File.join(app_dir, "cartracker.log")
      begin
        mode = File::WRONLY | File::APPEND
        mode |= File::CREAT unless File.exist?(log_file_name)
        log_file = File.open(log_file_name, mode)
      rescue IOError => e
        $stderr.puts "Cannot open log file #{log_file_name}: #{e.message}"
        return 1
      end
      Log.open(log_file)

      begin
        @db = PEROBS::Store.new(app_dir)

        unless (ac = @db['AudiConnector'])
          ac = @db['AudiConnector'] = @db.new(AudiConnector)
        end

        case argv[0]
        when 'update'
          ac.update_vehicles
        when 'list'
          ac.list_vehicles
        when 'sync'
          ac.sync_vehicles
        else
          $stderr.puts "Usage: cartracker <update|list|sync>"
        end
      ensure
        @db.exit if @db
      end

      log_file.close
    end

    private

    def create_directory(dir, name)
      return if Dir.exists?(dir)

      $stderr.puts "Creating #{name} directory #{dir}"
      begin
        FileUtils.mkdir_p(dir)
      rescue StandardError
        raise RuntimeError, "Cannot create #{name} directory #{dir}: #{$!}"
      end
    end

  end

end
