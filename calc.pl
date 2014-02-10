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



	// load dataset from csv
 	var data = d3.csv.parse(d3.select('#' + datasource).text());

	// get frequency bins
	var bins = d3.keys(data[0]).filter(function(key) { return key.indexOf("freq") == 0; }).map(function(key){return key.replace("freq","");});

	
  	var color_range = ['#39a43d', '#7dbd2f', '#b0ca28', '#d7bf20', '#e38e16', '#f04e0c', '#fc0000',
  		'#36344c', '#352f3f', '#2f2832', '#262026'];

	/*
	var color_range = [
				'#fff7ec',
				'#fee8c8',
				'#fdd49e',
				'#fdbb84',
				'#fc8d59',
				'#ef6548',
				'#d7301f',
				'#b30000',
				'#7f0000',
				'#6f0000',
				'#5f0000'];
	*/

	// this color scale might be more appropriate since 
	// it is ordered by saturation/intensity instead of hue
	/*var color_range = [	
				'rgba(251,227,153,255)',
				'rgba(247,205,137,255)',
				'rgba(244,183,122,255)',
				'rgba(240,161,107,255)',
				'rgba(237,139,92,255)',
				'rgba(233,118,77,255)',
				'rgba(230,96,62,255)',
				'rgba(226,74,47,255)',
				'rgba(223,52,32,255)',
				'rgba(219,30,17,255)',
				'rgba(216,9,2,255)'];
	*/

	max_count = 0;

	// calculate cumulative frequencies
	data.forEach(function(d,i){
		cfreq = 0;
		for(i in bins){
			cfreq += (+d["freq" + bins[i]]);
			d["cfreq"+bins[i]] = cfreq;
		}
		max_count = (+d.cnt > max_count) ? +d.cnt : max_count;
	});


	margin = {top:120,right:50,bottom:50,left:100};

	chartWidth = Math.floor(window.innerWidth*0.90) + margin.right  ;//+margin.left;
	barWidth = 20;

	chartHeight = (barWidth+1)*(data.length+1) + margin.bottom + margin.top;	

	// create chart
	var chart = d3.select("#chart").append("svg")
		.attr("width",chartWidth+"px")
		.attr("height",(barWidth+1)*(data.length+1) + margin.bottom + margin.top + "px");

	// bind data records to group elements
	var bars = chart.selectAll("g").data(data);
	barGroups = bars.enter().append("g");

	
	// calculate ticks interval
	scale_order = Math.floor(Math.log(max_count)/Math.LN10);
	interval = Math.pow(10,scale_order)/(5);

	intervals = [];
	for(i=0;i < max_count; i=i+interval){
		intervals.push(i);
	}

	// create legend
	var legend = d3.select("#chart svg").append("g")
		.attr("width",bins.length * 100)
		.attr("height",60)
		.attr("x",margin.left)
		.attr("y",10)
		.attr("stroke","#555")
		.attr("fill-opacity",0.0);

	var grid = d3.select("#chart svg").append("g");

	// add legend labels	
	legendlabel_w = (chartWidth / color_range.length)/2;
	legend.selectAll("rect").data(color_range).enter().append("rect")
		.attr("x",function(d,i){return i * legendlabel_w  + margin.left ;})
		.attr("y",10)
		.attr("width",function(d,i){return  legendlabel_w-5;})
		.attr("height",10)
		.attr("fill",function(d){return d;})
		.attr("fill-opacity",1.0);
	legend.selectAll("text").data(bins).enter().append("text")
		.text(function(d){
			return d/1000 + "s";
		})
		.attr("x",function(d,i){return i * legendlabel_w  + margin.left + legendlabel_w/2 -14 ;})
		.attr("y",40)
		.attr("fill-opacity",1.0);

	
	// add lines and ticks
	grid.append("line") // x-axis
		.attr("x1",margin.left-10)
		.attr("y1",margin.top)
		.attr("x2",chartWidth + 10)
		.attr("y2",margin.top)
		.attr("shape-rendering","crispEdges")
		.attr("stroke","black")
		.attr("stroke-width",1);

	//TODO: add x-axis label
	


	grid.append("line") // y-axis
		.attr("x1",margin.left)
		.attr("y1",margin.top -10)
		.attr("x2",margin.left)
		.attr("y2",chartHeight)
		.attr("shape-rendering","crispEdges")
		.attr("stroke","black")
		.attr("stroke-width",1);
	
	x_scale_factor =(max_count/(chartWidth-margin.left));

	
	for(i in intervals){
		grid.append("line") // horizontal-lines
			.attr("x1",margin.left + intervals[i]/x_scale_factor)
			.attr("y1",margin.top -10)
			.attr("x2",margin.left + intervals[i]/x_scale_factor)
			.attr("y2",chartHeight)
			.attr("stroke","#aaa")
			.attr("stroke-width",1);

		grid.append("text").text(d3.round(intervals[i],1))
			.attr("x",margin.left + intervals[i]/x_scale_factor - 5)
			.attr("y",margin.top -15);
	}


	// add date label to each bar
	barGroups.append("text").text(function(d,i){return d.date;})
		.attr("x",10)
		.attr("y",function(d,i){return (barWidth+1)*(i+1)+ margin.top;})
		.attr("font-size","16px");
	
	// draw bar segment for each frequency bin 
	bins.forEach(function(freq,j){	
		barGroups.append("rect")
			.attr("x",function(d,i){
				return ((d["cfreq"+freq]-d["freq"+freq])/max_count*(chartWidth-margin.left))+margin.left;
			})
			.attr("y",function(d,i){return (barWidth+1)*(i+1)-barWidth+5 + margin.top;})
			.attr("width",function(d,i){
				return ((d["freq"+freq])/max_count*(chartWidth-margin.left));
			})
			.attr("height",barWidth)
			.attr("freq",function(d,i){return d["freq"+freq];})
			.attr("cfreq",function(d,i){return d["cfreq"+freq];})
			.attr("fill",color_range[j])//"hsl("+(100-j*25) +",70%,60%)")
			.on("mouseover",function(){highlight_legend(j);})
			.on("mouseout",hide_summary);
	});

	function highlight_legend(j){
		colorboxes = legend.selectAll("rect")[0];
		console.log(colorboxes[j].x = j);
	}

	function hide_summary(d,i){
		//console.log("leaving");
	}

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
