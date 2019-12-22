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
        else
          $stderr.puts "Usage: cartracker <update|list>"
        end
      ensure
        @db.exit if @db
      end
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
