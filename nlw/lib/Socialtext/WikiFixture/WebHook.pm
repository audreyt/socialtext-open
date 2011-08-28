package Socialtext::WikiFixture::WebHook;
# @COPYRIGHT@
use Socialtext::AppConfig;
use Socialtext::System qw/shell_run/;
use Socialtext::File qw/get_contents_utf8/;
use Socialtext::JSON qw/decode_json/;
use Test::More;
use Moose;

extends 'Socialtext::WikiFixture::SocialRest';

after 'init' => sub {
    shell_run('nlwctl -c stop');
};

sub webhook_file { Socialtext::AppConfig->data_root_dir . '/webhooks.txt' }

sub clear_webhook {
    my $self = shift;
    unlink $self->webhook_file;
}

sub _get_webhook_contents {
    my $self = shift;
    if (-f $self->webhook_file) {
        return get_contents_utf8($self->webhook_file);
    }
    return '';
}

sub webhook_like {
    my $self = shift;
    my $expected = shift;

    my $contents = $self->_get_webhook_contents;
    like $contents, qr/$expected/, 'webhook contents';
}

sub webhook_unlike {
    my $self = shift;
    my $expected = shift;

    my $contents = $self->_get_webhook_contents;
    unlike $contents, qr/$expected/, 'webhook contents';
}

sub webhook_payload_parse {
    my $self = shift;
    my $contents = $self->_get_webhook_contents;
    unless ($contents) {
        fail "No webhook was received, can't parse contents!";
        return;
    }
    $contents =~ s/^URI:.+$//m;
    my $json = decode_json($contents);
    ok $self->{json} = $json, "JSON parsed";
}

around 'st_process_jobs' => sub {
    my $orig = shift;
    my $self = shift;

    local $ENV{ST_WEBHOOK_TO_FILE} = $self->webhook_file;
    return $self->$orig(@_);
};

sub new_webhook_testcase {
    my $self = shift;

    $self->st_clear_jobs;
    $self->clear_webhook;
    $self->clear_webhooks;

    $self->comment(@_);
};

1;
