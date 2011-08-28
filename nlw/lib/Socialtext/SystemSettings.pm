package Socialtext::SystemSettings;
# @COPYRIGHT@
use strict;
use warnings;
use base 'Exporter';
use Socialtext::SQL qw/sql_singlevalue sql_execute sql_txn/;

our @EXPORT_OK = qw/exists_system_setting get_system_setting set_system_setting/;

# This hook allows settings to have custom code run when they're fetched
# from the database.
our %Get_setting_hooks = (
    'default-account' => \&default_account,
    'default-skin' => \&default_skin,
);

sub exists_system_setting {
    my $name = shift;
    my $value = sql_singlevalue(<<EOT, $name);
SELECT COUNT(*) FROM "System"
    WHERE field = ?
EOT
    return $value;
}

# The field may not exist, so we'll need to be careful.
sub get_system_setting {
    my $name = shift;

    my $value = sql_singlevalue(<<EOT, $name);
SELECT value FROM "System"
    WHERE field = ?
EOT

    if (my $hook = $Get_setting_hooks{$name}) {
        $value = $hook->($value);
    }
    return $value;
}

sub set_system_setting {
    my $name = shift;
    my $value = shift;

    sql_txn {
        sql_execute('DELETE FROM "System" WHERE field = ?', $name);
        sql_execute('INSERT INTO "System" VALUES (?,?)', $name, $value);
    };
}


sub default_account {
    my $value = shift;
    require Socialtext::Account;
    return Socialtext::Account->new(account_id => $value)
        || Socialtext::Account->Unknown;
}

sub default_skin {
    my $value = shift;
    my $default_default_skin = 's3';
    return $value || $default_default_skin;
}

1;
