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

      if @token.nil? || @token_valid_until < Time.now
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
      url = 'https://msg.audi.de/fs-car/core/auth/v1/Audi/DE/token'
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

      url = 'https://msg.audi.de/fs-car/usermanagement/users/v1/Audi/DE/vehicles'
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

        fin = ary[0]
        unless @vehicles.include?(fin)
          Log.info "New vehicle with FIN #{fin} added"
          @vehicles[fin] = v = @store.new(Vehicle)
          v.fin = fin
        end
      end

      true
    end

    def list_vehicles
      puts "FIN"
      @vehicles.each do |fin, vehicle|
        puts vehicle.to_csv
      end
    end

    def update_vehicles
      @vehicles.each do |fin, vehicle|
        update_vehicle(fin)
      end
    end

    def update_vehicle(fin)
      return unless token_valid?

      get_current_vehicle_data(fin)

      vehicle = @vehicles[fin]

      record = @store.new(TelemetryRecord)

      if get_vehicle_status(vehicle, record) &&
          get_vehicle_position(vehicle, record) &&
          get_vehicle_charger(vehicle, record)
        vehicle.add_record(record)
      end

      url = "https://msg.audi.de/fs-car/bs/climatisation/v1/Audi/DE/vehicles/#{fin}/climater"
      #return false unless (data = connect_request(url))
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

    def get_current_vehicle_data(fin)
      url = "https://msg.audi.de/fs-car/bs/vsr/v1/Audi/DE/vehicles/#{fin}/requests"
      uri = URI.parse(url)

      response = post_request(uri)
      if response.code == '202'
        # Nothing to do here. Update from vehicle was received.
      else
        Log.error response.message
        return false
      end
    end

    def get_vehicle_status(vehicle, record)
      fin = vehicle.fin
      url = "https://msg.audi.de/fs-car/bs/vsr/v1/Audi/DE/vehicles/#{fin}/status"
      return false unless (data = connect_request(url))

      unless data.is_a?(Hash) && data['StoredVehicleDataResponse'] &&
          data['StoredVehicleDataResponse']['vehicleData'] &&
          data['StoredVehicleDataResponse']['vehicleData']['data'] &&
          data['StoredVehicleDataResponse']['vehicleData']['data'].is_a?(Array)
        Log.warn "StoredVehicleDataResponse data is corrupted"
        return false
      end
      data['StoredVehicleDataResponse']['vehicleData']['data'].each do |d|
        unless d.include?('id')
          Log.warn 'StoredVehicleDataResponse data does not contain an id'
          return false
        end

        if %w(0x0101010002 0x030102FFFF 0x030103FFFF).include?(d['id'])
          # Other potentially interesting sections:
          # 0x030104FFFF: Doors
          # 0x030105FFFF: Windows
          d['field'].each do |f|
            unless f.include?('id')
              Log.warn 'StoredVehicleDataResponse data field does not ' +
                'contain an id'
              return false
            end

            case f['id']
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
      fin = vehicle.fin
      url = "https://msg.audi.de/fs-car/bs/cf/v1/Audi/DE/vehicles/#{fin}/position"
      return false unless (data = connect_request(url))
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
      fin = vehicle.fin
      url = "https://msg.audi.de/fs-car/bs/batterycharge/v1/Audi/DE/vehicles/#{fin}/charger"
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
      if response.code == '200'
        return JSON.parse(response.body)
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

