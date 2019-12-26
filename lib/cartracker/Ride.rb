#!/usr/bin/env ruby -w
# encoding: UTF-8
#
# = Ride.rb -- CarTracker - Capture and analyze your EV telemetry.
#
# Copyright (c) 2019 by Chris Schlaeger <cs@taskjuggler.org>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of version 2 of the GNU General Public License as
# published by the Free Software Foundation.
#
require 'perobs'

module CarTracker

  class Ride < PEROBS::Object

    attr_persist :start_timestamp, :start_soc,
      :start_latitude, :start_longitude, :start_odometer, :start_temperature,
      :end_timestamp, :end_soc, :end_latitude, :end_longitude,
      :end_odometer, :end_temperature, :energy

    def initialize(p)
      super
    end

    def restore
    end

    def to_ary
      [
        @start_timestamp, @start_soc, @start_latitude, @start_longitude,
        @start_odometer, @start_temperature,
        @end_timestamp, @end_soc, @end_latitude, @end_longitude,
        @end_odometer, @end_temperature, @energy
      ]
    end

  end

end


