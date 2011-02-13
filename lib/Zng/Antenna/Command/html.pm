package Zng::Antenna::Command::html;

use strict;
use NKF;
use Zng::Antenna;

my $CHAR_RE = qr/[\x00-\x7f]|[\xc0-\xfd][\x80-\xbf]+/;

sub __limit_length ( $$ ) {
    my $length = shift;
    my $str = shift;
    $str =~ /^(?:$CHAR_RE){0,$length}/;
    return $&;
}

sub __age_info ( $ ) {
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

sub __format_li ( $$$$ ) {
    my $last_modified = shift;
    my $thread = shift;
    my $q = shift;
    my $fh = shift;

    my $is_smartphone = $q->param('type') eq 'smartphone';
    my $link = $is_smartphone ? $thread->smartphone_link : $thread->link;
    my $title = $thread->title;
    my $escaped_title = $q->escapeHTML($title);
    $fh->print($q->start_li,
	       $q->a({-class => 'title', -href => $link,
		      $is_smartphone ? () : (-title => $title) },
		     $escaped_title), ' ');

    my $feed = $thread->feed;
    unless ($feed->standalone) {
	my $link = $is_smartphone ? $feed->smartphone_link : $feed->link;
	my $escaped_title = $q->escapeHTML($feed->title);
	$fh->print($q->span({-class => 'source'}, '@',
			    $q->a({-href => $link}, $escaped_title)), ' ');
    }

    my $age = $last_modified - $thread->updated;
    my $age_info = __age_info $age;
    my $content = __limit_length 80, $thread->text_content;
    my $escaped_content = $q->escapeHTML($content);
    $fh->print($q->span({-class => $age_info->{class}}, $age_info->{number},
			$age_info->{unit}, 'ago'),
	       ' ', $q->span({-class => 'content'}, $escaped_content),
	       $q->end_li);
}

sub __format_page_link ( $$$$ ) {
    my $q = shift;
    my $page = shift;
    my $content = shift;
    my $fh = shift;

    $q = CGI->new($q);
    $q->param('page', $page);
    my $url = $q->url(-query => 1);
    $fh->print($q->a({ href => $url }, $content));
}

sub format ( $$$ ) {
    my $config = shift;
    my $q = shift;
    my $fh = shift;

    my $cache = Zng::Antenna::fetch $config;

    $q->charset('utf-8');

    my $url = $q->url(-relative => 1) || './';
    my $static_dir = $config->{static_dir};

    my $title = $config->{title};
    my $escaped_title = $q->escapeHTML($title);

    my $content = $cache->content;
    my $last_modified = $cache->last_modified;

    my $feeds = $content->{feeds};
    my $feed_ids = [];
    my $feed_title_map = {};
    for my $feed (@$feeds) {
	my $feed_id = Zng::Antenna::hex_id $feed->id;
	push @$feed_ids, $feed_id;
	$feed_title_map->{$feed_id} = $feed->title;
    }

    my $threads = $content->{threads};

    my $expected_title = $q->param('title');
    # perl 5.6 does not have Unicode::Normalize.
    # We use -Z1 --utf8mac-input instead.
    my $normalized_expected_title =
	nkf '-w -W -Z1 --utf8mac-input', lc $expected_title;

    my $advanced = $q->param('advanced');

    my $selected_feed_ids =
	[ $advanced ? $q->param('feed_ids') : @$feed_ids ];
    my $feed_id_selected = {};
    for my $feed_id (@$selected_feed_ids) {
	$feed_id_selected->{$feed_id} = 1;
    }

    my $page = int $q->param('page');
    my $count = $advanced ? $q->param('count') || 50 : 50;

    my $type = $q->param('type') || 'html';
    my $is_smartphone = $type eq 'smartphone';
    my $style_file = $is_smartphone ? 'antenna_smartphone.css' : 'antenna.css';
    my $meta = $is_smartphone ?
	{ viewport => 'width=device-width; user-scalable=0' } : {};

    my $basic_url = "$url?type=$type";
    my $advanced_url = "$url?type=$type;advanced=on";

    my $head =
	[ $q->Link({-href =>  "$url?type=atom",
		    -rel => 'alternate',
		    -title => $title,
		    -type => 'application/atom+xml'}),
	  $q->Link({-href => "$static_dir/antenna.ico",
		    -rel => 'icon',
		    -type => 'image/png'}),
	  ($is_smartphone ?
	   $q->Link({-href => "$static_dir/antenna_smartphone.png",
		     -rel => 'apple-touch-icon',
		     -type => 'image/png'}) : ()) ];

    $fh->print($q->header(-charset => 'utf-8',
			  -expires => $last_modified + $config->{expires}),
	       $q->start_html(-encoding => 'utf-8',
			      -lang => $config->{lang},
			      -title => $title,
			      -style => { -src => "$static_dir/$style_file" },
			      -meta => $meta,
			      -head => $head),
	       $q->h1($escaped_title),
	       $q->div({-class => 'nav'},
		       scalar localtime $last_modified, '|',
		       $is_smartphone ?
		       ($q->a({-href => "$url"}, 'Normal'), '|',
			$q->strong('Smartphone')) :
		       ($q->strong('Normal'), '|',
			$q->a({-href => "$url?type=smartphone"},
			      'Smartphone')), '|',
		       $q->a({-href => "$url?type=mobile"}, 'Mobile'), '|',
		       $q->a({-href => $config->{chart_dir}}, 'Analysis')),
	       $config->{nav} ? $q->div({-class => 'nav'}, $config->{nav}) : (),
	       $q->start_form({-method => 'get'}),
	       $q->div({-class => 'nav'},
		       'Search:',
		       $q->textfield(-name => 'title',
				     -default => $expected_title,
				     -override => 1), ' ',
		       $is_smartphone ?
		       $q->hidden(-name => 'type', -default => 'smartphone',
				  override => 1) : (),
		       $q->submit(-value => 'Refresh!'),
		       $advanced ?
		       ($q->a({-href => $basic_url }, 'Hide Options'),
			$q->hidden(-name => 'advanced', -value => 'on'),
			$q->checkbox_group(-name => 'feed_ids',
					   -values => $feed_ids,
					   -default => $selected_feed_ids,
					   -labels => $feed_title_map,
					   -override => 1),
			$q->textfield(-name => 'count', -default => $count,
				      -size => 3, -override => 1), 'items') :
		       $q->a({-href => $advanced_url }, 'Show Options')),
	       $q->end_form, $q->start_ol({-start => $page * $count + 1 }));

    my $i = 0;
    my $has_next = 0;
    for my $thread (@$threads) {
	my $feed = $thread->feed;
	my $feed_id = Zng::Antenna::hex_id $feed->id;
	$feed_id_selected->{$feed_id} or next;

	my $title = $thread->title;
	my $normalized_title = nkf '-w -W -Z1 --utf8mac-input', lc $title;
	index($normalized_title, $normalized_expected_title) >= 0 or next;

	if ($i >= ($page + 1) * $count) {
	    $has_next = 1;
	    last;
	}

	if ($i >= $page * $count) {
	    __format_li $last_modified, $thread, $q, $fh;
	}

	++$i;
    }

    $fh->print($q->end_ol);

    my $has_prev = $page > 0;
    if ($has_prev || $has_next) {
	$fh->print($q->start_div({class => 'page'}));
	if ($has_prev) {
	    __format_page_link($q, $page - 1, "« Prev Page", $fh);
	} else {
	    $fh->print("« Prev Page");
	}

	$fh->print(' | Page ', $page + 1, ' | ');

	if ($has_next) {
	    __format_page_link($q, $page + 1, 'Next Page »', $fh);
	} else {
	    $fh->print("Next Page »");
	}
	$fh->print($q->end_div);
    }

    $fh->print($q->end_html);
}

1;
