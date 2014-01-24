Highcharts.Chart.prototype.callbacks.push(function(chart) {
  var hasTouch = document.documentElement.ontouchstart !== undefined,
      container = chart.container;

  callTrough = function(f) {
    return function(e) {
      // if we have touch
      if (hasTouch) {
        // and it is a multitouch event
        if (e && e.touches && e.touches.length > 1) {
          return f(e);
        } else {
          if (chart.pointer.inClass(e.target, 'highcharts-tracker') || 
            chart.isInsidePlot(e.chartX - chart.plotLeft, e.chartY - chart.plotTop)) {
            //let system handle the event ot allow scralling
            setTimeout(function() {
              f(e);
            }, 1);
            return;
          } else {
            // call through
            return f(e);
          }
        }
      } else {
        //no touch so call through
        return f(e);
      }
    }
  };

  container.ontouchstart = callTrough(container.ontouchstart, 'touchstart');
  container.onmousemove = callTrough(container.ontouchmove, 'touchmove');
  container.ontouchmove = callTrough(container.onmousemove, 'mousemove');
 
  // mouseMove = function (e) {
  //   if (hasTouch) {
  //     if (e && e.touches && e.touches.length > 1) {
  //       mouseTracker.onContainerTouchMove(e);
  //     } else {
  //       if (mouseTracker.inClass(e.target, 'highcharts-tracker') || 
  //         chart.isInsidePlot(e.chartX - chart.plotLeft, e.chartY - chart.plotTop)) {
  //         ;
  //       } else {
  //         mouseTracker.onContainerTouchMove(e);
  //       }
  //       return
  //     }
  //   } else {
  //     mouseTracker.onContainerMouseMove(e);
  //   }
  // };
  
  // click = function (e) {
  //   if (hasTouch) {
  //       mouseTracker.onContainerMouseMove(e);   
  //   }
  //   mouseTracker.onContainerClick(e);
  // };
 
  // container.onmousemove = container.ontouchstart = container.ontouchmove = mouseMove;
  // container.onclick = click;

  console.log( container.onmousemove);
});