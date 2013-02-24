package Zng::Net::HTTP::Channel;

use strict;
use Zng::Net::HTTP::Stream;
use HTTP::Request;
use HTTP::Response;
use IO::Poll qw{POLLIN POLLOUT};
use IO::Socket::SSL;

my $PACKAGE = __PACKAGE__;

sub new ( $$$$ ) {
    my $class = shift;
    my $net = shift;
    my $addrport = shift;
    my $ssl = shift;

    my $self = {
	net => $net,
	addrport => $addrport,
	ssl => $ssl,
	errorstring => undef,
	sending_tasks => [],
	receiving_tasks => [],
	response => undef,
	buffer => undef,
	offset => 0,
	stream => undef,
	event => 0,
    };
    bless $self, $class;
}

sub add_request ( $$$ ) {
    my $self = shift;
    my $request = shift;
    my $listener = shift;

    my $net = $self->{net};

    my $errorstring = $self->{errorstring};
    if ($errorstring) {
	$net->add_log($request, "aborted: $errorstring");

	$@ = $errorstring;
	&$listener(undef);
	return;
    }

    my $sending_tasks = $self->{sending_tasks};
    my $receiving_tasks = $self->{receiving_tasks};

    my $task = {
	request => $request,
	listener => $listener,
    };
    push @$sending_tasks, $task;

    $net->add_log($request, 'connecting');
    if (@$sending_tasks == 1&& !@$receiving_tasks) {
	$self->__connect;
    }
}

sub handle ( $ )  {
    my $self = shift;

    return $self->{stream}->handle;
}

sub event ( $ ) {
    my $self = shift;

    return $self->{event};
}

sub __abort ( $$ ) {
    my $self = shift;
    my $errorstring = shift;

    my $net = $self->{net};
    my $stream = $self->{stream};

    if ($stream) {
	$self->{event} = 0;
	close $stream->handle;
    }

    my $log = $self->{log};

    my $sending_tasks = $self->{sending_tasks};
    my $receiving_tasks = $self->{receiving_tasks};
    for my $task (@$sending_tasks, @$receiving_tasks) {
	my $request = $task->{request};
	$net->add_log($request, "aborted: $errorstring");

	my $listener = $task->{listener};
	$@ = $errorstring;
	&$listener(undef);
    }

    $self->{errorstring} = $errorstring;
}

sub __connect ( $ ) {
    my $self = shift;

    my $addrport = $self->{addrport};
    my $stream = Zng::Net::HTTP::Stream->new(KeepAlive => 1,
					     PeerAddr => $addrport,
					     Blocking => 0);
    unless ($stream) {
	$self->__abort("$PACKAGE: cannot connect: $@");
	return;
    }

    my $net = $self->{net};
    $self->{event} = POLLIN | POLLOUT;

    $self->{stream} = $stream;
}

sub __receive_response_headers ( $ ) {
    my $self = shift;

    my $stream = $self->{stream};

    my ($code, $message, @headers) = eval {
	$stream->read_response_headers;
    };
    if ($@ eq "Zng::Net::HTTP::Stream: resource temporarily unavailable\n") {
	return;
    } elsif ($@) {
	$self->__abort($@);
	return;
    }

    my $headers = HTTP::Headers->new(@headers);
    my $response = HTTP::Response->new($code, $message, $headers);

    my $connection = $response->header('Connection');
    my @connection = split /\s*,\s*/, $connection;

    my $sending_tasks = $self->{sending_tasks};
    my $receiving_tasks = $self->{receiving_tasks};

    my $keep_alive = $stream->peer_http_version eq '1.1';
    $keep_alive &&= !grep /close/i, @connection;
    $keep_alive ||= grep /keep-alive/i, @connection;
    $keep_alive &&= @$sending_tasks && @$receiving_tasks == 1;
    if ($keep_alive) {
	my $net = $self->{net};
	$self->{event} = POLLOUT | POLLIN;
    }

    $self->{response} = $response;
}

sub __receive_response_body ( $ ) {
    my $self = shift;

    my $stream = $self->{stream};

    my $body;
    my $count = eval { $stream->read_entity_body($body, 8192) };
    if ($@ eq "Zng::Net::HTTP::Stream: resource temporarily unavailable\n") {
	return;
    } elsif ($@) {
	$self->__abort($@);
	return;
    } elsif (!defined $count) {
	$self->__abort("$PACKAGE: cannot receive: $!");
	return;
    }

    my $response = $self->{response};
    if ($count) {
	$response->add_content($body);
	return;
    }

    my $connection = $response->header('Connection');
    my @connection = split /\s*,\s*/, $connection;

    my $sending_tasks = $self->{sending_tasks};
    my $receiving_tasks = $self->{receiving_tasks};
    my $task = shift @$receiving_tasks;

    my $keep_alive = $stream->peer_http_version eq '1.1';
    $keep_alive &&= !grep /close/i, @connection;
    $keep_alive ||= grep /keep-alive/i, @connection;
    $keep_alive &&= @$sending_tasks ||  @$receiving_tasks;

    my $net = $self->{net};

    unless ($keep_alive) {
	$self->{event} = 0;
	close $stream->handle;
	if (@$sending_tasks) {
	    $self->__connect;
	}
    }

    my $request = $task->{request};
    $response->request($request);
    $net->add_log($request, 'completed');

    my $listener = $task->{listener};
    &$listener($response);

    $self->{response} = undef;
}

sub __receive_response ( $ ) {
    my $self = shift;

    if (!$self->{response}) {
	$self->__receive_response_headers;
	return;
    }
    $self->__receive_response_body;
}

sub __prepare_send_request ( $ ) {
    my $self = shift;

    my $sending_tasks = $self->{sending_tasks};
    my $task = shift @$sending_tasks;
    unless ($task) {
	return 0;
    }

    my $request = $task->{request};
    my $uri = $request->uri;
    my $host = $uri->port == $uri->default_port ? $uri->host : $uri->host_port;
    $request->header('Host', $host);
    unless (@$sending_tasks) {
	$request->header('Connection', 'close');
    }

    my $method = $request->method;
    my $path_query = $uri->path_query || '/';
    my @headers;
    $request->scan(sub { push @headers, @_; });

    $self->{buffer} .=
	$self->{stream}->format_request($method, $path_query, @headers);

    my $receiving_tasks = $self->{receiving_tasks};
    push @$receiving_tasks, $task;

    my $net = $self->{net};
    $net->add_log($request, 'communicating');
    1;
}

sub __prepare_send_requests ( $ ) {
    my $self = shift;

    if ($self->{stream}->peer_http_version ne '1.1') {
	$self->__prepare_send_request;
	return;
    }

    1 while ($self->__prepare_send_request);
}

sub __send_requests ( $ ) {
    my $self = shift;

    my $stream = $self->{stream};

    unless (defined $self->{buffer}) {
	$self->__prepare_send_requests;
    }

    my $buffer = $self->{buffer};
    my $offset = $self->{offset};
    my $count = $stream->handle->syswrite($buffer, undef, $offset);
    unless (defined $count) {
	$self->__abort("$PACKAGE: cannot send: $!");
	return;
    }

    $offset += $count;
    if ($offset == length $buffer) {
	my $net = $self->{net};
	$self->{event} = POLLIN;

	$buffer = undef;
	$offset = 0;
    }

    $self->{buffer} = $buffer;
    $self->{offset} = $offset;
}

sub handle_event ( $$ ) {
    my $self = shift;
    my $event = shift;

    unless ($event) {
	$self->__abort("$PACKAGE: timeout");
	return;
    }

    my $handle = $self->{stream}->handle;

    if ($self->{ssl} && !$handle->isa('IO::Socket::SSL')) {
	my $net = $self->{net};
	if (!IO::Socket::SSL->start_SSL($handle)) {
	    if ($SSL_ERROR == SSL_WANT_READ) {
		$self->{event} = POLLIN;
		return;
	    } elsif ($SSL_ERROR == SSL_WANT_WRITE) {
		$self->{event} = POLLOUT;
		return;
	    } else {
		$net->abort($SSL_ERROR);
		return;
	    }
	}
	$self->{event} = POLLIN | POLLOUT;
	return;
    }

    $self->__send_requests if $event & POLLOUT;
    $self->__receive_response if $event & POLLIN;
}

1;
