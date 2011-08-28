package Socialtext::MassAdd;
# @COPYRIGHT@
use strict;
use warnings;
use Text::CSV_XS;
use Socialtext::Encode;
use Socialtext::Log qw(st_log);
use Socialtext::User;
use Socialtext::l10n qw/loc/;
use Socialtext::String;
use List::MoreUtils qw/mesh/;

our $Has_People_Installed;
our @Required_fields = qw/username email_address/;
our @User_fields = qw/first_name middle_name last_name password private_external_id/;

# Note: these fields may not be created, now that fields are treated
# differently.  Please do some poking around before you change these. (See:
# Socialtext::People::Fields).
our @Profile_fields
    = qw/position company location work_phone mobile_phone home_phone/;

our @All_fields = (@Required_fields, @User_fields, @Profile_fields);
our %Non_profile_fields = map {$_ => 1} (@Required_fields, @User_fields, 'account_id');

unless (defined $Has_People_Installed) {
    require Socialtext::Pluggable::Adapter;
    $Has_People_Installed = 
        Socialtext::Pluggable::Adapter->plugin_exists('people');
}

sub new {
    my $self = bless {}, shift;
    my %opts = @_;
    $self->{pass_cb} = delete $opts{pass_cb} or die "pass_cb is mandatory!";
    $self->{fail_cb} = delete $opts{fail_cb} or die "fail_cb is mandatory!";
    $self->{account} = delete $opts{account};
    $self->{restrictions} = delete $opts{restrictions};
    $self->{failed_fields} = {};
    return $self;
}

sub from_csv {
    my $self = shift;
    my $csv  = shift;

    # Guess encoding of CSV file; default is UTF-8, falls back to CP1252.
    $csv = Socialtext::Encode::guess_decode($csv);

    # convert the CSV from whatever EOL format it has to Unix-style EOL
    $csv =~ s/\r\n/\n/g;        # DOS/Windows -> Unix EOL
    $csv =~ s/\r/\n/g;          # Mac -> Unix EOL

    # create a CSV parser, and set up our parse state
    my $parser = Text::CSV_XS->new( { eol => "\n" } );
    $self->{line} = 0;
    $self->{from_csv} = 1;

    # split up the CSV data into individual _lines_ so that they can be parsed
    # individually.
    my @lines = split "\n", $csv;

    # parse the CSV data
    my $have_parsed_header = 0;
    my @header_fields;
LINE:
    for my $user_record (@lines) {
        $self->{line}++;

        # parse the next line, choking if its not valid.
        my $parsed_ok = $parser->parse($user_record);
        my @fields    = $parser->fields();

        unless ($parsed_ok) {
            unless ($have_parsed_header) {
                my $msg = loc("error.parse-csv-header");
                $self->_fail($msg);
                last LINE;
            }
            my $msg = loc("error.parse-failed");
            $self->_fail($msg);
            next LINE;
        }

        ### CSV header *must* be the first thing in the file
        unless ($have_parsed_header) {
            # lower-case all of the header fields; case INsensitive lookups
            @header_fields = map { _clean_csv_header($_) } @fields;
            my %available  = map { $_=>1 } @header_fields;

            # SANITY CHECK: do we have all the required fields?
            my @missing_fields = grep { !exists $available{$_} } @Required_fields;
            if (@missing_fields) {
                my $missing = join ', ', @missing_fields;
                my $msg = loc("error.parse-header-missing=fields", $missing);
                $self->_fail($msg);
                last LINE;
            }

            # header looks good...
            $have_parsed_header++;
            next LINE;
        }

        ### everything after the CSV header are User records

        if (scalar @fields < scalar @header_fields) {
            # user data is missing fields that were defined in the header
            my $msg = loc("error.parse-missing-fields");
            $self->_fail($msg);
            next LINE;
        }

        if (scalar @fields > scalar @header_fields) {
            # user data contains fields that were NOT defined in the header
            my $msg = loc("error.parse-extra-fields");
            $self->_fail($msg);
            next LINE;
        }

        # mesh: missing values still have keys (value is undef)
        $self->add_user(mesh(@header_fields, @fields));
    }

    # TODO: link relationship profile fields
    # $self->finish_up();
}

sub _clean_csv_header {
    my $header = shift;
    $header = lc Socialtext::String::trim($header);
    $header =~ s/\W+/_/g;   # non-word chars become underscores
    return $header;
}

sub add_user {
    my $self = shift;
    my %args = @_;

    return unless $self->_validate_args(\%args);

    # see if we've got an existing record for this user, and add/update as
    # necessary.
    my $changed_user = 0;
    my $added_user = 0;

    my $user = eval { Socialtext::User->new(username => $args{username}) };
    if ($user) {
        my $acct = $self->{account};
        # If an account is specified, add the user to that account if they are
        # not already a member.
        if ($acct && !$acct->has_user($user)) {
            $acct->add_user(user => $user);
            $changed_user++;
        }

        if ($user->is_deactivated) {
            $user->reactivate($acct ? (account_id => $acct->account_id) : ());
        }
    }
    else {
        $user = $self->_create_user(%args);
        return unless $user; # failed
        $added_user++;
    }

    if ($user->can_update_store) {
        $changed_user += $self->_update_user_store($user, %args);
    }

    if ($Has_People_Installed) {
        my @prof_args = map {$_ => $args{$_}} 
                        grep {!$Non_profile_fields{$_}} keys %args;
        $changed_user += $self->_update_profile($user, @prof_args)
            if @prof_args;
    }

    if ($self->{restrictions}) {
        foreach my $r (@{$self->{restrictions}}) {
            my $restriction = $user->add_restriction($r);
            $restriction->send;
            $changed_user++;
        }
    }

    if ($added_user) {
        my $msg = loc("user.added=name", $args{username});
        $self->_pass($msg);
    }
    elsif ($changed_user) {
        my $msg = loc("user.updated=name", $args{username});
        $self->_pass($msg);
    }
    else {
        my $msg = loc("user.no-changes=name", $args{username});
        $self->_pass($msg);
    }
}

sub _validate_args {
    my $self = shift;
    my $args = shift;

    my $f;
    for $f (@Required_fields, @User_fields) {
        $args->{$f} = '' unless defined $args->{$f};
    }

    # sanity check the parsed data, to make sure that fields we *know* are
    # required are really present
    for $f ('username','email_address') {
        next if $args->{$f};
        my $mfield = ($f eq 'email_address') ? 'email' : $f;
        my $msg = loc("error.field-required=name", $mfield);
        $self->_fail($msg);
        return;
    }

    if (length($args->{password})) {
        my $result
            = Socialtext::User->ValidatePassword(password => $args->{password});
        if ($result) {
            $self->_fail($result);
            return;
        }
    }

    return 1;
}

sub _create_user {
    my $self = shift;
    my %args = @_;
    my $user;
    eval {
        $user = Socialtext::User->create(
            username      => $args{username},
            email_address => $args{email_address},
            ($args{password} ? (password => $args{password}) : ()),
            first_name    => $args{first_name},
            last_name     => $args{last_name},
            ($self->{account} ? (primary_account_id => $self->{account}->account_id) : ()),
        );
    };
    my $err = $@;
    if (my $e = Exception::Class->caught('Socialtext::Exception::DataValidation')) {
        foreach my $m ($e->messages) {
            $self->_fail($m);
        }
        return;
    }
    elsif ($err) {
        $self->_fail($err);
        return;
    }

    # Send the user a confirmation email, if they don't have a pw
    unless ($user->has_valid_password) {
        $user->create_email_confirmation();
        $user->send_confirmation_email();
    }

    return $user;
}

sub _update_user_store {
    my $self = shift;
    my $user = shift;
    my %args = @_;

    # build a list of fields to update; only those fields that we were
    # actually given a value for *and* that are different are suitable for
    # update.
    my %update_slice;
    foreach my $f (@User_fields) {
        my $new_val = $args{$f};

        next unless (defined $new_val);    # skip missing fields
        next if (length($new_val) == 0);   # skip blank fields

        my $old_val = $user->$f();
        next if ($old_val && ($old_val eq $new_val));  # skip unchanged fields

        $update_slice{$f} = $new_val;
    }

    # SPECIAL CASE: password; have to call a fcn to check to see if its the
    # same as what we've got already.
    if ($user->password_is_correct($args{password})) {
        delete $update_slice{password};
    }

    # if we actually have stuff to update, update the User record.
    if (keys %update_slice) {
        $user->update_store(%update_slice);
        return 1;
    }
    return 0;
}

sub _update_profile {
    my $self = shift;
    my $user = shift;
    my %profile_args = @_;

    local $Socialtext::People::Fields::AutomaticStockFields = 1;

    require Socialtext::Pluggable::Adapter;
    my $people = Socialtext::Pluggable::Adapter->plugin_class('people');
    return 0 unless $people;

    my ($changed_user, $failed) = 
        $people->UpdateProfileFields($user => \%profile_args,
                                     {source => 'mass-add'});

    foreach my $field (@$failed) {
        next if ($self->{failed_fields}{$field});
        $self->{failed_fields}{$field} = 1;
        $self->_fail(loc('error.update-failed=field', $field));
    }

    return $changed_user ? 1 : 0;
}

sub _pass {
    my $self = shift;
    my $msg = shift;
    st_log->info($msg);
    $self->{pass_cb}->($msg);
}

sub _fail {
    my $self = shift;
    my $msg = shift;
    $msg = loc("error.at=line,message", $self->{line}, $msg)
        if ($self->{from_csv});
    st_log->error($msg);
    $self->{fail_cb}->($msg);
}

sub ProfileFieldsForAccount {
    my $class = shift;
    my $account = shift;
    require Socialtext::Pluggable::Adapter;
    my $people = Socialtext::Pluggable::Adapter->plugin_class('people');
    return unless $people;
    local $Socialtext::People::Fields::AutomaticStockFields = 1;
    return $people->FieldsForAccount($account);
}

1;
