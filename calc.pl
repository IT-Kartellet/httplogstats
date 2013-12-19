#!/usr/bin/env perl
use strict;
use warnings;
use Data::Dumper;
use Storable qw(retrieve);

my $skip_url_re = qr{
    (?:^/wp/|/dynatracemonitor|/wp-content/|/wordpress/|/store/wp-content/|/_vti_bin)|(?:/blog/)|(?:.php|cmd.exe$)
}ix;

my @keys = qw(cnt min max avg);

my $filename = shift or die './calc.pl <filename>.dat [frequency|csv|html]';

my %stats = %{retrieve($filename)};

my $mode = (shift or 'text');

# Do some initial cleanup
foreach my $url (sort keys %stats) {
    # Fix up url's for mydamco and other application using rest style URL's
    if($url =~ m{^([^:]+:[^:]+:/.+)(/\d+|/)$}) {
        if(exists $stats{$1}) {
            $stats{$1}{sum} += $stats{$url}{sum}; 
            $stats{$1}{cnt} += $stats{$url}{cnt}; 
    
            foreach my $code (grep { /^code/ } keys %{$stats{$url}}) {
                $stats{$1}{$code} += $stats{$url}{$code};
            }
            
            foreach my $frequency (keys %{$stats{$url}{frequency}}) {
                $stats{$1}{frequency}{$frequency} += $stats{$url}{frequency}{$frequency};
            }
            
            $stats{$1}{max} = $stats{$url}{max} if $stats{$1}{max} < $stats{$url}{max}; 
            $stats{$1}{min} = $stats{$url}{min} if $stats{$1}{min} > $stats{$url}{min}; 
        
            push(@{$stats{$1}{error500}}, @{$stats{$url}{error500}}) if exists $stats{$url}{error500}; 

        } else { 
            $stats{$1} = $stats{$url};
        }
        delete $stats{$url};
        next;
    }
}

my %results;
my @urls = sort keys %stats;
my @extra_keys = ("error500", map { "freq$_" } sort { $a <=> $b } keys %{$stats{$urls[0]}{frequency}});
foreach my $url (@urls) {
    next if($stats{$url}{cnt} == 0);
    next if $url =~ $skip_url_re;
    next if $url =~ /\.(?:png|gif|jpg|css|ico|js)$/;

    #next if $url !~ /\*\.html$/i;
    #print Dumper($stats{$url});

    # Calculate avg
    $stats{$url}{avg} = $stats{$url}{cnt} ? int($stats{$url}{sum} / $stats{$url}{cnt}) : 0;
    
    # Print line with below keys
    my @values = @{$stats{$url}}{@keys};
   
    # Add error500 to the list of values in the csv 
    if(exists $stats{$url}->{error500}) {
        push(@values, int @{$stats{$url}->{error500}})
    } else {
        push(@values, 0);
    }
    
    # Split the key
    $url =~ /^(?<date>[^:]+):(?<method>[^:]+):(?<url>.+)/;
    # Generate csv value line
    $results{"$+{method} $+{url}"} .= "$+{date},'".$+{url}."',".join(",", 
        @values, 
        (map { $stats{$url}{frequency}{$_} } sort { $a <=> $b } keys %{$stats{$url}{frequency}}) # Add frequency
    )."\n";
}

if($mode eq 'html') {
    print html_header(sort keys %results);

    my $id = 0;
    foreach my $url (sort keys %results) {
        print qq|<script id="file|.($id++).qq|" type="text/csv">|;
        print "date,url,".join(",", @keys, @extra_keys)."\n";
        print $results{$url}; 
        print qq|</script>\n|;
    }

    print qq|<script>renderChart('file0', 'avg');</script>\n|;
    print html_footer() if $mode eq 'html';

} else {
    print "date,url,".join(",", @keys, @extra_keys)."\n";
    foreach my $url (sort keys %results) {
        print "$results{$url}";
    }
}

sub html_header {
    my $id = 0;
    return qq|<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">
<!-- Generated with d3-generator.com -->
<html>
  <head>
     <title>Results for $filename</title>
     <meta http-equiv="X-UA-Compatible" content="IE=9">
  </head>
  <body>
    <script src="http://d3js.org/d3.v2.min.js"></script>
  <div>
  <form>
    <select id="files" >|.
    (join "\n", map {  qq{<option value="file}.($id++).qq{">$_</option>} } @_).
   qq| </select>
    <select id="cols" >
      <option value="avg">avg</option>
      <option value="min">min</option>
      <option value="max">max</option>
      <option value="cnt">cnt</option>
      <option value="error500">error500</option>
      <option value="frequency">frequency</option>
    </select>
  <form>

  </div>
    <div id="chart"></div>
    <script>

function togglestuff () {
  var div = document.getElementById('chart');
  while (div.hasChildNodes()) {
    div.removeChild(div.lastChild);
  }
  
  var selectfiles = document.getElementById('files');
  var selectcols = document.getElementById('cols');

  if(selectcols.value.indexOf("frequency") == 0) {
    renderFrequencyChart(selectfiles.value);
  
  } else {
    renderChart(selectfiles.value, selectcols.value);
  }
  
  return false
};

document.getElementById("cols").onchange = togglestuff; 
document.getElementById("files").onchange = togglestuff; 

function renderChart(datasource, col) {

var data = d3.csv.parse(d3.select('#' + datasource).text());
var valueLabelWidth = 40; // space reserved for value labels (right)
var barHeight = 20; // height of one bar
var barLabelWidth = 100; // space reserved for bar labels
var barLabelPadding = 5; // padding between bar and bar labels (left)
var gridLabelHeight = 18; // space reserved for gridline labels
var gridChartOffset = 3; // space between start of grid and first bar
var maxBarWidth = 800; // width of the bar with the max value
 
// accessor functions 
var barLabel = function(d) { return d['date']; };
var barValue = function(d) { return parseFloat(d[col]); };
 
// scales
var yScale = d3.scale.ordinal().domain(d3.range(0, data.length)).rangeBands([0, data.length * barHeight]);
var y = function(d, i) { return yScale(i); };
var yText = function(d, i) { return y(d, i) + yScale.rangeBand() / 2; };
var x = d3.scale.linear().domain([0, d3.max(data, barValue)]).range([0, maxBarWidth]);
// svg container element
var chart = d3.select('#chart').append("svg")
  .attr('width', maxBarWidth + barLabelWidth + valueLabelWidth)
  .attr('height', gridLabelHeight + gridChartOffset + data.length * barHeight);
// grid line labels
var gridContainer = chart.append('g')
  .attr('transform', 'translate(' + barLabelWidth + ',' + gridLabelHeight + ')'); 
gridContainer.selectAll("text").data(x.ticks(10)).enter().append("text")
  .attr("x", x)
  .attr("dy", -3)
  .attr("text-anchor", "middle")
  .text(String);
// vertical grid lines
gridContainer.selectAll("line").data(x.ticks(10)).enter().append("line")
  .attr("x1", x)
  .attr("x2", x)
  .attr("y1", 0)
  .attr("y2", yScale.rangeExtent()[1] + gridChartOffset)
  .style("stroke", "#ccc");
// bar labels
var labelsContainer = chart.append('g')
  .attr('transform', 'translate(' + (barLabelWidth - barLabelPadding) + ',' + (gridLabelHeight + gridChartOffset) + ')'); 
labelsContainer.selectAll('text').data(data).enter().append('text')
  .attr('y', yText)
  .attr('stroke', 'none')
  .attr('fill', 'black')
  .attr("dy", ".35em") // vertical-align: middle
  .attr('text-anchor', 'end')
  .text(barLabel);
// bars
var barsContainer = chart.append('g')
  .attr('transform', 'translate(' + barLabelWidth + ',' + (gridLabelHeight + gridChartOffset) + ')'); 
barsContainer.selectAll("rect").data(data).enter().append("rect")
  .attr('y', y)
  .attr('height', yScale.rangeBand())
  .attr('width', function(d) { return x(barValue(d)); })
  .attr('stroke', 'white')
  .attr('fill', 'steelblue');
// bar value labels
barsContainer.selectAll("text").data(data).enter().append("text")
  .attr("x", function(d) { return x(barValue(d)); })
  .attr("y", yText)
  .attr("dx", 3) // padding-left
  .attr("dy", ".35em") // vertical-align: middle
  .attr("text-anchor", "start") // text-align: right
  .attr("fill", "black")
  .attr("stroke", "none")
  .text(function(d) { return d3.round(barValue(d), 2); });
// start line
barsContainer.append("line")
  .attr("y1", -gridChartOffset)
  .attr("y2", yScale.rangeExtent()[1] + gridChartOffset)
  .style("stroke", "#000");

}
</script>
<script>
function renderFrequencyChart(datasource, col) {
  var margin = {top: 20, right: 20, bottom: 30, left: 40},
      width = 960 - margin.left - margin.right,
      height = 500 - margin.top - margin.bottom;
   
  var x = d3.scale.ordinal()
      .rangeRoundBands([0, width], .1);
   
  var y = d3.scale.linear()
      .rangeRound([height, 0]);
   
  var color = d3.scale.ordinal()
  .range(
  ['#39a43d', '#7dbd2f', '#b0ca28', '#d7bf20', '#e38e16', '#f04e0c', '#fc0000',
  '#36344c', '#352f3f', '#2f2832', '#262026', '#191619', '#0d0c0c'
  ]
  );
  
  var xAxis = d3.svg.axis()
      .scale(x)
      .orient("bottom");
   
  var yAxis = d3.svg.axis()
      .scale(y)
      .orient("left")
      .tickFormat(d3.format(".2s"));
   
  var svg = d3.select("#chart").append("svg")
      .attr("width", width + margin.left + margin.right)
      .attr("height", height + margin.top + margin.bottom)
    .append("g")
      .attr("transform", "translate(" + margin.left + "," + margin.top + ")");
  
  var data = d3.csv.parse(d3.select('#' + datasource).text());

  color.domain(d3.keys(data[0]).filter(function(key) { return key.indexOf("freq") == 0; }));
 
  data.forEach(function(d) {
    var y0 = 0;
    d.samples = color.domain().map(function(name) {
      return {name: name, y0: y0, y1: y0 += +d[name]}; 
    });
    d.total = d.samples[d.samples.length - 1].y1;
  });
 
  //data.sort(function(a, b) { return b.total - a.total; });
 
  x.domain(data.map(function(d) { return d.date; }));
  y.domain([0, d3.max(data, function(d) { return d.total; })]);
 
  svg.append("g")
      .attr("class", "x axis")
      .attr("transform", "translate(0," + height + ")")
      .call(xAxis);
 
  svg.append("g")
      .attr("class", "y axis")
      .call(yAxis)
    .append("text")
      .attr("transform", "rotate(-90)")
      .attr("y", 6)
      .attr("dy", ".71em")
      .style("text-anchor", "end")
      .text("Samples");
 
  var state = svg.selectAll(".state")
      .data(data)
    .enter().append("g")
      .attr("class", "g")
      .attr("transform", function(d) { return "translate(" + x(d.date) + ",0)"; });
 
  state.selectAll("rect")
      .data(function(d) { return d.samples; })
    .enter().append("rect")
      .attr("width", x.rangeBand())
      .attr("y", function(d) { return y(d.y1); })
      .attr("height", function(d) { return y(d.y0) - y(d.y1); })
      .style("fill", function(d) { return color(d.name); });
 
  var legend = svg.selectAll(".legend")
      .data(color.domain().slice().reverse())
    .enter().append("g")
      .attr("class", "legend")
      .attr("transform", function(d, i) { return "translate(0," + i * 20 + ")"; });
 
  legend.append("rect")
      .attr("x", width - 18)
      .attr("width", 18)
      .attr("height", 18)
      .style("fill", color);
 
  legend.append("text")
      .attr("x", width - 24)
      .attr("y", 9)
      .attr("dy", ".35em")
      .style("text-anchor", "end")
      .text(function(d) { return d; });
 
}
</script>
|;
}

sub html_footer {
    return qq|
  </body>
</html>
|;
}
