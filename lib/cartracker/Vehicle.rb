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
require 'cartracker/FlexiTable'
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

    def add_record(record, rgc)
      # We only store the new record if at least one value differs from the
      # previous record (with the exception of the timestamp).
      if @telemetry.last != record
        update_next_poll_time(:shorter, record.state)
        @telemetry << record
        analyze_telemetry_record(@telemetry.length - 1, rgc)
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

    def dump_rides
      s = ''
      @rides.each { |r| s += r.to_ary.join(', ') + "\n" }
      s
    end

    def list_rides
      t = FlexiTable.new
      t.head
      Ride::table_header(t)
      t.body
      @rides.each { |ride| ride.table_row(t) }

      t
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

    def analyze_telemetry_record(index, rgc)
      # We need at least 3 entries for a meaningful result.
      return if index <= 2

      # Index    State  idx    record
      # index-5    A
      # index-4    A    idx3   r3
      # index-3    B    idx2   r2
      # index-2    B
      # index-1    B    idx1   r1
      # index      C    index  r0
      # r1 and r2 can be identical or any number of indicies apart. r3 is
      # identical to r1 and r2 if r1 and r2 are the same.

      r0 = @telemetry[index]
      r1 = @telemetry[idx1 = index - 1]
      state = r1.state
      if state_changed?(r1, r0)
        # Find the index of the end of state before the last state
        r3 = @telemetry[idx3 = idx1 - 1]
        while !state_changed?(r3, r1)
          r3 = @telemetry[idx3 -= 1]
        end
        if idx3 == idx1 - 1
          # We have not found a block of records with the same state after the
          # current record. In this case r1, r2, and r3 point to the record
          # right after the current record.
          idx2 = idx3 = idx1
          r2 = r3 = r1
        else
          # We have found a block of at least 2 consecutive records with the
          # same state.
          idx2 = idx3 + 1
          r2 = @telemetry[idx2]
        end

        if r0.odometer > r2.odometer
          extract_ride(r2, r0, rgc)
        end
        if r0.soc > r2.soc
          extract_charge(r2, r0, r2)
        end
      end
    end

    def extract_ride(start_record, end_record, rgc)
      energy = soc2energy(start_record.soc - end_record.soc)
      energy = 0.0 if energy < 0.0
      @rides << (ride = @store.new(Ride))
      ride.vehicle = myself
      ride.start_timestamp = start_record.last_vehicle_contact_time ||
        start_record.timestamp
      # If the SOC increased during a ride we ignore the increase and use
      # end SOC for both values.
      ride.start_soc = end_record.soc < start_record.soc ?
        start_record.soc : end_record.soc
      ride.start_latitude = start_record.latitude
      ride.start_longitude = start_record.longitude
      ride.map_locations_to_addresses(rgc)
      ride.start_odometer = start_record.odometer
      ride.start_temperature = start_record.outside_temperature
      ride.end_timestamp = end_record.last_vehicle_contact_time ||
        end_record.timestamp
      ride.end_soc = end_record.soc
      ride.end_latitude = end_record.latitude
      ride.end_longitude = end_record.longitude
      ride.end_odometer = end_record.odometer
      ride.end_temperature = end_record.outside_temperature
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
        charge_record.state == :charging_dc ? 'DC' : 'AC'
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
          180, 180, 180, 180, 90, 60,
          15, 15, 15, 15, 15, 15,
          15, 15, 15, 15, 15, 15,
          30, 30, 30, 90, 180, 180
        ]
        max_interval_mins = hourly_max_interval_mins[hour]
        pause_mins = (pause_mins * 1.5).to_i
        if pause_mins > max_interval_mins
          pause_mins = max_interval_mins
        end
      else
        # Immediately go to minimum pause time based on the current state of
        # the vehicle.
        pause_mins = state == :charging_dc ? 2 : 5
      end

      self.server_sync_pause_mins = pause_mins
      self.next_server_sync_time = Time.now + pause_mins * 60
      Log.info("Next server sync for #{@vin} is scheduled in " +
               "#{@server_sync_pause_mins} minutes at " +
               "#{@next_server_sync_time}")
    end

    def state_changed?(first_record, second_record)
      first_record.state != (state = second_record.state) ||
        (state != :driving && first_record.odometer < second_record.odometer) ||
        ((state != :charging_ac || state == :charging_dc) &&
         first_record.soc < second_record.soc)
    end

    def soc2energy(soc)
      # This is currently hardcoded for the Audi e-tron 55 Quattro. It has a
      # net battery capacity of 83.7 kWh.
      83.7 * soc / 100.0
    end

  end

end

