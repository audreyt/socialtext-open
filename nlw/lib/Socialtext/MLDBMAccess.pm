# @COPYRIGHT@
package Socialtext::MLDBMAccess;
use strict;
use warnings;

use DB_File;
use Encode;
use Fcntl;
use MLDBM 'DB_File::Lock', 'Data::Dumper';
use Readonly;
use Socialtext::Validate qw( validate SCALAR_TYPE BOOLEAN_TYPE );


{
    Readonly my $spec => {
        filename => SCALAR_TYPE,
        writing  => BOOLEAN_TYPE( default => 0 ),
    };
    sub tied_hashref {
        my %p = validate( @_, $spec );
        my $flags = $p{writing} ? O_CREAT | O_RDWR : O_RDONLY;

        tie my %hash,
            'MLDBM',
            $p{filename},
            $flags,
            0644,
            $DB_HASH,
            ( $p{writing} ? 'write' : 'read' );

        my $db = tied %hash;

        $db->filter_fetch_key(sub { $_ = Encode::decode('utf8', $_) });
        $db->filter_store_key(sub { $_ = Encode::encode('utf8', $_) });
        $db->filter_fetch_value(sub { $_ = Encode::decode('utf8', $_) });
        $db->filter_store_value(sub { $_ = Encode::encode('utf8', $_) });

        return \%hash;
    }
}

sub _mldbm_object {
    return tied( %{ tied_hashref(@_) } );
}

sub mldbm_access {
    my ($db_filename, $key, $value) = @_;
    my $writing = @_ > 2;

    return undef if (! -e $db_filename && ! $writing);

    my $db = _mldbm_object(
        filename => $db_filename,
        writing  => $writing,
    );

    if ($writing) {
        if (! defined $value) {
            $db->DELETE($key);
            $value = undef;
        } else {
            $value = $db->STORE($key, $value);
        }
    } else {
        $value = $db->FETCH($key);
    }
    undef $db;
    return $value;
}

1;

