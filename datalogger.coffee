module.exports = (env) ->

  convict = env.require "convict"
  Q = env.require 'q'
  assert = env.require 'cassert'

  path = require 'path'
  fs = require 'fs'

  Db = require("tingodb")().Db

  class DataLoggerPlugin extends env.plugins.Plugin

    deviceListener: {}

    init: (@app, @framework, @config) =>
      conf = convict require("./datalogger-config-shema")
      conf.load config 
      conf.validate()

      unless @config.sensors? then @config.sensors = []

      @dbPath = path.resolve framework.maindir, "../../db"
      unless fs.existsSync @dbPath
        fs.mkdirSync @dbPath
      @db = new Db(@dbPath, {})
      @collection = @db.collection("logged_data.db")


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


      @app.get '/datalogger/info/:deviceId', (req, res, next) =>
        deviceId = req.params.deviceId
        device = @framework.getDeviceById deviceId
        unless device?
          res.send 406, message: "Could not find device."
          return
        c = @getDeviceConfig device.id
        loggedSensorValueNames = (if c? then c.sensorValues else [])

        info =
         loggingSensorValues: {}

        if device.getSensorValuesNames?
          for sensorValue in device.getSensorValuesNames()
            info.loggingSensorValues[sensorValue] = (sensorValue in loggedSensorValueNames)

        res.send info
        return

      @app.get '/datalogger/add/:deviceId/:sensorValue', (req, res, next) =>
        deviceId = req.params.deviceId
        device = @framework.getDeviceById deviceId
        sensorValueName = req.params.sensorValue
        unless device?
          res.send 406, success: false, message: "Could not find device."
          return
        unless sensorValueName in device.getSensorValuesNames()
          res.send 406, success: false, message: "Illegal value for this device"
          return

        @addDeviceToConfig deviceId, [sensorValueName]
        @addLoggerForDevice device, [sensorValueName]
        res.send success: true, message: "Added logging for #{sensorValueName}."
        return

      @app.get '/datalogger/remove/:deviceId/:sensorValue', (req, res, next) =>
        deviceId = req.params.deviceId
        device = @framework.getDeviceById deviceId
        sensorValueName = req.params.sensorValue
        unless device?
          res.send 406, success: false, message: "Could not find device."
          return
        unless sensorValueName in device.getSensorValuesNames()
          res.send 406, success: false, message: "Illegal value for this device"
          return

        @removeDeviceFromConfig deviceId, [sensorValueName]
        @removeLoggerForDevice device, [sensorValueName]
        res.send success: true, message: "Removed logging for #{sensorValueName}."
        return

      @app.get '/datalogger/data/:deviceId/:sensorValueName', (req, res, next) =>
        deviceId = req.params.deviceId
        device = @framework.getDeviceById deviceId
        sensorValueName = req.params.sensorValueName
        unless device?
          res.send 406, success: false, message: "Could not find device."
          return
        unless sensorValueName in device.getSensorValuesNames()
          res.send 406, success: false, message: "Illegal value for this device"
          return

        @collection.find(
          deviceId: deviceId, 
          sensorValueName: sensorValueName
        ).toArray (err, docs) ->
          res.send data =
            title: 
              text: "#{device.name}: #{sensorValueName}"
            tooltip:
              valueDecimals: 2
            yAxis:
              labels:
                format: "{value}"
            series: [
              name: "Messwert"
              data: ([doc.date.getTime(), doc.value] for doc in docs)
            ]
        return

    addLoggerForDevice: (device, sensorValues) ->
      assert device? and device.id?
      assert Array.isArray sensorValues

      for sensorValue in sensorValues
        do (sensorValue) =>
          listener = (value) =>
            #console.log device.id, sensorValue, value
            @collection.insert(
              date: new Date
              deviceId: device.id
              sensorValueName: sensorValue
              value: value
            , w:1, (err) => if err then env.logger.error err
            )
 
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

    getDeviceConfig: (deviceId) ->
      for sensor in @config.sensors
        if sensor.id is deviceId then return sensor
      return null

    addDeviceToConfig: (deviceId, sensorValues) ->
      sensorConfig = @getDeviceConfig deviceId
      unless sensorConfig?
        @config.sensors.push
          if: deviceId
          sensorValues: sensorValues
      else for v in sensorValues
        unless (v in sensorConfig.sensorValues)
         sensorConfig.sensorValues.push v
      @framework.saveConfig()
      return

    removeDeviceFromConfig: (deviceId, sensorValuesToRemove) ->
      sensorConfig = @getDeviceConfig deviceId
      unless sensorConfig? then return
      else 
        newSensorValues = []
        for v in sensorConfig.sensorValues
          unless v in sensorValuesToRemove 
            newSensorValues.push v
        sensorConfig.sensorValues = newSensorValues
        @framework.saveConfig()
      return

  return new DataLoggerPlugin

