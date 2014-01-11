


$(document).on "pagecreate", '#index', (event) ->
  device = null

  $('#items').on "click", '.values', ->
    deviceId = $(this).parent('.item').data('item-id')
    device = pimatic.devices[deviceId]
    jQuery.mobile.changePage '#datalogger'


  $(document).on "pagecreate", '#datalogger', (event) ->
    sensorValuesNames = (n for n,v of device.values)
    console.log sensorValuesNames
    $.get "datalogger/data/#{device.id}/temperature", (data) ->
      $("#chart").highcharts "StockChart", data

