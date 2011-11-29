#!/usr/bin/env perl
use strict;
use warnings;

use Test::Socialtext;
use Test::More;
use Test::Warn;

use YAML qw(LoadFile);
use File::Temp qw(tempdir);
use Socialtext::Pluggable::Adapter;
use Socialtext::User;
use Socialtext::Upload;
use Socialtext::Signal;
use Socialtext::Signal::Attachment;

fixtures(qw(db clean));

my $account = create_test_account_bypassing_factory();
my $user = create_test_user(account => $account);
my ($signal,$upload);

write_signal: {
    my $filename = 'README';
    die "Can't find $filename" unless -e $filename;

    $upload = Socialtext::Upload->Create(
        creator => $user,
        filename => $filename,
        temp_filename => $filename,
    );
    ok $upload, 'created upload';

    $signal = Socialtext::Signal->Create(
        body => 'Remember, really read the readme.',
        user_id => $user->user_id,
        attachments => [
            Socialtext::Signal::Attachment->new(
                upload => $upload,
                attachment_id => $upload->attachment_id,
                signal_id => 0,
            ),
        ],
    );
    ok $signal, 'created signal using upload';
    $signal->hide($user);
    ok $signal->is_hidden, 'signal is hidden';

}

missing_attachment_on_disk: {
    # we don't know exactly how this is happening, but it is.
    # see {bz: 5516}
    unlink $upload->disk_filename;
    ok !-e $upload->disk_filename, 'upload is not written to disk';

    my $hub = Socialtext::Pluggable::Adapter->new()->make_hub(
        Socialtext::User->SystemUser);
    my $account_yaml;

    my $export_dir = tempdir();
    warning_is {
        $account_yaml = $account->export(dir => $export_dir, hub => $hub);
    } undef, 'no warnings while exporting';

    ok -f $account_yaml, 'accounts.yaml file created';
    my $yaml = LoadFile($account_yaml);
    is scalar(@{$yaml->{signals}}), 1, 'exported one signal';

    my $attachments = $yaml->{signals}[0]{attachments};
    is scalar(@$attachments), 1, 'exported one attachment';

    my $file = $export_dir .'/attachments/'. $attachments->[0]{temp_filename};
    ok -f $file, 'attachment body exported';
}

done_testing;
exit;
