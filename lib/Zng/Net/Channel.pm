package Zng::Net::Channel;

use strict;
use Zng::Net::Stream;
use HTTP::Request;
use HTTP::Response;
use IO::Poll qw{POLLIN POLLOUT};

my $PACKAGE = __PACKAGE__;

sub new ( $$ ) {
    my $class = shift;
    my $net = shift;
    my $addrport = shift;

    my $self = {
	net => $net,
	addrport => $addrport,
	errorstring => undef,
	sending_tasks => [],
	receiving_tasks => [],
	response => undef,
	buffer => undef,
	offset => 0,
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

sub __abort ( $$;$ ) {
    my $self = shift;
    my $errorstring = shift;
    my $handle = shift;

    my $net = $self->{net};

    if ($handle) {
	$net->set($handle);
	close $handle;
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
    my $handle = Zng::Net::Stream->new(KeepAlive => 1,
				       PeerAddr => $addrport);
    unless ($handle) {
	$self->__abort("$PACKAGE: cannot connect: $@");
	return;
    }

    my $net = $self->{net};
    $net->set($handle, POLLOUT, $self);
}

sub __receive_response_headers ( $$ ) {
    my $self = shift;
    my $handle = shift;

    my ($code, $message, @headers) = eval {
	$handle->read_response_headers;
    };
    if ($@ eq "Zng::Net::Stream: resource temporarily unavailable\n") {
	return;
    } elsif ($@) {
	$self->__abort($@, $handle);
	return;
    }

    my $headers = HTTP::Headers->new(@headers);
    my $response = HTTP::Response->new($code, $message, $headers);

    my $connection = $response->header('Connection');
    my @connection = split /\s*,\s*/, $connection;

    my $sending_tasks = $self->{sending_tasks};
    my $receiving_tasks = $self->{receiving_tasks};

    my $keep_alive = $handle->peer_http_version eq '1.1';
    $keep_alive &&= !grep /close/i, @connection;
    $keep_alive ||= grep /keep-alive/i, @connection;
    $keep_alive &&= @$sending_tasks && @$receiving_tasks == 1;
    if ($keep_alive) {
	my $net = $self->{net};
	$net->set($handle, POLLOUT | POLLIN, $self);
    }

    $self->{response} = $response;
}

sub __receive_response_body ( $$ ) {
    my $self = shift;
    my $handle = shift;

    my $body;
    my $count = eval { $handle->read_entity_body($body, 8192) };
    if ($@ eq "Zng::Net::Stream: resource temporarily unavailable\n") {
	return;
    } elsif ($@) {
	$self->__abort($@, $handle);
	return;
    } elsif (!defined $count) {
	$self->__abort("$PACKAGE: cannot receive: $!", $handle);
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

    my $keep_alive = $handle->peer_http_version eq '1.1';
    $keep_alive &&= !grep /close/i, @connection;
    $keep_alive ||= grep /keep-alive/i, @connection;
    $keep_alive &&= @$sending_tasks ||  @$receiving_tasks;

    my $net = $self->{net};

    unless ($keep_alive) {
	$net->set($handle);
	close $handle;
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

sub __receive_response ( $$ ) {
    my $self = shift;
    my $handle = shift;

    if (!$self->{response}) {
	$self->__receive_response_headers($handle);
	return;
    }
    $self->__receive_response_body($handle);
}

sub __prepare_send_request ( $$ ) {
    my $self = shift;
    my $handle = shift;

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

    $self->{buffer} .= $handle->format_request($method, $path_query, @headers);

    my $receiving_tasks = $self->{receiving_tasks};
    push @$receiving_tasks, $task;

    my $net = $self->{net};
    $net->add_log($request, 'communicating');
    1;
}

sub __prepare_send_requests ( $$ ) {
    my $self = shift;
    my $handle = shift;

    if ($handle->peer_http_version ne '1.1') {
	$self->__prepare_send_request($handle);
	return;
    }

    1 while ($self->__prepare_send_request($handle));
}

sub __send_requests ( $$ ) {
    my $self = shift;
    my $handle = shift;

    unless (defined $self->{buffer}) {
	$self->__prepare_send_requests($handle);
    }

    my $buffer = $self->{buffer};
    my $offset = $self->{offset};
    my $count = $handle->syswrite($buffer, undef, $offset);
    unless (defined $count) {
	$self->__abort("$PACKAGE: cannot send: $!", $handle);
	return;
    }

    $offset += $count;
    if ($offset == length $buffer) {
	my $net = $self->{net};
	$net->set($handle, POLLIN, $self);

	$buffer = undef;
	$offset = 0;
    }

    $self->{buffer} = $buffer;
    $self->{offset} = $offset;
}

sub handle_event ( $$$ ) {
    my $self = shift;
    my $handle = shift;
    my $type = shift;

    unless ($type) {
	$self->__abort("$PACKAGE: timeout", $handle);
	return;
    }

    $self->__send_requests($handle) if $type & POLLOUT;
    $self->__receive_response($handle) if $type & POLLIN;
}

1;
