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

    attr_persist :timestamp, :last_vehicle_contact_time,
      :odometer, :speed, :parking_lights, :outside_temperature,
      :doors_unlocked, :doors_open, :windows_open,
      :latitude, :longitude,
      :parking_brake_active, :soc, :range,
      :charging_mode, :charging_power, :external_power_supply_state,
      :energy_flow, :charging_state, :remaining_charging_time,
      :remaining_charging_time_target_soc, :plug_state,
      :climater_temperature, :climater_status

    def initialize(p)
      super

      self.timestamp = Time.now
      self.doors_unlocked = 0
      self.doors_open = 0
      self.windows_open = 0

      restore
    end

    def restore
      self.parking_lights = false if @parking_lights.nil?
      self.speed = 0 if @speed.nil?
      self.doors_unlocked = 0 unless @doors_unlocked.nil?
      self.doors_open = 0 unless @doors_open.nil?
      self.windows_open = 0 unless @windows_open.nil?
      unless @external_power_supply_state
        self.external_power_supply_state = ''
      end
      self.energy_flow = '' unless @energy_flow.nil?
      self.charging_state = '' unless @charging_state.nil?
      self.remaining_charging_time = 0 unless @remaining_charging_time.nil?
      unless @remaining_charging_time_target_soc.nil?
        self.remaining_charging_time_target_soc = ''
      end
      self.plug_state = '' unless @plug_state.nil?
      self.climater_temperature = 0 unless @climater_temperature.nil?
      self.climater_status = 'off' unless @climater_status.nil?
    end

    def ==(r)
      self.class.attributes.each do |a|
        # The timestamp alway changes from entry to entry. We can ignore it
        # for the purpose of this comparison.
        next if a == :timestamp

        unless r.instance_variable_get('@' + a.to_s) ==
            instance_variable_get('@' + a.to_s)
          return false
        end
      end

      true
    end

    def state
      if @charging_mode == 'AC'
        return :charging_ac
      elsif @charging_mode == 'DC'
        return :charging_dc
      elsif @parking_brake_active
        return :parking
      else
        return :driving
      end
    end

    def set_last_vehicle_contact_time(ts)
      # The timestamp of the last successful contact with the vehicle.
      begin
        self.last_vehicle_contact_time = Time.parse(ts)
      rescue ArgumentError
        return
      end
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

    def set_parking_lights(text_id)
      self.parking_lights = text_id != 'status_parking_light_off'

    end

    def set_outside_temperature(kelvin, text_id)
      return false unless text_id == 'temperature_outside_valid'

      # The temperature is stored in deci Centigrade.
      celsius = kelvin.to_i - 2732
      if celsius <= -300 || celsius > 500
        Log.warn "Outside temperature out of range: #{celsius / 10.0} C"
        return false
      end

      self.outside_temperature = celsius

      true
    end

    def set_climater_temperature(kelvin)
      return false unless kelvin

      # The temperature is stored in deci Centigrade.
      celsius = kelvin.to_i - 2732
      if celsius <= -300 || celsius > 500
        Log.warn "Climater temperature out of range: #{celsius / 10.0} C"
        return false
      end

      self.climater_temperature = celsius

      true
    end

    def set_climater_status(status)
      return false unless status

      self.climater_status = status

      true
    end

    def set_parking_brake_active(value)
      self.parking_brake_active = value.to_i != 0
      true
    end

    def set_soc(value, text_id)
      return false if text_id != 'soc_ok'

      # The state of charge is stored in % (0 - 100)
      soc = value.to_i
      if soc < 0 || soc > 100
        Log.warn "SoC out of range: #{soc}%"
        return false
      end
      self.soc = soc

      true
    end

    def set_speed(value, text_id)
      return false if text_id != 'speed_ok'

      # The speed is stored in km/h
      speed = value.to_i
      if speed < 0 || speed > 300
        Log.warn "Speed out of range: #{speed} km/h"
        return false
      end

      self.speed = speed

      true
    end

    def set_door_unlocked(door, status)
      case door
      when :front_left
        self.doors_unlocked |= 1 if status != 'door_locked'
      when :rear_left
        self.doors_unlocked |= 2 if status != 'door_locked'
      when :front_right
        self.doors_unlocked |= 4 if status != 'door_locked'
      when :rear_right
        self.doors_unlocked |= 8 if status != 'door_locked'
      when :hatch
        self.doors_unlocked |= 16 if status != 'door_locked'
      else
        raise ArgumentError, "Unknown door type: #{door}"
      end
    end

    def set_door_open(door, status)
      case door
      when :front_left
        self.doors_open |= 1 if status != 'door_closed'
      when :front_right
        self.doors_open |= 2 if status != 'door_closed'
      when :rear_left
        self.doors_open |= 4 if status != 'door_closed'
      when :rear_right
        self.doors_open |= 8 if status != 'door_closed'
      when :hatch
        self.doors_open |= 16 if status != 'door_closed'
      when :hood
        self.doors_open |= 32 if status != 'door_closed'
      else
        raise ArgumentError, "Unknown door type: #{door}"
      end
    end

    def set_window_open(window, status)
      case window
      when :front_left
        self.windows_open |= 1 if status != 'window_closed'
      when :front_right
        self.windows_open |= 2 if status != 'window_closed'
      when :rear_left
        self.windows_open |= 4 if status != 'window_closed'
      when :rear_right
        self.windows_open |= 8 if status != 'window_closed'
      else
        raise ArgumentError, "Unknown window type: #{window}"
      end
    end

    def set_range(value, text_id)
      return false if text_id != 'range_ok'

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
      return false unless latitude && longitude

      # Latitude and longitude are stored in a millions of a degree.
      latitude = latitude.to_i

      if latitude == -134217726 || longitude == -134217726
        # This value is sent if the GPS did not properly transfer the current
        # position to the telemetry system.
        self.latitude = nil
        self.longitude = nil

        return true
      end

      if latitude < -90000000 || latitude > 90000000
        Log.warn "Latitude is out of range: #{latitude / 1000000.0}"
        return false
      end

      longitude = longitude.to_i
      if longitude < -180000000 || longitude > 1800000000
        Log.warn "Longitude is out of range: #{longitude / 1000000.0}"
        return false
      end

      self.latitude = latitude
      self.longitude = longitude

      true
    end

    def set_charging(mode, power, external_power_supply_state,
                     energy_flow, charging_state, remaining_charging_time,
                     remaining_charging_time_target_soc, plug_state)
      return false unless mode && power

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
      self.external_power_supply_state = external_power_supply_state
      self.energy_flow = energy_flow
      self.charging_state = charging_state
      self.remaining_charging_time = remaining_charging_time
      self.remaining_charging_time_target_soc =
        remaining_charging_time_target_soc
      self.plug_state = plug_state

      true
    end

    def latitude_f
      return nil unless @latitude
      @latitude / 1000000.0
    end

    def longitude_f
      return nil unless @longitude
      @longitude / 1000000.0
    end

    def to_csv
      [
        @timestamp, @last_vehicle_contact_time,
        @odometer, @speed, @outside_temperature,
        @doors_unlocked, @doors_open, @windows_open,
        @latitude, @longitude,
        @parking_brake_active, @soc, @range, @charging_mode, @charging_power,
        @remaining_charging_time, @remaining_charging_time_target_soc,
        @climater_temperature, @climater_status
      ].join(',')
    end

  end

end

