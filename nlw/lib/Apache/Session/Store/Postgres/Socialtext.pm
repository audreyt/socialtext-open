# @COPYRIGHT@
package Apache::Session::Store::Postgres::Socialtext;

use strict;
use warnings;

use base 'Apache::Session::Store::Postgres';


sub connection {
    my $self = shift;

    $self->SUPER::connection(@_);

    $self->{insert_sth} =
        $self->{dbh}->prepare_cached(qq{
            INSERT INTO $self->{'table_name'} (id, a_session, last_updated) VALUES (?,?,CURRENT_TIMESTAMP)});

    $self->{update_sth} =
        $self->{dbh}->prepare_cached(qq{
            UPDATE $self->{'table_name'} SET a_session = ?, last_updated = CURRENT_TIMESTAMP WHERE id = ?});

    # no need to SELECT FOR UPDATE since the handle has AutoCommit on anyway
    $self->{materialize_sth} = 
        $self->{dbh}->prepare_cached(qq{
            SELECT a_session FROM $self->{'table_name'} WHERE id = ?});
}


1;

# XXX - should turn into a patch for Apache::Session (right, cwest?)
