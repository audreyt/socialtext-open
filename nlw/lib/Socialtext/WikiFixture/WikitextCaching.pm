package Socialtext::WikiFixture::WikitextCaching;
# @COPYRIGHT@
use Socialtext::System qw/shell_run/;
use Socialtext::AppConfig;
use Socialtext::File qw/get_contents set_contents/;
use Test::Socialtext;
use Test::More;
use Moose;

extends 'Socialtext::WikiFixture::SocialRest';

my $cache_dir = Socialtext::AppConfig->formatter_cache_dir;

after 'init' => sub {
    clear_wikitext_cache();
};

sub clear_wikitext_cache {
    shell_run('nlwctl -c stop');
    shell_run("rm -rf $cache_dir/*");
}

sub cache_created_ok {
    my $self = shift;
    my $ws   = shift;

    my $ws_id = Socialtext::Workspace->new(name => $ws)->workspace_id;
    my $ws_cache_dir = "$cache_dir/$ws_id";
    ok -d $ws_cache_dir, "Cache directory $ws_cache_dir exists";
}

sub _question_filename {
    my $self      = shift;
    my $ws_name   = shift;
    my $page_name = shift;

    my $ws = Socialtext::Workspace->new(name => $ws_name);
    my $ws_id = $ws->workspace_id;
    my $ws_cache_dir = "$cache_dir/$ws_id";

    my $hub = new_hub($ws_name);
    my $page = $hub->pages->new_from_uri($page_name);
    my $rev_id = $page->revision_id;
    unless ($rev_id) {
        die "Can't find revision_id for $page_name!";
    }

    return "$ws_cache_dir/" . $page->id . '-' . $rev_id . '-Q';
}

sub _question_file_contents {
    my $self = shift;
    my $Q_file = $self->_question_filename(@_);
    ok -e $Q_file, "Question file $Q_file exists";

    return get_contents($Q_file) || '';
}

sub question_file_is {
    my $self      = shift;
    my $page_name = shift;
    my $expected  = shift;

    my $contents = $self->_question_file_contents($self->{workspace}, $page_name);
    is $contents, $expected, "Q file is '$expected'";
}

sub question_file_like {
    my $self      = shift;
    my $page_name = shift;
    my $expected  = shift;

    my $contents = $self->_question_file_contents($self->{workspace}, $page_name);
    like $contents, $expected, "Q file matches '$expected'";
}

sub set_question_file {
    my $self      = shift;
    my $page_name = shift;
    my $new_value = shift;
    my $Q_file = $self->_question_filename($self->{workspace}, $page_name);

    set_contents($Q_file, \$new_value);
}

sub fetch_page {
    my $self = shift;
    my $page_name = shift;
    my $cache_header = shift;

    $self->get("/data/workspaces/$self->{workspace}/pages/$page_name");
    $self->code_is(200);
    $self->{http}->header_is('X-Socialtext-Cache', $cache_header,
        'X-Socialtext-Cache header');
}

1;
