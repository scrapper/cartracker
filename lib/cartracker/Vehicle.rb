#!/usr/bin/env ruby -w
# encoding: UTF-8
#
# = Vehicle.rb -- CarTracker - Capture and analyze your EV telemetry.
#
# Copyright (c) 2019 by Chris Schlaeger <cs@taskjuggler.org>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of version 2 of the GNU General Public License as
# published by the Free Software Foundation.
#
require 'perobs'

require 'cartracker/Log'

module CarTracker

  class Vehicle < PEROBS::Object

    attr_persist :fin, :telemetry

    def initialize(p)
      super(p)
      restore
    end

    def restore
      unless @telemetry
        self.telemetry = @store.new(PEROBS::BigArray)
      end
    end

    def add_record(record)
      @telemetry << record
    end

    def to_csv
      s = ''
      @telemetry.each { |t| s += t.to_csv + "\n" }

      s
    end

  end

end

