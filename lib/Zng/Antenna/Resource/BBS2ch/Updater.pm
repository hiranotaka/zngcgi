package Zng::Antenna::Resource::BBS2ch::Updater;

use strict;
use HTTP::Request;
use HTTP::Status;
use NKF;
use Time::Local;

sub __thread_parse_line ( $$ ) {
    my $thread = shift;
    my $line = shift;

    my ($author_with_signature, $email, $updated_str, $content) =
	split /<>/, $line;
    $updated_str =~ /(\d+)\/(\d+)\/(\d+)/ or return;
    my $year = int $1;
    my $mon = int $2 - 1;
    my $day = int $3;

    $updated_str =~ /\s(\d+):(\d+)(?::(\d+))?/ or return;
    my $hour = int $1;
    my $min = int $2;
    my $sec = int $3;

    my $updated = eval { timegm($sec, $min, $hour, $day, $mon, $year) };
    $@ eq '' or return;
    $updated -= 540;

    $author_with_signature =~ /^(.*?)(?: (◆.*))?$/;
    my $author = $1 ne '' ? $1 : $2;

    $email = '' if $email eq 'sage';

    $thread->{updated} = $updated;
    $thread->{author} = $author;
    $thread->{email} = $email;
    $thread->{html_content} = $content;
    $thread->{text_content} = Zng::Antenna::Updater::html_to_text $content;
}

sub __thread_parse_content ( $$ ) {
    my $thread = shift;
    my $sjis_content = shift;

    my $content = nkf '-w -S -x', $sjis_content;
    my $lines = [ split /\n/, $content ];
    @$lines or return;
    __thread_parse_line $thread, $lines->[$#$lines];

    $thread->{num_bytes} = $thread->{num_bytes} + length($sjis_content);
    $thread->{num_fetched_messages} = $thread->{num_messages};
}

sub __thread_clear ( $ ) {
    my $thread = shift;

    $thread->{num_fetched_messages} = 0;
    $thread->{num_bytes} = 0;
}

sub __thread_parse_response ( $$ ) {
    my $thread = shift;
    my $response = shift;

    unless ($response) {
	$thread->{temporary_error} = $@;
	return;
    }

    my $code = $response->code;
    my $content = $response->content;
    if ($code == RC_OK) {
	__thread_parse_content $thread, $content;
    } elsif ($code == RC_PARTIAL_CONTENT) {
	if (substr($content, 0, 1) ne "\n") {
	    __thread_clear $thread;
	} else {
	    __thread_parse_content $thread, substr $content, 1;
	}
    } elsif ($code ==  RC_REQUEST_RANGE_NOT_SATISFIABLE) {
	__thread_clear $thread;
    } else {
	$thread->{temporary_error} = "unexpected HTTP status $code";
	return;
    }

    $thread->{updated} = $response->last_modified;
    $thread->{temporary_error} = undef;
}

sub __thread_handle_response ( $$ ) {
    my $thread = shift;
    my $response = shift;

    __thread_parse_response $thread, $response;
}

sub __thread_update ( $$ ) {
    my $thread = shift;
    my $net = shift;

    $thread->{num_messages} != $thread->{num_fetched_messages} or return;

    my $feed = $thread->{feed};
    my $server = $feed->{server};
    my $directory = $feed->{directory};
    my $created = $thread->{created};

    my $url = "$server/$directory/dat/$created.dat";
    my $num_bytes = $thread->{num_bytes};
    my $request = HTTP::Request->new(GET => $url);
    if ($num_bytes) {
	my $pos = $num_bytes - 1;
	$request->header('Range', "bytes=$pos-");
    }

    my $handler = sub {
	my $response = shift;
	__thread_handle_response $thread, $response;
    };
    $net->add_request($request, $handler);
}

sub __parse_line ( $$ ) {
    my $thread = shift;
    my $line = shift;

    my ($file, $html_title_with_num_messages) = split /<>/, $line;

    $file =~ /^(\d+)\.dat$/ or return;
    my $created = int $1;

    $html_title_with_num_messages =~ /^(.*) \((\d+)\)$/ or return;
    my $html_title = $1;
    my $num_messages = int $2;

    my $title = Zng::Antenna::Updater::html_to_text $html_title;
    $title = $html_title unless defined $title;

    $thread->{created} = $created;
    $thread->{title} = $title;
    $thread->{num_messages} = $num_messages;
}

sub __parse_content ( $$ ) {
    my $feed = shift;
    my $sjis_content = shift;

    my $threads = $feed->{threads} || [];
    my $thread_map = {};
    for my $thread (@$threads) {
	my $created = $thread->{created};
	$thread_map->{$created} = $thread;
    }

    $threads = [];
    $feed->{threads} = $threads;

    my $content = nkf '-w -S -x', $sjis_content;
    my $lines = [ split /\n/, $content ];
    for my $line (@$lines) {
	my $thread_stub = {};
	__parse_line $thread_stub, $line;

	my $created = $thread_stub->{created};
	my $thread = $thread_map->{$created} || {
	    feed => $feed,
	    num_fetched_messages => 0,
	    num_bytes => 0,
	};
	%$thread = ( %$thread, %$thread_stub );
	push @$threads, $thread;
    }
}

sub __parse_response ( $$ ) {
    my $feed = shift;
    my $response = shift;

    unless ($response) {
	$feed->{temporary_error} = $@;
	return;
    }

    my $code = $response->code;
    if ($code == RC_OK) {
	$feed->{http_last_modified} = $response->last_modified;
	__parse_content $feed, $response->content;
    } elsif ($code == RC_NOT_MODIFIED) {
    } else {
	$feed->{temporary_error} = "unexpected HTTP status $code";
	return;
    }

    $feed->{temporary_error} = undef;
}

sub __handle_response ( $$$ ) {
    my $feed = shift;
    my $response = shift;
    my $net = shift;

    __parse_response $feed, $response;

    my $threads = $feed->{threads};
    for my $thread (@$threads) {
	__thread_update $thread, $net;
    }
}

sub update ( $$ ) {
    my $feed = shift;
    my $net = shift;

    my $server = $feed->{server};
    my $directory = $feed->{directory};

    my $url = "$server/$directory/subject.txt";
    my $request = HTTP::Request->new(GET => $url);
    $request->if_modified_since($feed->{http_last_modified});

    my $handler = sub {
	my $response = shift;
	__handle_response $feed, $response, $net;
    };
    $net->add_request($request, $handler);
}

1;
