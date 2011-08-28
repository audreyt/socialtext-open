#!perl
# @COPYRIGHT@

use warnings;
use strict;
use Test::Socialtext tests => 15;
use Socialtext::Attachments;
use Socialtext::User;

fixtures(qw( db ));

sub booleanize { $_[0] ? 1 : '' } # could be a filter

my $hub     = create_test_hub();
my $creator = $hub->current_user();

run {
    my $case = shift;
    my $path = "t/attachments/" . $case->in;

    open my $fh, '<', $path or die "$path\: $!";
    $hub->attachments->create(
        filename => $case->in,
        fh => $fh,
        creator => $creator,
    );
    my $name = Socialtext::Encode::ensure_is_utf8($case->in);
    my ($attachment) =
        grep { $name eq $_->filename } @{ $hub->attachments->all };
    ok($attachment, $case->in . ' should actually attach');

    is
        $attachment->mime_type,
        $case->mime_type,
        $case->in . " = " . $case->mime_type;
    is
        booleanize($attachment->should_popup),
        booleanize($case->should_popup),
        $case->in.' should '.($case->should_popup ? '' : 'not ').'pop-up';
};

# TODO (Maybe): Detect if content looks like application/binary or text/plain.

__DATA__
===
--- in: foo.txt
--- mime_type: text/plain
--- should_popup: 0

===
--- in: foo.htm
--- mime_type: text/html
--- should_popup: 0

===
--- in: foo.html
--- mime_type: text/html
--- should_popup: 0

===
--- in: foo
--- mime_type: text/plain
--- should_popup: 0

===
--- in: Internationalization.txt
--- mime_type: text/plain
--- should_popup: 0
