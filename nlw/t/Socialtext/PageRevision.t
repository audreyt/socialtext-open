#!perl
use warnings;
use strict;

use Test::Socialtext tests => 70;
use Test::Socialtext::Fatal;
use Socialtext::String;
use utf8;
require bytes;
use ok 'Socialtext::PageRevision';

fixtures(qw(db));

my $hub = create_test_hub();

simple: {
    my $rev = Socialtext::PageRevision->Blank(
        hub => $hub, name => "My Fiancée");
    isa_ok $rev, 'Socialtext::PageRevision';
    ok $rev->mutable, "rev is mutable";
    ok !$rev->revision_id, "no rev id";
    ok !$rev->revision_num, "no rev num";
    is $rev->page_id, 'my_fianc%C3%A9e', "title got id-ified";
    ok !$rev->has_body_ref;
    ok !$rev->body_modified;
    is $rev->body_length, 0, "initially empty body length";
    ok $rev->editor == $hub->current_user, 'default editor is current_user';
    is $rev->page_type, 'wiki', "It's a wiki by default";

    my $content = "Fantastic\nGreat\n❤❤\n";
    {
        $rev->body_ref(\$content);
        ok $rev->body_modified;
        ok $rev->has_body_ref, "has a body ref";
        is $rev->body_length, length($content), "length got calculated as chars";
        isnt $rev->body_length, bytes::length($content), "length isn't bytes";
    }

    is exception { $rev->store() }, undef, "stored!";
    ok !$rev->mutable, "rev is immutable";

    like exception { $rev->store() }, qr/isn't mutable/,
        "can't store immutable rev";

    is $rev->revision_num, 1, "first revision";
    ok $rev->revision_id, "has a revision_id";
    ok $rev->has_body_ref, "has the body_ref still";
    is ${$rev->body_ref}, $content, "body is OK";

    $rev->clear_body_ref;
    ok $rev->has_body_length, "body length sticks around";
    is ${$rev->body_ref}, $content, "body lazy-loaded from db";

    # simulate an odd case where the body_length isn't set
    is exception {
        $rev->clear_body_ref;
        $rev->clear_body_length;
    }, undef, "ok clearing body ref and length";

    ok $rev->body_length, "body length call first";
    ok $rev->has_body_ref, "... sets the body ref too";
    is ${$rev->body_ref}, $content, "body loaded correctly from db";
}

clone_to_edit: {
    my $rev = Socialtext::PageRevision->Blank(
        hub => $hub, name => "My Pet Cat");
    $rev->body_ref(\'My Pet Cat is teh awesome');
    $rev->store();
    isa_ok $rev, 'Socialtext::PageRevision';
    ok !$rev->mutable;

    my $next = $rev->mutable_clone();
    ok $next->mutable;
    is $next->revision_num, $rev->revision_num+1, "revision_num incremented";
    ok !$next->has_body_ref, "body not automatically cloned";

    like exception { $next->mutable_clone() },
        qr/PageRevision is already mutable/, "can't clone a mutable copy";

    is exception { $next->store() }, undef,
        "stored revision without modifying body";
    ok !$next->mutable, "made immutable after store";
    is ${$next->body_ref}, 'My Pet Cat is teh awesome', "cloned body";
    ok $next->revision_id, "got assigned a revision_id";

    $next = $next->mutable_clone(copy_body => 1);
    ok $next->mutable;
    ok $next->has_body_ref;
    ok $next->body_modified, "body starts out as modified";
    is ${$next->body_ref}, 'My Pet Cat is teh awesome', "cloned body";
    ok !$next->revision_id, "no revision_id on the clone";
    is exception { $next->store() }, undef, "stored revision";
    ok !$next->mutable, "made immutable after store";
    ok $next->revision_id, "got assigned a revision_id";

    $next = $next->mutable_clone();
    ok $next->mutable;
    $next->body_ref(\'My Pet Cat is teh suck.');
    ok $next->body_modified, "body was modified";
    ok !$next->revision_id, "no revision_id on the clone";
    is exception { $next->store() }, undef, "stored revision";
    ok !$next->mutable, "made immutable after store";
    ok $next->revision_id, "got assigned a revision_id";
    $next->clear_body_ref();
    is ${$next->body_ref}, 'My Pet Cat is teh suck.',
        "updated body lazy-loaded";
}

restore: {
    my $rev = Socialtext::PageRevision->Blank(
        hub => $hub, name => "My Pet Turtle");
    $rev->body_ref(\'My Pet Turtle is really quite nice');
    $rev->store();
    isa_ok $rev, 'Socialtext::PageRevision';
    ok !$rev->mutable;

    my $next = $rev->mutable_clone();
    $next->body_ref(\'My Pet Turtle is a jackass');
    $next->store();

    is exception {
        my $restore = $rev->mutable_clone();
        $restore->revision_num(1);
        $restore->store();
    }, undef, "can change the revision_num of an old revision if mutable";
}

bad_name: {
    my $rev = Socialtext::PageRevision->Blank(
        hub => $hub, name => "My Pet Gerbil");
    $rev->body_ref(\'My Pet Gerbil is omnomnom');
    $rev->store();

    my $next = $rev->mutable_clone();
    like exception {
        $next->name("My Pet Snake");
        $next->store();
    }, qr/\QCannot change page name: requires a different page_id/,
        "can't make name changes that result in a different id";

    $next = $rev->mutable_clone();
    is exception {
        $next->name("MY PET GERBIL"); # same id
        $next->store();
    }, undef, "case changes are OK";
}

tags: {
    my $rev = Socialtext::PageRevision->Blank(
        hub => $hub, name => "Animal or Not");

    $rev->add_tags("First");
    $rev->add_tags("ANIMUL");
    $rev->add_tags("❤");
    $rev->add_tags("animul");
    $rev->add_tags("Étienne");
    $rev->add_tags("stephen");
    # simulate un-decoded data from a ReST API
    $rev->add_tags(Encode::encode_utf8("étienne"));

    is_deeply $rev->tags, [qw(First ANIMUL ❤ Étienne stephen)],
        "first tag with this casing wins";

    $rev->delete_tags("AniMul",Encode::encode_utf8("ÉTIENNE"),"stephen");
    is_deeply $rev->tags, [qw(First ❤)], "after delete";

    my $rev = Socialtext::PageRevision->Blank(
        hub => $hub, name => "Sweedish", tags => ['eeer']);
    is_deeply $rev->tags, ['eeer'];
    $rev->tags([qw(bork BoRk bOrK)]);
    is_deeply $rev->tags, ['bork'], "setting tags de-dupes, but only from new";

    my $created = Socialtext::PageRevision->Blank(
        hub => $hub, name => "Animal or Not",
        tags => ['A','a','ä',Encode::encode_utf8('Ä')],
    );
    is_deeply $created->tags, ['A','ä'], "created de-duped tags";
}

tag_revs: {
    my $rev = Socialtext::PageRevision->Blank(
        hub => $hub, name => "Tag Revisions");
    $rev->tags(["foobar"]);
    $rev->store();

    my $edit = $rev->mutable_clone();
    $edit->add_tag("bleh");
    is_deeply $edit->tags, ['foobar','bleh'], "new tags";
    is_deeply $rev->tags, ['foobar'], "orig tags unmodified";
}

body_edit: {
    my $rev = Socialtext::PageRevision->Blank(
        hub => $hub, name => "Content Test");
    $rev->body_ref(\"initial");
    $rev->store();

    my $edit = $rev->mutable_clone();
    ok !$edit->has_body_ref;
    is ${$edit->body_ref}, "initial", "content gets lazy-copied";
    $edit->store();

}

body_is_utf8: {
    my $rev = Socialtext::PageRevision->Blank(
        hub => $hub, name => "Content Test");

    like exception {
        my $non_const = "oh \xdamnit";
        $rev->body_ref(\$non_const);
    }, qr/is not encoded as valid utf8/, "invalid utf8 barfs";

    like exception {
        $rev->body_ref(\"oh \xdamnit"); # ref to a string constant
    }, qr/is not encoded as valid utf8/, "invalid utf8 barfs on const";
}

pass "done";
