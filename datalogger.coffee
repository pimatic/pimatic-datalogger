module.exports = (env) ->

  convict = env.require "convict"
  Q = env.require 'q'
  assert = env.require 'cassert'
  _ = env.require 'lodash'
  fs = env.require 'fs.extra'

  path = require 'path'
  Db = require("tingodb")().Db

  class DataLoggerPlugin extends env.plugins.Plugin

    deviceListener: {}

    init: (@app, @framework, @config) =>
      conf = convict require("./datalogger-config-shema")
      conf.load config 
      conf.validate()

      unless @config.sensors? then @config.sensors = []

      @framework.on "device", (device) =>
        c =  @getDeviceConfig device.id
        if c? then @addLoggerForDevice device, c.sensorValues
        return

      @framework.on "after init", =>
        
        mobileFrontend = @framework.getPlugin 'mobile-frontend'
        if mobileFrontend?
          mobileFrontend.registerAssetFile 'js', "pimatic-datalogger/app/js/highstock.js"
          mobileFrontend.registerAssetFile 'js', "pimatic-datalogger/app/datalogger-page.coffee"
          mobileFrontend.registerAssetFile 'css', "pimatic-datalogger/app/css/datalogger.css"
          mobileFrontend.registerAssetFile 'html', "pimatic-datalogger/app/datalogger-page.jade"
        else
          env.logger.warn "datalogger could not find mobile-frontend. No gui will be available"

        for sensor in @config.sensors 
          unless @deviceListener[sensor.id]?
            env.logger.warn "No device with id: #{sensor.id} found to log values."
        return

      sendError = (res, error) =>
        res.send 406, success: false, message: error.message

      sendSuccess = (res, message) =>
        res.send success: true, message: message

      getDeviceFromRequest = (req) =>
        deviceId = req.params.deviceId
        if not deviceId? or deviceId is "undefined"
          throw new Error "No deviceId given" 
        device = @framework.getDeviceById deviceId
        unless device?
          throw new Error "Could not find device."
        return device

      getSensorValueNameFromRequest = (req, device) =>
        sensorValueName = req.params.sensorValue
        if not sensorValueName? or sensorValueName is "undefined"
          throw new Error "No sensorValueName given." 
        unless sensorValueName in device.getSensorValuesNames()
          throw new Error "Illegal value for this device."
        return sensorValueName

      @app.get '/datalogger/info/:deviceId', (req, res, next) =>
        try
          device = getDeviceFromRequest req
        catch e
          console.log e
          return sendError res, e

        c = @getDeviceConfig device.id
        loggedSensorValueNames = (if c? then c.sensorValues else [])

        info =
         loggingSensorValues: {}

        if device.getSensorValuesNames?
          for sensorValue in device.getSensorValuesNames()
            info.loggingSensorValues[sensorValue] = (sensorValue in loggedSensorValueNames)

        res.send info

      @app.get '/datalogger/add/:deviceId/:sensorValue', (req, res, next) =>
        try
          device = getDeviceFromRequest req
          sensorValueName = getSensorValueNameFromRequest req, device
        catch e
          return sendError res, e

        @addDeviceToConfig device.id, [sensorValueName]
        @addLoggerForDevice device, [sensorValueName]
        sendSuccess res, "Added logging for #{sensorValueName}."

      @app.get '/datalogger/remove/:deviceId/:sensorValue', (req, res, next) =>
        try
          device = getDeviceFromRequest req
          sensorValueName = getSensorValueNameFromRequest req, device
        catch e
          return sendError res, e

        @removeDeviceFromConfig device.id, [sensorValueName]
        @removeLoggerForDevice device, [sensorValueName]
        sendSuccess res, "Removed logging for #{sensorValueName}."

      @app.get '/datalogger/data/:deviceId/:sensorValue', (req, res, next) =>
        try
          device = getDeviceFromRequest req
          sensorValueName = getSensorValueNameFromRequest req, device
        catch e
          console.log e
          return sendError res, e

        @getData(device.id, sensorValueName).then( (data) =>
          res.send
            title: 
              text: "#{device.name}: #{sensorValueName}"
            tooltip:
              valueDecimals: 2
            yAxis:
              labels:
                format: "{value}"
            series: [
              name: "Messwert"
              data: data
            ]
        ).done()

    logData: (deviceId, sensorValue, value, date = new Date()) ->
      assert deviceId?
      assert sensorValue?
      assert value?

      file = @getPathOfLogFile deviceId, sensorValue, date
      defer = Q.defer()
      Q.nfcall(fs.exists, file, defer.resolve)
      defer.promise.then( (exists) =>
        unless exists
          Q.nfcall fs.mkdirs, path.dirname(file)
      ).then( =>
        Q.nfcall fs.appendFile, file, "#{date.getTime()},#{value}"
      )



    getData: (deviceId, sensorValue, date = new Date()) ->
      file = @getPathOfLogFile deviceId, sensorValue, date
      defer = Q.defer()
      Q.nfcall(fs.exists, file, defer.resolve)
      defer.promise.then( (exists) =>
        unless exists then return []
        else Q.nfcall(fs.readFile, file).then( (csv) =>
          csv = csv.toString()
          if csv.length is 0 then return []
          json = '[[' + csv.replace(/\r\n|\n|\r/gm, '],[') + ']]'
          JSON.parse(json)
        )
      )

    getPathOfLogFile: (deviceId, sensorValue, date) ->
      assert deviceId?
      assert sensorValue?
      assert date instanceof Date
      pad = (n) => if n < 10 then '0'+n else n
      year = pad date.getFullYear()
      month = pad(date.getMonth()+1)
      day = pad date.getDate()
      return path.resolve @framework.maindir, 
        "../../datalogger/#{deviceId}/#{sensorValue}/#{year}/#{month}/#{day}.csv"


    # ##addLoggerForDevice()
    # Add a sensor value listener for the given device and sensorValues
    addLoggerForDevice: (device, sensorValues) ->
      assert device? and device.id?
      assert Array.isArray sensorValues

      for sensorValue in sensorValues
        do (sensorValue) =>
          listener = (value) => @logData(device.Id, sensorValue, value).done()
          unless @deviceListener[device.id]?
            @deviceListener[device.id] =
              listener: {}
          unless @deviceListener[device.id].listener[sensorValue]?
            @deviceListener[device.id].listener[sensorValue] = listener  
            device.on sensorValue, listener
      return

    removeLoggerForDevice: (device, sensorValues) ->
      if @deviceListener[device.id]?
        for sensorValue in sensorValues
          do (sensorValue) =>
            listener = @deviceListener[device.id].listener[sensorValue]
            device.removeListener sensorValue, listener
            delete @deviceListener[device.id].listener[sensorValue]
        if (l for l of @deviceListener[device.id].listener).length is 0
          delete @deviceListener[device.id]
      return

    # ##getDeviceConfig()
    # Get the config entry for the given if
    getDeviceConfig: (deviceId) ->
      assert deviceId?
      return _(@config.sensors).find (s) => s.id is deviceId

    # ##addDeviceToConfig()
    # Add the given device id with the fiven sensor values to the config.
    addDeviceToConfig: (deviceId, sensorValues) ->
      assert deviceId?
      assert Array.isArray sensorValues
      # Get the config entry for the given id.
      entry = @getDeviceConfig deviceId
      # If the entry does not exist
      unless entry?
        # then create it.
        @config.sensors.push
          id: deviceId
          sensorValues: sensorValues
      else 
        # Else just add the sensor values.
        entry.sensorValues = _.union entry.sensorValues, sensorValues
      # Save the config and return.
      @framework.saveConfig()
      return

    # ##removeDeviceFromConfig()
    # Removes the given sensor values from the sensor config entry with the id of deviceId
    removeDeviceFromConfig: (deviceId, sensorValuesToRemove) ->
      assert deviceId?
      assert Array.isArray sensorValuesToRemove
      # Get the sensor config entry.
      entry = @getDeviceConfig deviceId
      # If an entry was found
      if entry?
        # then remove the given sensor values.
        entry.sensorValues = _.difference entry.sensorValues, sensorValuesToRemove
        # If the entry has no sensor values anymore
        if entry.sensorValues.length is 0
          # then remove the entry completly from the config.
          @config.sensors = _.filter @config.sensors, (s) => s.id isnt deviceId
      # Save the config and return.
      @framework.saveConfig()
      return

  return new DataLoggerPlugin

