#!/usr/bin/perl

use strict;
use utf8;
use vars qw{$config};
use FindBin;
use lib "$FindBin::RealBin/../lib";
use Encode;
use CGI qw{-nosticky :standard form start_ul end_ul};
use Time::Local;
use Zng::Cache;

sub print_html ( $ ) {
    my $vars = shift;

    binmode STDOUT, ':encoding(utf-8)';

    my $static_dir = $config->{static_dir};
    print(header(-charset => 'utf-8'),
	  start_html(-title => $config->{title},
		     -style => "$static_dir/antenna.css"),
	  h1($config->{title}));

    if ($vars->{has_greetings}) {
	print p('今なら広告掲載は無料です！');
    }

    if ($vars->{has_receipt}) {
	print p('出稿したよ！');
    }

    my $errors = $vars->{errors};
    if ($errors) {
	print div(strong('申し訳ありませんが、処理できませんでした。' .
			 '次の項目を確認していだだけますか？'),
		  start_ul);
	for my $error (@$errors) {
	    print li $error;
	}
	print end_ul;
    }

    my $form = $vars->{form};
    if ($form) {
	print(form({-action => url, -method => 'post'},
		   dl(dt('宣伝文:'),
		      dd(textfield(-name => 'content', -size => 60,
				   -value => $form->{content})),
		      dt('URL:'),
		      dd(textfield(-name => 'url', -size => 60,
				   -value => $form->{url})),
		      dt('掲載終了日(YYYY-MM-DD):'),
		      dd(textfield(-name => 'expire_date', -size => 12,
				   -value => $form->{expire_date})),
		      p(submit(-value => '広告を出稿する！')))));
    }

    print end_html;
}

sub commit ( $ ) {
    my $ad = shift;

    my $updater = sub ( $ ) {
	my $ads = shift || [];
	push @$ads, $ad;
	return $ads;
    };

    Zng::Cache->new(updater => $updater,
		    file => $config->{data_file})->update;
}

sub handle_post () {
    my $errors = [];

    my $content = decode_utf8 param('content');
    if ($content eq '') {
	push @$errors, '宣伝文が空です。';
    }

    my $url = decode_utf8 param('url');
    unless ($url =~ /^http:\/\//) {
	push @$errors, 'URL は http:// から始めて下さい。';
    }

    my $created_time = time;

    my $expire_date = decode_utf8 param('expire_date');
    my $expire_time;
    if ($expire_date =~ /^(\d\d\d\d)-(\d\d)-(\d\d)$/) {
	my $year = int $1;
	my $month = int $2;
	my $day = int $3;
	eval {
	    $expire_time =
		timelocal(0, 0, 0, $day, $month - 1, $year - 1900) + 86400;
	};
    }
    if (!defined $expire_time) {
	push @$errors, '掲載終了日が謎です。';
    } elsif ($expire_time <= $created_time) {
	push @$errors, '掲載終了日が過去です。';
    } elsif ($expire_time > 30 * 86400 + $created_time) {
	push @$errors, '掲載終了日が未来過ぎます。';
    }

    if (@$errors) {
	print_html {
	    errors => $errors,
	    form => {
		url => $url,
		content => $content,
		expire_date => $expire_date,
	    },
	};
	return;
    }

    commit {
	url => $url,
	content => $content,
	created_time => $created_time,
	expire_time => $expire_time,
    };

    print_html { has_receipt => 1 };
}

sub handle_get () {
    my $expire_tm = [ localtime 7 * 86400 + time ];
    my $expire_date = sprintf('%04d-%02d-%02d', 1900 + $expire_tm->[5],
			      1 + $expire_tm->[4], $expire_tm->[3]);
    print_html {
	has_greetings => 1,
	form => {
	    url => '',
	    content => '',
	    expire_date => $expire_date,
	},
    };
}

sub handle_request () {
    my %handlers = (
	'GET' => \&handle_get,
	'HEAD' => \&handle_get,
	'POST' => \&handle_post,
    );

    my $method = request_method || param('request_method');
    unless ($handlers{$method})  {
	print(header(-type => 'text/plain',
		     -status => '406 Method Not Allowed',
		     Allow => join ',', keys %handlers));
	return;
    }

    &{$handlers{$method}};
}

eval {
    require './adsconfig.pl';
    handle_request;
};

if ($@) {
    print(header(-type => 'text/plain', -charset => 'utf-8'),
	  "ZngAds\n",
	  "--\n",
	  "A fatal error occurred on answering your query.\n",
	  "Sorry for your inconvenience.\n");

    open my $handle, '>>', 'error.log';
    print $handle scalar localtime, ': ', $@;
}
