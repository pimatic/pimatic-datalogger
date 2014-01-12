( ->
  deviceId = null
  chartInfo = null
  sensorListener = null

  $(document).on "pagecreate", '#index', (event) ->

    $('#items').on "click", '.values', ->
      deviceId = $(this).parent('.item').data('item-id')
      jQuery.mobile.changePage '#datalogger'


  $(document).on "pagecreate", '#datalogger', (event) ->
    $("#logger-sensor-values").on "click", '.show ', (event) ->
      sensorValueName = $(this).parents(".sensor-value").data('sensor-value-name')
      showGraph deviceId, sensorValueName
      return

    $("#logger-sensor-values").on "change", ".logging-switch",(event, ui) ->
      sensorValueName = $(this).parents(".sensor-value").data('sensor-value-name')
      action = (if $(this).val() is 'yes' then "add" else "remove")
      $.get("/datalogger/#{action}/#{deviceId}/#{sensorValueName}")
        .done(ajaxShowToast)
        .fail(ajaxAlertFail)
      return


  $(document).on "pageshow", '#datalogger', (event) ->
    pimatic.socket.on 'sensor-value', sensorListener = (data) ->
      unless chartInfo? then return
      if data.id is chartInfo.deviceId and data.name is chartInfo.sensorValue
        point = [new Date().getTime(), data.value]
        showToast __('new sensor value: %s', data.value)
        $("#chart").highcharts().series[0].addPoint point, true, true
      return
    return

  $(document).on "pagehide", '#datalogger', (event) ->
    if sensorListener?
      pimatic.socket.removeListener 'sensor-value', sensorListener
    return
  

  $(document).on "pagebeforeshow", '#datalogger', (event) ->
    $("#logger-sensor-values").find('li.sensor-value').remove()
    $.get "datalogger/info/#{deviceId}", (data) ->
      for name, logged of data.loggingSensorValues
        li = $ $('#datalogger-sensor-value-template').html()
        li.find('.sensor-value-name').text(name)
        li.find('label').attr('for', "flip-sensor-value-#{name}")
        select = li.find('select')
          .attr('name', "flip-sensor-value-#{name}")
          .attr('id', "flip-sensor-value-#{name}")             
        li.data('sensor-value-name', name)
        val = (if logged then 'yes' else 'no')
        select.find("option[value=#{val}]").attr('selected', 'selected')
        select.slider() 
        li.find('.show').button()
        $("#logger-sensor-values").append li

      $("#logger-sensor-values").listview('refresh')
      for name, logged of data.loggingSensorValues
        if logged 
          showGraph deviceId, name
          return
      return

  showGraph = (deviceId, sensorValue) ->
    $.get "datalogger/data/#{deviceId}/#{sensorValue}", (data) ->
      chart = $("#chart").highcharts "StockChart", data
      chartInfo =
        deviceId: deviceId
        sensorValue: sensorValue

)()