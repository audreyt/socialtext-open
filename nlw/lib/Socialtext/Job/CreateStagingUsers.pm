package Socialtext::Job::CreateStagingUsers;
# @COPYRIGHT@
use Moose;
use Socialtext::Resting::Getopt qw/get_rester rester_usage/;
use Socialtext::File qw(get_contents);
use Socialtext::JSON qw(decode_json);
use Socialtext::SQL qw(sql_execute);
use Socialtext::People::Profile;
use Socialtext::Log qw/st_log/;
use Socialtext::Account;
use Socialtext::Signal;
use Socialtext::Group;
use Socialtext::User;
use Socialtext::Role;
use HTML::Entities;
use namespace::clean -except => 'meta';

extends 'Socialtext::Job';

sub do_work {
    my $self = shift;
    $self->create_socialtext_users;
    $self->create_socialtext_signals;
    $self->completed("Imported data from www2.socialtext.net");
}

has 'rester' => (
    is => 'ro', isa => 'Socialtext::Resting', lazy_build => 1,
);
sub _build_rester {
    my $r = get_rester(); # reads @ARGV and ~/.wikeditrc
    $r->server('https://www2.socialtext.net:443');
    $r->accept('perl_hash');
    return $r;
}

has 'account' => (
    is => 'ro', isa => 'Socialtext::Account', lazy_build => 1,
);
sub _build_account {
    my $self = shift;
    # Create a Socialtexters account and group
    my $account = Socialtext::Account->new( name => 'Socialtexters' )
               || Socialtext::Account->create( name => 'Socialtexters' );
    $account->enable_plugin('people');
    $account->enable_plugin('signals');
    return $account;
}

has 'group' => (
    is => 'ro', isa => 'Socialtext::Group', lazy_build => 1,
);
sub _build_group {
    my $self = shift;
    my $all_groups = Socialtext::Group->All();
    while (my $g = $all_groups->next) {
        return $g if $g->driver_group_name eq 'Socialtexters';
    }
    return Socialtext::Group->Create({
        driver_group_name => 'Socialtexters',
        created_by_user_id => Socialtext::User->SystemUser->user_id,
        primary_account_id => $self->account->account_id,
    });
}

has 'me' => (
    is => 'ro', isa => 'Socialtext::User', lazy_build => 1,
);
sub _build_me {
    my $self = shift;
    my $user = Socialtext::User->new(username => 'devnull1@socialtext.com');
    return Socialtext::People::Profile->GetProfile($user);
}

has 'people' => (
    is => 'ro', isa => 'ArrayRef', lazy_build => 1,
);
sub _build_people {
    my $self = shift;
    return $self->rester->get_people(
        fields => "first_name,last_name,email"
    );
}

has 'email_map' => (
    is => 'ro', isa => 'HashRef', lazy_build => 1,
);
sub _build_email_map {
    my $self = shift;
    return {
        map {
            # Convert emails into @ken.socialtext.net emails
            $_->{id} => $_->{email} eq $self->rester->username
                ? 'devnull1@socialtext.com'
                : ($_->{email} =~ m{^([^\@]+)})[0] . '@ken.socialtext.net';
        } grep { $_->{email} } @{$self->people}
    };
}

sub create_socialtext_users {
    my $self = shift;
    for my $person (@{$self->people}) {
        next unless $person->{last_name};

        my $email = $person->{email};
        my $role;
        if ($person->{email} eq $self->rester->username) {
            $email = 'devnull1@socialtext.com';
            $role = Socialtext::Role->new(name => 'admin');
        }
        else {
            $role = Socialtext::Role->new(name => 'member');
            $email =~ s{\@.*}{\@ken.socialtext.net};
        }

        st_log->debug("CREATESTAGINGUSERS: Creating user $email");

        my $user = Socialtext::User->new(username => $email)
           || Socialtext::User->create(
                  username => $email,
                  email_address => $email,
                  first_name => $person->{first_name},
                  last_name => $person->{last_name},
                  password => 'd3vnu11l',
              );

        # Add the new user to the socialtexters group and account
        $user->primary_account($self->account->account_id);
        $self->group->add_user(role => $role, user => $user)
            unless $self->group->has_user($user);

        # Set the profile image
        my $profile = Socialtext::People::Profile->GetProfile($user);
        $profile->first_name($person->{first_name});
        $profile->last_name($person->{last_name});

        my $img = $self->rester->get_profile_photo($person->{id});
        $profile->photo->set( \$img );
        $profile->save;

        eval { $self->me->modify_watchlist(watch_add => $user->user_id) };
    }
}

sub create_socialtext_signals {
    my $self = shift;

    sql_execute('DELETE FROM event');
    sql_execute('DELETE FROM signal');

    my $signals = $self->rester->get_signals(
        count => $self->arg->{count} || 300,
        direct => 'none',
    );
    @$signals = reverse @$signals;

    # Calculate and fetch missing reply_to signals
    st_log->debug("CREATESTAGINGUSERS: Determining missing staging signals");
    my %missing = map { $_->{in_reply_to}{signal_id} => 1 }
                  grep { $_->{in_reply_to} }
                  @$signals;
    delete $missing{$_->{signal_id}} for @$signals;

    if (%missing) {
        my ($status, $content) = $self->rester->_request(
            uri    => '/data/signals/' . join(',', sort keys %missing),
            method => 'GET',
            accept => 'application/json',
        );
        my $missing_signals = decode_json($content);
        unshift @$signals, @$missing_signals;
    }

    my %ids;
    st_log->debug("CREATESTAGINGUSERS: Creating staging signals");
    for my $www2_signal (@$signals) {
        my $email_map = $self->email_map;
        my $email = $email_map->{$www2_signal->{user_id}};
        my $user = Socialtext::User->Resolve($email) || next;
        my $body = HTML::Entities::decode_entities($www2_signal->{body});

        $body =~ s!<b>(.*?)</b>!*$1*!g;
        $body =~ s!<i>(.*?)</i>!_$1_!g;
        $body =~ s!#<a href="/\?action[^"]+">([^<]+)</a>!{hashtag: $1}!g;
        $body =~ s!<a href="/st/profile/(\d+)">[^<]+</a>!{user: $email_map->{$1}}!g;
        $body =~ s!<a href="/[^/]+/[^"]+">([^<]+)</a>!{link: admin \[$1\]}!g;
        $body =~ s!<a href="([^"]+)">([^<]+)</a>!"$2"<$1>!g;

        my %signal_opts = (
            account_ids => [ $self->account->account_id ],
            user_id => $user->user_id,
            body => $body,
            at => $www2_signal->{at},
        );

        if (my $www2_reply_to_id = $www2_signal->{in_reply_to}{signal_id}) {
            my $in_reply_to_id = $ids{$www2_reply_to_id};
            next unless $in_reply_to_id;
            $signal_opts{in_reply_to_id} = $in_reply_to_id;
        }
        
        my $new_signal = Socialtext::Signal->Create(%signal_opts);
        $ids{$www2_signal->{signal_id}} = $new_signal->signal_id;
    }
}

no Moose;
__PACKAGE__->meta->make_immutable(inline_constructor => 1);
1;

=head1 NAME

Socialtext::Job::Test::ImportStagingData - Add users and signals from staging

=head1 SYNOPSIS

    use Socialtext::JobCreator;

    Socialtext::JobCreator->insert(
        'Socialtext::Job::Test::ImportStagingData',
        {
            signal_count => $count, # Default is 300
        },
    );

=head1 DESCRIPTION

Schedule a job to be run by TheCeq which will update a widget from its source.

=cut
