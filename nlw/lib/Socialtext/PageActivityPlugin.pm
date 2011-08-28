# @COPYRIGHT@
package Socialtext::PageActivityPlugin;
use strict;
use warnings;

use base 'Socialtext::Plugin';

use Class::Field qw( const field );
use IO::File;
use Socialtext::AppConfig;
use Socialtext::Helpers;
use Socialtext::Exceptions;
use Socialtext::TT2::Renderer;
use Socialtext::l10n qw(loc system_locale __);
use Socialtext::BrowserDetect;
use Socialtext::JSON;
use Encode;

const class_id => 'page_activity';
const class_title => __('class.page_activity');
const cgi_class   => 'Socialtext::PageActivityPlugin::CGI';


sub register {
    my $self = shift;
    my $registry = shift;
    $registry->add( action => 'page_activity' );
}

sub page_activity {
    my $self = shift;
    if ($self->cgi->activities) {
        my $text = $self->cgi->activities;

        if ( Encode::is_utf8($text) ) {
            Encode::_utf8_off( $text );
        }

        my $activities = decode_json( $text );
        my $res = {};
        for my $a (@$activities) {
            if ($a->{page_activity}) {
                $self->create([
                    $a->{page_id},
                    $a->{user_id},
                    $a->{page_activity},
                ]);
            }
            $res->{ $a->{page_id}  } =
                $self->find_all_by_page_id( $a->{page_id} );
        }
        $res->{"__current_time"} = time;
        return encode_json($res);
    }

    if ($self->cgi->page_activity) {
        $self->create;
    }

    return encode_json($self->find_all_by_page_id)
}

sub find_all_by_page_id {
    my $self = shift;
    my $page_id = shift || $self->cgi->page_id;
    my $dbh = $self->_dbh;
    my $sth = $dbh->prepare("SELECT page_id, user_id, page_activity, MAX(created_at) FROM activity WHERE page_id = ? AND created_at > ? GROUP BY user_id ORDER BY MAX(created_at) DESC;");

    $sth->execute( $page_id, time - 30*60 );

    # Need to encode each single scalar here to UTF8 for being able to be
    # correctly encode to JSON with Socialtext::JSON
    my @all = 
        map { [ map { Encode::decode_utf8($_) } @$_] }
        @{$sth->fetchall_arrayref};
    return \@all;
}

sub create {
    my $self = shift;
    my $data = shift;

    my $dbh = $self->_dbh;
    my $sth = $dbh->prepare("INSERT INTO activity VALUES (?,?,?,?)");

    if ($data) {
        $sth->execute(@$data, time);
    }
    else {
        $sth->execute(
            $self->cgi->page_id,
            $self->cgi->user_id,
            $self->cgi->page_activity,
            time
        );
    }
}

sub _dbh {
    my $self = shift;
    my $dbfile = File::Spec->catdir($self->plugin_directory, 'main.db');
    my $dbh = (-f $dbfile)
        ? DBI->connect("dbi:SQLite:dbname=$dbfile", "", "", { AutoCommit => 1 })
        : $self->_init_database($dbfile);

    return $dbh;
}

sub _init_database {
    my $self = shift;
    my $dbfile = shift;

    my $dbh = DBI->connect("dbi:SQLite:dbname=$dbfile", "", "");
    $dbh->do("CREATE TABLE activity (page_id, user_id, page_activity, created_at)");
    return $dbh;
}

package Socialtext::PageActivityPlugin::CGI;

use base 'Socialtext::CGI';
use Socialtext::CGI qw( cgi );

cgi 'workspace_id';
cgi 'page_id';
cgi 'user_id';
cgi 'page_activity'; # view|leave|edit|save|cancel|tag|attach

cgi 'activities'; # JSON

1;

