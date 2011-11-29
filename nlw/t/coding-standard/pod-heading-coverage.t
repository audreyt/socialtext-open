#!perl
# @COPYRIGHT@
use warnings;
use strict;
use Test::More;
use Socialtext::Pod::HeadingCoverage;

###############################################################################
# These modules have been grandfathered in as "todo", as per discussion in
# early June 2009.
#
# Any NEW modules written after that discussion MUST have the appropriate POD
# sections; those modules are not being grandfathered in.
#
# Thus, you should never be _adding_ to this list, only potentially removing
# things from it if/as POD gets written.
my %ToDoModules = map { $_ => 1 } qw(
    Apache::Session::Store::Postgres::Socialtext
    Socialtext
    Socialtext::AccessHandler::IsBusinessAdmin
    Socialtext::AccountInvitation
    Socialtext::AccountLogo
    Socialtext::ApacheDaemon
    Socialtext::Attachment
    Socialtext::Attachments
    Socialtext::AttachmentsUIPlugin
    Socialtext::BacklinksPlugin
    Socialtext::BreadCrumbsPlugin
    Socialtext::BrowserDetect
    Socialtext::BugsPlugin
    Socialtext::Build
    Socialtext::Build::ConfigureValues
    Socialtext::Cache::Hash
    Socialtext::CGI
    Socialtext::CGI::Scrubbed
    Socialtext::CLI
    Socialtext::CategoryPlugin
    Socialtext::CommentUIPlugin
    Socialtext::CredentialsExtractor::Apache
    Socialtext::CredentialsExtractor::BasicAuth
    Socialtext::CredentialsExtractor::Cookie
    Socialtext::CredentialsExtractor::Guest
    Socialtext::DaemonUtil
    Socialtext::Data
    Socialtext::Date
    Socialtext::Date::l10n
    Socialtext::Date::l10n::en
    Socialtext::Date::l10n::ja
    Socialtext::DeletePagePlugin
    Socialtext::DevEnvPlugin
    Socialtext::DisplayPlugin
    Socialtext::DuplicatePagePlugin
    Socialtext::EditPlugin
    Socialtext::EmailNotifier
    Socialtext::EmailNotifyPlugin
    Socialtext::EmailPageUIPlugin
    Socialtext::EmailReceiver::Factory
    Socialtext::EmailReceiver::en
    Socialtext::EmailReceiver::ja
    Socialtext::EmailSender::Factory
    Socialtext::Encode
    Socialtext::Events
    Socialtext::Events::Recorder
    Socialtext::Events::Reporter
    Socialtext::Exceptions
    Socialtext::FetchRSSPlugin
    Socialtext::File
    Socialtext::File::Stringify
    Socialtext::File::Stringify::Default
    Socialtext::File::Stringify::application_msword
    Socialtext::File::Stringify::application_pdf
    Socialtext::File::Stringify::application_postscript
    Socialtext::File::Stringify::application_vnd_ms_excel
    Socialtext::File::Stringify::application_vnd_ms_powerpoint
    Socialtext::File::Stringify::application_zip
    Socialtext::File::Stringify::audio_mpeg
    Socialtext::File::Stringify::text_html
    Socialtext::File::Stringify::text_plain
    Socialtext::File::Stringify::text_rtf
    Socialtext::File::Stringify::text_xml
    Socialtext::FillInFormBridge
    Socialtext::Formatter::AbsoluteLinkDictionary
    Socialtext::Formatter::Block
    Socialtext::Formatter::LiteLinkDictionary
    Socialtext::Formatter::Phrase
    Socialtext::Formatter::RESTLinkDictionary
    Socialtext::Formatter::RailsDemoLinkDictionary
    Socialtext::Formatter::SharepointLinkDictionary
    Socialtext::Formatter::SkinLinkDictionary
    Socialtext::Formatter::Wafl
    Socialtext::Formatter::WaflBlock
    Socialtext::Formatter::WaflPhrase
    Socialtext::Functional
    Socialtext::Group::Default
    Socialtext::Group::Homunculus
    Socialtext::HTMLArchive
    Socialtext::HTTP
    Socialtext::Handler::Authen
    Socialtext::Handler::ControlPanel
    Socialtext::Handler::REST
    Socialtext::Handler::URIMap
    Socialtext::Headers
    Socialtext::Helpers
    Socialtext::HitCounterPlugin
    Socialtext::HomepagePlugin
    Socialtext::Hub
    Socialtext::Image
    Socialtext::Indexes
    Socialtext::InitFunctions
    Socialtext::l10n
    Socialtext::Locales
    Socialtext::MLDBMAccess
    Socialtext::MassAdd
    Socialtext::Migration
    Socialtext::Migration::Utils
    Socialtext::MultiPlugin
    Socialtext::NewFormPagePlugin
    Socialtext::OpenIdPlugin
    Socialtext::Page
    Socialtext::Page::TablePopulator
    Socialtext::PageActivityPlugin
    Socialtext::PageAnchorsPlugin
    Socialtext::Pages
    Socialtext::Pageset
    Socialtext::PdfExport::LinkDictionary
    Socialtext::PdfExportPlugin
    Socialtext::PerfData
    Socialtext::Pluggable::Adapter
    Socialtext::Pluggable::Plugin
    Socialtext::Pluggable::Plugin::Default
    Socialtext::Pluggable::Plugin::Groups
    Socialtext::Pluggable::Plugin::Test
    Socialtext::Pluggable::Plugin::Widgets
    Socialtext::Pluggable::Plugin::Homepage
    Socialtext::Pluggable::WaflPhrase
    Socialtext::Pluggable::WaflPhraseDiv
    Socialtext::Plugin
    Socialtext::PreferencesPlugin
    Socialtext::ProvisionPlugin
    Socialtext::Query::CGI
    Socialtext::Query::Plugin
    Socialtext::Query::Wafl
    Socialtext::RecentChangesPlugin
    Socialtext::RefcardPlugin
    Socialtext::RenamePagePlugin
    Socialtext::RequestContext
    Socialtext::Rest
    Socialtext::Rest::AccountLogo
    Socialtext::Rest::AccountUsers
    Socialtext::Rest::Accounts
    Socialtext::Rest::App
    Socialtext::Rest::Attachment
    Socialtext::Rest::Attachments
    Socialtext::Rest::Backlinks
    Socialtext::Rest::BreadCrumbs
    Socialtext::Rest::Challenge
    Socialtext::Rest::Collection
    Socialtext::Rest::Comments
    Socialtext::Rest::Echo
    Socialtext::Rest::Entity
    Socialtext::Rest::Events
    Socialtext::Rest::Events::Activities
    Socialtext::Rest::Events::Awesome
    Socialtext::Rest::Events::Conversations
    Socialtext::Rest::Events::Followed
    Socialtext::Rest::Events::Page
    Socialtext::Rest::EventsBase
    Socialtext::Rest::Feed
    Socialtext::Rest::Frontlinks
    Socialtext::Rest::Help
    Socialtext::Rest::HomePage
    Socialtext::Rest::Hydra
    Socialtext::Rest::Jobs
    Socialtext::Rest::Links
    Socialtext::Rest::Lite
    Socialtext::Rest::Log
    Socialtext::Rest::Page
    Socialtext::Rest::PageAttachments
    Socialtext::Rest::PageRevision
    Socialtext::Rest::PageRevisions
    Socialtext::Rest::PageTagHistory
    Socialtext::Rest::Pages
    Socialtext::Rest::ReportAdapter
    Socialtext::Rest::Settings::DefaultWorkspace
    Socialtext::Rest::Tag
    Socialtext::Rest::TaggedPages
    Socialtext::Rest::Tags
    Socialtext::Rest::User
    Socialtext::Rest::UserSharedAccounts
    Socialtext::Rest::Users
    Socialtext::Rest::Version
    Socialtext::Rest::Wafl
    Socialtext::Rest::Workspace
    Socialtext::Rest::WorkspaceAttachments
    Socialtext::Rest::WorkspaceUser
    Socialtext::Rest::WorkspaceUsers
    Socialtext::Rest::Workspaces
    Socialtext::Resting::RegressionTest
    Socialtext::RevisionPlugin
    Socialtext::RtfExportPlugin
    Socialtext::SOAPGoogle
    Socialtext::Search::Basic::Factory
    Socialtext::Search::Basic::Indexer
    Socialtext::Search::Basic::Searcher
    Socialtext::Search::Hit
    Socialtext::Search::Utils
    Socialtext::SearchPlugin
    Socialtext::ShortcutLinksPlugin
    Socialtext::Skin
    Socialtext::Statistic
    Socialtext::Statistic::CpuTime
    Socialtext::Statistic::ElapsedTime
    Socialtext::Statistic::HeapDelta
    Socialtext::Statistics
    Socialtext::Stax
    Socialtext::Storage
    Socialtext::String
    Socialtext::Syndicate::Atom
    Socialtext::Syndicate::RSS20
    Socialtext::System
    Socialtext::SystemSettings
    Socialtext::Template
    Socialtext::Template::Plugin::decorate
    Socialtext::Template::Plugin::encode_mailto
    Socialtext::Template::Plugin::fillinform
    Socialtext::Template::Plugin::flatten
    Socialtext::Template::Plugin::html_encode
    Socialtext::TheSchwartz
    Socialtext::TiddlyPlugin
    Socialtext::TimeZonePlugin
    Socialtext::Timer
    Socialtext::UniqueArray
    Socialtext::UploadedImage
    Socialtext::User::Base
    Socialtext::User::Cache
    Socialtext::User::Factory
    Socialtext::User::Find
    Socialtext::User::Find::Workspace
    Socialtext::UserPreferencesPlugin
    Socialtext::UserSettingsPlugin
    Socialtext::Validate
    Socialtext::WatchlistPlugin
    Socialtext::WebApp
    Socialtext::WeblogArchive
    Socialtext::WeblogPlugin
    Socialtext::WikiFixture::ApplianceConfig
    Socialtext::WikiFixture::EmailJob
    Socialtext::WikiFixture::OpenLDAP
    Socialtext::WikiFixture::SocialBase
    Socialtext::WikiFixture::SocialCalc
    Socialtext::WikiFixture::SocialRest
    Socialtext::WikiFixture::SocialWidgets
    Socialtext::WikiFixture::SocialpointPlugin
    Socialtext::WikiFixture::Socialtext
    Socialtext::WikiFixture::WebHook
    Socialtext::WikiText::Emitter::HTML
    Socialtext::WikiText::Emitter::Messages::Base
    Socialtext::WikiText::Emitter::Messages::Canonicalize
    Socialtext::WikiText::Emitter::Messages::HTML
    Socialtext::WikiText::Emitter::SearchSnippets
    Socialtext::WikiText::Parser
    Socialtext::WikiText::Parser::Messages
    Socialtext::Wikil10n
    Socialtext::Wikiwyg::AnalyzerPlugin
    Socialtext::WikiwygPlugin
    Socialtext::Workspace::Importer
    Socialtext::Workspace::Permissions
    Socialtext::WorkspaceInvitation
    Socialtext::WorkspaceListPlugin
    Socialtext::WorkspacesUIPlugin
    Test::HTTP::Socialtext
    Test::Live
    Test::SeleniumRC
    Test::Socialtext
    Test::Socialtext::Rest
    Test::Socialtext::Account
    Test::Socialtext::CGIOutput
    Test::Socialtext::Ceqlotron
    Test::Socialtext::Environment
    Test::Socialtext::Fixture
    Test::Socialtext::Search
    Test::Socialtext::Thrower
    Socialtext::Template::Plugin::html_truncate
    Socialtext::Rest::WebHooks
    Socialtext::Rest::WebHook
    Socialtext::WebHook
    Socialtext::Job::Test
    Socialtext::Job::AttachmentIndex
    Socialtext::Job::Cmd
    Socialtext::Job::EmailNotify
    Socialtext::Job::EmailNotifyUser
    Socialtext::Job::PageIndex
    Socialtext::Job::Upgrade::MigrateUserWorkspacePrefs
    Socialtext::Job::WatchlistNotify
    Socialtext::Job::WatchlistNotifyUser
    Socialtext::Job::WeblogPing
    Socialtext::Job::SignalDMNotify
    Socialtext::Job::WebHook
    Socialtext::Jobs
    Socialtext::Job
    Socialtext::JobCreator
);

###############################################################################
# Find all the modules, and plan our tests
my @all_modules = @ARGV;
unless (@all_modules) {
    @all_modules = all_core_modules();
}
plan tests => scalar @all_modules;

###############################################################################
# Test each module in turn
foreach my $file (sort @all_modules) {
    my $module  = file_to_module($file);
    my $message = "Pod coverage on $module";

    my $pc = Socialtext::Pod::HeadingCoverage->new(
        package           => $module,
        required_headings => [qw( NAME SYNOPSIS DESCRIPTION )],
    );
    my $rating = $pc->coverage() || 0;
    my $is_ok  = ($rating == 1);
    my @nakies = sort $pc->naked;

    if (exists $ToDoModules{$module}) {
        if (@nakies) {
            $message = "OLD $module; " .  join(', ', @nakies);
            $is_ok = 1;
        }
    }
    if ($module =~ m/WikiFixture/) {
        $message = "TEST $module; " .  join(', ', @nakies);
        $is_ok = 1;
    }

    ok $is_ok, $message;
    unless ($is_ok) {
        diag(
            sprintf(
                "Coverage for %s is %3.1f%%, with %d missing:",
                $module, $rating * 100, scalar @nakies
            )
        );
        diag("\t$_") for @nakies;
    }
}
exit;


###############################################################################
# Find all modules in "lib/" that are *files* (e.g. they haven't been
# symlinked in from some other part of the system).
sub all_core_modules {
    my @all_files = `find lib -type f -name "*.pm"`;
    chomp @all_files;
    return grep { -s $_ > 3 } @all_files;
}

###############################################################################
# Takes a filename (e.g. "lib/Socialtext/Apache/AuthenHandler.pm") and
# converts that into a module name (e.g. "Socialtext::Apache::AuthenHandler").
sub file_to_module {
    my $file = shift;
    $file =~ s{lib/}{};             # strip leading "lib/"
    $file =~ s{\.pm$}{};            # strip file suffix
    $file =~ s{/}{::}g;             # convert file to module name
    return $file;
}
