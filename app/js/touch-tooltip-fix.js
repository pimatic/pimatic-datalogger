Highcharts.Chart.prototype.callbacks.push(function(chart) {
  var hasTouch = document.documentElement.ontouchstart !== undefined,
      mouseTracker = chart.pointer,
      container = chart.container,
      mouseMove;
 
  mouseMove = function (e) {
    if (hasTouch) {
        if (e && e.touches && e.touches.length > 1) {
            mouseTracker.onContainerTouchMove(e);
        } else {
            // normalize
            e = this.normalize(e);    
            if (this.inClass(e.target, 'highcharts-tracker') || 
              chart.isInsidePlot(e.chartX - chart.plotLeft, e.chartY - chart.plotTop)) {
              console.log('yes');
              mouseTracker.onContainerMouseMove(e);
            } else {
              console.log('no');
            }
            return;
        }
    } else {
                  // normalize
            e = this.normalize(e);    
            if (this.inClass(e.target, 'highcharts-tracker') || 
              chart.isInsidePlot(e.chartX - chart.plotLeft, e.chartY - chart.plotTop)) {
              console.log('yes');
              mouseTracker.onContainerMouseMove(e);
            } else {
              console.log('no');
            }
    }
  };
  
  click = function (e) {
    if (hasTouch) { 
        mouseTracker.onContainerMouseMove(e);      
    }
    mouseTracker.onContainerClick(e);    
  }
 
  container.onmousemove = container.ontouchstart = container.ontouchmove = mouseMove;
  container.onclick = click;
});