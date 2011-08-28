#!perl
# @COPYRIGHT@

use strict;
use warnings;

use Test::Live fixtures => ['admin'];
use Test::More;

plan tests => 4;

my $TMP_FILE = "/tmp/login-message." . $< . $$;
my $message = "<p>Monkey, <strong>What do you want!?</strong></p>";
_make_message_file($message, $TMP_FILE);

my $tester = Test::Live->new;
$tester->dont_log_in(1);

$tester->mech->get($tester->base_url . '/nlw/login.html');
like ($tester->mech->content, qr{Log in to Socialtext}, 'we see the login message');
unlike ($tester->mech->content, qr{Monkey}, 'no monkeys seen');

# reset the config and hup the apache-perl server
$ENV{NLW_APPCONFIG} = "login_message_file=$TMP_FILE";
#system("st-config set login_message_file $TMP_FILE");
#$tester->apache_perl->hup();
$tester->apache_perl->stop();
$tester->apache_perl->start();
$tester->mech->get($tester->base_url . '/nlw/login.html');
like ($tester->mech->content, qr{Log in to Socialtext}, 'we see the login message again');
like ($tester->mech->content, qr{Monkey}, 'we see monkeys');

sub _make_message_file {
    my $message = shift;
    my $file = shift;

    open my $fh, ">$file" || die "unable to write to $file\n";
    print $fh $message . "\n";
    close $fh;
}

