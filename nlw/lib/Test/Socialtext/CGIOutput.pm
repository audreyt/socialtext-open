# @COPYRIGHT@
package Test::Socialtext::CGIOutput;
use strict;
use warnings;
use CGI;
use base 'Exporter';
our @EXPORT = qw(set_query test_init get_action_output);

sub set_query {
    test_init();
    $ENV{QUERY_STRING} = shift;
}

sub test_init {
    CGI->initialize_globals;
    $ENV{'GATEWAY_INTERFACE'} = 1;
    $ENV{'REQUEST_METHOD'} = 'GET';
}

# cause edit page to display
sub get_action_output {
    my $hub = shift;
    my $class_id = shift;
    my $action = shift;

    $hub->preload;
    my $class = $hub->$class_id;
    my $html;

    eval {
        $html = $class->$action();
    };
    
    return($@, $html);
}

1;
