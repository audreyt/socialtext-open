package Socialtext::Annotations;

use Moose::Role;
use Socialtext::JSON qw/encode_json decode_json_utf8/;

has anno_blob => (is => 'rw', isa => 'Maybe[Str]', lazy_build => 1);

before 'anno_blob' => sub {
    my $self = shift;

    $self->_check_annotations(@_) if (@_);
};

sub annotations {
    my $self = shift;
    my $anno_blob = $self->anno_blob;
    return unless $anno_blob;
    return decode_json_utf8($anno_blob);
}

sub annotation_triplets {
    my $self = shift;

    my $annos = $self->annotations;
    my @triplets;
    for my $anno (@$annos) {
        for my $namespace (keys %$anno) {
            while (my ($key, $val) = each %{ $anno->{$namespace} }) {
                push @triplets, [$namespace => $key => $val];
            }
        }
    }
    return \@triplets;
}

sub _check_annotations {
    my $self = shift;
    my $anno_string = shift;
    my $max_length = shift;

    return unless defined $anno_string;

    my $annos = decode_json_utf8($anno_string);
    die "Annotation must be an array\n" unless ref($annos) eq 'ARRAY';
    for my $anno (@$annos) {
        while (my ($type, $keyvals) = each %$anno) {
            die "Annotation type cannot contain '|' character\n"
                if $type =~ m/\|/;
            die "Annotation types must hold HASHes\n"
                unless ref($keyvals) eq 'HASH';
            my @keys = keys %$keyvals;
            for my $key (@keys) {
                die "Annotation key cannot contain '|' character\n"
                    if $key =~ m/\|/;
                my $val = $anno->{$type}{$key};
                die "Annotation value must be a Scalar - (is: "
                    . ref($val) . ")\n" if ref($val);
            }
        }
    }

    if ($max_length) {
        my $len = length($anno_string);
        die "Annotation must be <= " . $max_length . " in size (is: $len)\n"
           if $len > $max_length;
    }
}

sub MergeAnnotations {
    my $current_annos = shift;
    my $new_annos = shift;
    foreach my $n_anno (@$new_annos) {
        while (my ($n_type, $n_keyvals) = each %$n_anno) {
            my $found = 0;
            foreach my $c_anno (@$current_annos) {
                while (my ($c_type, $c_keyvals) = each %$c_anno) {
                    if ($c_type eq $n_type) {
                        $found = 1;
                        %$c_keyvals = (%$c_keyvals, %$n_keyvals);
                        last;
                    }
                }
                last if $found;
            }

            if (!$found) {
                push @$current_annos, $n_anno;
            }
        }
    }

    RemoveNullAnnotations($current_annos);
}

sub RemoveNullAnnotations {
    my $annotations = shift;

    my $i = 0;
    while ($i < scalar (@$annotations)) {
        my $no_null = 1;
        my $anno = $annotations->[$i];
        if (0 == scalar(keys(%$anno))) {
            splice(@$annotations, $i, 1);
            $no_null = 0;
        }
        else {
            while (my ($type, $keyvals) = each %$anno) {
                if (0 == scalar(keys(%$keyvals)) or !defined($keyvals)) {
                    $no_null = 0;
                    delete $anno->{$type};
                }
                else {
                    while (my ($key, $value) = each %$keyvals) {
                        if (!defined($value)) {
                            delete $keyvals->{$key};
                            $no_null = 0;
                        }
                    }
                }
            }
        }
        $i++ if ($no_null);
    }
}

1;

__END__

=head1 NAME

Socialtext::Anotations - Annotation role for Socialtext objects

=head1 SYNOPSIS

A Moose role to add annotaion functionality to a class. Classes that use
the role will likely need to add a lazy builder for anno_blob to fetch
the value from storage.

=head1 DESCRIPTION

Moose role for Annotations. Supplies

* annotations
* annotation_triplets

methods. Annotations are stored as json in the anno_blob field which is parsed
as needed by annotations and annotation_triplets.

=head1 AUTHOR

Socialtext, C<< <code@socialtext.com> >>

=head1 COPYRIGHT & LICENSE

Copyright 2011 Socialtext, Inc. All Rights Reserved.

=cut
