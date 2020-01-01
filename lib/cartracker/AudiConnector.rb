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

module CarTracker

  class AudiConnector < PEROBS::Object

    attr_persist :username, :password, :token, :token_valid_until, :vehicles,
      :default_vehicle, :last_vehicle_list_update

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
        'ADRUM': 'isAray:true'
      }

      # Make sure we have an authentication token that is valid for at least
      # 60 more seconds.
      if @token.nil? || @token_valid_until < Time.now + 60
        unless authenticate
          Log.fatal "Cannot authenticate with Audi Connect"
        end
      end

      @request_header['Authorization'] = "AudiAuth 1 #{@token}"

      if @vehicles.nil? || @vehicles.empty? || @last_vehicle_list_update.nil? ||
          @last_vehicle_list_update < Time.now - 60 * 60 * 24
        self.vehicles = @store.new(PEROBS::Hash) if @vehicles.nil?

        update_vehicle_list
        self.last_vehicle_list_update = Time.now
      end
    end

    def authenticate
      url = @base_url + 'core/auth/v1/Audi/DE/token'
      uri = URI.parse(url)
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

    def analyze_telemetry
      @vehicles.each do |vin, vehicle|
        vehicle.analyze_telemetry
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
        puts vehicle.list_charges
      end
    end

    def list_rides(vin = nil)
      vehicle = @vehicles[vin] || @default_vehicle
      puts vehicle.list_rides
    end

    def update_vehicles
      @vehicles.each do |vin, vehicle|
        update_vehicle(vin)
      end
    end

    def update_vehicle(vin)
      return unless token_valid?

      vehicle = @vehicles[vin]
      # The timestamp for the next server sync of this vehicle determines if
      # we actually connect to the server or not. If we are still in the pause
      # period we abort the update.
      if vehicle.next_server_sync_time &&
         Time.now < vehicle.next_server_sync_time - 10
        return
      end

      record = @store.new(TelemetryRecord)

      if get_vehicle_status(vehicle, record) &&
          get_vehicle_position(vehicle, record) &&
          get_vehicle_charger(vehicle, record)
        vehicle.add_record(record)
      end

      #url = @base_url + "bs/climatisation/v1/Audi/DE/vehicles/#{vin}/climater"
      #return false unless (data = connect_request(url))
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
      uri = URI.parse(url)

      response = post_request(uri)
      if response.code == '202'
        data = JSON.parse(response.body)
        if data.is_a?(Hash) && data.include?('CurrentVehicleDataResponse') &&
            (cvdr = data['CurrentVehicleDataResponse']).is_a?(Hash) &&
            cvdr.include?('requestId')
          request_id = cvdr['requestId']
        else
          Log.warn "CurrentVehicleDataResponse corrupted: #{data}"
          return false
        end

        url = @base_url + "bs/vsr/v1/Audi/DE/vehicles/#{vin}/requests/#{request_id}/jobstatus"
        loop do
          return false unless (data = connect_request(url))

          if data.is_a?(Hash) && data.include?('requestStatusResponse') &&
              (rsr = data['requestStatusResponse']).is_a?(Hash) &&
              rsr.include?('status')
            case rsr['status']
            when 'request_in_progress'
              sleep(1)
            when 'request_successful'
              break
            when 'request_fail'
              return false
            else
              puts "Unknown status: #{rsr['status']}"
              return false
            end
          else
            Log.warn "request_in_progress is corrupted: #{data}"
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

      unless data.is_a?(Hash) &&
          (response = data['StoredVehicleDataResponse']) &&
          (vehicle_data = response['vehicleData']) &&
          (svdr_data = vehicle_data['data']) && svdr_data.is_a?(Array)
        Log.warn "StoredVehicleDataResponse data is corrupted: #{response}"
        return false
      end
      svdr_data.each do |d|
        unless d.include?('id')
          Log.warn "StoredVehicleDataResponse data does not contain an id: " +
            d
          return false
        end

        if %w(0x0101010001 0x0101010002 0x030102FFFF
              0x030103FFFF).include?(d['id'])
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
            when '0x0301020001'
              # Outside temperature in dKelvin
              record.set_outside_temperature(f['value'])
            when '0x0301030001'
              # parking brake active (0/1)
              record.set_parking_brake_active(f['value'])
            when '0x0301030002'
              # SOC (%)
              record.set_soc(f['value'])
            when '0x0301030004'
              # Speed (km/h)
              record.set_speed(f['value'])
            when '0x0301030005'
              # Range (km)
              record.set_range(f['value'])
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
        vehicle.set_position(nil, nil)
        return true
      end

      if data.is_a?(Hash) && data.include?('findCarResponse') &&
          data['findCarResponse'].include?('Position') &&
          (position = data['findCarResponse']['Position']).is_a?(Hash)
        if position.include?('carCoordinate') &&
           (coordinates = position['carCoordinate']).is_a?(Hash) &&
           position.include?('timestampCarCaptured')
          if coordinates.include?('latitude') &&
              coordinates.include?('longitude')
            record.set_position(coordinates['latitude'],
                                coordinates['longitude'])
            return true
          else
            Log.warn "findCarResponse position corrupted: #{position.inspect}"
          end
        else
          Log.warn "findCarResponse coordinates corrupted: " +
            "#{coordinates.inspect}"
        end
      else
        Log.warn "findCarResponse is corrupted: #{data.inspect}"
      end

      false
    end

    def get_vehicle_charger(vehicle, record)
      vin = vehicle.vin
      url = @base_url + "bs/batterycharge/v1/Audi/DE/vehicles/#{vin}/charger"
      return false unless (data = connect_request(url))

      if data.is_a?(Hash) && data.include?('charger') &&
          (charger = data['charger']).is_a?(Hash)
        if charger.include?('status') &&
            (status = charger['status']).is_a?(Hash) &&
            status.include?('chargingStatusData') &&
            (chargingStatusData = status['chargingStatusData']).is_a?(Hash) &&
            status.include?('batteryStatusData') &&
            (batteryStatusData = status['batteryStatusData']).is_a?(Hash)
          if chargingStatusData.include?('chargingPower') &&
             (chargingPower = chargingStatusData['chargingPower']).is_a?(Hash) &&
             chargingPower.include?('content') &&
             chargingPower.include?('timestamp') &&
             (chargingMode = chargingStatusData['chargingMode']).is_a?(Hash) &&
             chargingMode.include?('content') &&
             chargingMode.include?('timestamp')
            record.set_charging(chargingMode['content'],
                                chargingPower['content'])
          else
            Log.warn "chargingStatusData is corrupted: #{chargingStatusData}"
            return false
          end
        else
          Log.warn "charger status is corrupted: #{charger}"
        end
      else
        Log.warn "charger data is corrupted: #{data}"
      end

    end

    def connect_request(url)
      uri = URI.parse(url)

      response = get_request(uri)
      case response.code.to_i
      when 200
        return JSON.parse(response.body)
      when 204
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

      request = Net::HTTP::Post.new(uri.path, @request_header)
      request.set_form_data(form_data)

      http.request(request)
    end

    def get_request(uri)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.verify_mode = OpenSSL::SSL::VERIFY_PEER

      request = Net::HTTP::Get.new(uri.path, @request_header)

      http.request(request)
    end

  end

end

