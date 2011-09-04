use utf8;
use Zng::Antenna::Resource::BBS2ch::Feed;
use Zng::Antenna::Resource::HTML::Feed;
use Zng::Antenna::Resource::Hatena::Feed;
use Zng::Antenna::Resource::JBBS::Feed;
use Zng::Antenna::Resource::XML::Feed;
use Zng::Antenna::Resource::Twitter::Feed;

$config = {
    id => 'tag:is.zng.info,2011:antenna',
    lang => 'ja',
    title => 'IS2005 Antenna',
    author => '平野貴仁',

    static_dir => 'static',
    cache_file => 'cache5.dat',
    chart_dir => 'analysis',
    chart_style_file => "../static/analysis.css",
    chart_count => 10,
    log_file => 'update.log',

    nav =>
	'<div>Generated By ZngAntenna 5.0.2 | ' .
	'<a href="http://is2009.2-d.jp/">2009</a> | ' .
	'<a href="http://www.is2008er.is-a-geek.org/">2008</a> | ' .
	'<a href="http://a.hatena.ne.jp/is2007/">2007</a> | ' .
	'<a href="http://is2006.matritic.net/">2006</a> | ' .
	'<strong>2005</strong> | ' .
	'<a href="http://is2004.starlancer.org/">2004</a> | ' .
	'<a href="http://www.il.is.s.u-tokyo.ac.jp/~s_fox/quintet/cgi/' .
	'currier">2003</a></div>' .
	'<div># ' . `uptime` . '</div>',

    expires => 300,

    timeout => 4,

    feeds => [
	Zng::Antenna::Resource::HTML::Feed->new({
	    url => 'http://plapla.tk/~plaster/d/',
	    title => '\')\'観察にっき' }),
	Zng::Antenna::Resource::HTML::Feed->new({
	    url => 'http://inazz.jp/~dm/',
	    title => 'しす☆こん' }),
	Zng::Antenna::Resource::HTML::Feed->new({
	    url => 'http://www.ketan.jp/diary/',
	    title => 'けたん日記(仮)' }),
	Zng::Antenna::Resource::XML::Feed->new({
	    url => 'http://is.zng.info/hiki/recruit/hiki.cgi?c=rss' }),
	Zng::Antenna::Resource::XML::Feed->new({
	    url => 'http://is.zng.info/hiki/generic/?c=rss' }),
	Zng::Antenna::Resource::XML::Feed->new({
	    url => 'http://ymatsux.seesaa.net/index.rdf' }),
	Zng::Antenna::Resource::Hatena::Feed->new({
	    user_id => 'succeed' }),
	Zng::Antenna::Resource::XML::Feed->new({
	    url => 'http://blog.goo.ne.jp/dragonfly7/index.rdf' }),
	Zng::Antenna::Resource::Hatena::Feed->new({
	    user_id => 'sekine360' }),
	Zng::Antenna::Resource::Hatena::Feed->new({
	    user_id => 'naka-jima' }),
	Zng::Antenna::Resource::Hatena::Feed->new({
	    user_id => 'OoX' }),
	Zng::Antenna::Resource::Hatena::Feed->new({
	    user_id => 'letter' }),
	Zng::Antenna::Resource::XML::Feed->new({
	    url => 'http://blog.livedoor.jp/toroinomogura/index.rdf' }),
	Zng::Antenna::Resource::Hatena::Feed->new({
	    user_id => 'namasute0' }),
	Zng::Antenna::Resource::XML::Feed->new({
	    url => 'http://henge.blog66.fc2.com/?xml' }),
	Zng::Antenna::Resource::Hatena::Feed->new({
	    user_id => 'kosak' }),
	Zng::Antenna::Resource::XML::Feed->new({
	    url => 'http://d.nikori.tk/rss_full.php' }),
	Zng::Antenna::Resource::XML::Feed->new({
	    url => 'http://blog.zng.jp/feeds/posts/default?alt=rss' }),
	Zng::Antenna::Resource::BBS2ch::Feed->new({
	    server => 'http://kamome.2ch.net',
	    directory => 'informatics',
	    thread_title_re => '情報理工学(?:系)?研究科',
	    title => '情報学(仮)＠2ch掲示板' }),
	Zng::Antenna::Resource::JBBS::Feed->new({
	    directory => 'school/18717',
	    title => '29ちゃんねる' }),
	Zng::Antenna::Resource::Twitter::Feed->new({
	    user_id => 'hiranotaka',
	    list_id => 'CS' }) ] };
