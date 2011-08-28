package Socialtext;
# @COPYRIGHT@
use strict;
use warnings;

use base 'Socialtext::Base';

use Class::Field qw( const field );
use Socialtext::AppConfig;
use Socialtext::Statistics qw( stat_call );
use DateTime;
# use POSIX;
use Readonly;
use Carp;
use Socialtext::Authz;
use Socialtext::Permission 'ST_READ_PERM';
use Socialtext::Validate qw( validate SCALAR_TYPE USER_TYPE WORKSPACE_TYPE );

our $VERSION = '4.7.4.28';

const product_version => $VERSION;
field using_debug => 0;
field 'hub';

sub process {
    my $self = shift;
    stat_call(nlw_process_et => 'tic');

    $self->debug if Socialtext::AppConfig->debug();

    $self->load_hub(@_);
    $self->hub->registry->load;
    $self->check_uid;
    $self->check_user_authorization;

    my $html = $self->hub->process;

    stat_call(nlw_process_et => 'toc');
    stat_call(heap_delta => 'note_delta');

    return $html;
}

sub load_hub {
    my $self = shift;
    return $self->hub
      if $self->hub;

    $self->hub($self->new_hub(@_));
}

{
    Readonly my $spec => {
        current_workspace => WORKSPACE_TYPE,
        current_user      => USER_TYPE,
    };

    sub new_hub {
        my $self = shift;
        my %p = validate( @_, $spec );

        # XXX - loading these when Socialtext.pm is loaded causes
        # massive errors, seemingly related to functions not being
        # exported to classes that expect them.
        require Socialtext::Hub
            unless Socialtext::Hub->can('new');

        my $hub = Socialtext::Hub->new(%p);

        $hub->init;
        $hub->main($self);

        $self->hub($hub);
        $self->init;

        return $hub;
    }
}

sub debug {
    my $self = shift;

    $self->using_debug(1);
    return $self;
}

sub check_user_authorization {
    my $self = shift;
    my $ws = $self->hub->current_workspace;
    return unless $ws;

    return if
        $self->hub->authz->user_has_permission_for_workspace(
            user       => $self->hub->current_user,
            permission => ST_READ_PERM,
            workspace  => $self->hub->current_workspace,
        );

    my $error_type = 'unauthorized_workspace';
    if ( $self->hub->current_user->is_guest
        and !$self->hub->checker->check_permission('read') ) {
        $error_type = 'not_logged_in';
    }

    $self->hub->authz_error( error_type => $error_type );
}

sub check_uid {
    my $self = shift;
    my $uid = (stat Socialtext::AppConfig->data_root_dir() )[4];
    unless ($uid == $>) {
        my $effective = getpwuid($>);
        my $owned = getpwuid($uid);

        die "This script must be run as $owned, not $effective";
    }
}

sub status_message {
    my $self = shift;
    return $self->{status_message} if defined $self->{status_message} and !@_;
    return $self->{status_message} = shift if @_;

    my $file = Socialtext::AppConfig->status_message_file;

    return
        $self->{status_message} = $file && -f $file
            ? Socialtext::File::get_contents_utf8($file)
            : undef;
}

sub version_tag {
    my $self = shift;
    return 'Socialtext v' .  $self->product_version;
}

sub version_paragraph {
    my $self = shift;
    my $this_year = DateTime->now->year;    
    return join '', map { "$_\n" } (
        $self->version_tag,
        "Copyright 2004-$this_year Socialtext, Inc.",
    );
}

1;
