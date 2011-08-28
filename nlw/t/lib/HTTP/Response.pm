package HTTP::Response;
# @COPYRIGHT@
use strict;
use warnings;
use unmocked 'HTTP::Status';

sub new {
    my ($class, $content) = @_;
    my $self = {};
    $content ||= 500;
    if ($content =~ /^\d+$/) {
        $self->{_rc} = $content;
        $self->{_msg} = HTTP::Status::status_message($content);
    }
    else {
        $self->{_rc} = 200;
        $self->{_msg} = HTTP::Status::status_message($content);
        $self->{_content} = $content;
    };
    bless $self, $class;
    return $self;
}

sub status_line {
    my $self = shift;
    return "$self->{_rc} $self->{_msg}";
}

sub content {
    my $self = shift;
    return $self->{_content} || $self->{_msg};
}

sub decoded_content { shift->content }

sub code {
    my $self = shift;
    return $self->{_rc};
}

{
    no warnings 'redefine';
    sub is_success ($) {
        my $self = shift;
        HTTP::Status::is_success($self->{'_rc'});
    }
}

1;
