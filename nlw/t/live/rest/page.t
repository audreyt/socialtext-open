#!perl
# @COPYRIGHT@

use warnings;
use strict;
use utf8;

use Test::HTTP::Socialtext '-syntax', tests => 97;

use Readonly;
use Socialtext::JSON;
use Socialtext::Page;
use Socialtext::User;
use Socialtext::Workspace;
use Socialtext::String ();
use Test::Live fixtures => ['admin_with_extra_pages', 'help', 'foobar'];
use Test::More;

Readonly my $BASE =>
    Test::HTTP::Socialtext->url('/data/workspaces/admin/pages');
Readonly my $EXISTING_NAME => 'Admin Wiki';
Readonly my $UTF8_PAGE      => 'Και';

# http://www.homestarrunner.com/sbemail147.html
Readonly my $NEW_NAME      => 'Wretched Simmons';
Readonly my $NEW_NAME_FF3_B5      => 'Wretched Simmons FF3';
Readonly my $NEW_BODY =>
    "You got to $UTF8_PAGE drop her like a trig class.\n";
Readonly my $NEWER_BODY =><<"EOF";
Trying to get some girl $UTF8_PAGE to like some guy I don't know

Visit "recent changes"<http:index.cgi?action=recent_changes>.

{file: [formattingtest] Robot.txt}

{category: welcome}

{search: hello}

{category-list welcome}
EOF

Readonly my $JSON_BODY => "This is the json $UTF8_PAGE version\n";
my $JSON_ADMIN_HASH = {
    content => $JSON_BODY,
    from    => 'devnull9@socialtext.com',
    date    => 'Sat, 30 Sep 2006 22:22:22 GMT',
};
Readonly my $JSON_ADMIN_OBJ => encode_json($JSON_ADMIN_HASH);
my $JSON_ADMIN_TAG_HASH = {
    content => $JSON_BODY,
    from    => 'devnull9@socialtext.com',
    date    => 'Sat, 30 Sep 2006 23:23:23 GMT',
    tags    => [ 'apple', 'orange', $UTF8_PAGE],
};
Readonly my $JSON_ADMIN_TAG_OBJ => encode_json($JSON_ADMIN_TAG_HASH);

Readonly my $HTML_BODY =><<'EOF';
<h1>Hello</h1>

<p>HTML is the format of the nineties dude
repent from that stuff.</p>

<ul>
<li>one</li>
<li>two</li>
</ul>
EOF

my $LastModified;
test_http "GET existing page" {
    >> GET $BASE/$EXISTING_NAME

    << 200

    $LastModified = $test->response->header('Last-Modified');
}

# Also check for etag and pragma
my $Etag;
test_http "HEAD existing page" {
    >> HEAD $BASE/$EXISTING_NAME
    >> Accept: text/x.socialtext-wiki

    << 200
    ~< ETag: ^\d{14}

    is $test->response->decoded_content, '',
        'content is empty on head of existing page';

    is $test->response->header('Last-Modified'), $LastModified,
        "Last modified on HEAD is same as GET: $LastModified";
    ok !defined( $test->response->header('Pragma') ),
        'pragma header should not be set when etag header is set';
    ok !defined( $test->response->header('Cache-control') ),
        'cache-control header should not be set when etag header is set';

    $Etag = $test->response->header('Etag');
}

test_http "GET with a good Etag" {
    >> GET $BASE/$EXISTING_NAME
    >> Accept: text/x.socialtext-wiki
    >> If-None-Match: $Etag

    << 304
}

test_http "GET with a bad Etag" {
    >> GET $BASE/$EXISTING_NAME
    >> Accept: text/x.socialtext-wiki
    >> If-None-Match: slartibartfast

    << 200
}

test_http "HEAD non existing page" {
    >> HEAD $BASE/$NEW_NAME

    << 404
}

TODO: {
    local $TODO = "The 2F problem is hairy.";

    test_http "GET existing page with embedd %2F" {
        >> GET $BASE/admin%2Fwiki

        << 200
    }
}

test_http "GET existing page as html" {
    >> GET $BASE/$EXISTING_NAME
    >> Accept: text/html

    << 200
    ~< Content-Type: text/html

    my $body = $test->response->decoded_content();

    like $body, qr{<a href="start_here"\s*>start here</a>},
        'body has a properly formatted start here link';
    like $body,
        qr{href="/data/workspaces/help-en/pages/socialtext_documentation"\s*>Socialtext Documentation</a>},
        'body has a properly formatted doc link';
}

test_http "GET existing page as json" {
    >> GET $BASE/$EXISTING_NAME
    >> Accept: application/json

    << 200
    ~< Content-Type: application/json

    my $result = decode_json($test->response->decoded_content);

    is ref($result), 'HASH', 'result is a hash ref';

    is $result->{name}, 'Admin Wiki', 'page name is Admin Wiki';
}

test_http "GET page list match $EXISTING_NAME" {
    >> GET $BASE
    >> Accept: text/plain

    << 200
    <<
    ~< $EXISTING_NAME
}

test_http "PUT page with Etag for $EXISTING_NAME" {
    >> PUT $BASE/$EXISTING_NAME
    >> Content-Type: text/x.socialtext-wiki
    >> If-Match: $Etag
    >>
    >> Hello

    << 204
}

test_http "PUT page with out of date Etag for $EXISTING_NAME" {
    >> PUT $BASE/$EXISTING_NAME
    >> Content-Type: text/x.socialtext-wiki
    >> If-Match: $Etag
    >>
    >> Hello

    << 412
}

test_http "DELETE existing page" {
    >> DELETE $BASE/$EXISTING_NAME

    << 204

    >> GET $BASE/$EXISTING_NAME

    << 404
}

test_http "GET page list doesn't match $EXISTING_NAME" {
    >> GET $BASE
    >> Accept: text/plain

    << 200

    unlike $test->response->decoded_content, qr{$EXISTING_NAME},
        "page list does not contain $EXISTING_NAME";
}

test_http "PUT new page" {
    >> PUT $BASE/$NEW_NAME
    >> Content-type: text/x.socialtext-wiki
    >>
    >> $NEW_BODY
    

    << 201

    >> GET $BASE/$NEW_NAME
    >> Accept: text/x.socialtext-wiki

    << 200
    ~< Content-type: \btext/x.socialtext-wiki\b
    <<
    << $NEW_BODY
}


test_http "PUT new page FF3" {
    >> PUT $BASE/$NEW_NAME_FF3_B5
    >> Content-type: text/x.socialtext-wiki; charset=UTF-8
    >>
    >> $NEW_BODY
    

    << 201

    >> GET $BASE/$NEW_NAME_FF3_B5
    >> Accept: text/x.socialtext-wiki

    << 200
    ~< Content-type: \btext/x.socialtext-wiki\b
    <<
    << $NEW_BODY
}

test_http "PUT to existing page" {
    >> PUT $BASE/$NEW_NAME
    >> Content-type: text/x.socialtext-wiki
    >>
    >> $NEWER_BODY

    << 204

    >> GET $BASE/$NEW_NAME
    >> Accept: text/x.socialtext-wiki

    << 200
    ~< Content-type: \btext/x.socialtext-wiki\b

    my $body = $test->response->decoded_content();
    my $new_body = $NEWER_BODY;
    $body =~ s/\n+//gs;
    $new_body =~ s/\n+//gs;
    is( $body, $new_body, "newer body is returns as newer body" );

    confirm_subject($NEW_NAME, Socialtext::String::title_to_id($NEW_NAME));
}


test_http "PUT to existing page with uri not name" {
    my $name = Socialtext::String::title_to_id($NEW_NAME);

    >> PUT $BASE/$name
    >> Content-type: text/x.socialtext-wiki
    >>
    >> $NEWER_BODY

    << 204

    confirm_subject($NEW_NAME, $name);
}


test_http "GET HTML for formatting" {
    >> GET $BASE/$NEW_NAME
    >> Content-type: text/html

    << 200

    my $body = $test->response->decoded_content();

    like $body,
        qr{/admin/index.cgi\?action=recent_changes".*recent changes},
        'special link gets its special formatting';
    like $body,
        qr{/data/workspaces/admin/pages\?q=hello},
        'search link is correct';
    like $body,
        qr{/data/workspaces/admin/tags/welcome/pages},
        'category link is correct';
    like $body,
        qr{/data/workspaces/admin/attachments/formattingtest:\d+-\d+-\d+/files/Robot.txt},
        'attachment link is correct';

}

test_http "create new page (die die die)" {
    >> POST $BASE
    >> Content-type: text/x.socialtext-wiki
    >>
    >> I'd paint two murals.

    << 201
    ~< Location: devnull1
}

$Test::HTTP::BasicUsername = 'devnull2@socialtext.com';
test_http "create new page (die die die) an non-member" {
    >> POST $BASE
    >> Content-type: text/x.socialtext-wiki
    >>
    >> I'd paint two murals.

    << 403

}

$Test::HTTP::BasicUsername = 'devnull1@socialtext.com';
test_http "PUT new utf8 page" {
    >> PUT $BASE/$UTF8_PAGE
    >> Content-type: text/x.socialtext-wiki
    >>
    >> $NEW_BODY
    

    << 201

    >> GET $BASE/$UTF8_PAGE
    >> Accept: text/x.socialtext-wiki

    << 200
    ~< Content-type: \btext/x.socialtext-wiki\b
    <<
    << $NEW_BODY
}

test_http "PUT new utf8 page via JSON" {
    >> PUT $BASE/$UTF8_PAGE
    >> Content-type: application/json
    >>
    >> $JSON_ADMIN_OBJ

    << 204
}

test_http "GET JSON created page" {
    >> GET $BASE/$UTF8_PAGE
    >> Accept: application/json

    << 200

    my $info = decode_json($test->response->decoded_content());

    like $info->{last_edit_time}, qr{22:22:22},
        'last modified time appears correct';
    is $info->{last_editor}, 'devnull9@socialtext.com',
        'last editor is the expected devnull9';
}

my $user = Socialtext::User->new(username => 'devnull2@socialtext.com');
Socialtext::Workspace->new(name => 'admin')->add_user(user => $user);
$Test::HTTP::BasicUsername = 'devnull2@socialtext.com';
test_http "PUT utf8 page via JSON non-admin" {
    >> PUT $BASE/$UTF8_PAGE
    >> Content-type: application/json
    >>
    >> $JSON_ADMIN_OBJ

    << 204
}

test_http "GET JSON created page (again)" {
    >> GET $BASE/$UTF8_PAGE
    >> Accept: application/json

    << 200

    my $info = decode_json($test->response->decoded_content());

    unlike $info->{last_edit_time}, qr{2006-09-30},
        'last modified time was not to older time';
    isnt $info->{last_editor}, 'devnull9@socialtext.com',
        'last editor was not set to devnull9';
}

test_http "PUT JSON page with tags" {
    >> PUT $BASE/$UTF8_PAGE
    >> Content-type: application/json
    >>
    >> $JSON_ADMIN_TAG_OBJ

    << 204
}

test_http "GET tags of updated page" {
    >> GET $BASE/$UTF8_PAGE/tags
    >> Accept: text/html

    << 200
    <<
    ~< apple
    ~< orange
    ~< $UTF8_PAGE

}

test_http "PUT HTML" {
    >> PUT $BASE/HTML Page
    >> Content-type: text/html
    >>
    >> $HTML_BODY

    << 201
}

# REVIEW: Because HTML::WikiConverter does a best effort attempt
# at making HTML to Wiki converstion, it's not always going to 
# be super luxe nor super ono, so rather than string matching
# here, we'll go for regular expression.
test_http "GET Converted HTML" {
    >> GET $BASE/html_page
    >> Accept: text/x.socialtext-wiki

    << 200
    <<
    ~< \^ Hello
    ~< \* one
    ~< \* two
}

test_http "GET JSON verbose rep" {
    >> GET $BASE/html_page?verbose=1
    >> Accept: application/json

    << 200

    my $info = decode_json( $test->response->decoded_content() );

    # check meta
    is $info->{page_id}, 'html_page', 'html_page id is html_page';
    is $info->{uri},     'html_page', 'html_page uri is html_page';
    is $info->{last_editor}, 'devnull2@socialtext.com',
        'html_page from is devnull2@socialtext.com';

    # check wikitext
    like $info->{wikitext}, qr{\^ Hello}, 'wikitext looks right';

    # check html
    like $info->{html}, qr{<h1 id="hello">Hello</h1>}, 'html looks right';
}

test_http "GET JSON non-verbose rep" {
    >> GET $BASE/html_page
    >> Accept: application/json

    << 200

    my $info = decode_json( $test->response->decoded_content() );

    ok( !defined( $info->{html} ),
        'html is not defined in non verbose json rep' );
    ok( !defined( $info->{wikitext} ),
        'html is not defined in non verbose json rep' );
    is $info->{page_id}, 'html_page', 'html_page id is html_page';
}

test_http "PUT a single link page" {
    >> PUT $BASE/html_page
    >> Content-type: text/x.socialtext-wiki
    >> 
    >> Hello [monkey]

    << 204
}

test_http "GET JSON verbose default (REST) link_dictionary" {
    >> GET $BASE/html_page?verbose=1
    >> Accept: application/json

    << 200

    my $info = decode_json( $test->response->decoded_content() );
    my $html = $info->{html};

    like $html, qr{href="monkey"[^>]*>monkey</a>}, 'monkey link is RESTish';
}

test_http "GET JSON verbose alternate link_dictionary" {
    >> GET $BASE/html_page?verbose=1;link_dictionary=s2
    >> Accept: application/json

    << 200

    my $info = decode_json( $test->response->decoded_content() );
    my $html = $info->{html};

    like $html, qr{href="index.cgi\?monkey"[^>]*>monkey</a>}, 'monkey link is s2 style';
}

test_http "GET JSON verbose bad link_dictionary" {
    >> GET $BASE/html_page?verbose=1;link_dictionary=slap
    >> Accept: application/json

    << 500
}

test_http "GET HTML with alternate link_dictionary" {
    >> GET $BASE/html_page?link_dictionary=S2
    >> Accept: text/html

    << 200
    <<
    ~< href="index.cgi\?monkey"[^>]*>monkey</a>
}

test_http "GET HTML with lite link_dictionary" {
    >> GET $BASE/html_page?link_dictionary=Lite
    >> Accept: text/html

    << 200
    <<
    ~< href="monkey"[^>]*>monkey</a>
}

test_http "GET HTML with bad link_dictionary" {
    >> GET $BASE/html_page?link_dictionary=slap
    >> Accept: text/html

    << 500
}

sub confirm_subject {
    my $name = shift;
    my $uri  = shift;
    my $hub = Test::Socialtext::Environment->instance()
        ->hub_for_workspace('admin');
    my $page = $hub->pages->new_from_name($name);

    is $page->uri, $uri, "page has right uri $uri";
    is $page->title, $name, "page has right title $name";
    is $page->name, $name,
        "page has right Subject $name";
}

