package Zng::Antenna::Updater;

use strict;
use utf8;
use File::stat;
use XML::LibXML;
use Zng::Net;

sub update ( $$ ) {
    my $config = shift;
    my $data = shift;

    my $feeds = $data->{feeds};
    my $feed_map = {};
    for my $feed (@$feeds) {
	my $id = $feed->id;
	$feed_map->{$id} = $feed;
    }

    my $feeds = $config->{feeds};
    $data->{feeds} = $feeds;
    for my $feed (@$feeds) {
	my $id = $feed->id;
	$feed = $feed_map->{$id} || $feed;
    }

    my $log_handle;
    my $log_file = $config->{log_file};
    if (defined $log_file) {
	open $log_handle, '>>', $log_file
	    or die 'cannot open the log file';
	my $stat = stat $log_handle;
	my $size = $stat->size;
	truncate $log_handle, 0 if $size > $config->{log_size};
    }

    my $net = Zng::Net->new(log_handle => $log_handle,
			    chart_dir => $config->{chart_dir},
			    chart_style_file => $config->{chart_style_file},
			    chart_count => $config->{chart_count},
			    ssl_ca_file => $config->{ssl_ca_file});

    my $offset = int rand scalar @$feeds;
    for my $index ($offset .. $#$feeds, 0 .. $offset - 1) {
	$feeds->[$index]->update($net);
    }

    $net->dispatch($config->{timeout});

    my $threads = [];
    $data->{threads} = $threads;

    for my $feed (@$feeds) {
	push @$threads, $feed->threads;
    }

    @$threads = sort { $b->updated <=> $a->updated } @$threads;

    return $data;
}

sub html_to_text ( $ ) {
    my $html = shift;

    my $wrapped_html =
	q{<meta content="text/html; charset=utf-8" http-equiv="Content-Type">} .
	qq{<div>$html</div>};
    my $parser = XML::LibXML->new(recover => 1);
    my $document = eval {
	$parser->parse_html_string($wrapped_html);
    };
    if ("$@" ne '') {
	return $html;
    }

    my $text = $document->textContent;
    return $text;
}

1;
