package Socialtext::CGI;
# @COPYRIGHT@
use strict;
use warnings;
use base 'Socialtext::MockBase';
use base 'Exporter';
use unmocked 'Data::Dumper';
use unmocked 'Class::Field', 'field';
our @EXPORT_OK = qw/cgi/;

field 'class';
field 'action';

our $QUERY = {};

sub class_id { 'cgi' }
sub full_uri { 'full_uri' }

sub query { return $_[0] }

sub query_string {
    return join ';', map { "$_=$QUERY->{$_}" } sort keys %$QUERY;
}

sub param {
    my ($self, $key) = @_;
    return $QUERY->{$key};
}

sub cgi {
    my $package = caller;
    my $field = shift;

    # NOTE: this getter is a *highly simplified* version of the real thing
    my $getter = sub { 
        my $value = $_[0]->{$field};
        # warn "Unknown value for CGI ($field)" unless defined $value;
        if (!defined $value and wantarray) {
            return ();
        }
        return $value;
    };

    {
        no strict 'refs';
        no warnings 'redefine';
        *{"$package\::$field"} = $getter;
    }
};

sub page_name { $_[0]->{page_name} }

sub all {}

sub init {}

1;
