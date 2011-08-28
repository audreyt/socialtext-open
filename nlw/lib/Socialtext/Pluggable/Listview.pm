package Socialtext::Pluggable::Listview;
# @COPYRIGHT@
use strict;
use warnings;
use Socialtext::Exceptions;
use Socialtext::Pageset;
use Socialtext::String;
use Socialtext::SearchPlugin;
use Socialtext::l10n qw(loc);

sub _prepare_listview {
    my $self = shift;
    my $is_search = shift;

    my %cgi_vars = $self->cgi_vars;
    my $user = $self->user;
    my $plugin_name = $self->name;

    eval { $self->_check_user($user) };
    $self->redirect('/') if $@;

    my ($accounts,$acct_group_set,$group_count) =
        $user->accounts_and_groups(plugin => $plugin_name);
    my %acct_set = map { $_->account_id => 1 } @$accounts;

    Socialtext::Exception::Auth->throw(
        loc("error.no-account-with=plugin", $plugin_name)."\n")
        unless @$accounts;

    my ($account_id, $all_accounts, $group_id);
    if ($cgi_vars{account_id}) {
        if ($cgi_vars{account_id} ne 'all') {
            $account_id = $cgi_vars{account_id};
        }
        else {
            $account_id   = 'all';
            $all_accounts = 1;
        }
    }
    elsif ($cgi_vars{group_id}) {
        $account_id = 'all';
        $all_accounts = 1;
        $group_id = $cgi_vars{group_id};
    }
    else {
        if ($cgi_vars{search_term}) {
            $account_id = 'all';
            $all_accounts = 1;
        }
        else {
            $account_id = $user->primary_account_id;
            if (!$acct_set{$account_id}) {
                # pick some account
                $account_id = $accounts->[0]->account_id;
            }
        }
    }

    Socialtext::Exception::Auth->throw(loc("error.account-forbidden")."\n")
        unless ($account_id eq 'all' || $acct_set{$account_id});

    my $sortby = $self->_calc_sortby($is_search, \%cgi_vars);;
    my $tag = delete $cgi_vars{tag};
    my $pageset = Socialtext::Pageset->new(
        cgi => {$self->cgi_vars},
        page_size => 20,
        max_page_size => 50,
    );

    my $direction = $cgi_vars{direction}
        || Socialtext::SearchPlugin->sortdir->{$sortby};

    my @list_args = (
        sort => $sortby,
        order => $sortby,
        viewer => $user,
        limit => $pageset->limit,
        offset => $pageset->offset,
        direction => $direction,
    );
    push @list_args, tag => $tag if $tag;
    push @list_args, account_id => $account_id unless $all_accounts;
    push @list_args, group_id => $group_id if $group_id;

    my $title = $self->_calc_title($tag, $cgi_vars{search_term});
    my @common = (
        unescaped_search_term => $cgi_vars{search_term},
        search_term => Socialtext::String::uri_escape($cgi_vars{search_term}),
        html_escaped_search_term =>
            Socialtext::String::html_escape($cgi_vars{search_term}),
        account_id => $account_id,
        group_id => $group_id, #maybe need name?
    );

    my @template_args = (
        viewer => $user,
        tag => $tag,
        title => $title,
        display_title => $title,
        sortby => $sortby,
        accounts => $accounts,
        account_groups => $acct_group_set,
        direction => $direction,
        @common,
    );

    my %other_args = (
        all_accounts => $all_accounts,
        pageset      => $pageset,
        acct_set     => \%acct_set,
        tag          => $tag,
        scope => $cgi_vars{scope} || '_',
        @common,
    );

    return (\@list_args, \@template_args, \%other_args);
}

sub _default_sort { 'relevance' }

sub _store_and_get_search_sort_order {
    my $self = shift;
    my %cgivars = $self->cgi_vars;
    my $cgi_sortby = $cgivars{sortby};

    if ($cgi_sortby) {
        $self->set_user_prefs(sortby => $cgi_sortby);
        return $cgi_sortby;
    }
    else {
        my $savedorder = $self->get_user_prefs->{sortby};
        return $savedorder || _default_sort();
    }
}

1;

__END__

=head1 NAME

Socialtext::Pluggable::Listview - Base class for pluggable plugins that produce list views.

=head1 SYNOPSIS

  See Socialtext::Pluggable::Plugin::Signals for usage

=head1 DESCRIPTION

Nothing fancing just refactored code here.

=cut
