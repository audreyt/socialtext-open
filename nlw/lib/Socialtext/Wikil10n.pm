package Socialtext::Wikil10n;
# @COPYRIGHT@
use strict;
use warnings;
use Encode qw(decode_utf8);
use Socialtext::Resting;
use Socialtext::System qw/shell_run/;
use base 'Exporter';
our @EXPORT_OK = qw(load_existing_l10ns make_rester);

sub load_existing_l10ns {
    my $r     = shift;
    my $title = shift;

    my $content = $r->get_page($title);
    return {} if $r->response->code ne 200;

    #use Data::Dumper;
    #print Dumper($content);
    my %l10n;
    my $cellex = qr/\s+(.+?)?\s+/;
    my $cellex_last = qr/\s+(.+?).+?/;
    my $rowgex = qr/^\|$cellex\|$cellex\|$cellex\|$cellex_last/;
    for (split "\n", $content) {
        next unless m/^\|/;
        next if m/^\|\s+\*/;
        my $row = $_;
        my @cols = $row =~ m/$rowgex/;
        $l10n{ $cols[0] || "" } = {
            msgstr    => $cols[1] || '',
            reference => $cols[2] || "",
            other     => $cols[3] || "",
        };
    }

    return \%l10n;
}

sub make_rester {
    # Run stl10n-to-wiki if the stl10n workspace doesn't yet exist.
    unless (-d "$ENV{HOME}/.nlw/root/data/stl10n") {
        warn "stl10n workspace doesn't yet exist!  Creating it.\n";
        shell_run("$ENV{HOME}/src/st/current/nlw/dev-bin/stl10n-to-wiki");
    }

    return Socialtext::Resting->new(
        username  => 'devnull1@socialtext.com',
        password  => 'd3vnu11l',
        workspace => 'stl10n',
        server    => "http://localhost:" . ( $> + 20000 ),
    );
}

1;
