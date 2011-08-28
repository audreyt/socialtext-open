# @COPYRIGHT@
package Socialtext::Statistic::HeapDelta;
use warnings;
use strict;

use base 'Socialtext::Statistic';

sub new {
    my $class = shift;

    my $new_obj = $class->SUPER::new(@_);

    $new_obj->{pid} = $$;
    $new_obj->_check_size;

    return $new_obj;
}

sub note_delta {
    my $self = shift;

    if ($self->{pid} == $$) {
        my $size0 = $self->{heap_size};
        $self->_check_size;
        $self->observe($self->{heap_size} - $size0);
    } else {
        $self->{pid} = $$;
        $self->_check_size;
    }
}

sub _check_size {
    my $self = shift;

    # Return silently if the file's not there.
    open my $status_fh, '<', $self->_status_file or return;
    while (<$status_fh>) {
        $self->{heap_size} = $1
            if /^VmData:.*(\d+) kB/;
    }
    close $status_fh;
}

sub _status_file { "/proc/$_[0]->{pid}/status" }

1;

__END__

=head1 DESCRIPTION

Socialtext::Statistic::HeapDelta - Measure change in process heap size.

=head1 OBJECT METHODS

=over 4

=item $stat->note_delta();

=back

=head1 BUGS

Only works on Linux with procfs.

=head1 SEE ALSO

L<Socialtext::Statistic>, L<proc(5)>
