package Zng::Antenna::Resource::JBBS::Updater;

use strict;
use HTTP::Request;
use HTTP::Status;
use NKF;
use Time::Local;

sub __thread_parse_line ( $$ ) {
    my $thread = shift;
    my $line = shift;

    my ($index, $author_with_signature, $email, $updated_str, $content) =
	split /<>/, $line;
    $updated_str =~ /^(\d\d\d\d)\/(\d\d)\/(\d\d)\(.+\) (\d\d):(\d\d):(\d\d)$/
	or return;

    my $updated = eval { timegm($6, $5, $4, $3, $2 - 1, $1) };
    $@ eq '' or return;
    $updated -= 9 * 60 * 60;

    $author_with_signature =~ /^(.*?)(?:<\/b> (◆.*)<b>)?$/;
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
    my $eucjp_content = shift;

    my $content = nkf '-w -E -x', $eucjp_content;
    my $lines = [ split /\n/, $content ];
    @$lines or return;
    __thread_parse_line $thread, $lines->[$#$lines];

    $thread->{num_fetched_messages} = $thread->{num_messages};
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
    } else {
	$thread->{temporary_error} = "unexpected HTTP status $code";
	return;
    }

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

    my $directory = $thread->{feed}->{directory};
    my $created = $thread->{created};
    my $num_messages = $thread->{num_messages};

    my $url = "http://jbbs.livedoor.jp/bbs/rawmode.cgi/$directory/$created/" .
	"$num_messages";
    my $request = HTTP::Request->new(GET => $url);

    my $handler = sub {
	my $response = shift;
	__thread_handle_response $thread, $response;
    };
    $net->add_request($request, $handler);
}

sub __parse_line ( $$ ) {
    my $thread = shift;
    my $line = shift;

    my ($file, $html_title_with_num_messages) = split /,/, $line;
    $file =~ /^(\d+)\.cgi$/ or return 0;
    my $created = int $1;

    $html_title_with_num_messages =~ /^(.*)\((\d+)\)$/ or return 0;

    my $html_title = $1;
    my $num_messages = int $2;

    my $title = Zng::Antenna::Updater::html_to_text $html_title;
    $title =~ s/＠｀/,/g;

    my $title_re = $thread->{feed}->{thread_title_re};
    if (defined $title_re) {
	$title =~ /$title_re/ or return 0;
    }

    $thread->{created} = $created;
    $thread->{title} = $title;
    $thread->{num_messages} = $num_messages;
    return 1;
}

sub __parse_content ( $$ ) {
    my $feed = shift;
    my $eucjp_content = shift;

    my $threads = $feed->{threads} || [];
    my $thread_map = {};
    for my $thread (@$threads) {
	my $created = $thread->{created};
	$thread_map->{$created} = $thread;
    }

    $threads = [];
    $feed->{threads} = $threads;

    my $content = nkf '-w -E -x', $eucjp_content;
    my $lines = [];
    (undef, @$lines) = split /\n/, $content;
    for my $line (@$lines) {
	my $thread_stub = { feed => $feed };
	__parse_line $thread_stub, $line or next;

	my $created = $thread_stub->{created};
	my $thread = $thread_map->{$created} || {};
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

    my $directory = $feed->{directory};

    my $url = "http://jbbs.livedoor.jp/$directory/subject.txt";
    my $request = HTTP::Request->new(GET => $url);
    $request->if_modified_since($feed->{http_last_modified});

    my $handler = sub {
	my $response = shift;
	__handle_response $feed, $response, $net;
    };
    $net->add_request($request, $handler);
}

1;
