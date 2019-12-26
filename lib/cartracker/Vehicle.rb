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
require 'cartracker/Charge'
require 'cartracker/Ride'

module CarTracker

  class Vehicle < PEROBS::Object

    attr_persist :vin, :telemetry, :rides, :charges, :next_server_sync_time, :server_sync_pause_mins

    def initialize(p)
      super(p)
      restore
    end

    def restore
      self.telemetry = @store.new(PEROBS::BigArray) unless @telemetry
      self.rides = @store.new(PEROBS::BigArray) unless @rides
      self.charges = @store.new(PEROBS::BigArray) unless @charges
      self.server_sync_pause_mins = 10 unless @server_sync_pause_mins
    end

    def add_record(record)
      # We only store the new record if at least one value differs from the
      # previous record (with the exception of the timestamp).
      if @telemetry.last != record
        update_next_poll_time(:shorter, record.state)
        @telemetry << record
        analyze_telemetry_record(@telemetry.length - 1)
      else
        update_next_poll_time(:longer)
      end
    end

    def analyze_telemetry
      self.rides = @store.new(PEROBS::BigArray)
      self.charges = @store.new(PEROBS::BigArray)

      2.upto(@telemetry.length - 1) do |i|
        analyze_telemetry_record(i)
      end
    end

    def list_rides
      s = ''
      @rides.each { |r| s += r.to_ary.join(', ') + "\n" }
      s
    end

    def list_charges
      s = ''
      @charges.each { |c| s += c.to_ary.join(', ') + "\n" }
      s
    end

    def to_csv
      s = ''
      @telemetry.each { |t| s += t.to_csv + "\n" }
      s
    end

    private

    def analyze_telemetry_record(index)
      # We need at least 3 previous entries for a meaningful result.
      return if index < 2

      # Index    State  idx    record
      # index-5    A
      # index-4    A    idx3   r3
      # index-3    B    idx2   r2
      # index-2    B
      # index-1    B    idx1   r1
      # index      C    index  r0
      # r1 and r2 can be identical or any number of indicies apart.

      r0 = @telemetry[index]
      r1 = @telemetry[idx1 = index - 1]
      state = r1.state
      if state != r0.state
        # Find the index of the end of state before the last state
        idx3 = idx1
        while idx3 > 0 && @telemetry[idx3].state == state
          idx3 -= 1
        end
        idx2 = @telemetry[idx3].state != @telemetry[idx3 + 1].state ?
          idx3 + 1 : idx3
        r2 = @telemetry[idx2]
        r3 = @telemetry[idx3]

        # The vehicle state has changed.
        case state
        when :charging_ac, :charging_dc
          extract_charge(r3, r0, r2)
          if r3.state == :parking && r2.odometer > r3.odometer
            # We are missing a ride in the telemetry right before reaching the
            # charing station. Let's try to reconstruct it.
            extract_ride(r3, r2)
          end
          if r0.state == :parking && r0.odometer > r1.odometer
            # We are missing a ride in the telemetry right after the charing.
            # Let's try to reconstruct it.
            extract_ride(r1, r2)
          end
        when :driving
          extract_ride(r3, r0)
          if r3.state == :parking && r2.soc > r3.soc
            # We are missing a charge in the telemetry data right before the
            # ride. Let's try to reconstruct it.
            extract_charge(r3, r2)
          end
          if r0.state == :parking && r0.soc > r1.soc
            # We are missing a charge in the telemetry data right after the
            # ride. Let's try to reconstruct it.
            extract_charge(r1, r0)
          end
        end
      elsif r0.state == :parking && r1.state == :parking
        if r0.odometer > r1.odometer
          # We are missing a driving record in the telemetry data. Let's try to
          # reconstruct it.
          extract_ride(r1, r0)
        elsif r0.soc > r1.soc
          # We are missing a charging record in the telemetry data. Let's try
          # to reconstruct it.
          extract_charge(r1, r0)
        end
      end
    end

    def extract_ride(start_record, end_record)
      energy = soc2energy(start_record.soc - end_record.soc)
      energy = 0.0 if energy < 0.0
      @rides << (ride = @store.new(Ride))
      ride.start_timestamp = start_record.timestamp
      ride.start_soc = start_record.soc
      ride.start_latitude = start_record.latitude
      ride.start_longitude = start_record.longitude
      ride.end_timestamp = end_record.timestamp
      ride.end_soc = end_record.soc
      ride.end_latitude = end_record.latitude
      ride.end_longitude = end_record.longitude
      ride.distance = end_record.odometer - start_record.odometer
      ride.energy = energy
    end

    def extract_charge(start_record, end_record, charge_record = nil)
      start_soc = charge_record && charge_record.soc < start_record.soc ?
        charge_record.soc : start_record.soc
      if (soc_delta = end_record.soc - start_soc) < 2 &&
          (charge_record.nil? || charge_record.charging_mode == 'off')
        # Small SoC increases can be caused by temperature variations.
        # If we don't have a confirmation from the charging_mode field
        # we don't count the increase as a charge cycle.
        return
      end
      energy = soc2energy(soc_delta)
      energy = 0.0 if energy < 0.0
      @charges << (charge = @store.new(Charge))
      charge.energy = energy
      charge.type = charge_record.nil? ? 'AC' :
        charge_record.state == :charging_ac ? 'AC' : 'DC'
      charge.start_timestamp = start_record.timestamp
      charge.start_soc = start_soc
      charge.end_timestamp = end_record.timestamp
      charge.end_soc = end_record.soc
      charge.latitude = charge_record ? charge_record.latitude : nil
      charge.longitude = charge_record ? charge_record.longitude : nil
    end

    def update_next_poll_time(direction, state = nil)
      pause_mins = @server_sync_pause_mins
      if direction == :longer
        hour = Time.now.hour
        hourly_max_interval_mins = [
          180, 180, 180, 180, 180, 90,
          60, 30, 15, 15, 15, 15,
          15, 15, 15, 15, 15, 15,
          30, 30, 30, 90, 180, 180
        ]
        max_interval_mins = hourly_max_interval_mins[hour]
        pause_mins = (pause_mins * 1.5).to_i
        if pause_mins > max_interval_mins
          pause_mins = max_interval_mins
        end
      else
        # Immediately go to minimum paus time case on current state of the vehicle.
        pause_mins = state == :charging_dc ? 2 : 5
      end

      self.server_sync_pause_mins = pause_mins
      self.next_server_sync_time = Time.now + pause_mins * 60
      Log.info("Next server sync for #{@vin} is scheduled for #{@next_server_sync_time}")
    end

    def soc2energy(soc)
      # This is currently hardcoded for the Audi e-tron 55 Quattro. It has a
      # net battery capacity of 83.7 kWh.
      83.7 * soc / 100.0
    end

  end

end

