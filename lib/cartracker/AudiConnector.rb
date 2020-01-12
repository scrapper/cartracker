#!/usr/bin/env ruby -w
# encoding: UTF-8
#
# = AudiConnector.rb -- CarTracker - Capture and analyze your EV telemetry.
#
# Copyright (c) 2019 by Chris Schlaeger <cs@taskjuggler.org>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of version 2 of the GNU General Public License as
# published by the Free Software Foundation.
#

require 'net/http'
require 'json'
require 'uri'
require 'perobs'

require 'cartracker/Log'
require 'cartracker/Vehicle'
require 'cartracker/TelemetryRecord'
require 'cartracker/FlexiTable'

module CarTracker

  class AudiConnector < PEROBS::Object

    attr_persist :username, :password, :token, :token_valid_until, :vehicles,
      :default_vehicle, :last_vehicle_list_update

    attr_writer :server_log

    def initialize(p)
      super(p)
      restore
    end

    def restore
      @base_url = 'https://msg.audi.de/fs-car/'
      @request_header = {
        'Accept': 'application/json',
        'X-App-ID': 'de.audi.mmiapp',
        'X-App-Name': 'MMIconnect',
        'X-App-Version': '2.8.3',
        'X-Brand': 'audi',
        'X-Country-Id': 'DE',
        'X-Language-Id': 'de',
        'X-Platform': 'google',
        'User-Agent': 'okhttp/2.7.4',
        'ADRUM_1': 'isModule:true',
        'ADRUM': 'isAray:true',
        'X-Market': 'de_DE'
      }
      @server_log = nil

      # Make sure we have an authentication token that is valid for at least
      # 60 more seconds.
      if @token.nil? || @token_valid_until < Time.now + 60
        unless authenticate
          Log.fatal "Cannot authenticate with Audi Connect"
        end
      end

      @request_header['Authorization'] = "AudiAuth 1 #{@token}"
      #@request_header['Authorization'] = "Bearer #{@token}"

      if @vehicles.nil? || @vehicles.empty? || @last_vehicle_list_update.nil? ||
          @last_vehicle_list_update < Time.now - 60 * 60 * 24
        self.vehicles = @store.new(PEROBS::Hash) if @vehicles.nil?

        update_vehicle_list
        self.last_vehicle_list_update = Time.now
      end
    end

    def authenticate
      url = @base_url + 'core/auth/v1/Audi/DE/token'
      uri = URI(url)
      if @username.nil? || @password.nil?
        Log.warn 'No login credentials stored in database. Requesting ' +
          'from user.'
        puts "Please provide login and password for Audi Connect service:"
        print "Login: "
        self.username = gets
        print "Password: "
        self.password = gets
      end

      form_data =  {
        grant_type: 'password',
        username: @username,
        password: @password,
      }

      response = post_request(uri, form_data)
      if response.code == '200'
        log_server_message(response.body)
        data = JSON.parse(response.body)
        self.token = data['access_token']
        self.token_valid_until = Time.now + data['expires_in']
        Log.info 'New login token received'

        return true
      else
        Log.error response.message
        return false
      end
    end

    def update_vehicle_list
      return unless token_valid?

      url = @base_url + 'usermanagement/users/v1/Audi/DE/vehicles'
      return false unless (data = connect_request(url))

      unless data.is_a?(Hash) && data.include?('userVehicles') &&
          data['userVehicles'].is_a?(Hash)
        Log.warn "userVehicles data is corrupted: #{data}"
        return false
      end

      data['userVehicles'].each do |name, ary|
        unless ary.is_a?(Array) && ary.length > 0
          Log.warn "userVehicles list corrupted: #{ary.inspect}"
        end

        vin = ary[0]
        unless @vehicles.include?(vin)
          Log.info "New vehicle with VIN #{vin} added"
          @vehicles[vin] = v = @store.new(Vehicle)
          v.vin = vin
        end
      end

      unless @default_vehicle
        self.default_vehicle = @vehicles.first[1]
      end

      true
    end

    def analyze_telemetry(rgc)
      @vehicles.each do |vin, vehicle|
        vehicle.analyze_telemetry(rgc)
      end
      @store.gc
    end

    def list_vehicles
      @vehicles.each do |vin, vehicle|
        puts "Vehicle #{vin}\n"
        puts vehicle.to_csv
        puts "\nRides\n"
        puts vehicle.dump_rides
        puts "\nCharges\n"
        puts vehicle.dump_charges
      end
    end

    def list_rides(vin = nil)
      vehicle = @vehicles[vin] || @default_vehicle
      puts vehicle.list_rides
    end

    def list_charges(vin = nil)
      vehicle = @vehicles[vin] || @default_vehicle
      puts vehicle.list_charges
    end

    def update_vehicles(rgc, force_update = false)
      @vehicles.each do |vin, vehicle|
        update_vehicle(vin, rgc, force_update)
      end
    end

    def update_vehicle(vin, rgc, force_update)
      return unless token_valid?

      vehicle = @vehicles[vin]

      # The timestamp for the next server sync of this vehicle determines if
      # we actually connect to the server or not. If we are still in the pause
      # period we abort the update.
      if !force_update && vehicle.next_server_sync_time &&
         Time.now < vehicle.next_server_sync_time - 10
        return
      end

      record = @store.new(TelemetryRecord)

      unless get_vehicle_status(vehicle, record)
        # Likely some kind of server problem. Back off and hope the problem
        # gets resolved.
        vehicle.update_next_poll_time(:longer)
        return
      end

      # If the vehicle contact time hasn't changed the server does not have
      # any new vehicle data. We only request more data from the server if it
      # actually has an update from the vehicle.
      if force_update ||
          record.last_vehicle_contact_time > vehicle.last_vehicle_contact_time
        if get_vehicle_position(vehicle, record) &&
            get_vehicle_charger(vehicle, record) &&
            get_vehicle_climater(vehicle, record)
          vehicle.add_record(record, rgc)
          vehicle.update_next_poll_time(:shorter)
        else
          # Likely some server issue. Back off.
          vehicle.update_next_poll_time(:longer)
        end
      else
        vehicle.update_next_poll_time(:longer)
      end
    end

    def show_status(rgc, vin = nil)
      vehicle = @vehicles[vin] || @default_vehicle
      puts vehicle.show_status(rgc)
    end

    def sync_vehicles
      @vehicles.each do |vin, vehicle|
        sync_vehicle(vin)
      end
    end

    def sync_vehicle(vin)
      return false unless token_valid?

      # The direct communication with the car is strongly rate limited. Only a
      # few calls per day are allowed.
      url = @base_url + "bs/vsr/v1/Audi/DE/vehicles/#{vin}/requests"
      uri = URI(url)

      response = post_request(uri)
      if response.code == '202'
        log_server_message(response.body)
        data = JSON.parse(response.body)

        request_id = hash_extract(data, 'CurrentVehicleDataResponse',
                                  'requestId')
        return false unless request_id

        url = @base_url + "bs/vsr/v1/Audi/DE/vehicles/#{vin}/requests/#{request_id}/jobstatus"
        loop do
          return false unless (data = connect_request(url))

          status = hash_extract(data, 'requestStatusResponse', 'status')

          case status
          when 'request_in_progress'
            sleep(10)
          when 'request_successful'
            break
          when 'request_fail'
            Log.warn "Vehicle status request failed"
            return false
          else
            puts "Unknown status: #{status}"
            return false
          end
        end

        # This operation returns a CurrentVehicleDataResponse that is
        # identical to a StoredVehicleDataResponse in format.
        # url = @base_url + "bs/vsr/v1/Audi/DE/vehicles/#{vin}/requests/#{request_id}/status"
        # return false unless (data = connect_request(url))
      else
        Log.error response.message
        return false
      end

      true
    end

    def tripdata(vin = nil)
      vin = @default_vehicle.vin

      url = @base_url + "bs/tripstatistics/v1/Audi/DE/vehicles/#{vin}/tripdata/shortTerm?type=list"

      return false unless (data = connect_request(url))

      tripDataList = hash_extract(data, 'tripDataList', 'tripData')

      return unless tripDataList && tripDataList.is_a?(Array)

      t = FlexiTable.new
      t.head
      t.row([ 'Date', 'Odometer', 'Distance', 'Duration', 'Avg. Energy' ])

      t.body
      tripDataList.each do |trip|
        #pp trip
        t.new_row
        t.cell(Time.parse(trip['timestamp']))
        t.cell(trip['startMileage'])
        t.cell(trip['mileage'])
        t.cell(trip['traveltime'])
        t.cell(trip['averageElectricEngineConsumption'])
      end

      puts t
    end

    private

    def token_valid?
      if !@token.nil? && Time.now < @token_valid_until
        return true
      else
        Log.info "Invalid token"
      end

      false
    end

    def get_vehicle_status(vehicle, record)
      vin = vehicle.vin
      url = @base_url + "bs/vsr/v1/Audi/DE/vehicles/#{vin}/status"
      return false unless (data = connect_request(url))

      svdr_data = hash_extract(data, 'StoredVehicleDataResponse',
                               'vehicleData', 'data')
      return false unless svdr_data && svdr_data.is_a?(Array)

      svdr_data.each do |d|
        unless d.include?('id')
          Log.warn "StoredVehicleDataResponse data does not contain an id: " +
            d
          return false
        end

        if %w(0x0101010001 0x0101010002 0x030101FFFF 0x030102FFFF
              0x030103FFFF 0x030104FFFF 0x030105FFFF).include?(d['id'])
          # Other potentially interesting sections:
          # 0x030104FFFF: Doors
          # 0x030105FFFF: Windows
          d['field'].each do |f|
            unless f.include?('id')
              Log.warn 'StoredVehicleDataResponse data field does not ' +
                "contain an id: #{f}"
              return false
            end

            case f['id']
            when '0x0101010001'
              if (ts = f['tsCarSentUtc'])
                # The timestamp of the last successful transmission from the
                # vehicle.
                record.set_last_vehicle_contact_time(ts)
              else
                Log.warn "StoredVehicleDataResponse has no tsCarSentUtc " +
                  "field: #{f}"
                return false
              end
            when '0x0101010002'
              # Odometer
              record.set_odometer(f['value'])
            when '0x0301010001'
              # Parking lights active
              record.set_parking_lights(f['textId'])
            when '0x0301020001'
              # Outside temperature in dKelvin
              record.set_outside_temperature(f['value'], f['textId'])
            when '0x0301030001'
              # parking brake active (0/1)
              record.set_parking_brake_active(f['value'])
            when '0x0301030002'
              # SOC (%)
              record.set_soc(f['value'], f['textId'])
            when '0x0301030004'
              # Speed (km/h)
              record.set_speed(f['value'], f['textId'])
            when '0x0301030005'
              # Range (km)
              record.set_range(f['value'], f['textId'])
            when '0x0301040001'
              # Front left door lock/unlock
              record.set_door_unlocked(:front_left, f['textId'])
            when '0x0301040002'
              # Front left door open/closed
              record.set_door_open(:front_left, f['textId'])
            when '0x0301040004'
              # Front right door lock/unlock
              record.set_door_unlocked(:front_right, f['textId'])
            when '0x0301040005'
              # Front right door open/closed
              record.set_door_open(:front_right, f['textId'])
            when '0x0301040007'
              # Rear left door lock/unlock
              record.set_door_unlocked(:rear_left, f['textId'])
            when '0x0301040008'
              # Rear left door open/closed
              record.set_door_open(:rear_left, f['textId'])
            when '0x030104000A'
              # Rear right door lock/unlock
              record.set_door_unlocked(:rear_right, f['textId'])
            when '0x030104000B'
              # Rear right door open/closed
              record.set_door_open(:rear_right, f['textId'])
            when '0x030104000D'
              # Hatch locked/unlocked
              record.set_door_unlocked(:hatch, f['textId'])
            when '0x030104000E'
              # Hatch open/closed
              record.set_door_open(:hatch, f['textId'])
            when '0x0301040011'
              # Hood open/closed
              record.set_door_open(:hood, f['textId'])
            when '0x0301050001'
              # Front left window
              record.set_window_open(:front_left, f['textId'])
            when '0x0301050003'
              # Rear left window
              record.set_window_open(:rear_left, f['textId'])
            when '0x0301050005'
              # Front right window
              record.set_window_open(:front_right, f['textId'])
            when '0x0301050007'
              # Rear right window
              record.set_window_open(:rear_right, f['textId'])
            end
          end
        end
      end

      true
    end

    def get_vehicle_position(vehicle, record)
      vin = vehicle.vin
      url = @base_url + "bs/cf/v1/Audi/DE/vehicles/#{vin}/position"
      return false unless (data = connect_request(url))

      if data.empty?
        # When the car is in motion no position information is available.
        record.set_position(nil, nil)
        return true
      end

      record.set_position(
        hash_extract(data, 'findCarResponse', 'Position', 'carCoordinate',
                     'latitude'),
        hash_extract(data, 'findCarResponse', 'Position', 'carCoordinate',
                     'longitude'))

      true
    end

    def get_tripdata(vehicle, record)
      vin = vehicle.vin
      url = @base_url + "bs/tripstatistics/v1/Audi/DE/vehicles/#{vin}/tripdata/longTerm?type=list"

      return false unless (data = connect_request(url))

      pp data
    end

    def get_vehicle_charger(vehicle, record)
      vin = vehicle.vin
      url = @base_url + "bs/batterycharge/v1/Audi/DE/vehicles/#{vin}/charger"
      return false unless (data = connect_request(url))

      record.set_charging(
        hash_extract(data, 'charger', 'status', 'chargingStatusData',
                     'chargingMode', 'content'),
        hash_extract(data, 'charger', 'status', 'chargingStatusData',
                     'chargingPower', 'content'),
        hash_extract(data, 'charger', 'status', 'chargingStatusData',
                     'externalPowerSupplyState', 'content'),
        hash_extract(data, 'charger', 'status', 'chargingStatusData',
                     'energyFlow', 'content'),
        hash_extract(data, 'charger', 'status', 'chargingStatusData',
                     'chargingState', 'content'),
        hash_extract(data, 'charger', 'status', 'batteryStatusData',
                     'remainingChargingTime', 'content'),
        hash_extract(data, 'charger', 'status', 'batteryStatusData',
                     'remainingChargingTimeTargetSOC', 'content'),
        hash_extract(data, 'charger', 'status', 'plugStatusData',
                     'plugState', 'content')
      )
    end

    def get_vehicle_climater(vehicle, record)
      vin = vehicle.vin
      url = @base_url + "bs/climatisation/v1/Audi/DE/vehicles/#{vin}/climater"
      return false unless (data = connect_request(url))

      record.set_climater_temperature(
        hash_extract(data, 'climater', 'settings',
                     'targetTemperature', 'content'))
      record.set_climater_status(
        hash_extract(data, 'climater', 'settings',
                     'climatisationWithoutHVpower', 'content'),
        hash_extract(data, 'climater', 'status', 'climatisationStatusData',
                     'climatisationState', 'content'))
    end

    def connect_request(url)
      uri = URI(url)

      response = get_request(uri)
      case response.code.to_i
      when 200
        log_server_message(response.body)
        return JSON.parse(response.body)
      when 204
        log_server_message(response.body)
        return ''
      else
        Log.error "connect_request for #{uri} failed: #{response.message}"
        return nil
      end
    end

    def post_request(uri, form_data = {})
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.verify_mode = OpenSSL::SSL::VERIFY_PEER

      request = Net::HTTP::Post.new(uri, @request_header)
      request.set_form_data(form_data)

      http.request(request)
    end

    def get_request(uri)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.verify_mode = OpenSSL::SSL::VERIFY_PEER

      request = Net::HTTP::Get.new(uri, @request_header)

      http.request(request)
    end

    def hash_extract(hash, *path)
      hp = hash
      dotted_path = ''

      path.each do |key|
        unless hp.is_a?(Hash)
          Log.warn "#{dotted_path} is not a hash in: #{hp}"
          return nil
        end
        unless hp.include?(key)
          Log.warn "#{dotted_path} does not contain an key named #{key}: " +
            hp.inspect
          return nil
        end

        hp = hp[key]
        dotted_path += key + '.'
      end

      hp
    end

    def log_server_message(msg)
      return unless @server_log

      File.open(@server_log, 'a') do |f|
        f.puts "#{Time.now}: #{msg}"
      end
    end

  end

end

