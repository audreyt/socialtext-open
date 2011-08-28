# @COPYRIGHT@
package Socialtext::WikiFixture::EmailJob;
use Socialtext::AppConfig;
use Socialtext::System qw/shell_run/;
use Socialtext::File qw/get_contents_utf8/;
use Test::More;
use Moose;

extends 'Socialtext::WikiFixture::SocialRest';

after 'init' => sub {
    shell_run('nlwctl -c stop');
};

sub email_file { Socialtext::AppConfig->data_root_dir . '/emails.txt' }

sub clear_email {
    my $self = shift;
    unlink $self->email_file;
}

sub _get_email_contents {
    my $self = shift;
    my $contents = '__NO CONTENT!__';
    if (-f $self->email_file) {
        $contents = get_contents_utf8($self->email_file);
    }
    return $contents;
}

sub email_like {
    my $self = shift;
    my $expected = $self->quote_as_regex(shift);

    my $contents = $self->_get_email_contents;
    like $contents, $expected, 'email contents';
}

sub email_unlike {
    my $self = shift;
    my $expected = $self->quote_as_regex(shift);

    my $contents = $self->_get_email_contents;
    unlike $contents, $expected, 'email contents';
}


around 'st_process_jobs' => sub {
    my $orig = shift;
    my $self = shift;

    local $ENV{ST_EMAIL_TO_FILE} = $self->email_file;
    return $self->$orig(@_);
};

1;
