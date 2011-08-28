package Socialtext::HTTP;
# @COPYRIGHT@

use warnings;
use strict;

use base 'Exporter';

our %EXPORT_TAGS = (
    codes => [qw(
        HTTP_100_Continue
        HTTP_101_Switching_Protocols
        HTTP_200_OK
        HTTP_201_Created
        HTTP_202_Accepted
        HTTP_203_Non_Authoritative_Information
        HTTP_204_No_Content
        HTTP_205_Reset_Content
        HTTP_206_Partial_Content
        HTTP_300_Multiple_Choices
        HTTP_301_Moved_Permanently
        HTTP_302_Found
        HTTP_303_See_Other
        HTTP_304_Not_Modified
        HTTP_305_Use_Proxy
        HTTP_307_Temporary_Redirect
        HTTP_400_Bad_Request
        HTTP_401_Unauthorized
        HTTP_402_Payment_Required
        HTTP_403_Forbidden
        HTTP_404_Not_Found
        HTTP_405_Method_Not_Allowed
        HTTP_406_Not_Acceptable
        HTTP_407_Proxy_Authentication_Required
        HTTP_408_Request_Timeout
        HTTP_409_Conflict
        HTTP_410_Gone
        HTTP_411_Length_Required
        HTTP_412_Precondition_Failed
        HTTP_413_Request_Entity_Too_Large
        HTTP_414_Request_URI_Too_Long
        HTTP_415_Unsupported_Media_Type
        HTTP_416_Requested_Range_Not_Satisfiable
        HTTP_417_Expectation_Failed
        HTTP_500_Internal_Server_Error
        HTTP_501_Not_Implemented
        HTTP_502_Bad_Gateway
        HTTP_503_Service_Unavailable
        HTTP_504_Gateway_Timeout
        HTTP_505_HTTP_Version_Not_Supported
    )]
);
our @EXPORT_OK = @{$EXPORT_TAGS{codes}};

sub HTTP_100_Continue            {'100 Continue'}
sub HTTP_101_Switching_Protocols {'101 Switching Protocols'}
sub HTTP_200_OK                  {'200 OK'}
sub HTTP_201_Created             {'201 Created'}
sub HTTP_202_Accepted            {'202 Accepted'}

sub HTTP_203_Non_Authoritative_Information {
    '203 Non-Authoritative Information'
}
sub HTTP_204_No_Content         {'204 No Content'}
sub HTTP_205_Reset_Content      {'205 Reset Content'}
sub HTTP_206_Partial_Content    {'206 Partial Content'}
sub HTTP_300_Multiple_Choices   {'300 Multiple Choices'}
sub HTTP_301_Moved_Permanently  {'301 Moved Permanently'}
sub HTTP_302_Found              {'302 Found'}
sub HTTP_303_See_Other          {'303 See Other'}
sub HTTP_304_Not_Modified       {'304 Not Modified'}
sub HTTP_305_Use_Proxy          {'305 Use Proxy'}
sub HTTP_307_Temporary_Redirect {'307 Temporary Redirect'}
sub HTTP_400_Bad_Request        {'400 Bad Request'}
sub HTTP_401_Unauthorized       {'401 Unauthorized'}
sub HTTP_402_Payment_Required   {'402 Payment Required'}
sub HTTP_403_Forbidden          {'403 Forbidden'}
sub HTTP_404_Not_Found          {'404 Not Found'}
sub HTTP_405_Method_Not_Allowed {'405 Method Not Allowed'}
sub HTTP_406_Not_Acceptable     {'406 Not Acceptable'}

sub HTTP_407_Proxy_Authentication_Required {
    '407 Proxy Authentication Required'
}
sub HTTP_408_Request_Timeout          {'408 Request Timeout'}
sub HTTP_409_Conflict                 {'409 Conflict'}
sub HTTP_410_Gone                     {'410 Gone'}
sub HTTP_411_Length_Required          {'411 Length Required'}
sub HTTP_412_Precondition_Failed      {'412 Precondition Failed'}
sub HTTP_413_Request_Entity_Too_Large {'413 Request Entity Too Large'}
sub HTTP_414_Request_URI_Too_Long     {'414 Request-URI Too Long'}
sub HTTP_415_Unsupported_Media_Type   {'415 Unsupported Media Type'}

sub HTTP_416_Requested_Range_Not_Satisfiable {
    '416 Requested Range Not Satisfiable'
}
sub HTTP_417_Expectation_Failed         {'417 Expectation Failed'}
sub HTTP_500_Internal_Server_Error      {'500 Internal Server Error'}
sub HTTP_501_Not_Implemented            {'501 Not Implemented'}
sub HTTP_502_Bad_Gateway                {'502 Bad Gateway'}
sub HTTP_503_Service_Unavailable        {'503 Service Unavailable'}
sub HTTP_504_Gateway_Timeout            {'504 Gateway Timeout'}
sub HTTP_505_HTTP_Version_Not_Supported {'505 HTTP Version Not Supported'}

=head1 NAME

Socialtext::HTTP - HTTP status codes

=head1 SYNOPSIS

use Socialtext::HTTP ':codes';

    sub GET {
        if (something_is_here) {
            return HTTP_200_OK;
        } else {
            return HTTP_404_Not_Found;
        }
    }

Each C<HTTP_> symbol expands to a string containing the numerical code
followed by its semantics taken from RFC 2616.  E.g., C<404 Not Found>.

=head1 RATIONALE

These exportable routines offer ^N/^P completion in vim for the HTTP codes and
their semantics.  This provides more information than, say C<413> alone, but
doesn't require the programmer to look up in RFC 2616 to find that the
canonical text is C<Request Entity Too Large>.

=head1 SEE ALSO

L<http://www.w3.org/Protocols/rfc2616/rfc2616.html>

=cut

1;
