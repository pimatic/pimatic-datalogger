module.exports = (env) ->

  convict = env.require "convict"
  Q = env.require 'q'
  assert = env.require 'cassert'

  path = require 'path'
  fs = require 'fs'

  Db = require("tingodb")().Db

  class DataLoggerPlugin extends env.plugins.Plugin

    init: (app, @framework, @config) =>
      conf = convict require("./datalogger-config-shema")
      conf.load config 
      conf.validate()
      @config = conf.get ""


      @dbPath = path.resolve framework.maindir, "../../db"
      unless fs.existsSync @dbPath
        fs.mkdirSync @dbPath
      @db = new Db(@dbPath, {})
      @collection = @db.collection("logged_data.db")

      # @collection.find().toArray (err, docs) ->
      #   console.log docs

      @framework.on "after init", =>
        
        mobileFrontend = @framework.getPlugin 'mobile-frontend'
        if mobileFrontend?
          mobileFrontend.registerAssetFile 'js', "pimatic-datalogger/app/js/highstock.js"
          mobileFrontend.registerAssetFile 'js', "pimatic-datalogger/app/main.coffee"
        else
          env.logger.warn "datalogger could not find mobile-frontend. No gui will be available"

        for sensor in @config.sensors
          do (sensor) =>
            device = @framework.getDeviceById sensor.id
            for sensorValue in sensor.sensorValues
              do (sensorValue) =>
                device.on sensorValue, (value) =>
                  console.log device.id, sensorValue, value
                  @collection.insert data =
                    date: new Date
                    deviceId: device.id
                    sensorValueName: sensorValue
                    value: value
                  , w:1, (err) => if err then env.logger.error err


  return new DataLoggerPlugin