package Socialtext::User;
# @COPYRIGHT@
use strict;
use warnings;
use base 'Socialtext::MockBase';
use Socialtext::Workspace;
use unmocked 'Socialtext::MultiCursor';
use unmocked 'Socialtext::Exceptions', qw/data_validation_error/;
use unmocked 'Socialtext::Account';

our $WORKSPACES = [ [ 1 ] ];
our %CAN_USE_PLUGIN = ();

# Copied from the real UserSet.pm
use constant USER_END => 0x10000000;

our %Users;

sub new {
    my $class = shift;
    my $type = shift;
    my $value = shift || '';
    if (defined $type) {
        if ($type eq 'username') {
            return undef if $value =~ m/^bad/;
            if (exists $Users{$value} and !@_) {
                # warn "RETURNING cached user for $value";
                return $Users{$value};
            }
        }
        elsif ($type eq 'user_id') {
            return undef if $value =~ m/^\d+$/ and $value >= USER_END;
            if (exists $Users{$value}) {
                # warn "RETURNING cached user for $value";
                return $Users{$value};
            }
        }
    }
    return $class->_new( $type ? ($type => $value) : (), @_ );
}

sub _new {
    my $class = shift;
    my $self = { @_ };
    bless $self, $class;
    return $self;
}

sub create { 
    my $class = shift;
    my %opts = @_;

    unless ($opts{email_address} =~ m/@/) {
        data_validation_error(
            errors => ["$opts{email_address} is not a valid email address"]);
    }
    if ($opts{email_address} =~ m/^duplicate/) {
        data_validation_error(
            errors => ["The email address you provided ($opts{email_address}) "
                      . "is already in use."],
        );
    }
    if (exists $opts{password} and length($opts{password}) < 6) {
        die "Passwords must be at least 6 characters long.\n";
    }

    return Socialtext::MockBase::new($class, %opts);
}

sub confirm_email_address {}

sub confirmation_uri { 'blah/nlw/submit/confirm/foo' }

sub FormattedEmail { 'One Loser <one@foo.bar>' }

sub guess_real_name { 
    my $self = shift;
    return $self->first_name . ' ' . $self->last_name;
}

sub guess_sortable_name { 
    my $self = shift;
    return $self->last_name . ' ' . $self->first_name;
}

sub best_full_name { 'Best FullName' }
sub first_name { $_[0]->{first_name} ||= 'Mocked First' }
sub middle_name { $_[0]->{middle_name} ||= 'Mocked Middle' }
sub last_name { $_[0]->{last_name} ||= 'Mocked Last' }

sub is_authenticated { ! $_[0]->is_guest() }

sub is_guest { $_[0]->{is_guest} || 0 }
sub is_business_admin { $_[0]->{is_business_admin} || 0 }

sub is_profile_hidden { $_[0]->{is_profile_hidden} || 0 }

sub is_deactivated { $_[0]->{is_deactivated} || 0 }
sub is_system_created { $_[0]->{is_system_created} || 0 }
sub reactivate { $_[0]->{is_deactivated} = 0 }

sub user_id { $_[0]->{user_id} || 1 }
sub user_set_id { $_[0]->user_id }

sub username { $_[0]->{username} || 'oneusername' }
sub password { $_[0]->{password} || 'default-pass' }
sub password_is_correct {
    my $self = shift;
    return ($self->{password} || '') eq shift;
}

sub can_update_store { 1 }
sub update_store {
    my $self = shift;
    my %args = @_;
    $self->{$_} = $args{$_} for keys %args;
}

sub default_role { 
    return Socialtext::Role->AuthenticatedUser();
}

sub email_address { $_[0]->{email_address} ||= 'one@foo.bar' }
sub masked_email_address {
    my $self = shift;
    return $self->MaskEmailAddress($self->email_address);
}

sub workspaces {
    return Socialtext::MultiCursor->new(
        iterables => [ $WORKSPACES ],
        apply => sub { 
            my $row = shift;
            return Socialtext::Workspace->new( workspace_id => $row->[0]);
        },
    );
}

sub Resolve {
    my $class = shift;
    my $user_id = shift;
    my $user = Socialtext::User->new(user_id => $user_id);
    unless ($user) {
        die "Couldn't find user $user_id";
    }
    return $user;
}

our %Sent_email;
sub send_confirmation_email {
    my $self = shift;
    $Sent_email{$self->{username}} = 1;
}

sub has_valid_password {
    my $self = shift;
    return $self->{password};
}

sub ValidatePassword {
    my ($class, undef, $pass) = @_;
    if ( length($pass) < 6 ) {
        return "Passwords must be at least 6 characters long.";
    }
    return;
}

our $MASK_EMAILS = 0;
sub MaskEmailAddress {
    my ($class, $addr, $ws) = @_;
    $addr =~ s/@.+$/\@masked/ if $MASK_EMAILS;
    return $addr;
}

sub primary_account {
    my $self = shift;
    $self->{primary_account} ||= Socialtext::Account->Default;
    return $self->{primary_account};
}
sub primary_account_id { 
    my $self = shift;
    $self->primary_account->account_id 
}

sub can_use_plugin {
    my ($self, $plugin) = @_;
    return exists $CAN_USE_PLUGIN{$plugin} ? $CAN_USE_PLUGIN{$plugin} : 1;
}

sub profile_is_visible_to { 1 }

sub clear_profile { }

sub avatar_is_visible { 1 }

sub Guest {
    return shift->new( username => 'guest' );
}

sub accounts {
    my $self = shift;

    my @accounts = @{ $self->{accounts} || [] };
    return wantarray ? @accounts : \@accounts;
}

sub SystemUser {
    return shift->new( username => 'system-user' );
}

sub display_name {
    return join ' ', grep defined, @{$_[0]}{qw[ first_name last_name ]};
}


1;
