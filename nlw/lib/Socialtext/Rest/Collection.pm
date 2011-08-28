package Socialtext::Rest::Collection;
# @COPYRIGHT@
use warnings;
use strict;
use base 'Socialtext::Rest';

use Socialtext::JSON;
use Socialtext::HTTP ':codes';
use Socialtext::Timer qw/time_scope/;
use Socialtext::AppConfig;
use Socialtext::TT2::Renderer;
use Socialtext::URI;
use Socialtext::Exceptions;
use Socialtext::Base;
use Socialtext::l10n;
use Socialtext::Log qw/st_log/;

=head1 NAME

Socialtext::Rest::Collection - Base class for exposing collections via REST.

=head1 SYNOPSIS

    package Socialtext::Rest::MyCollection;

    use base 'Socialtext::Rest::Collection';

    sub get_resource {
        # Returns a listref of collection elements, each of which should be a
        # hashref containing both 'name' and 'uri' elements.
    }

    sub add_text_element {
        # Given a text/plain representation of some proposed element in the
        # collection, adds it.
    }

=cut

=head1 REQUEST METHODS

=head2 POST_text

Calls add_text_element with the text/plain representation it was given.

=cut

sub POST_text {
    my ( $self, $rest ) = @_;

    return $self->no_workspace() unless $self->workspace;
    return $self->not_authorized() unless $self->user_can('edit');

    my $location = $self->add_text_element($rest->getContent);
    $rest->header( -status    => HTTP_201_Created,
                   -type      => 'text/plain',
                   -Location  => $location );
    return "Added.";
}

=head2 GET_html, GET_json, GET_atom, GET_text

Returns representations of your resource in text/html, application/json,
application/atom+xml and text/plain, respectively.

=cut

{
    no warnings 'once';
    *GET_html = _make_getter(resource_to_html => 'text/html');
    *GET_json = _make_getter(resource_to_json => 'application/json');
    *GET_atom = _make_getter(resource_to_atom => 'application/atom+xml');
    *GET_text = _make_getter(resource_to_text => 'text/plain');
    *GET_yaml = _make_getter(
        \&Socialtext::Rest::resource_to_yaml, 'text/x-yaml');
}

sub extra_headers {
    my $self = shift;
    my $resource = shift;

    my $lm = $self->make_http_date(
        $self->last_modified($resource)
    );
    return (
        -Last_Modified => $lm,
    );
}

sub _make_getter {
    my ( $perl_method, $content_type ) = @_;
    return sub {
        my ( $self, $rest ) = @_;
        my $t_outer = time_scope "GET_$content_type";
        my $rv = eval { $self->if_authorized( 'GET', sub {
            my $t_inner = time_scope "get_resource";
            my $resource = $self->get_resource($rest, $content_type);
            $resource = [] unless ref $resource;

            my %new_headers = (
                -status => HTTP_200_OK,
                -type => $content_type . '; charset=UTF-8',
                # override those with:
                $self->extra_headers($resource), $rest->header,
            );
            $rest->header(%new_headers);
            return $self->$perl_method($resource);
        })};
        if (my $e = $@) {
            my %error_handlers = (
                'Auth'           => sub { $self->not_authorized },
                'NotFound'       => sub { $self->http_404($rest) },
                'NoSuchResource' => sub { $self->no_resource($e->name) },
                'Conflict'       => sub { $self->conflict($e->errors) },
                'BadRequest'     => sub { $self->http_400($rest, $e->message) },
            );
            for my $class_type (keys %error_handlers) {
                my $class = 'Socialtext::Exception::' . $class_type;
                if (Exception::Class->caught($class)) {
                    return $error_handlers{$class_type}->();
                }
            }
            $e->rethrow if Exception::Class->caught('Socialtext::Exception');

            # Rely on error thrower to set HTTP headers properly.
            my ($error) = split "\n", $e; # first line only
            st_log->info("Rest Collection Error: $e");
            warn "Rest Collection Error: $e\n";
        }

        return $rv;
    };
}

sub new {
    my $proto = shift;

    my $class = ref($proto) || $proto;
    my $new_object = $class->SUPER::new(@_);

    return $new_object;
}


=head1 SUBCLASSING

The below methods may be overridden to specialize behaviour of a particular
implementation.

=cut

sub _initialize {
    my ( $self, $rest, $params ) = @_;

    $self->SUPER::_initialize($rest, $params);

    $self->{FilterParameters} = {
        'filter' => 'name',
        'name_filter' => 'name',
        'type' => 'type',
    };
}



=head3 $obj->get_resource($rest)

Returns a listref of the elements in this collection.  Each element should be a hashref containing both 'uri' and 'name' elements.

=cut
sub get_resource {
    my ($self) = @_;

    return [
        $self->_limit_collectable(
            $self->_sort_collectable(
                [ $self->_hashes_for_query ]
            )
        )
    ];
}

=head2 $obj->_hashes_for_query

Returns a list of HASHREFs corresponding to the current query.  By default,
this simply calls

    map { $obj->_entity_hash($_) } $obj->_entities_for_query

but subclasses can override this.

=cut

sub _hashes_for_query {
    my $self = shift;
    my $t = time_scope '_entities_for_query';
    my @results =  $self->_entities_for_query;
    $t = time_scope '_entity_hash_map';
    return map { $self->_entity_hash($_) } @results;
}

=head2 $obj->add_text_element($text);

POST_text calls this with a text/plain representation of an element to be
added to the collection.  If a new element was created, this should return the
URI of that new element.  If not, it should return undef.

=head2 $obj->last_modified($resource)

Returns a timestamp identifying when the current resource was last modified.
The default implementation just returns the current time.

=cut

sub last_modified { time }

=head2 $obj->collection_name

Returns a suitable name for this collection, such as "Tags for Admin wiki".

=cut

sub collection_name { 'Collection' }

=head2 $obj->element_list_item($element)

Returns an HTML representation of a single list item.  The passed in $element
is a hashref containing both values for both the 'uri' and 'name' keys.

=cut

# REVIEW: Does name need to be html escaped?
sub element_list_item { 
    my $self = shift;
    my $elem = shift;
    $elem->{name} ||= '';
    if ($elem->{uri}) {
        return "<li><a href='$elem->{uri}'>$elem->{name}</a></li>\n" 
    }
    return "<li>{uri}'>$elem->{name}</li>\n" 
}

# FIXME: Add conversion of 'is_*' slots to 'true'/'false' values.
sub resource_to_html {
    my ( $self, $resource ) = @_;

    my $name = $self->collection_name;
    my $body = join '', map { $self->element_list_item($_) } @$resource;
    return (<< "END_OF_HEADER" . $body . << "END_OF_TRAILER");
<html>
<head>
<title>$name</title>
</head>
<body>
<h1>$name</h1>
<ul>
END_OF_HEADER
</ul>
</body>
</html>
END_OF_TRAILER
}

sub resource_to_json { encode_json($_[1]) }
sub resource_to_text { $_[0]->_resource_to_text($_[1]) }
sub _resource_to_text { 
    my $self = shift;
    my $resource = shift;

    return join '', map { "$_->{name}\n" } @$resource;
}

sub allowed_methods { 'GET, HEAD, POST' }

sub filter_spec { return $_[0]->{FilterParameters}; }

sub create_filter {
    my $self = shift;

    my $filter_sub = sub { @_ };
    my %filter_field = %{ $self->filter_spec };
    while (my( $param, $field ) = each %filter_field) {
        my $param_value = $self->rest->query->param($param);
        if ($param_value) {
            my $old_filter_sub = $filter_sub;
            $filter_sub = sub {
                grep {$_->{$field} =~ /$param_value/i}
                &$old_filter_sub
            };
        }
    }

    return $filter_sub;
}

# Limit the results based on the count query parameter
sub _limit_collectable {
    my $self = shift;
    my $count = $self->rest->query->param('count');
    my $offset = $self->rest->query->param('offset') || 0;
    #my $filter = $self->rest->query->param('filter');
    #my $filter_sub = $filter
    #    ? sub {grep {$_->{name} =~ /$filter/i} @_}
    #    : sub { @_ };

    my $filter_sub = sub { @_ };
    my %filter_field = %{ $self->filter_spec };
    while (my( $param, $field ) = each %filter_field) {
        my $param_value = $self->rest->query->param($param);
        if (defined $param_value and length $param_value) {
            $param_value = Socialtext::Base->utf8_decode($param_value);
            my $old_filter_sub = $filter_sub;
            $filter_sub = sub {
                grep {$_->{$field} =~ /$param_value/i}
                &$old_filter_sub
            };
        }
    }


    my $count_sub = $count || $offset
        ? sub {
        $count ||= @_;
        my $limit = ($offset + $count) - 1;
        $limit = ( $#_ < $limit ) ? $#_ : $limit;
        @_[ $offset .. $limit ];
        }
        : sub {@_};
    return &$count_sub( &$filter_sub(@_) );
}

# The default sorts available for the 'order' parameter.
# See _sort_collectable
sub SORTS {
    return +{
        alpha => sub {
            lcmp($Socialtext::Rest::Collection::a->{name},
                 $Socialtext::Rest::Collection::b->{name});
        },
        newest => sub {
            $Socialtext::Rest::Collection::b->{modified_time} <=>
                $Socialtext::Rest::Collection::a->{modified_time};
        },
    };
}

# Given a list of entities, orders them based on the 'order' query param.
sub _sort_collectable {
    my $self         = shift;
    my $entities_ref = shift;
    my $order        = $self->rest->query->param('order');

    my $sub = $self->SORTS->{$order} if $order;

    return $sub
        ? sort $sub @$entities_ref
        : @$entities_ref;
}

=head2 Sorting

In addition, each class has a constant hash SORT which contains
sort types paired with sort methods for that sort in the class using it.
If SORT is not defined in the class, the defaults described in
the parent class are used.

=cut

1;

=head1 AUTHOR

Socialtext, Inc. C<< <code@socialtext.com> >>

=head1 COPYRIGHT & LICENSE

Copyright 2006 Socialtext, Inc., all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut
