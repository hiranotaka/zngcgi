#!/usr/bin/perl

use strict;
use FindBin;
use lib "$FindBin::RealBin/../lib";

use Time::localtime;
use Time::Local;

use CGI qw{:standard start_table end_table start_Tr end_Tr};
use HTTP::Status;
use GD;
use NKF;

use Zng::Cache;

my $PACKAGE = $0;

sub check_response ( $$ ) {
    my $entry = shift;
    my $response = shift;

    delete $entry->{temporary_error};

    unless ($response) {
	$entry->{temporary_error} = $@;
	return 0;
    }

    my $code = $response->code;
    my $request = $response->request;
    unless ($code == RC_OK ||
	    $code == RC_NOT_MODIFIED && defined $request->if_modified_since) {
	$entry->{temporary_error} = "$PACKAGE: unexpected HTTP status $code\n";
	return 0;
    }

    return 1;
}

sub parse_png {
    my $content = shift;
    my $entry = shift;

    require GD;
    my $image = GD::Image->new($content) or return;

    my $forecasts = [{min => 80, max => undef},
		     {min => 50, max => 80},
		     {min => 30, max => 50},
		     {min => 20, max => 30},
		     {min => 10, max => 20},
		     {min => 5, max => 10},
		     {min => 1, max => 5},
		     {min => 0, max => 1}];

    my $x = 511;
    my $y = 287;
    my $color_forecasts = {};
    for my $forecast (@$forecasts) {
	my $color = $image->getPixel($x, $y);
	$color_forecasts->{$color} = $forecast;
	$y += 19;
    }

    my $default_forecast = {min => undef, max => 0};

    my $spots = $::spots;
    my $spot_forecasts;;
    for my $index (0..$#$spots) {
	my $spot = $spots->[$index];
	my $color = $image->getPixel($spot->{x}, $spot->{y});
	my $forecast = $color_forecasts->{$color} || $default_forecast;
	$spot_forecasts->[$index] = $forecast;
    }

    $entry->{forecasts} = $spot_forecasts;
}

sub handle_response_png {
    my ($source, $entry, $response) = @_;

    check_response $entry, $response or return;
    parse_png $response->content, $entry;
}

sub add_request_png ( $$$ ) {
    my $net = shift;
    my $source = shift;
    my $entry = shift;

    my $index = $source->{index};
    my $interval = $source->{interval};
    my $time = $source->{time};
    my $start_time = ($index + 1) * $interval + $time;
    my $end_time = $start_time + $interval;
    $entry->{start_time} = $start_time;
    $entry->{end_time} = $end_time;

    my $dir = $source->{dir};
    my $png_dir = $source->{png_dir};
    my $area = $::area;
    my $localtime = localtime $time;
    my $png_file =
	sprintf('%04d%02d%02d%02d%02d-%02d.png', $localtime->year + 1900,
		$localtime->mon + 1, $localtime->mday, $localtime->hour,
		$localtime->min, $index + 2);
    my $uri = "http://www.jma.go.jp/jp/$dir/imgs/$png_dir/$area/$png_file";
    $entry->{link} = $uri;

    my $request = HTTP::Request->new(GET => $uri);
    my $listener = sub {
	my ($response) = shift;
	handle_response_png($source, $entry, $response);
    };
    $net->add_request($request, $listener);
}

sub parse_javascript ( $$ ) {
    my $feed = shift;
    my $content = shift;

    delete $feed->{parmanent_error};

    my (undef, $line) = split /\n/, $content;

    my $datetime = substr $line, 40, 12;
    unless ($datetime =~ /^(\d\d\d\d)(\d\d)(\d\d)(\d\d)(\d\d)$/) {
	$feed->{parmanent_error} = "$PACKAGE: Cannot parse date\n";
	return;
    }

    my $time = eval { timelocal(0, $5, $4, $3, $2 - 1, $1) };
    if ($@) {
	$feed->{parmanent_error} = "$PACKAGE: Cannot parse date: $@";
	return;
    }

    $feed->{__time} = $time;

    my $entries = [];
    for my $index (0..4) {
	my $entry = {
	    temporary_error => '$PACKAGE: needs update',
	};
	push @$entries, $entry;
    }
    $feed->{entries} = $entries;
}

sub handle_response_javascript ( $$$$ ) {
    my $net = shift;
    my $source = shift;
    my $feed = shift;
    my $response = shift;

    check_response $feed, $response or return;

    if ($response->code == RC_OK) {
	$feed->{__last_modified} = $response->last_modified;

	my $content = $response->content;
	parse_javascript $feed, $content;
    }

    my $dir = $source->{dir};
    my $png_dir = $source->{png_dir};
    my $interval = $source->{interval};
    my $time = $feed->{__time};

    my $entries = $feed->{entries};
    for my $index (0..$#$entries) {
	my $entry = $entries->[$index];
	defined $entry->{temporary_error} or next;

	my $source = {
	    dir => $dir,
	    png_dir => $png_dir,
	    index => $index,
	    interval => $interval,
	    time => $time,
	};
	add_request_png($net, $source, $entry);
    }
}

sub add_request_javascript ( $$$ ) {
    my $net = shift;
    my $source = shift;
    my $feed = shift;

    my $dir = $source->{dir};
    my $javascript_file = $source->{javascript_file};
    my $uri = "http://www.jma.go.jp/jp/${dir}/hisjs/${javascript_file}";
    my $request = HTTP::Request->new(GET => $uri);

    my $last_modified = $feed->{__last_modified};
    $request->if_modified_since($last_modified);

    my $handler = sub ( $ ){
	my $response = shift;
	handle_response_javascript($net, $source, $feed, $response);
    };

    $net->add_request($request, $handler);
}

sub update ( $ ) {
    my $feeds = shift || [];

    my $sources = [
	{
	    dir => 'radnowc',
	    javascript_file => 'nowcast.js',
	    png_dir => 'nowcast',
	    interval => 10 * 60,
	},
	{
	    dir => 'radame',
	    javascript_file => 'shttime.js',
	    png_dir => 'prec',
	    interval => 60 * 60,
	}
	];

    require Zng::Net;
    my $net = Zng::Net->new(log_handle => $::log_handle,
			    chart_dir => $::chart_dir,
			    chart_style_file => $::chart_style_file,
			    chart_count => $::chart_count);

    for my $index (0.. $#$sources) {
	my $source = $sources->[$index];
	my $feed = $feeds->[$index];
	unless ($feed) {
	    $feed = {};
	    $feeds->[$index] = $feed;
	}
	add_request_javascript($net, $source, $feed);
    }

    my $timeout = $::timeout || 4;
    $net->dispatch($timeout);

    return $feeds;
}

sub print_perl ($) {
    my $cache = shift;

    use Data::Dumper;
    print(header(-type => 'text/plain', -charset => 'us-ascii'),
	  Dumper($cache->content));
}

sub print_html ( $ ) {
    my $cache = shift;
    my $dtd = ['-//W3C//DTD XHTML 1.0 Strict//EN',
	       'http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd'];
    my $content = '';
    my $title = $::title || 'ZngWeather 3.0.1';
    my $static_dir = $::static_dir || 'static';
    my $style_file = $::style_file || $static_dir . '/weather.css';
    $content .= start_html(-dtd => $dtd,
			   -encoding => 'shift_jis',
			   -lang => 'ja',
			   -title => $title,
			   -style => { src => $style_file });
    my $is_mobile = param('type') eq 'mobile';
    my $mobile_link =
	'http://weather.mobile.yahoo.co.jp/p/weather/disaster/earthquake';
    my $link = 'http://typhoon.yahoo.co.jp/weather/jp/earthquake/';
    my $url = url(-relative => 1) || './';
    my $nav = $is_mobile ?
	a({-href => $mobile_link }, '地震速報') :
	a({-href => $link}, '地震速報') . ' | ' .
	a({-href => "$url?type=mobile"}, 'Mobile') . ' | ' .
	a({-href => "$url?type=perl"}, 'Raw');
    $content .= div({-class => 'nav'}, $nav);
    $content .= start_table({-class => 'numeric'});
    $content .= caption('降水量 (気象庁発表)');
    $content .= start_Tr . th('');
    for my $spot (@$::spots) {
	my $label = $spot->{label};
	$content .= th($label);
    }
    $content .= end_Tr;
    my $feeds = $cache->content;
    for my $feed (@$feeds) {
	my $entries = $feed->{entries};
	for my $entry (@$entries) {
	    $content .= start_Tr;
	    my $link = $entry->{link};
	    my $start_time = localtime $entry->{start_time};
	    my $end_time = localtime $entry->{end_time};
	    $content .= th(a({-href => $link},
			     sprintf('%02d:%02d-%02d:%02d',
				     $start_time->hour, $start_time->min,
				     $end_time->hour, $end_time->min)));

	    my $forecasts = $entry->{forecasts};
	    for my $forecast (@$forecasts) {
		my $min = $forecast->{min};
		my $max = $forecast->{max};
		my $attr = {};
		$attr->{-class} = "pcpn-$min" if defined $min;
		my $range = '';
		$range .= "$min-" if defined $min;
		$range .= "$max" if defined $max;
		$content .= td($attr, $range, 'mm/h');
	    }
	    $content .= end_Tr;
	}
    }
    $content .= start_Tr . th('3時間毎');
    for my $spot (@$::spots) {
	my $code = $spot->{code};
	my $area = $spot->{area};
	my $ken = $spot->{ken};
	my $link =
	    "http://weather.yahoo.co.jp/weather/jp/$ken/$area/$code.html";
	my $mobile_link =
	    'http://weather.mobile.yahoo.co.jp/p/weather/forecast/pnts?' .
	    "code=$code&area=$area&ken=$ken";
	$content .= td(a({-href => $is_mobile ? $mobile_link : $link}, '▼'));
    }
    $content .= end_Tr;
    $content .= end_table;
    $content .= end_html;

    my $sjis_content = nkf '-s -W -x', $content;
    print(header(-charset => 'shift_jis',
		 -Content_lengh => length $sjis_content),
	  $sjis_content);
}

my $printers = {
    perl => \&print_perl,
};

require './weather.conf';

my $cache_file = $::cache_file || 'cache.dat';
my $ttl = $::ttl || 10;
my $cache = Zng::Cache->new(updater => \&update,
			    file => $cache_file,
			    ttl => $ttl);
$cache->fetch;

my $type = param('type');
my $printer = $printers->{$type} || \&print_html;
&$printer($cache);
