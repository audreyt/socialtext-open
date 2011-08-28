# @COPYRIGHT@
package Socialtext::Stax;
use strict;
use warnings;

use base 'Socialtext::Plugin';
use File::Spec;
use Socialtext::AppConfig;
use Socialtext::Helpers;
use YAML;

sub class_id { 'stax' }

sub hacks_info {
    my ($self) = @_;

    my $info = {
        paths => [],
        entries => [],
    };

    my $config_file =  File::Spec->catdir(  
        Socialtext::AppConfig->config_dir(),
        "stax",
        $self->hub->current_workspace->name . ".yaml"
    );

    return $info if not -f $config_file;

    my $config;
    eval { $config = YAML::LoadFile($config_file) };
    return $info if $@;

    return $info unless ref $config eq 'ARRAY';

    my $action = $self->hub->action;

    my $tags = $self->hub->pages->current->tags;

    for my $entry (@$config) {
        next unless defined $entry->{hack};
        if (not defined $entry->{action}) {
            if (defined $entry->{tag} || defined $entry->{'tag-match'}) {
                $entry->{action} = ['display'];
            }
            else {
                $entry->{action} = '*';
            }
        }
        if ($entry->{action} ne '*')  {
            $entry->{action} = [$entry->{action}]
                unless (ref($entry->{action}) eq 'ARRAY');
            next unless grep {$_ eq $action} @{$entry->{action}};
        }

        if ($action eq 'display') {
            if (defined $entry->{tag} || defined $entry->{'tag-match'}) {
                next unless @$tags;
                my $re;
                if (defined $entry->{tag}) {
                    $entry->{tag} = [$entry->{tag}]
                        unless (ref($entry->{tag}) eq 'ARRAY');
                    $re = eval('qr{^(' . join('|', @{$entry->{tag}}) . ')$}i');
                    next if $@;
                }
                else {
                    $re = eval('qr{' . $entry->{'tag-match'} . '}i');
                    next if $@;
                }
                next unless grep {
                    ($_ =~ $re)
                    ? do { $entry->{'tag-matched'} = $_; 1}
                    : 0
                } @$tags;
            }
        }

        push @{ $info->{paths} }, $entry->{staxBaseURI}
            ? join("/", $entry->{staxBaseURI}, $entry->{hack}, "stax.js" )
            : $entry->{webpluginURI} . join("/",
                $entry->{hack},
                "stax",
                "stax.js"
            );

        $entry->{useremail} = $self->hub->current_user->email_address;

        push @{$info->{entries}}, $entry;
    }

    return $info;
}

1;

