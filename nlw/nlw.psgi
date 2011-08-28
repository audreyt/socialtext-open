#!/usr/bin/env perl
# @COPYRIGHT@
use 5.12.0;
use FindBin;
use lib "$ENV{ST_CURRENT}/nlw/lib";
use lib "$FindBin::Bin/lib";
use Socialtext::PlackApp 'PerlHandler';
use Plack::Builder;
use Plack::App::CGIBin;
use Socialtext::AppConfig;
use Path::Class;
use File::Basename;

builder {
    enable SizeLimit => (
        max_unshared_size_in_kb => '368640',
    );

    enable "ServerStatus::Lite" => (
        path => '/server-status',
        scoreboard => Socialtext::AppConfig->pid_file_dir,
        allow => [qw(127.0.0.1/8)],
    );

    enable XForwardedFor => (
        trust => [qw(127.0.0.1/8)],
    );

    # mount webplugins/
    my @webplugin_paths = glob(dir(
        Socialtext::AppConfig->data_root_dir,
        'webplugin',
        '*',
    ));
    for my $path ( @webplugin_paths ) {
        my $name = basename($path);
        next if $name eq 'cgi';

        mount "/webplugin/cgi/$name" => Plack::App::CGIBin->new(
            root => dir($path, 'cgi'),
            exec_cb => sub {
                ($_[0] =~ /\.cgi$/i)
                    or Plack::App::CGIBin->exec_cb_default(@_);
            },
        )->to_app if -d dir($path, 'cgi');

        mount "/webplugin/$name" => Plack::App::File->new(
            root => dir($path, 'static'),
        )->to_app if -d dir($path, 'static');
    }

    # Default handlers
    mount '/nlw/control' => PerlHandler(
        'Socialtext::Handler::ControlPanel',
        'Socialtext::AccessHandler::IsBusinessAdmin',
    ),
    mount '/nlw/ntlm' => PerlHandler(
        'Socialtext::Handler::NTLM',
        'Socialtext::Apache::Authen::NTLM',
    ),
    mount '/nlw' => PerlHandler('Socialtext::Handler::Authen'),
    mount '/' => PerlHandler('Socialtext::Handler::REST'),
};

