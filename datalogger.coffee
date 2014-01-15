module.exports = (env) ->

  convict = env.require "convict"
  Q = env.require 'q'
  assert = env.require 'cassert'
  _ = env.require 'lodash'
  fs = env.require 'fs.extra'

  path = require 'path'

  class DataLoggerPlugin extends env.plugins.Plugin

    deviceListener: {}

    init: (@app, @framework, @config) =>
      conf = convict require("./datalogger-config-shema")
      conf.load config 
      conf.validate()

      unless @config.sensors? then @config.sensors = []

      @framework.on "device", (device) =>
        c =  @getDeviceConfig device.id
        if c? then @addLoggerForDevice device, c.properties
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

      getPropertyFromRequest = (req, device) =>
        property = req.params.property
        if not property? or property is "undefined"
          throw new Error "No property name given." 
        unless device.hasProperty property
          throw new Error "Illegal value for this device."
        return property

      @app.get '/datalogger/info/:deviceId', (req, res, next) =>
        try
          device = getDeviceFromRequest req
        catch e
          return sendError res, e

        c = @getDeviceConfig device.id
        loggedProperties = (if c? then c.properties else [])

        info =
         loggingProperties: {}

        for property of device.properties
          info.loggingProperties[property] = (property in loggedProperties)

        res.send info

      @app.get '/datalogger/add/:deviceId/:property', (req, res, next) =>
        try
          device = getDeviceFromRequest req
          property = getPropertyFromRequest req, device
        catch e
          return sendError res, e

        @addDeviceToConfig device.id, [property]
        @addLoggerForDevice device, [property]
        sendSuccess res, "Added logging for #{property}."

      @app.get '/datalogger/remove/:deviceId/:property', (req, res, next) =>
        try
          device = getDeviceFromRequest req
          property = getPropertyFromRequest req, device
        catch e
          return sendError res, e

        @removeDeviceFromConfig device.id, [property]
        @removeLoggerForDevice device, [property]
        sendSuccess res, "Removed logging for #{property}."

      @app.get '/datalogger/data/:deviceId/:property', (req, res, next) =>
        try
          device = getDeviceFromRequest req
          property = getPropertyFromRequest req, device
        catch e
          console.log e
          return sendError res, e

        @getData(device.id, property).then( (data) =>
          res.send
            title: 
              text: "#{device.name}: #{property}"
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

    logData: (deviceId, property, value, date = new Date()) ->
      assert deviceId?
      assert property?
      assert value?

      file = @getPathOfLogFile deviceId, property, date
      defer = Q.defer()
      Q.nfcall(fs.exists, file, defer.resolve)
      defer.promise.then( (exists) =>
        unless exists
          Q.nfcall fs.mkdirs, path.dirname(file)
      ).then( =>
        Q.nfcall fs.appendFile, file, "#{date.getTime()},#{value}\n"
      )



    getData: (deviceId, property, date = new Date()) ->
      file = @getPathOfLogFile deviceId, property, date
      defer = Q.defer()
      Q.nfcall(fs.exists, file, defer.resolve)
      defer.promise.then( (exists) =>
        unless exists then return []
        else Q.nfcall(fs.readFile, file).then( (csv) =>
          csv = csv.toString()
          if csv.length is 0 then return []
          json = '[[' + 
            csv.replace(/\r\n|\n|\r/gm, '],[') #replace new lines with `],[`
            .replace(/,\[\]/g, '') # remove empty arrays: `[]`
            .replace(/\],\[$/, '') + # remove last `],[`
            ']]'
          JSON.parse(json)
        )
      )

    getPathOfLogFile: (deviceId, property, date) ->
      assert deviceId?
      assert property?
      assert date instanceof Date
      pad = (n) => if n < 10 then '0'+n else n
      year = pad date.getFullYear()
      month = pad(date.getMonth()+1)
      day = pad date.getDate()
      return path.resolve @framework.maindir, 
        "../../datalogger/#{deviceId}/#{property}/#{year}/#{month}/#{day}.csv"


    # ##addLoggerForDevice()
    # Add a sensor value listener for the given device and properties
    addLoggerForDevice: (device, properties) ->
      assert device? and device.id?
      assert Array.isArray properties

      for property in properties
        do (property) =>
          listener = (value) => @logData(device.id, property, value).done()
          unless @deviceListener[device.id]?
            @deviceListener[device.id] =
              listener: {}
          unless @deviceListener[device.id].listener[property]?
            @deviceListener[device.id].listener[property] = listener  
            device.on property, listener
      return

    removeLoggerForDevice: (device, properties) ->
      if @deviceListener[device.id]?
        for property in properties
          do (property) =>
            listener = @deviceListener[device.id].listener[property]
            device.removeListener property, listener
            delete @deviceListener[device.id].listener[property]
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
    addDeviceToConfig: (deviceId, properties) ->
      assert deviceId?
      assert Array.isArray properties
      # Get the config entry for the given id.
      entry = @getDeviceConfig deviceId
      # If the entry does not exist
      unless entry?
        # then create it.
        @config.sensors.push
          id: deviceId
          properties: properties
      else 
        # Else just add the sensor values.
        entry.properties = _.union entry.properties, properties
      # Save the config and return.
      @framework.saveConfig()
      return

    # ##removeDeviceFromConfig()
    # Removes the given sensor values from the sensor config entry with the id of deviceId
    removeDeviceFromConfig: (deviceId, propertiesToRemove) ->
      assert deviceId?
      assert Array.isArray propertiesToRemove
      # Get the sensor config entry.
      entry = @getDeviceConfig deviceId
      # If an entry was found
      if entry?
        # then remove the given sensor values.
        entry.properties = _.difference entry.properties, propertiesToRemove
        # If the entry has no sensor values anymore
        if entry.properties.length is 0
          # then remove the entry completly from the config.
          @config.sensors = _.filter @config.sensors, (s) => s.id isnt deviceId
      # Save the config and return.
      @framework.saveConfig()
      return

  return new DataLoggerPlugin

