package Zng::Net;

use strict;
use vars qw{$VERSION};
use CGI;
use File::Spec;
use IO::Poll;
use Socket;
use Time::HiRes qw{gettimeofday tv_interval};
use Zng::Net::DNS::Channel;
use Zng::Net::HTTP::Channel;

$VERSION = '1.00';

sub new ( $;% ) {
    my $class = shift;
    my %options = @_;

    my $self = {
	dns_channels => {},
	http_channels => {},
	https_channels => {},
	logs => [],
	log_handle => $options{log_handle},
	chart_dir => $options{chart_dir},
	chart_style_file => $options{chart_style_file},
	chart_count => $options{chart_count},
	ssl_ca_file => $options{ssl_ca_file},
    };
    bless $self, $class;
}

my $DEC_OCTET_RE = qr/(?:[1-9]?\d|1\d\d|2[0-4]\d|25[1-5])/;
my $IPADDR_RE = qr/$DEC_OCTET_RE(?:\.$DEC_OCTET_RE){3}/;

sub add_query ( $$$ ) {
    my $self = shift;
    my $host = shift;
    my $answer_handler = shift;

    if ($host =~ /^$IPADDR_RE$/) {
    	my $addr = inet_aton($host);
	&$answer_handler($addr);
	return;
    }

    my $channels = $self->{dns_channels};
    my $channel = $channels->{$host};
    unless ($channel) {
	$channel = Zng::Net::DNS::Channel->new($self, $host);
	$channels->{$host} = $channel;
    }

    $channel->add_query($answer_handler);
}

sub add_request_addrport ( $$$$$ ) {
    my $self = shift;
    my $request = shift;
    my $response_handler = shift;
    my $addrport = shift;
    my $ssl = shift;

    my $channels = $ssl ? $self->{https_channels} : $self->{http_channels};
    my $channel = $channels->{$addrport};
    unless ($channel) {
	$channel = Zng::Net::HTTP::Channel->new($self, $addrport, $ssl);
	$channels->{$addrport} = $channel;
    }

    $channel->add_request($request, $response_handler);
}

sub add_request ( $$$ ) {
    my $self = shift;
    my $request = shift;
    my $response_handler = shift;

    my $uri = $request->uri;
    my $scheme = $uri->scheme;
    unless ($scheme eq 'http' || $scheme eq 'https') {
	$@ = __PACKAGE__ . ': unsupported scheme';
	&$response_handler(undef);
	return 1;
    }

    $self->add_log($request, 'resolving');

    my $host = $uri->host;
    my $port = $uri->port;
    my $answer_handler = sub ( $ ) {
	my $addr = shift;

	unless ($addr) {
	    $self->add_log($request, "aborted: $@");
	    &$response_handler(undef);
	    return;
	}
	$self->add_request_addrport($request, $response_handler, "$addr:$port",
				    $scheme eq 'https');
    };

    $self->add_query($host, $answer_handler);
    return;
}

sub dispatch ( $;$ ) {
    my $self = shift;
    my $timeout = shift;

    my @then;
    if (defined $timeout) {
	@then = gettimeofday;
    }

    while (1) {
	my $poll_timeout;
	if (defined $timeout) {
	    my @now = gettimeofday;
	    my $interval = tv_interval \@then, \@now;
	    $poll_timeout = $timeout - $interval;
	    $poll_timeout = 0 if ($poll_timeout < 0);
	}

	my $poll = new IO::Poll;
	my $channels = [
	    values %{$self->{dns_channels}},
	    values %{$self->{http_channels}},
	    values %{$self->{https_channels}},
	];
	for my $channel (@$channels) {
	    my $handle = $channel->handle;
	    my $type = $channel->event;
	    $poll->mask($handle, $type);
	}

	my $count = $poll->poll($poll_timeout);
	if ($count < 0) {
	    return;
	}

	if ($count == 0)  {
	    for my $channel (@$channels) {
		$channel->handle_event(0);
	    }
	    last;
	}

	my @handles = $poll->handles;
	foreach my $channel (@$channels) {
	    my $handle = $channel->handle;
	    my $event = $poll->events($handle) or next;
	    $channel->handle_event($event);
	}
    }

    $self->{dns_channels} = {};
    $self->{http_channels} = {};
    $self->{https_channels} = {};

    my $logs = $self->{logs};

    my $chart_count = $self->{chart_count};
    $chart_count > 0 or return;

    my $chart_dir = $self->{chart_dir};
    my @chart_files = glob File::Spec->catfile($chart_dir, "*.html");
    @chart_files = sort { $a <=> $b } @chart_files;

    while (@chart_files >= $chart_count) {
	unlink shift @chart_files;
    }

    my $chart_file = File::Spec->catfile($chart_dir, "$then[0].html");
    open my $handle, '>', $chart_file or return;

    my $first_time;
    my $last_time;

    my $requests = [];
    my $requests_logs = {};
    for my $log (@$logs) {
	my $time = $log->{time};
	$first_time ||= $time;
	$last_time = $time;

	my $request = $log->{request};
	my $request_logs = $requests_logs->{$request};
	unless ($request_logs) {
	    push @$requests, $request;
	    $request_logs = [];
	    $requests_logs->{$request} = $request_logs;
	}
	push @$request_logs, $log;
    }

    my $cgi = new CGI;

    $handle->print($cgi->start_html(-declare_xml => 1,
				    -lang => 'en',
				    -title => 'Zng::Net Chart',
				    -style => {
					-src => $self->{chart_style_file}
				    }),
		   $cgi->h1('Zng::Net Chart'),
		   $cgi->h2(scalar localtime),
		   $cgi->div({-class => 'resolving'}, ''),
		   $cgi->div({-class => 'label'},
			     'Resolving DNS hostnames'),
		   $cgi->div({-class => 'connecting'}, ''),
		   $cgi->div({-class => 'label'},
			     'Preparing HTTP pipelines'),
		   $cgi->div({-class => 'communicating'}, ''),
		   $cgi->div({-class => 'label'},
			     'Communicating HTTP messages'),
		   $cgi->div({-class => 'return'}, ''));

    my $first_last_interval = tv_interval($first_time, $last_time);

    for my $request (@$requests) {

	my $request_logs = $requests_logs->{$request};

	my $prev_time = $first_time;
	my $prev_state;

	for my $log (@$request_logs) {
	    my $time = $log->{time};
	    my $state = $log->{state};

	    my $prev_current_interval = tv_interval($prev_time, $time);
	    my $first_current_interval = tv_interval($first_time, $time);

	    my $class = $prev_state || 'tab';
	    my $width = $prev_current_interval * 75 / $first_last_interval;
	    $handle->print($cgi->div({-class => $class,
				      -style => "width: ${width}\%"},
				     "${first_current_interval}s"));

	    $prev_time = $time;
	    $prev_state = $state;
	}

	$handle->print($cgi->div({-class => 'label'}, $request->uri),
		       $cgi->div({-class => 'return'}, ''));
    }

    $handle->print($cgi->end_html);
    @$logs = ();
}

sub add_log ( $$$ ) {
    my $self = shift;
    my $request = shift;
    my $state = shift;

    my @time = gettimeofday;

    my $log_handle = $self->{log_handle};
    if ($log_handle) {
	$log_handle->printf("[%d.%06d] %s: %s\n", @time, $request->uri, $state);
	$log_handle->flush;
    }

    my $chart_count = $self->{chart_count};
    if ($chart_count) {
	my $log = {
	    time => \@time,
	    request => $request,
	    state => $state,
	};

	my $logs = $self->{logs};
	push @$logs, $log;
    }
}

sub ssl_ca_file ( $ ) {
  my $self = shift;
  return $self->{ssl_ca_file};
}

1;
