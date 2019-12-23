#!/usr/bin/env ruby -w
# encoding: UTF-8
#
# = Charge.rb -- CarTracker - Capture and analyze your EV telemetry.
#
# Copyright (c) 2019 by Chris Schlaeger <cs@taskjuggler.org>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of version 2 of the GNU General Public License as
# published by the Free Software Foundation.
#
require 'perobs'

module CarTracker

  class Charge < PEROBS::Object

    attr_persist :start_timestamp, :start_soc,
      :end_timestamp, :end_soc, :energy, :type, :latitude, :longitude

    def initialize(p)
      super
    end

    def restore
    end

    def to_ary
      [
        @start_timestamp, @start_soc, @end_timestamp, @end_soc,
        @energy, @type, @latitude, @longitude
      ]
    end

  end

end

