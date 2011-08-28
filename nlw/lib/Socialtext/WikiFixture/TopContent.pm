package Socialtext::WikiFixture::TopContent;
# @COPYRIGHT@
use Moose;
use Test::More;
use Socialtext::Reports::DB;
use Socialtext::Workspace;

extends 'Socialtext::WikiFixture::SocialRest';

sub add_report_test_data {
    my $self = shift;
    my $workspace = shift;

    # Create some pages
    $self->edit_page($workspace, 'Awesome', 'content');
    $self->edit_page($workspace, 'Middle', 'content');
    $self->edit_page($workspace, 'Boring', 'content');
    my $ws = Socialtext::Workspace->new(name => $workspace);
    $ws->update(title => 'Awesome'); # set the workspace homepage

    # Now insert some rows into the DB for these pages
    my $dbh = Socialtext::Reports::DB->get_dbh;
    my $sth = $dbh->prepare('DELETE FROM workspace_actions_by_user');
    $sth->execute;
    $sth = $dbh->prepare('DELETE FROM top_content_rollup');
    $sth->execute;

    $sth = $dbh->prepare(
        'INSERT INTO workspace_actions_by_user VALUES (?,?,?,?,?,?,?)'
    );
    my @common = ('yesterday', 42, $workspace, 'user1');
    my $mult = 1;
    for my $action (qw/view_page edit_page add_to_watchlist email_page/) {
        diag "inserting $action";
        $sth->execute(@common, 'awesome', $action, 2 * $mult) || die $sth->errstr;
        $sth->execute(@common, '',        $action, 1 * $mult) || die $sth->errstr;
        $sth->execute(@common, 'middle',  $action, 2 * $mult) || die $sth->errstr;
        $sth->execute(@common, 'boring',  $action, 1 * $mult) || die $sth->errstr;
        $mult++;
    }
    $sth->execute(@common, 'Untitled Page',  'view_page', 1) || die $sth->errstr;
    $sth->execute(@common, 'untitled_page',  'view_page', 1) || die $sth->errstr;
    $sth->execute(@common, 'Untitled Spreadsheet',  'view_page', 1) || die $sth->errstr;
    $sth->execute(@common, 'untitled_spreadsheet',  'view_page', 1) || die $sth->errstr;

    $dbh->commit;
};

1;
