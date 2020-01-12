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
require 'cartracker/TimeUtils'


#   /---\
#  |/   \|
#  <\---/>
#  ||   ||
#  |/---\|
#  \-----/


module CarTracker

  class Vehicle < PEROBS::Object

    attr_persist :vin, :telemetry, :rides, :charges, :next_server_sync_time,
      :server_sync_pause_mins

    @@DOORS = [ 'FL', 'FR', 'RL', 'RR', 'hatch', 'hood' ]

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

    def last_vehicle_contact_time
      @telemetry.last.last_vehicle_contact_time
    end

    def add_record(record, rgc)
      # We only store the new record if at least one value differs from the
      # previous record (with the exception of the timestamp).
      if @telemetry.last != record
        @telemetry << record
        analyze_telemetry_record(@telemetry.length - 1, rgc)
      end
    end

    def analyze_telemetry(rgc)
      self.rides = @store.new(PEROBS::BigArray)
      self.charges = @store.new(PEROBS::BigArray)

      2.upto(@telemetry.length - 1) do |i|
        analyze_telemetry_record(i, rgc)
      end
    end

    def dump_rides
      s = ''
      @rides.each { |r| s += r.to_ary.join(', ') + "\n" }
      s
    end

    def dump_charges
      s = ''
      @charges.each { |c| s += c.to_ary.join(', ') + "\n" }
      s
    end

    def list_rides
      t = FlexiTable.new
      t.head
      Ride::table_header(t)
      t.body
      @rides.each { |ride| ride.table_row(t) }
      t.foot
      Ride::table_footer(t)

      t
    end

    def list_charges
      t = FlexiTable.new
      t.head
      Charge::table_header(t)
      t.body
      @charges.each { |charge| charge.table_row(t) }
      t.foot
      Charge::table_footer(t)

      t
    end

    def show_status(rgc)
      r = @telemetry.last

      t = FlexiTable.new
      t.body
      t.cell('Last vehicle contact:')
      t.cell(r.last_vehicle_contact_time)
      t.new_row
      t.cell('Odometer:')
      t.cell("#{r.odometer} km")
      t.new_row
      t.cell('Parking lights:')
      t.cell(r.parking_lights ? 'on' : 'off')
      t.new_row
      t.cell('Open doors:')
      if r.doors_open == 0
        t.cell('all closed')
      else
        doors = []
        0.upto(5) do |bit|
          doors << @@DOORS[bit] if r.doors_open & (1 << bit) != 0
        end
        t.cell(doors.join(', '))
      end
      t.new_row
      t.cell('Unlocked doors:')
      if r.doors_unlocked == 0
        t.cell('all locked')
      else
        doors = []
        0.upto(5) do |bit|
          doors << @@DOORS[bit] if r.doors_unlocked & (1 << bit) != 0
        end
        t.cell(doors.join(', '))
      end
      t.new_row
      t.cell('Open windows: ')
      if r.windows_open == 0
        t.cell('all closed')
      else
        s = ''
        0.upto(3) do |bit|
          s << @@DOORS[bit] + ', ' if r.windows_open & (1 << bit) != 0
        end
        s << 'open'
        t.cell(s)
      end
      t.new_row
      t.cell('Position:')
      if r.latitude && r.longitude
        address = rgc.map_to_address(r.latitude_f, r.longitude_f)
        t.cell("#{address.street}, #{address.city}")
      else
        t.cell('')
      end
      t.new_row
      t.cell('Outside Temperature:')
      t.cell("#{"%.1f" % (r.outside_temperature / 10.0)} °C")
      t.new_row
      t.cell('Parking brake:')
      t.cell(r.parking_brake_active ? 'active' : 'inactive')
      t.new_row
      t.cell('State of charge:')
      t.cell("#{r.soc}%")
      t.new_row
      t.cell('Estimated range:')
      t.cell("#{r.range} km")
      t.new_row
      t.cell('Charging mode:')
      t.cell(r.charging_mode)
      t.new_row
      t.cell('Charging power:')
      t.cell("#{r.charging_power} KW")
      t.new_row
      t.cell('Remaining charging time:')
      t.cell((time = r.remaining_charging_time) == 65535 ?
             '-' : TimeUtils::mins2dhm(time))
      t.new_row
      t.cell('Charger state:')
      t.cell(r.external_power_supply_state)
      t.new_row
      t.cell('Plug state:')
      t.cell(r.plug_state)
      t.new_row
      t.cell('Energy flow:')
      t.cell(r.energy_flow)
      t.new_row
      t.cell('Charging state:')
      t.cell(r.charging_state)
      t.new_row
      t.cell('Target SoC:')
      t.cell(r.remaining_charging_time_target_soc)
      t.new_row
      t.cell('AC Temperature:')
      t.cell("#{"%.1f" % (r.climater_temperature / 10.0)} °C")
      t.new_row
      t.cell('AC status:')
      t.cell(r.climater_status)

      t
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
      # r1 and r2 can be identical or any number of indicies apart.
      r0 = @telemetry[index]
      r1 = @telemetry[idx1 = index - 1]
      state = r1.state
      if state_changed?(r1, r0)
        # Find the index of the end of state before the last state
        r3 = @telemetry[idx3 = idx1 - 1]
        while !state_changed?(r3, r1)
          r3 = @telemetry[idx3 -= 1]
        end
        idx2 = idx3 + 1
        r2 = @telemetry[idx2]

        if r0.odometer > r1.odometer
          # Rides never show up as a block. If we have a block it's from a
          # charging or parking period. So we always use r1 and r0 to
          # determine the ride data.
          extract_ride(r1, r0, rgc)
        end
        if r1.soc < (r0.soc - 1) && !r1.is_charging? && !r0.is_charging?
          # We have an SoC increase but no charging record. We ignore
          # increases of 1% since these can be caused by temperature
          # variations.
          extract_charge(r1, r0, rgc)
        elsif r1.is_charging?
          # We have a charging record.
          extract_charge(r2, r1, rgc)
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
      ride.map_locations_to_addresses(rgc)
    end

    def extract_charge(start_record, end_record, rgc)
      energy = soc2energy(end_record.soc - start_record.soc)
      energy = 0.0 if energy < 0.0
      @charges << (charge = @store.new(Charge))
      charge.energy = energy
      charge.type = start_record.state == :charging_dc ? 'DC' : 'AC'
      charge.start_timestamp = start_record.timestamp
      charge.start_soc = start_record.soc
      charge.end_timestamp = end_record.timestamp
      charge.end_soc = end_record.soc
      charge.latitude = start_record.latitude
      charge.longitude = start_record.longitude
      charge.map_location_to_address(rgc)
      charge.odometer = start_record.odometer
    end

    def state_changed?(first_record, second_record)
      first_record.state != (state = second_record.state) ||
        (state != :driving && first_record.odometer < second_record.odometer) ||
        (state != :charging_ac && state != :charging_dc &&
         first_record.soc < second_record.soc)
    end

    def soc2energy(soc)
      # This is currently hardcoded for the Audi e-tron 55 Quattro. It has a
      # net battery capacity of 83.7 kWh.
      83.7 * soc / 100.0
    end

  end

end

