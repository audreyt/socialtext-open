package Socialtext::WikiFixture::Search;
# @COPYRIGHT@
use Socialtext::System qw/shell_run/;
use Socialtext::Encode;
use Socialtext::People::Search;
use Socialtext::AppConfig;
use Socialtext::String;
use Test::More;
use Moose;

extends 'Socialtext::WikiFixture::SocialRest';

after 'init' => sub {
    shell_run('nlwctl -c stop');
    shell_run('ceq-rm .');
    if (Socialtext::AppConfig->syslog_level ne 'debug') {
        Socialtext::AppConfig->set('syslog_level' => 'debug');
        Socialtext::AppConfig->write();
    }
};

sub set_searcher {
    my $self     = shift;
    my $searcher = shift;

    my $class  = 'Socialtext::Search::' . ucfirst($searcher) . '::Factory';
    my $config = Socialtext::AppConfig->new();
    $config->set( 'search_factory_class' => $class );
    $config->write();
}

sub search_people {
    my $self = shift;
    my $query = shift;
    my $num_results = shift;

    my $viewer = Socialtext::User->Resolve( $self->{http_username} );
    my ($ppl, $num) = Socialtext::People::Search->Search(
        $query,
        viewer => $viewer,
    );

    my $count = @$ppl;
    is $count, $num_results, "search '$query' results: $num_results";
    if ($count != $num_results) {
        use Data::Dumper;
        diag Dumper $ppl;
    }
}

sub people_search {
    my $self = shift;
    my $query = shift;
    my $expected_results = shift;
    my $other_params = shift;

    if (defined($other_params)) {
        $other_params = ";$other_params";
    } else {
        $other_params = '';
    }

    $query = Socialtext::String::uri_escape(Socialtext::Encode::ensure_is_utf8($query));
    $self->comment("People search: '$query'");

    $self->get('/data/people?q=' . $query.$other_params, 'application/json');
    $self->code_is(200);
    $self->json_parse();
    $self->json_array_size($expected_results);
}

sub ws_search {
    my $self = shift;
    my $q = shift;
    my $expected_results = shift;
    $q = Socialtext::String::uri_escape(Socialtext::Encode::ensure_is_utf8($q));

    $self->st_process_jobs();
    $self->get("/$self->{workspace}/index.cgi?action=search;search_term=$q");
    $self->code_is(200);

    my $body = $self->{http}->_decoded_content;
    if ($body =~ m/Showing 1 - \d+ of (\d+) total/) {
        my $matches = $1;
        is $matches, $expected_results, "expected results for '$q'";
    }
    elsif ($body =~ m/Your search returned 0 results\./) {
        is 0, $expected_results, "expected results for '$q'";
    }
    else {
        ok 0, "Couldn't find the number of results";
    }
}

1;
