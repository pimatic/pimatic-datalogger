module.exports = (env) ->

  assert = env.require "assert"
  express = env.require 'express'
  request = env.require 'supertest'

  fs = env.require 'fs.extra'
  os = require 'os'
  events = require 'events'

  describe "datalogger", ->

    plugin = (require '../datalogger') env

    before =>
      @app = express()
      @frameworkDummy = new events.EventEmitter
      @frameworkDummy.maindir = "#{os.tmpdir()}/pimatic-test/mode_modules/pimatic"
      @config = {}
      fs.mkdirsSync @frameworkDummy.maindir

    describe '#init', =>

      it 'should init', =>
        plugin.init @app, @frameworkDummy, @config

        assert @config.sensors
        assert Array.isArray @config.sensors

        assert fs.existsSync "#{os.tmpdir()}/pimatic-test/db"

    describe 'getDeviceConfig()', =>

      it 'should get the entry', =>
        @config.sensors = [
          {
            id: "test"
            sensorValues: ["t1", "t2"]
          }
        ]

        entry = plugin.getDeviceConfig("test")
        assert entry?
        assert.deepEqual entry, @config.sensors[0]

      it 'should not find the entry', =>
        @config.sensors = [
          {
            id: "test"
            sensorValues: ["t1", "t2"]
          }
        ]

        entry = plugin.getDeviceConfig "test2"
        assert not entry?


    describe 'addDeviceToConfig()', =>
      saveConfigCalled = false

      beforeEach =>
        saveConfigCalled = false
        @frameworkDummy.saveConfig = =>
          saveConfigCalled = true

      it 'should add the first entry', =>
        
        @config.sensors = []
        expectedEntry = 
          id: "test"
          sensorValues: ["t1", "t2"]

        plugin.addDeviceToConfig "test", ["t1", "t2"]
        assert.deepEqual expectedEntry, @config.sensors[0]
        assert saveConfigCalled

      it 'should add the sensor value', =>

        expectedEntry = 
          id: "test"
          sensorValues: ["t1", "t2", "t3"]

        plugin.addDeviceToConfig "test", ["t3"]
       
        assert.deepEqual expectedEntry, @config.sensors[0]
        assert saveConfigCalled

      it 'should add the second sensor', =>

        expectedEntry = 
          id: "test2"
          sensorValues: ["t3"]

        plugin.addDeviceToConfig "test2", ["t3"]
       
        assert.equal 2, @config.sensors.length
        assert.deepEqual expectedEntry, @config.sensors[1]
        assert saveConfigCalled

    describe 'removeDeviceFromConfig()', =>
      
      saveConfigCalled = false
      beforeEach =>
        saveConfigCalled = false
        @frameworkDummy.saveConfig = =>
          saveConfigCalled = true

      it 'should remove the entry', =>

        @config.sensors = [
          {
            id: "test"
            sensorValues: ["t1", "t2"]
          }
        ]

        plugin.removeDeviceFromConfig "test", ["t1", "t2"]
        assert.equal 0, @config.sensors.length
        assert saveConfigCalled

      it 'should remove a sensorValue', =>

        @config.sensors = [
          {
            id: "test"
            sensorValues: ["t1", "t2"]
          }
        ]

        expectedEntry = 
          id: "test"
          sensorValues: ["t1"]


        plugin.removeDeviceFromConfig "test", ["t2"]
        assert.equal 1, @config.sensors.length
        assert.deepEqual expectedEntry, @config.sensors[0]
        assert saveConfigCalled

    describe 'addLoggerForDevice()', =>

      it 'should add the first listener', =>
        listener = null

        testDevice =
          id: "test1"
          on: (event, l) =>
            assert.equal "t1", event
            assert typeof l is "function"
            listener = l


        plugin.addLoggerForDevice testDevice, ["t1"]

        assert plugin.deviceListener["test1"]?
        assert plugin.deviceListener["test1"].listener["t1"]?
        assert.equal listener, plugin.deviceListener["test1"].listener["t1"]

      it 'should add the second listener', =>
        listener = null

        testDevice =
          id: "test1"
          on: (event, l) =>
            assert.equal "t2", event
            assert typeof l is "function"
            listener = l


        plugin.addLoggerForDevice testDevice, ["t2"]

        assert plugin.deviceListener["test1"]?
        assert plugin.deviceListener["test1"].listener["t2"]?
        assert.equal listener, plugin.deviceListener["test1"].listener["t2"]


    describe 'removeLoggerForDevice()', =>
      removeListenerCalled = false

      beforeEach =>
        removeListenerCalled = false


      it 'should remove the first listener', =>

        testDevice =
          id: "test1"
          removeListener: (event, l) =>
            assert.equal "t1", event
            assert typeof l is "function"
            removeListenerCalled = true


        plugin.removeLoggerForDevice testDevice, ["t1"]

        assert plugin.deviceListener["test1"]?
        assert not plugin.deviceListener["test1"].listener["t1"]?
        assert plugin.deviceListener["test1"].listener["t2"]
        assert removeListenerCalled

      it 'should remove the second listener', =>

        testDevice =
          id: "test1"
          removeListener: (event, l) =>
            assert.equal "t2", event
            assert typeof l is "function"
            removeListenerCalled = true


        plugin.removeLoggerForDevice testDevice, ["t2"]

        assert not plugin.deviceListener["test1"]?
        assert removeListenerCalled