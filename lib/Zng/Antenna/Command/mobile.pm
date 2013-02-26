package Zng::Antenna::Command::mobile;

use strict;
use Encode;
use NKF;
use Unicode::Normalize;
use Zng::Antenna;

my $CHAR_RE = qr/[\x00-\x7f]|[\xc0-\xfd][\x80-\xbf]+/;
my $HALFWIDTH_CHAR_RE =
    qr/[\x20-\x7e]|\xef\xbd[\xa1-\xbf]|\xef\xbe[\x80-\x9f]/;

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

sub __format_li ( $$$ ) {
    my $last_modified = shift;
    my $thread = shift;
    my $q = shift;

    my $content;

    my $title = __limit_width 24, __shrink_width $thread->title;
    my $escaped_title = $q->escapeHTML($title);
    $content .= $q->start_li;
    $content .= $q->a({-href => $thread->mobile_link}, $title) . ' ';

    my $feed = $thread->feed;
    if ($feed) {
	my $title = __limit_width 8, __shrink_width $feed->title;
	my $escaped_title = $q->escapeHTML($title);
	$content .= '@' . $escaped_title . ' ';
    }

    my $sec = $last_modified - $thread->updated;
    $sec = 0 if $sec < 0;
    my $min = int $sec / 60;
    my $hour = int $min / 60;
    my $day = int $hour / 24;
    my $age_str = $day ? "${day}d" : $hour ? "${hour}h" : "${min}m";
    $content .= $age_str;

    my $thread_content = $thread->content;
    if (defined $thread_content) {
	my $thread_content = __limit_width 32, __shrink_width $thread_content;
	$content .= ' / ' .  $q->escapeHTML($thread_content);
    }

    $content .= $q->end_li;

    return $content;
}

sub __format_page_link ( $$$ ) {
    my $q = shift;
    my $page = shift;
    my $content = shift;

    $q = CGI->new($q);
    $q->param('page', $page);

    my $url = $q->url(-query => 1);
    return $q->a({ href => $url }, $content);
}

sub format ( $$$ ) {
    my $config = shift;
    my $q = shift;
    my $fh = shift;

    my $cache = Zng::Antenna::fetch $config;

    $q->charset('shift_jis');

    my $last_modified = $cache->last_modified;
    my $threads = $cache->content->{threads};

    my $content;

    my $lang = $config->{lang};
    my $title = $config->{title};
    my $escaped_title = $q->escapeHTML($title);
    my $formatted_last_modified = localtime $last_modified;

    my $expected_title = decode 'shift_jis', $q->param('title');
    my $normalized_expected_title = NFKC lc $expected_title;

    my $page = int $q->param('page');

    $content .= $q->start_html(-encoding => 'shift_jis',
			       -lang => $lang,
			       -title => $title);
    $content .= $q->h1($escaped_title);
    $content .= $q->div($formatted_last_modified);
    $content .= $q->start_form({-method => 'get'});
    $content .= $q->div($q->textfield(-name => 'title',
				      -default => $expected_title,
				      -override => 1),
			$q->hidden(-name => 'type', -default => 'mobile',
				   override => 1),
			$q->submit(-value => 'Refresh!'));
    $content .= $q->end_form;
    $content .= $q->start_ol({start => $page * 25 + 1});

    my $i = 0;
    my $has_next = 0;
    for my $thread (@$threads) {
	my $title = $thread->title;
	my $normalized_title = NFKC $title;
	index($normalized_title, $normalized_expected_title) >= 0 or next;

	if ($i >= ($page + 1) * 25) {
	    $has_next = 1;
	    last;
	}

	if ($i >= $page * 25) {
	    $content .= __format_li $last_modified, $thread, $q ;
	}

	++$i;
    }

    $content .= $q->end_ol;

    my $has_prev = $page > 0;
    if ($has_prev || $has_next) {
	$content .= $q->start_div;
	if ($has_prev) {
	    $content .= __format_page_link($q, $page - 1, '&lt; Prev');
	}
	if ($has_prev && $has_next) {
	    $content .= ' ';
	}
	if ($has_next) {
	    $content .= __format_page_link($q, $page + 1, 'Next &gt;');
	}
	$content .= $q->end_div;
    }

    $content .= $q->end_html;

    my $sjis_content = nkf '-s -W -x', encode_utf8 $content;
    $fh->print($q->header(-expires => $last_modified + $config->{ttl},
			  -Content_lengh => length $sjis_content),
	       $sjis_content);
}

1;
