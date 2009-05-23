#!/usr/bin/perl

use strict;
use FindBin;
use lib "$FindBin::RealBin/../lib";
BEGIN { eval { require bytes; bytes->import; }; }
use File::stat;
use Time::Local;
use CGI qw{-nosticky :standard start_ul end_ul start_ol end_ol start_li end_li},
    qw{start_div end_div};
use HTTP::Status;
use HTTP::Date qw{time2isoz str2time};
use NKF;
use Zng::Cache;

my $PACKAGE = $0;

my $parser;

sub __handle_response ( $$$$$ ) {
    my $net = shift;
    my $source = shift;
    my $entry = shift;
    my $response = shift;
    my $handler = shift;

    delete $entry->{temporary_error};

    unless ($response) {
	$entry->{temporary_error} = $@;
	return;
    }

    my $code = $response->code;
    my $request = $response->request;

    my $expected = $code == RC_OK;
    $expected ||=
	$code == RC_NOT_MODIFIED && defined $request->if_modified_since;
    $expected ||=
	($code == RC_PARTIAL_CONTENT
	 || $code == RC_REQUEST_RANGE_NOT_SATISFIABLE)
	&& $request->header('Range');
    unless ($expected) {
	$entry->{temporary_error} = "$PACKAGE: unexpected HTTP status $code\n";
	return;
    }

    &$handler($net, $source, $entry, $response);
}

sub __add_request ( $$$$$ ) {
    my $net = shift;
    my $source = shift;
    my $entry = shift;
    my $request = shift;
    my $handler = shift;

    my $listener = sub ( $ ) {
	my $response = shift;
	__handle_response($net, $source, $entry, $response, $handler);
    };
    $net->add_request($request, $listener);
}

sub __handle_response_html ( $$$$ ) {
    my $net = shift;
    my $source = shift;
    my $feed = shift;
    my $response = shift;

    $response->code == RC_OK or return;

    my $url = $source->{url};
    $feed->{id} = $url;
    $feed->{title} = $source->{title};
    $feed->{link} = $url;
    $feed->{mobile_link} = $url;
    $feed->{updated} = $response->last_modified;
}

sub __add_request_html ( $$$ ) {
    my $net = shift;
    my $source = shift;
    my $feed = shift;

    my $url = $source->{url};
    my $request = HTTP::Request->new(HEAD => $url);
    __add_request($net, $source, $feed, $request, \&__handle_response_html);
}

sub __parse_uri ( $$$ ) {
    my $entry = shift;
    my $relative_uri = shift;
    my $base_uri = shift;

    my $absolute_uri = URI->new_abs($relative_uri, $base_uri);
    unless ($absolute_uri->scheme eq 'http') {
	$entry->{permanent_error} .= "$PACKAGE: cannot resolve URI\n";
	return undef;
    }

    return $absolute_uri->as_string;
}

sub __parse_html ( $$ ) {
    my $entry = shift;
    my $html_content = shift;

    my $wrapped_html_content =
	q{<meta content="text/html; charset=utf-8" http-equiv="Content-Type">} .
	qq{<div>$html_content</div>};
    unless ($parser) {
	require XML::LibXML;
	$parser = XML::LibXML->new;
    }
    my $document = eval {
	$parser->parse_html_string($wrapped_html_content);
    };
    if ($@) {
	$entry->{permanent_error} .= "$PACKAGE: cannot parse HTML: $@\n";
	return undef;
    }

    my $text_content = $document->textContent;
    $text_content = substr $text_content, 0; # strip the utf-8 flag
    return $text_content;
}

sub __parse_minithread_thread ( $$$ ) {
    my $entry = shift;
    my $sjis_content = shift;
    my $base_uri = shift;

    delete $entry->{permanent_error};

    my (undef, @sjis_lines) = split /\n/, $sjis_content;
    my $sjis_line = pop @sjis_lines;
    $sjis_line or return;

    my $line = nkf '-w -S -x', $sjis_line;
    my ($author_with_sign, $mail, undef, $comment) = split /<>/, $line;

    $author_with_sign =~ /^(.*?)(?: ◆.*)?$/;
    my $author = $1;
    my $author_with_mail =
	$mail eq '' || $mail eq 'sage' ? $author  : "$author &lt;$mail&gt;";

    my $html_content =
	qq{<dl><dt>$author_with_mail:</dt><dd>$comment</dd></dl>};
    $entry->{html_content} = $html_content;
    $entry->{base_uri} = $base_uri;

    my $text_content = __parse_html $entry, $html_content;
    $entry->{text_content} = $text_content;
}

sub __handle_response_minithread_thread ( $$$$ ) {
    my $net = shift;
    my $source = shift;
    my $entry = shift;
    my $response = shift;

    my $top_url = $source->{top_url};
    my $board_id = $source->{board_id};
    my $thread_id = $source->{thread_id};

    $entry->{id} = "$top_url/test/read.cgi/$board_id/$thread_id/";
    $entry->{title} = $source->{title};
    $entry->{link} = "$top_url/test/read.cgi/$board_id/$thread_id/l20";
    my $mobile_link;
    if ($top_url =~ m{^http://[^/]+\.2ch\.net(?:/|$)}) {
	$mobile_link = "http://c.2ch.net/test/-/$board_id/$thread_id/n";
    } else {
	$mobile_link = "$top_url/test/cell.cgi?/$board_id/$thread_id/l5n";
    }
    $entry->{mobile_link} = $mobile_link;
    $entry->{updated} = $response->last_modified;

    my $code = $response->code;
    if ($code == RC_OK) {
	my $accept_ranges = $response->header('Accept-Ranges');
	my @accept_ranges = split /\s*,\s*/, $accept_ranges;
	if (grep /bytes/i, @accept_ranges) {
	    $entry->{__instance_length} = $response->content_length;
	} else {
	    delete $entry->{__instance_length};
	}
	return;
    } else {
	my $content_range = $response->header('Content-Range');
	my $CONTENT_RANGE_RE =
	    qr/^bytes\s* \s*(?:\*|\d+\s*\-\s*\d+)\s*\/\s*(\d+)$/i;
	unless ($content_range =~ $CONTENT_RANGE_RE) {
	    $entry->{temporary_error} = "$PACKAGE: cannot parse range\n";
	    delete $entry->{__instance_length};
	    return;
	}
	$entry->{__instance_length} = $1;

	$code == RC_PARTIAL_CONTENT or return;
    }

    my $content = $response->content;
    my $base_uri = "$top_url/$board_id/";
    __parse_minithread_thread($entry, $content, $base_uri);
}

sub __add_request_minithread_thread ( $$$ ) {
    my $net = shift;
    my $source = shift;
    my $entry = shift;

    my $top_url = $source->{top_url};
    my $board_id = $source->{board_id};
    my $thread_id = $source->{thread_id};

    my $url = "$top_url/$board_id/dat/$thread_id.dat";
    my $instance_length = $entry->{__instance_length};
    my $request;
    if ($instance_length) {
	$request = HTTP::Request->new(GET => $url);
	my $pos = $instance_length - 1;
	$request->header('Range', "bytes=$pos-");
    } else {
	$request = HTTP::Request->new(HEAD => $url);
	# $request = HTTP::Request->new(GET => $url);
	# $request->header('Range', "bytes=-512");
    }
    __add_request($net, $source, $entry, $request,
		  \&__handle_response_minithread_thread);
}

sub __parse_minithread_board ( $$ ) {
    my $feed = shift;
    my $sjis_content = shift;

    delete $feed->{permanent_error};

    my $entries = $feed->{entries};
    my %cached_entries;
    for my $entry (@$entries) {
	my $thread_id = $entry->{__thread_id};
	$cached_entries{$thread_id} = $entry;
    }

    my $content = nkf '-w -S -x', $sjis_content;
    my @lines = split /\n/, $content;

    $entries = [];
    for my $line (@lines) {
	my ($name, $title_with_count) = split /<>/, $line;

	unless ($name =~ /^(\d+)\.dat$/) {
	    $feed->{permanent_error} = "$PACKAGE: cannot parse subject.txt\n";
	    return;
	}
	my $thread_id = $1;

	my $entry = $cached_entries{$thread_id};
	$entry ||= { __thread_id => $thread_id };
	push @$entries, $entry;

	unless ($title_with_count =~ /^(.*) \((.*)\)$/) {
	    $feed->{permanent_error} = "$PACKAGE: cannot parse subject.txt\n";
	    return;
	}
	my $title = $1;
	my $count = $2;

	$count ne $entry->{__count} or next;
	$entry->{__count} = $count;

	$entry->{title} = __parse_html($feed, $title) || $title;
	$entry->{temporary_error} = "$PACKAGE: needs update\n";
    }
    $feed->{entries} = $entries;
}

sub __handle_response_minithread_board ( $$$$ ) {
    my $net = shift;
    my $source = shift;
    my $feed = shift;
    my $response = shift;

    my $top_url = $source->{top_url};
    my $board_id = $source->{board_id};

    $feed->{id} = "$top_url/$board_id/";
    $feed->{title} = $source->{title};
    $feed->{link} = "$top_url/$board_id/";
    $feed->{mobile_link} = "$top_url/$board_id/i/";

    if ($response->code == RC_OK) {
	$feed->{__last_modified} = $response->last_modified;

	my $content = $response->content;
	__parse_minithread_board($feed, $content);
    }

    my $entries = $feed->{entries};
    for my $entry (@$entries) {
	$entry->{temporary_error} or next;

	my $title = $entry->{title};
	my $thread_id = $entry->{__thread_id};
	my $source = {
	    id => "$top_url/",
	    top_url => $top_url,
	    board_id => $board_id,
	    thread_id => $thread_id,
	    title => $title,
	};
	__add_request_minithread_thread($net, $source, $entry);
    }
}

sub __add_request_minithread_board ( $$$ ) {
    my $net = shift;
    my $source = shift;
    my $feed = shift;

    my $top_url = $source->{top_url};
    my $board_id = $source->{board_id};
    my $title_id = $source->{title_id};

    my $url = "$top_url/$board_id/subject.txt";
    my $request = HTTP::Request->new(GET => $url);
    $request->if_modified_since($feed->{__last_modified});
    __add_request($net, $source, $feed, $request,
		  \&__handle_response_minithread_board);
}

sub __parse_jbbs_thread ( $$$ ) {
    my $entry = shift;
    my $eucjp_content = shift;
    my $base_uri = shift;

    delete $entry->{permanent_error};

    chomp $eucjp_content;
    my $content = nkf '-w -E -x', $eucjp_content;
    my (undef, $author_with_sign, $mail, $date, $comment) =
	split /<>/, $content;

    if ($date !~ /^(\d\d\d\d)\/(\d\d)\/(\d\d)\(.+\) (\d\d):(\d\d):(\d\d)$/) {
	$entry->{permanent_error} = "$PACKAGE: cannot parse date\n";
	return;
    }

    my $updated = eval { timelocal($6, $5, $4, $3, $2 - 1, $1) };
    if ($@) {
	$entry->{permanent_error} = "$PACKAGE: cannot parse date: $@";
	return;
    }
    $entry->{updated} = $updated;

    $author_with_sign =~ /^[^<]*/;
    my $author = $&;

    my $author_with_mail =
	$mail eq '' || $mail eq 'sage' ? $author : "$author &lt;$mail&gt;";

    my $html_content =
	qq{<dl><dt>$author_with_mail:</dt><dd>$comment</dd></dl>};
    $entry->{html_content} = $html_content;
    $entry->{base_uri} = $base_uri;

    my $text_content = __parse_html $entry, $html_content;
    $entry->{text_content} = $text_content;
}

sub __handle_response_jbbs_thread ( $$$ ) {
    my $net = shift;
    my $source = shift;
    my $entry = shift;
    my $response = shift;

    my $board_id = $source->{board_id};
    my $thread_id = $source->{thread_id};

    $entry->{id} =
	"http://jbbs.livedoor.jp/bbs/read.cgi/$board_id/$thread_id/";
    $entry->{title} = $source->{title};
    $entry->{link} =
	"http://jbbs.livedoor.jp/bbs/read.cgi/$board_id/$thread_id/l20";
    $entry->{mobile_link} =
	"http://jbbs.livedoor.jp/bbs/i.cgi/$board_id/$thread_id/n";

    my $content = $response->content;
    my $base_uri = "http://jbbs.livedoor.jp/bbs/read.cgi/$board_id/$thread_id/";
    __parse_jbbs_thread($entry, $content, $base_uri);
}

sub __add_request_jbbs_thread ( $$$ ) {
    my $net = shift;
    my $source = shift;
    my $entry = shift;

    my $board_id = $source->{board_id};
    my $thread_id = $source->{thread_id};

    my $url
	= "http://jbbs.livedoor.jp/bbs/rawmode.cgi/$board_id/$thread_id/l1-";
    my $request = HTTP::Request->new(GET => $url);
    __add_request($net, $source, $entry, $request,
		  \&__handle_response_jbbs_thread);
}

sub __parse_jbbs_board ( $$ ) {
    my $feed = shift;
    my $eucjp_content = shift;

    delete $feed->{permanent_error};

    my $id = $feed->{id};
    my $entries = $feed->{entries};

    my %cached_entries;
    for my $entry (@$entries) {
	my $thread_id = $entry->{__thread_id};
	$cached_entries{$thread_id} = $entry;
    }

    my $content = nkf '-w -E -x', $eucjp_content;
    my (undef, @lines) = split /\n/, $content;

    $entries = [];
    for my $line (@lines) {
	my ($name, $title_with_count) = split m/,/, $line;

	unless ($name =~ /^(\d+)\.cgi$/) {
	    $feed->{permanent_error} = "$PACKAGE: cannot parse subject.txt\n";
	    return;
	}
	my $thread_id = $1;

	my $entry = $cached_entries{$thread_id};
	$entry ||= {  __thread_id => $thread_id };
	push @$entries, $entry;

	unless ($title_with_count =~ /^(.*)\((.*)\)$/) {
	    $feed->{permanent_error} = "$PACKAGE: cannot parse subject.txt\n";
	    return;
	}
	my $title = $1;
	my $count = $2;

	$count ne $entry->{__count} or next;
	$entry->{__count} = $count;

	$title =~ s/＠｀/,/g;
	$entry->{title} = __parse_html($feed, $title);
	$entry->{temporary_error} = "$PACKAGE: needs update\n";
    }
    $feed->{entries} = $entries;
}

sub __handle_response_jbbs_board ( $$$$ ) {
    my $net = shift;
    my $source = shift;
    my $feed = shift;
    my $response = shift;

    my $board_id = $source->{board_id};

    $feed->{id} = "http://jbbs.livedoor.jp/$board_id/";
    $feed->{title} = $source->{title};
    $feed->{link} = "http://jbbs.livedoor.jp/$board_id/";
    $feed->{mobile_link} = "http://jbbs.livedoor.jp/bbs/i.cgi/$board_id/";

    if ($response->code == RC_OK) {
	$feed->{__last_modified} = $response->last_modified;

	my $content = $response->content;
	__parse_jbbs_board($feed, $content);
    }

    my $entries = $feed->{entries};
    for my $entry (@$entries) {
	$entry->{temporary_error} or next;

	my $title = $entry->{title};
	my $thread_id = $entry->{__thread_id};
	my $source = {
	    board_id => $board_id,
	    thread_id => $thread_id,
	    title => $title,
	};
	__add_request_jbbs_thread($net, $source, $entry);
    }
}

sub __add_request_jbbs_board ( $$$ ) {
    my $net = shift;
    my $source = shift;
    my $feed = shift;

    my $board_id = $source->{board_id};

    my $url = "http://jbbs.livedoor.jp/$board_id/subject.txt";
    my $request = HTTP::Request->new(GET => $url);
    $request->if_modified_since($feed->{__last_modified});
    __add_request($net, $source, $feed, $request,
		  \&__handle_response_jbbs_board);
}

my $XML_NS = 'http://www.w3.org/XML/1998/namespace';
my $RDF_NS = 'http://www.w3.org/1999/02/22-rdf-syntax-ns#';
my $RSS_NS = 'http://purl.org/rss/1.0/';
my $DC_NS = 'http://purl.org/dc/elements/1.1/';
my $CONTENT_NS ="http://purl.org/rss/1.0/modules/content/";

sub __parse_xml_base ( $$ ) {
    my $base_uri_ref = shift;
    my $element = shift;

    my $base_uri = $element->getAttributeNS($XML_NS, 'base');
    $base_uri or return;

    $base_uri = substr $base_uri, 0; # strip the utf-8 flag
    $$base_uri_ref = $base_uri;
}

sub __parse_rss_title ( $$ ) {
    my $entry = shift;
    my $element = shift;

    my $title = $element->textContent;
    $title = substr $title, 0; # strip the utf-8 flag
    $entry->{title} = $title;
}

sub __parse_rss_description ( $$ ) {
    my $entry = shift;
    my $element = shift;

    my $content = $element->textContent;
    $content = substr $content, 0; # strip the utf-8 flag
    $entry->{text_content} = $content;
}

sub __parse_rss_link ( $$$ ) {
    my $entry = shift;
    my $element = shift;
    my $base_uri = shift;

    __parse_xml_base(\$base_uri, $element);

    my $link = $element->textContent;
    $link = substr $link, 0; # strip the utf-8 flag
    $entry->{link} = __parse_uri($entry, $link, $base_uri);
}

sub __parse_dc_date ( $$ ) {
    my $entry = shift;
    my $element = shift;

    my $updated = $element->textContent;
    $updated = str2time $updated;
    $entry->{updated} = $updated;
}

sub __parse_content_encoded ( $$$ ) {
    my $entry = shift;
    my $element = shift;
    my $base_uri = shift;

    __parse_xml_base(\$base_uri, $element);

    my $html_content = $element->textContent;
    $html_content = substr $html_content, 0; # strip the utf-8 flag
    $entry->{html_content} = $html_content;
    $entry->{base_uri} = $base_uri;

    my $text_content = __parse_html($entry, $html_content);
    $entry->{text_content} = $text_content if defined $text_content;
}

sub __parse_rdf_about ( $$ ) {
    my $entry = shift;
    my $element = shift;

    my $id = $element->getAttributeNS($RDF_NS, 'about');
    $id = substr $id, 0; # strip the utf-8 flag
    $entry->{id} = $id;
}

sub __parse_rss_item ( $$$ ) {
    my $entry = shift;
    my $element = shift;
    my $base_uri = shift;

    __parse_xml_base(\$base_uri, $element);
    __parse_rdf_about($entry, $element);

    my @nodes = $element->childNodes;
    for my $node (@nodes) {
	my $localname = $node->localname;
	my $namespaceURI = $node->namespaceURI;
	if ($localname eq 'title' && $namespaceURI eq $RSS_NS) {
	    __parse_rss_title($entry, $node);
	} elsif ($localname eq 'description' && $namespaceURI eq $RSS_NS) {
	    __parse_rss_description($entry, $node);
	} elsif ($localname eq 'link' && $namespaceURI eq $RSS_NS) {
	    __parse_rss_link($entry, $node, $base_uri);
	} elsif ($localname eq 'date' && $namespaceURI eq $DC_NS) {
	    __parse_dc_date($entry, $node);
	} elsif ($localname eq 'encoded' && $namespaceURI eq $CONTENT_NS) {
	    __parse_content_encoded($entry, $node, $base_uri);
	}
    }
}

sub __parse_rdf ( $$$ ) {
    my $feed = shift;
    my $element = shift;
    my $base_uri = shift;

    __parse_xml_base(\$base_uri, $element);

    my $entries = [];
    $feed->{entries} = $entries;

    my @nodes = $element->childNodes;
    for my $node (@nodes) {
	my $localname = $node->localname;
	my $namespaceURI = $node->namespaceURI;
	if ($localname eq 'channel' && $namespaceURI eq $RSS_NS) {
	    __parse_rss_item($feed, $node, $base_uri);
	} elsif ($localname eq 'item' && $namespaceURI eq $RSS_NS) {
	    my $entry = {};
	    push @$entries, $entry;
	    __parse_rss_item($entry, $node, $base_uri);
	}
    }
}

sub __parse_rss2_guid ( $$ ) {
    my $entry = shift;
    my $element = shift;

    my $id = $element->textContent;
    $id = substr $id, 0; # strip the utf-8 flag
    $entry->{id} = $id;
}

sub __parse_rss2_item ( $$$ ) {
    my $entry = shift;
    my $element = shift;
    my $base_uri = shift;

    __parse_xml_base(\$base_uri, $element);

    my @nodes = $element->childNodes;
    for my $node (@nodes) {
	my $localname = $node->localname;
	my $namespaceURI = $node->namespaceURI;
	if ($localname eq 'guid' && $namespaceURI eq '') {
	    __parse_rss2_guid($entry, $node);
	} elsif ($localname eq 'title' && $namespaceURI eq '') {
	    __parse_rss_title($entry, $node);
	} elsif ($localname eq 'link' && $namespaceURI eq '') {
	    __parse_rss_link($entry, $node, $base_uri);
	} elsif ($localname eq 'pubDate' && $namespaceURI eq '') {
	    __parse_dc_date($entry, $node);
	} elsif ($localname eq 'description' && $namespaceURI eq '') {
	    __parse_content_encoded($entry, $node, $base_uri);
	}
    }
}

sub __parse_rss2_channel ( $$$ ) {
    my $feed = shift;
    my $element = shift;
    my $base_uri = shift;

    __parse_xml_base(\$base_uri, $element);

    my $entries = [];
    $feed->{entries} = $entries;

    my @nodes = $element->childNodes;
    for my $node (@nodes) {
	my $localname = $node->localname;
	my $namespaceURI = $node->namespaceURI;
	if ($localname eq 'title' && $namespaceURI eq '') {
	    __parse_rss_title($feed, $node);
	} elsif ($localname eq 'link' && $namespaceURI eq '') {
	    __parse_rss_link($feed, $node, $base_uri);
	} elsif ($localname eq 'item' && $namespaceURI eq '') {
	    my $entry = {};
	    push @$entries, $entry;
	    __parse_rss2_item($entry, $node, $base_uri);
	}
    }
}

sub __parse_rss2 ( $$$ ) {
    my $feed = shift;
    my $element = shift;
    my $base_uri = shift;

    __parse_xml_base(\$base_uri, $element);

    my @nodes = $element->childNodes;
    for my $node (@nodes) {
	my $localname = $node->localname;
	my $namespaceURI = $node->namespaceURI;
	if ($localname eq 'channel' && $namespaceURI eq '') {
	    __parse_rss2_channel($feed, $node, $base_uri);
	}
    }
}

sub __parse_xml ( $$$ ) {
    my $feed = shift;
    my $content = shift;
    my $base_uri = shift;

    delete $feed->{permanent_error};

    unless ($parser) {
	require XML::LibXML;
	$parser = XML::LibXML->new;
    }
    my $document = eval { $parser->parse_string($content) };
    if ($@) {
	$feed->{permanent_error} = "$PACKAGE: cannot parse XML: $@";
	return;
    }

    my $element = $document->documentElement;
    my $localname = $element->localname;
    my $namespaceURI = $element->namespaceURI;
    if ($localname eq 'RDF' && $namespaceURI eq $RDF_NS) {
	__parse_rdf($feed, $element, $base_uri);
    } elsif ($localname eq 'rss' && $namespaceURI eq '') {
	__parse_rss2($feed, $element, $base_uri);
    } else {
	$feed->{permanent_error} =
	    "$PACKAGE: unsupported XML type $localname\n";
	return;
    }
}

sub __handle_response_xml ( $$$$ ) {
    my $net = shift;
    my $source = shift;
    my $feed = shift;
    my $response = shift;

    $response->code == RC_OK or return;

    $feed->{__last_modified} = $response->last_modified;

    my $content = $response->content;
    my $base_uri = $source->{url};
    __parse_xml($feed, $response->content, $response->request->uri->as_string);
}

sub __add_request_xml ( $$$ ) {
    my $net = shift;
    my $source = shift;
    my $feed = shift;

    my $url = $source->{url};

    my $request = HTTP::Request->new(GET => $url);
    $request->if_modified_since($feed->{__last_modified});
    __add_request($net, $source, $feed, $request, \&__handle_response_xml);
}

sub __handle_response_fc2wiki ( $$$$ ) {
    my $net = shift;
    my $source = shift;
    my $feed = shift;
    my $response = shift;

    $response->code == RC_OK or return;
    $feed->{__last_modified} = $response->last_modified;
    __parse_xml($feed, $response->content, $response->request->uri->as_string);

    my $link_re = quotemeta $feed->{link};
    my $wiki_id = $source->{wiki_id};
    my $mobile_link = "http://$wiki_id.wiki.fc2.com/wiki/";
    $feed->{mobile_link} = $mobile_link;

    my $entries = $feed->{entries};
    for my $entry (@$entries) {
	$entry->{link} =~m{^{$link_re}wiki/([^\/\?\#]+)$} or next;
	my $name = $1;
	$name =~ s/%([0-9a-fA-F]{2})/chr hex $1/eg;
	my $sjis_name = nkf '-s -W -x', $name;
	$sjis_name =~ s/[^a-zA-Z0-9\-\.\_\~]/sprintf '%%%02x', ord $&/eg;
	$entry->{mobile_link} = $mobile_link . $sjis_name;
    }
}

sub __add_request_fc2wiki ( $$$ ) {
    my $net = shift;
    my $source = shift;
    my $feed = shift;

    my $wiki_id = $source->{wiki_id};

    my $url = "http://$wiki_id.wiki.fc2.com/index.rdf";
    my $request = HTTP::Request->new(GET => $url);
    $request->if_modified_since($feed->{__last_modified});
    __add_request($net, $source, $feed, $request, \&__handle_response_fc2wiki);
}

sub __handle_response_hatena ( $$$$ ) {
    my $net = shift;
    my $source = shift;
    my $feed = shift;
    my $response = shift;

    $response->code == RC_OK or return;
    $feed->{__last_modified} = $response->last_modified;
    __parse_xml($feed, $response->content, $response->request->uri->as_string);

    my $link = $feed->{link};
    my $link_re = quotemeta $link;
    $feed->{mobile_link} = "${link}archivemobile";

    my $entries = $feed->{entries};
    for my $entry (@$entries) {
	my $id_re = qr/[a-zA-Z0-9\-\.\_\~]/;
	$entry->{link} =~
	    m{^${link_re}($id_re+)(?:/($id_re+))?(?:#($id_re+))?$} or next;
	my $date = $1;
	my $section = $2 || $3;
	$entry->{link} = "${link}$date/$section";
	$entry->{mobile_link} = "${link}mobile?date=$date&section=$section";
    }
}

sub __add_request_hatena ( $$$ ) {
    my $net = shift;
    my $source = shift;
    my $feed = shift;

    my $hatena_id = $source->{hatena_id};

    my $url = "http://d.hatena.ne.jp/${hatena_id}/rss";
    my $request = HTTP::Request->new(GET => $url);
    $request->if_modified_since($feed->{__last_modified});
    __add_request($net, $source, $feed, $request, \&__handle_response_hatena);
}

sub __handle_response_twitter ( $$$$ ) {
    my $net = shift;
    my $source = shift;
    my $entry = shift;
    my $response = shift;

    $response->code == RC_OK or return;
    $entry->{__last_modified} = $response->last_modified;

    my $feed = {};
    __parse_xml($feed, $response->content, $response->request->uri->as_string);

    my $first_entry = $feed->{entries}[0];
    $first_entry or return;

    my $twitter_id = $source->{twitter_id};
    my $twitter_id_re = quotemeta $twitter_id;
    $entry->{title} = $feed->{title};
    $entry->{link} = $feed->{link};
    $entry->{mobile_link} = 'http://m.twitter.com/' . $twitter_id;
    $entry->{updated} = $first_entry->{updated};

    my $text_content = $first_entry->{text_content};
    $text_content =~ s/^$twitter_id_re: //;
    $entry->{text_content} = $text_content;

    my $html_content = $first_entry->{html_content};
    $html_content =~ s/^$twitter_id_re: //;
    $entry->{html_content} = $html_content;
    $entry->{base_uri} = $first_entry->{base_uri};
}

sub __add_request_twitter ( $$$ ) {
    my $net = shift;
    my $source = shift;
    my $entry = shift;

    my $twitter_id = $source->{twitter_id};

    my $url =
	"http://twitter.com/statuses/user_timeline/${twitter_id}.rss?count=1";
    my $request = HTTP::Request->new(GET => $url);
    $request->if_modified_since($entry->{__last_modified});
    __add_request($net, $source, $entry, $request, \&__handle_response_twitter);
}

my $drivers = {
    'HTML' => \&__add_request_html,
    'MiniThread Board' => \&__add_request_minithread_board,
    'MiniThread Thread' => \&__add_request_minithread_thread,
    'JBBS Board' => \&__add_request_jbbs_board,
    'JBBS Thread' => \&__add_request_jbbs_thread,
    'XML' => \&__add_request_xml,
    'FC2WIKI' => \&__add_request_fc2wiki,
    'Hatena' => \&__add_request_hatena,
    'Twitter' => \&__add_request_twitter,
};

my $CHAR_RE = qr/[\x00-\x7f]|[\xc0-\xfd][\x80-\xbf]+/;
my $HALFWIDTH_CHAR_RE =
    qr/[\x20-\x7e]|\xef\xbd[\xa1-\xbf]|\xef\xbe[\x80-\x9f]/;

sub __limit_length ( $$ ) {
    my $length = shift;
    my $str = shift;
    $str =~ /^(?:$CHAR_RE){0,$length}/;
    return $&;
}

sub __limit_width ( $$ ) {
    my $width = shift;
    my $str = shift;

    my $length;
    while ($str =~ /$CHAR_RE/g) {
	if ($& =~ /^$HALFWIDTH_CHAR_RE$/) {
	    $width--;
	} else {
	    $width -= 2;
	}

	if ($width >= 2) {
	    $length = pos $str;
	} elsif ($width < 0) {
	    return substr($str, 0, $length) . '..';
	}
    }
    return $str;
}

my %FULLWIDTH_HALFWIDTH =
    ('　' => ' ', '！' => '!', '＂' => '"', '＃' => '#', '＄' => '$',
     '％' => '%', '＆' => '&', '＇' => '\'', '（' => '(', '）' => ')',
     '＊' => '*', '＋' => '+', '，' => ',', '－' => '-', '．' => '.',
     '／' => '/', '０' => '0', '１' => '1', '２' => '2', '３' => '3',
     '４' => '4', '５' => '5', '６' => '6', '７' => '7', '８' => '8',
     '９' => '9', '：' => ':', '；' => ';', '＜' => '<', '＝' => '=',
     '＞' => '>', '？' => '?', '＠' => '@', 'Ａ' => 'A', 'Ｂ' => 'B',
     'Ｃ' => 'C', 'Ｄ' => 'D', 'Ｅ' => 'E', 'Ｆ' => 'F', 'Ｇ' => 'G',
     'Ｈ' => 'H', 'Ｉ' => 'I', 'Ｊ' => 'J', 'Ｋ' => 'K', 'Ｌ' => 'L',
     'Ｍ' => 'M', 'Ｎ' => 'N', 'Ｏ' => 'O', 'Ｐ' => 'P', 'Ｑ' => 'Q',
     'Ｒ' => 'R', 'Ｓ' => 'S', 'Ｔ' => 'T', 'Ｕ' => 'U', 'Ｖ' => 'V',
     'Ｗ' => 'W', 'Ｘ' => 'X', 'Ｙ' => 'Y', 'Ｚ' => 'Z', '［' => '[',
     '＼' => '\\', '］' => ']', '＾' => '^', '＿' => '_', '｀' => '`',
     'ａ' => 'a', 'ｂ' => 'b', 'ｃ' => 'c', 'ｄ' => 'd', 'ｅ' => 'e',
     'ｆ' => 'f', 'ｇ' => 'g', 'ｈ' => 'h', 'ｉ' => 'i', 'ｊ' => 'j',
     'ｋ' => 'k', 'ｌ' => 'l', 'ｍ' => 'm', 'ｎ' => 'n', 'ｏ' => 'o',
     'ｐ' => 'p', 'ｑ' => 'q', 'ｒ' => 'r', 'ｓ' => 's', 'ｔ' => 't',
     'ｕ' => 'u', 'ｖ' => 'v', 'ｗ' => 'w', 'ｘ' => 'x', 'ｙ' => 'y',
     'ｚ' => 'z', '｛' => '{', '｜' => '|', '｝' => '}', '～' => '~',
     '、' => '､', '。' => '｡', '「' => '｢', '」' => '｣', '・' => '･',
     '゛' => 'ﾞ', '゜' => 'ﾟ', 'ァ' => 'ｧ', 'ア' => 'ｱ', 'ィ' => 'ｨ',
     'イ' => 'ｲ', 'ゥ' => 'ｩ', 'ウ' => 'ｳ', 'ェ' => 'ｪ', 'エ' => 'ｴ',
     'ォ' => 'ｫ', 'オ' => 'ｵ', 'カ' => 'ｶ', 'ガ' => 'ｶﾞ', 'キ' => 'ｷ',
     'ギ' => 'ｷﾞ', 'ク' => 'ｸ', 'グ' => 'ｸﾞ', 'ケ' => 'ｹ', 'ゲ' => 'ｹﾞ',
     'コ' => 'ｺ', 'ゴ' => 'ｺﾞ', 'サ' => 'ｻ', 'ザ' => 'ｻﾞ', 'シ' => 'ｼ',
     'ジ' => 'ｼﾞ', 'ス' => 'ｽ', 'ズ' => 'ｽﾞ', 'セ' => 'ｾ', 'ゼ' => 'ｾﾞ',
     'ソ' => 'ｿ', 'ゾ' => 'ｿﾞ', 'タ' => 'ﾀ', 'ダ' => 'ﾀﾞ', 'チ' => 'ﾁ',
     'ヂ' => 'ﾁﾞ', 'ッ' => 'ｯ', 'ツ' => 'ﾂ', 'ヅ' => 'ﾂﾞ', 'テ' => 'ﾃ',
     'デ' => 'ﾃﾞ', 'ト' => 'ﾄ', 'ド' => 'ﾄﾞ', 'ナ' => 'ﾅ', 'ニ' => 'ﾆ',
     'ヌ' => 'ﾇ', 'ネ' => 'ﾈ', 'ノ' => 'ﾉ', 'ハ' => 'ﾊ', 'バ' => 'ﾊﾞ',
     'パ' => 'ﾊﾟ', 'ヒ' => 'ﾋ', 'ビ' => 'ﾋﾞ', 'ピ' => 'ﾋﾟ', 'フ' => 'ﾌ',
     'ブ' => 'ﾌﾞ', 'プ' => 'ﾌﾟ', 'ヘ' => 'ﾍ', 'ベ' => 'ﾍﾞ', 'ペ' => 'ﾍﾟ',
     'ホ' => 'ﾎ', 'ボ' => 'ﾎﾞ', 'ポ' => 'ﾎﾟ', 'マ' => 'ﾏ', 'ミ' => 'ﾐ',
     'ム' => 'ﾑ', 'メ' => 'ﾒ', 'モ' => 'ﾓ', 'ャ' => 'ｬ', 'ヤ' => 'ﾔ',
     'ュ' => 'ｭ', 'ユ' => 'ﾕ', 'ョ' => 'ｮ', 'ヨ' => 'ﾖ', 'ラ' => 'ﾗ',
     'リ' => 'ﾘ', 'ル' => 'ﾙ', 'レ' => 'ﾚ', 'ロ' => 'ﾛ', 'ワ' => 'ﾜ',
     'ヲ' => 'ｦ', 'ン' => 'ﾝ', 'ー' => 'ｰ');
my $FULLWIDTH_RE = '(?:' . join('|', keys %FULLWIDTH_HALFWIDTH) .')';

sub __shrink_width ( $ ) {
    my $str = shift;
    $str =~ s/$FULLWIDTH_RE/$FULLWIDTH_HALFWIDTH{$&}/g;
    return $str;
}


sub print_perl ( $ ) {
    my $cache = shift;

    use Data::Dumper;
    print(header(-type => 'text/plain', -charset => 'utf-8',
		 -expires => $cache->last_modified + $::expires),
	  Dumper $cache->content->{feeds});
}

sub __age ( $ ) {
    my $sec = shift;
    $sec = 0 if $sec < 0;

    my $min = int $sec / 60;
    my $hour = int $min / 60;
    unless ($hour) {
	return {
	    class => 'updated-min',
	    number => $min,
	    unit => $min <= 1 ? 'minute' : 'minutes',
	};
    }

    my $day = int $hour / 24;
    unless ($day) {
	return {
	    class => 'updated-hour',
	    number => $hour,
	    unit => $hour <= 1 ? 'hour' : 'hours',
	};
    }

    return {
	class => 'updated-day',
	number => $day,
	unit => $day <= 1 ? 'day' : 'days',
    };
}

sub __print_li ( $$ ) {
    my $last_modified = shift;
    my $entry = shift;

    my $link = $entry->{link};
    my $title = $entry->{title};
    my $escaped_title = escapeHTML $title;
    print(start_li,
	  a({-class => 'title', -href => $link, -title => $title},
	    $escaped_title), ' ');

    my $source = $entry->{source};
    if ($source) {
	my $link = $source->{link};
	my $escaped_title = escapeHTML $source->{title};
	print(span({-class => 'source'},
		   '@', a({-href => $link}, $escaped_title)), ' ');
    }

    my $sec = $last_modified - $entry->{updated};
    my $age = __age $sec;
    my $content = __limit_length 80, $entry->{text_content};
    my $escaped_content = escapeHTML $content;
    print(span({-class => $age->{class}}, $age->{number}, $age->{unit}, 'ago'),
	  ' ', span({-class => 'content'}, $escaped_content),
	  end_li);
}

sub print_html ( $ ) {
    my $cache = shift;

    charset 'utf-8';

    my $feeds = $cache->content->{feeds};
    my $last_modified = $cache->last_modified;

    my $lang = $::lang;
    my $title = $::title;
    my $escaped_title = escapeHTML $title;
    my $url = url(-relative => 1) || './';

    my @tags;
    my %titles;
    for my $feed (@$feeds) {
	my $tag = $feed->{tag};
	push @tags, $tag;
	$titles{$tag} = $feed->{title};
    }

    my @selected_tags = param('tags');
    @selected_tags = @tags unless @selected_tags;
    my $expected_title = param('title');
    $expected_title = nkf '-W -w ', $expected_title;
    my $count = int param('count') || 50;

    print(header(-charset => 'utf-8',
		 -expires => $last_modified + $::expires),
	  start_html(-encoding => 'utf-8',
		     -lang => $lang,
		     -title => $title,
		     -style => { -src => $::static_dir . '/antenna.css' },
		     -head => [
			  Link({-href =>  "$url?type=atom",
				-rel => 'alternate',
				-title => "$title",
				-type => 'application/atom+xml'}),
			  Link({-href => $::static_dir . '/antenna.png',
				-rel => 'icon',
				-type => 'image/png'})]),
	  h1($escaped_title),
	  div({-class => 'nav'},
	      scalar localtime $last_modified, '|',
	      a({-href => "$url?type=mobile"}, 'Mobile'), '|',
	      a({-href => "$url?type=atom"}, 'Atom'), '|',
	      a({-href => "$url?type=perl"}, 'Raw'), '|',
	      a({-href => $::chart_dir}, 'Analysis')),
	  $::nav ? div({-class => 'nav'}, $::nav) : (),
	  start_form({-method => 'get'}),
	  div({-class => 'nav'},
	      textfield(-name => 'title', -default => $expected_title,
			-override => 1), ' ',
	      span({-class => 'checkbox_group'},
		   checkbox_group(-name => 'tags', -values => \@tags,
				  -default => \@selected_tags,
				  -labels => \%titles, -override => 1)),
	      textfield(-name => 'count', -default => $count,
			-size => 3, -override => 1), 'items ',
	      submit(-value => 'Refresh!')),
	  end_form, start_ol);

    my %tag_selected;
    for my $tag (@selected_tags) {
	$tag_selected{$tag} = 1;
    }
    my $expected_title_re = quotemeta __shrink_width($expected_title);

    my $entries = $cache->content->{entries};
    my $i = 0;
    for my $entry (@$entries) {
	my $source = $entry->{source};
	my $tag = $entry->{tag} || $source->{tag};
	next unless ($tag_selected{$tag});

	my $title = $entry->{title};
	next unless __shrink_width($title) =~ /$expected_title_re/io;

	__print_li $last_modified, $entry;

	++$i < $count or last;
    }

    my $library_script_file =
	'http://ajax.googleapis.com/ajax/libs/prototype/1.6.0.3/prototype.js';
    print(end_ol,
	  script({-src => $library_script_file}, ''),
	  script({-src => $::static_dir . '/antenna.js'}, ''),
	  end_html);
}

sub __print_mobile_li ( $$ ) {
    my $last_modified = shift;
    my $entry = shift;

    my $content;

    my $mobile_link = $entry->{mobile_link} || $entry->{link};
    my $title = __limit_width 24, __shrink_width $entry->{title};
    my $escaped_title = escapeHTML $title;
    $content .= start_li;
    $content .= a({-href => $mobile_link}, $escaped_title) . ' ';

    my $source = $entry->{source};
    if ($source) {
	my $title = __limit_width 8, __shrink_width $source->{title};
	my $escaped_title = escapeHTML $title;
	$content .= '@' . $escaped_title . ' ';
    }

    my $sec = $last_modified - $entry->{updated};
    $sec = 0 if $sec < 0;
    my $min = int $sec / 60;
    my $hour = int $min / 60;
    my $day = int $hour / 24;
    my $age = $day ? "${day}d" : $hour ? "${hour}h" : "${min}m";
    $content .= $age;

    my $text_content =  $entry->{text_content};
    if ($text_content) {
	my $text_content = __limit_width 32, __shrink_width $text_content;
	$content .= ' / ' .  escapeHTML $text_content;
    }

    $content .= end_li;

    return $content;
}

sub print_mobile_html ( $ ) {
    my $cache = shift;

    charset('shift_jis');

    my $last_modified = $cache->last_modified;
    my $entries = $cache->content->{entries};

    my $content;

    my $lang = $::lang;
    my $title = $::title;
    my $escaped_title = escapeHTML $title;
    my $formatted_last_modified = localtime $last_modified;

    my $sjis_expected_title = param('title');
    my $expected_title = nkf '-w -S -x', $sjis_expected_title;

    $content .= start_html(-encoding => 'shift_jis',
			   -lang => $lang,
			   -title => $title);
    $content .= h1($escaped_title);
    $content .= div($formatted_last_modified);
    $content .= start_form({-method => 'get'});
    $content .= div(textfield(-name => 'title', -default => $expected_title,
			      -override => 1),
		    hidden(-name => 'type', -default => 'mobile',
			   override => 1),
		    submit(-value => 'Refresh!'));
    $content .= end_form;
    $content .= start_ol;

    my $expected_title_re = quotemeta __shrink_width($expected_title);
    my $i = 0;
    for my $entry (@$entries) {
	my $title = $entry->{title};
	next unless __shrink_width($title) =~ /$expected_title_re/io;
	$content .= __print_mobile_li $last_modified, $entry;
	++$i < 25 or last;
    }
    $content .= end_ol;
    $content .= end_html;

    my $sjis_content = nkf '-s -W -x', $content;
    print(header(-expires => $last_modified + $::expires,
		 -Content_lengh => length $sjis_content),
	  $sjis_content);
}

sub print_atom ( $ ) {
    my $cache = shift;

    charset 'utf-8';

    my $last_modified = $cache->last_modified;
    my $entries = $cache->content->{entries};

    my $escaped_lang = escapeHTML $::lang;
    my $escaped_id = escapeHTML $::id;
    my $escaped_title = escapeHTML $::title;
    my $escaped_author = escapeHTML $::author;
    my $escaped_self_url = escapeHTML self_url;
    my $escaped_url = escapeHTML url;

    my $formatted_updated = join 'T', split / /, time2isoz $last_modified;
    print(header(-type => 'application/atom+xml',
		 -charset => 'utf-8',
		 -expires => $last_modified + $::expires),
	  qq{<?xml version="1.0" encoding="utf-8"?>},
	  qq{<feed xmlns="http://www.w3.org/2005/Atom"},
	  qq{ xml:lang="$escaped_lang">},
	  qq{<id>$escaped_url</id>},
	  qq{<title>$escaped_title</title>},
	  qq{<author><name>$escaped_author</name></author>},
	  qq{<link href="$escaped_self_url" rel="self" />},
	  qq{<link href="$escaped_url" rel="alternate" type="text/html" />},
	  qq{<updated>$formatted_updated</updated>});

    for my $i (0..49) {
	my $entry = $entries->[$i] or last;

	my $escaped_id = escapeHTML $entry->{id};
	my $escaped_title = escapeHTML $entry->{title};
	my $escaped_link = escapeHTML $entry->{link};
	my $formatted_updated =
	    join 'T', split / /, time2isoz $entry->{updated};
	my $escaped_base_uri = escapeHTML $entry->{base_uri};
	my $content = $entry->{html_content};
	$content = escapeHTML $entry->{text_content} unless defined $content;
	print(q{<entry>},
	      qq{<id>$escaped_id</id>},
	      qq{<title>$escaped_title</title>},
	      qq{<link href="$escaped_link" rel="alternate" />},
	      qq{<updated>$formatted_updated</updated>});

	if (defined $content) {
	    my $escaped_content = escapeHTML $content;
	    print(qq{<content type="html" xml:base="$escaped_base_uri">},
		  $escaped_content,
		  q{</content>});
	}

	my $source = $entry->{source};
	if ($source) {
	    my $escaped_id = escapeHTML $source->{id};
	    my $escaped_title = escapeHTML $source->{title};
	    my $escaped_link = escapeHTML $source->{link};
	    my $updated = $source->{updated};
	    my $formatted_updated =  join 'T', split / /, time2isoz $updated;

	    print(q{<source>},
		  qq{<id>$escaped_id</id>},
		  qq{<title>$escaped_title</title>},
		  qq{<link href="$escaped_link" rel="alternate" />},
		  qq{<updated>$formatted_updated</updated>},
		  q{</source>});
	}
	print(q{</entry>});
    }
    print q{</feed>};
}

sub print_rdf ( $ ) {
    my $cache = shift;

    charset 'utf-8';

    my $last_modified = $cache->last_modified;
    my $entries = $cache->content->{entries};

    my $escaped_lang = escapeHTML $::lang;
    my $escaped_id = escapeHTML $::id;
    my $escaped_title = escapeHTML $::title;
    my $escaped_url = escapeHTML url;
    my $formatted_updated = join 'T', split / /, time2isoz $last_modified;
    print(header(-type => 'application/rdf+xml',
		 -charset => 'utf-8',
		 -expires => $last_modified + $::expires),
	  q{<?xml version="1.0" encoding="utf-8"?>},
	  q{<rdf:RDF xmlns="http://purl.org/rss/1.0/"},
	  q{ xmlns:dc="http://purl.org/dc/elements/1.1/"},
	  q{ xmlns:content="http://purl.org/rss/1.0/modules/content/"},
	  q{ xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"},
	  qq{ xml:lang="$escaped_lang">},
	  qq{<channel rdf:about="$escaped_id">},
	  qq{<title>$escaped_title</title>},
	  qq{<link>$escaped_url</link>},
	  qq{<dc:date>$formatted_updated</dc:date>},
	  q{<description></description>},
	  q{<items>},
	  q{<rdf:Seq>});

    for my $i (0..49) {
	my $entry = $entries->[$i] or last;
	my $escaped_id = escapeHTML $entry->{id};
	print qq{<rdf:li rdf:resource="$escaped_id" />};
    }

    print(q{</rdf:Seq>},
	  q{</items>},
	  q{</channel>});

    for my $i (0..49) {
	my $entry = $entries->[$i] or last;
	my $escaped_id = escapeHTML $entry->{id};
	my $title = $entry->{title};
	my $source = $entry->{source};
	$title .= ' @ ' . $source->{title} if $source;
	my $escaped_title = escapeHTML $title;
	my $escaped_link = escapeHTML $entry->{link};
	my $updated = $entry->{updated};
	my $formatted_updated =  join 'T', split / /, time2isoz $updated;
	my $content = $entry->{html_content};
	$content ||= escapeHTML $entry->{text_content};
	print(qq{<item rdf:about="$escaped_id">},
	      qq{<title>$escaped_title</title>},
	      qq{<link>$escaped_link</link>},
	      qq{<dc:date>$formatted_updated</dc:date>});

	if (defined $content) {
	    my $escaped_content = escapeHTML $content;
	    my $escaped_base_uri = escapeHTML $entry->{base_uri};
	    print(qq{<content:encoded xml:base="$escaped_base_uri">},
		  $escaped_content,
		  q{</content:encoded>});
	}

	print q{</item>};
    }
    print q{</rdf:RDF>};
}

my $printers = {
    'perl' => \&print_perl,
    'mobile' => \&print_mobile_html,
    'atom' => \&print_atom,
    'rdf' => \&print_rdf,
};

sub update ( $ ) {
    # Yes, I can use the map functions three times in this subroutine
    # to reduce the code size, which I don't like very much.
    my $content = shift;
    $content ||= {
	feeds => [],
	entries => [],
    };

    my $feeds = $content->{feeds};
    my %cached_feeds;
    for my $feed (@$feeds) {
	my $tag = $feed->{tag};
	$cached_feeds{$tag} = $feed;
    }

    my $log_handle;
    my $log_file = $::log_file;
    if (defined $log_file) {
	open $log_handle, '>>', $log_file
	    or die 'cannot open the log file';
	my $stat = stat $log_handle;
	my $size = $stat->size;
	truncate $log_handle, 0 if $size > $::log_size;
    }

    @$feeds = ();
    require Zng::Net;
    my $net = Zng::Net->new(log_handle => $log_handle,
			    chart_dir => $::chart_dir,
			    chart_style_file => $::chart_style_file,
			    chart_count => $::chart_count);
    for my $source (@$::sources) {

	my $tag = $source->{tag};
	my $type = $source->{type};

	my $feed = $cached_feeds{$tag} || { tag => $tag };
	push @$feeds, $feed;

	my $driver = $drivers->{$type};
	&$driver($net, $source, $feed);
    }
    $net->dispatch($::timeout);

    my $entries = $content->{entries};
    @$entries = ();
    for my $feed (@$feeds) {
	my $feed_entries = $feed->{entries};
	if ($feed_entries) {
	    my $updated;
	    for my $feed_entry (@$feed_entries) {
		my $entry_updated = $feed_entry->{updated};
		$updated = $entry_updated if $updated < $entry_updated;

		$feed_entry->{source} = $feed;
	    }
	    $feed->{updated} = $updated;

	    push @$entries, @$feed_entries;
	} else {
	    push @$entries, $feed;
	}
    }

    @$feeds = sort { $b->{updated} <=> $a->{updated} } @$feeds;
    @$entries = sort { $b->{updated} <=> $a->{updated} } @$entries;

    return $content;
}

eval {
    require './antenna.conf';
    my $cache = Zng::Cache->new(updater => \&update,
				file => $::cache_file,
				expires => $::expires);
    $cache->fetch;

    my $type = param('type');
    my $printer = $printers->{$type} || \&print_html;
    &$printer($cache);
};
if ($@) {
    print(header(-type => 'text/plain', -charset => 'utf-8'),
	  "ZngAntenna 4.0\n",
	  "--\n",
	  "A fatal error occurred on answering your query.\n",
	  "Sorry for your inconvenience.\n");

    open my $handle, '>>', 'error.log';
    print $handle scalar localtime, ': ', $@;
}
