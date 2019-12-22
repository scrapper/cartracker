#!/usr/bin/env ruby -w
# encoding: UTF-8
#
# = TelemetryRecord.rb -- CarTracker - Capture and analyze your EV telemetry.
#
# Copyright (c) 2019 by Chris Schlaeger <cs@taskjuggler.org>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of version 2 of the GNU General Public License as
# published by the Free Software Foundation.
#

require 'perobs'

module CarTracker

  class TelemetryRecord < PEROBS::Object

    attr_persist :timestamp, :odometer, :speed, :outside_temperature,
      :latitude, :longitude,
      :parking_brake_active, :soc, :range, :charging_mode, :charging_power

    def initialize(p)
      super

      self.timestamp = Time.now

      restore
    end

    def restore
      self.speed = 0 if @speed.nil?
    end

    def set_odometer(km)
      # The odometer value is stored in km
      km = km.to_i
      if km <= 0 && km > 100000000
        Log.warn "Odometer value out of range: #{km}"
        return false
      end

      self.odometer = km

      true
    end

    def set_outside_temperature(kelvin)
      # The temperature is stored in deci Centigrade.
      celsius = kelvin.to_i - 2732
      if celsius <= -300 || celsius > 500
        Log.warn "Outside temperature out of range: #{celsius / 10.0} C"
        return false
      end

      self.outside_temperature = celsius

      true
    end

    def set_parking_brake_active(value)
      self.parking_brake_active = value.to_i != 0
      true
    end

    def set_soc(value)
      # The state of charge is stored in % (0 - 100)
      soc = value.to_i
      if soc < 0 || soc > 100
        Log.warn "SoC out of range: #{soc}%"
        return false
      end
      self.soc = soc

      true
    end

    def set_speed(value)
      # The speed is stored in km/h
      speed = value.to_i
      if speed < 0 || speed > 300
        Log.warn "Speed out of range: #{speed} km/h"
        return false
      end

      self.speed = speed

      true
    end

    def set_range(value)
      # The range is stored in km.
      range = value.to_i
      if range < 0 || range > 1000
        Log.warn "Range out of range: #{range} km"
        return false
      end
      self.range = range

      true
    end

    def set_position(latitude, longitude)
      # Latitude and longitude are stored in a millions of a degree.
      latitude = latitude.to_i
      if latitude < -90000000 || latitude > 90000000
        Log.warn "Latitude is out of range: #{latitude / 1000000.0}"
        return false
      end

      longitude = longitude.to_i
      if longitude < 0 || longitude > 360000000
        Log.warn "Longitude is out of range: #{longitude / 1000000.0}"
        return false
      end

      self.latitude = latitude
      self.longitude = longitude

      true
    end

    def set_charging(mode, power)
      # The mode can be off, AC or DC
      unless %w(off AC DC).include?(mode)
        Log.warn "Unknown charging mode: #{mode}"
        return false
      end
      # The power is stored in Watts
      power = power.to_i
      if power < 0 || power > 350000
        Log.warn "Power out of range: #{power / 1000.0} KW"
        return false
      end
      self.charging_mode = mode
      self.charging_power = power

      true
    end

    def to_csv
      [
        @timestamp, @odometer, @speed, @outside_temperature,
        @latitude, @longitude,
        @parking_brake_active, @soc, @range, @charging_mode, @charging_power
      ].join(',')
    end

  end

end

