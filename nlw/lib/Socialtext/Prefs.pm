package Socialtext::Prefs;
use Moose::Role;
use Try::Tiny;
use Socialtext::JSON qw(encode_json decode_json);
use Socialtext::SQL qw(sql_txn);

requires qw(_get_blob _get_inherited_prefs _update_db _update_objects);

has 'prefs' => (is => 'ro', isa => 'HashRef',
                lazy_build => 1, clearer => '_clear_prefs');
has 'all_prefs' => (is => 'ro', isa => 'HashRef',
                    lazy_build => 1, clearer =>'_clear_all_prefs');

around '_update_db' => \&sql_txn;

sub _build_prefs {
    my $self = shift;
    
    my $blob = $self->_get_blob;
    return {} unless $blob;

    my $prefs = eval { decode_json($blob) };
    if (my $e = $@) { 
        st_log->error("failed to load prefs blob: $e");
        return {};
    }

    return $prefs;
}

sub _build_all_prefs {
    my $self = shift;
    my $inherited_prefs = $self->_get_inherited_prefs();
    my $my_prefs = $self->prefs;

    return +{%$inherited_prefs, %$my_prefs};
}

sub save {
    my $self = shift;
    my $updates = shift;
    my $current = $self->prefs;

    my %prefs = clear_undef_indexes(%$current, %$updates);

    try {
        my $blob = eval { encode_json(\%prefs) };
        $self->_update_db($blob);
        $self->_update_objects($blob);
    }
    catch { die "saving account prefs: $_\n" };

    return 1;
}

sub parse_form_data { # parse data from ST::TimeZonePlugin generated form
    my $self = shift;
    my $data = shift;
    
    my $index = $data->{preferences_class_id};
    my $cut_length = length($index) + 2;

    # args are formatted as '${index}__${pref_name}'
    my %all = map { substr($_, $cut_length) => $data->{$_} }
        grep { $_ =~ /^\Q$index\E__/ }
        grep { $_ !~ /-boolean$/ }
        keys %$data;

    # for checkboxes, there's also an '${index}__${pref_name}-boolean' arg
    # in case the check box is not checked.
    my %bools = map {
        my $name = substr($_, 0, -8);
        substr($name, $cut_length) => $data->{$name}
            ? $data->{$name}
            : $data->{$_};

    } grep { $_ =~ /-boolean$/ } keys %$data;

    return +{$index => {%all, %bools}};
}

sub clear_undef_indexes {
    my %prefs = @_;

    return map { $_ => $prefs{$_} }
        grep { $prefs{$_} } keys %prefs;
}

1;

=head1 NAME

Socialtext::Prefs

=head1 SYNOPSIS

    package SomePrefs;
    use Moose;
    with 'Socialtext::Prefs';

    ...

=head1 DESCRIPTION

Role for Prefs objects. Responsible for taking a text blob and rendering it as
a JSON structure, or taking a JSON structure and transforming it back into a
text blob.

=cut
