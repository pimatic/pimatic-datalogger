( ->
  deviceId = null
  chartInfo = null
  sensorListener = null

  $(document).on "pagecreate", '#index', (event) ->

    $('#items').on "click", 'li.item .attributes.contains-attr-type-Number', ->
      deviceId = $(this).parent('.item').data('item-id')
      jQuery.mobile.changePage '#datalogger'


  $(document).on "pagecreate", '#datalogger', (event) ->
    $("#logger-attr-values").on "click", '.show ', (event) ->
      sensorValueName = $(this).parents(".attr-value").data('attr-value-name')
      if deviceId?
        showGraph deviceId, sensorValueName
      return

    $("#logger-attr-values").on "change", ".logging-switch",(event, ui) ->
      sensorValueName = $(this).parents(".attr-value").data('attr-value-name')
      action = (if $(this).val() is 'yes' then "add" else "remove")
      $.get("/datalogger/#{action}/#{deviceId}/#{sensorValueName}")
        .done(ajaxShowToast)
        .fail(ajaxAlertFail)
      return


  $(document).on "pageshow", '#datalogger', (event) ->
    pimatic.socket.on 'device-attribute', sensorListener = (data) ->
      unless chartInfo? then return
      if data.id is chartInfo.deviceId and data.name is chartInfo.attrName
        point = [new Date().getTime(), data.value]
        showToast __('new sensor value: %s', data.value)
        $("#chart").highcharts().series[0].addPoint point, true, true
      return
    return

  $(document).on "pagehide", '#datalogger', (event) ->
    if sensorListener?
      pimatic.socket.removeListener 'device-attribute', sensorListener
    return
  

  $(document).on "pagebeforeshow", '#datalogger', (event) ->
    unless deviceId?
      jQuery.mobile.changePage '#index'
      return false
    
    $("#logger-attr-values").find('li.attr-value').remove()
    $.get( "datalogger/info/#{deviceId}", (data) ->
      for name, logged of data.loggingAttributes
        attribute = pimatic.devices[deviceId]?.attributes?[name]
        unless attribute
          console.log "could not find attribute #{name}"
        li = $ $('#datalogger-attr-value-template').html()
        li.find('.attr-value-name').text(attribute.label)
        li.find('label').attr('for', "flip-attr-value-#{name}")
        select = li.find('select')
          .attr('name', "flip-attr-value-#{name}")
          .attr('id', "flip-attr-value-#{name}")             
        li.data('attr-value-name', name)
        val = (if logged then 'yes' else 'no')
        select.find("option[value=#{val}]").attr('selected', 'selected')
        select.slider() 
        li.find('.show').button()
        $("#logger-attr-values").append li

      $("#logger-attr-values").listview('refresh')
      for name, logged of data.loggingAttributes
        if logged 
          showGraph deviceId, name
          return
    ).done(ajaxShowToast).fail(ajaxAlertFail)
    return

  showGraph = (deviceId, attrName) ->
    device = pimatic.devices[deviceId]
    unless device
      console.log "device not found?"
      return
    attribute = device.attributes[attrName]
    unless attribute
      console.log "attribute not found?"
      return

    to = new Date
    from = new Date()
    from.setDate(to.getDate()-1)

    $.ajax(
      url: "datalogger/data/#{deviceId}/#{attrName}"
      timeout: 30000 #ms
      type: "POST"
      data: 
        fromTime: from.getTime()
        toTime: to.getTime()
    ).done( (data) ->

      options =
        title: 
          text: attribute.label
        tooltip:
          valueDecimals: 2
        yAxis:
          labels:
            format: "{value} #{attribute.unit}"
        rangeSelector:
          enabled: no
        series: [
          name: attribute.label
          data: data.data
        ]


      chart = $("#chart").highcharts "StockChart", options
      chartInfo =
        deviceId: deviceId
        attrName: attrName
    ).fail(ajaxAlertFail)

)()