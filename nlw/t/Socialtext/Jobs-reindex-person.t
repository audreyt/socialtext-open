#!/usr/bin/env perl
# @COPYRIGHT@
use strict;
use warnings;
use Test::Socialtext tests => 24;
use Test::Socialtext::Fatal;
use Socialtext::Cache ();

fixtures('db', 'foobar');

BEGIN {
    use_ok 'Socialtext::Jobs';
    use_ok 'Socialtext::JobCreator';
    use_ok 'Socialtext::People::Profile';
    use_ok 'Socialtext::People::Fields';
}

my $hub = new_hub('foobar', 'system-user');
ok $hub, "loaded hub";
my $foobar = $hub->current_workspace;
ok $foobar, "loaded foobar workspace";

my $jobs = Socialtext::Jobs->instance;
ok !exception {
     $jobs->clear_jobs();
}, "can clear jobs";

my $acct = create_test_account_bypassing_factory();

my $fields = Socialtext::People::Fields->new(account_id => $acct->account_id);
$fields->add_stock_fields();
my $field = $fields->create_field({field_class => 'relationship', name => "field$^T", title => "Field $^T"});
isa_ok $field, 'Socialtext::People::Field';
ok $field->is_relationship, "field is a relationship field";

my $user_a = create_test_user(account => $acct);
my $prof_a = Socialtext::People::Profile->GetProfile($user_a);
ok $prof_a, "got a profile for the primary user";
my $user_b = create_test_user(account => $acct);
my $user_c = create_test_user(account => $acct);
ok !exception {
    $prof_a->set_reln('assistant', $user_b);
    $prof_a->set_reln($field->name, $user_c);
    $prof_a->save();
}, "set custom field and assistant";

direct: {
    Socialtext::Cache->clear;
    ok !exception { Socialtext::Jobs->clear_jobs() }, 'cleared out all jobs';

    is scalar(Socialtext::JobCreator->list_jobs( funcname => 'Socialtext::Job::PersonIndex' )), 0;

    ok(Socialtext::JobCreator->index_person($user_a, name_is_changing => 1), "index job sent");

    my @jobs = Socialtext::JobCreator->list_jobs( funcname => 'Socialtext::Job::PersonIndex' );
    is scalar(@jobs), 3, "extra jobs inserted";
    isnt $jobs[0]->coalesce, $jobs[1]->coalesce, "different coalesce keys, 0 & 1";
    isnt $jobs[0]->coalesce, $jobs[2]->coalesce, "different coalesce keys, 0 & 2";
    isnt $jobs[1]->coalesce, $jobs[2]->coalesce, "different coalesce keys, 1 & 2";
}

indirect: {
    Socialtext::Cache->clear;
    ok !exception { Socialtext::Jobs->clear_jobs() }, 'cleared out all jobs';
    is scalar(Socialtext::JobCreator->list_jobs( funcname => 'Socialtext::Job::PersonIndex' )), 0;

    $user_a->update_store(first_name => "An", last_name => "User");

    my @jobs = Socialtext::JobCreator->list_jobs( funcname => 'Socialtext::Job::PersonIndex' );
    is scalar(@jobs), 3, "extra jobs inserted";
    isnt $jobs[0]->coalesce, $jobs[1]->coalesce, "different coalesce keys, 0 & 1";
    isnt $jobs[0]->coalesce, $jobs[2]->coalesce, "different coalesce keys, 0 & 2";
    isnt $jobs[1]->coalesce, $jobs[2]->coalesce, "different coalesce keys, 1 & 2";
}
