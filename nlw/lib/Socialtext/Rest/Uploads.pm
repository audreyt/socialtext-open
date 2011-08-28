package Socialtext::Rest::Uploads;
# @COPYRIGHT@
use Moose;
extends 'Socialtext::Rest::Collection';
use Socialtext::HTTP ':codes';
use Socialtext::BrowserDetect;
use Socialtext::Upload;
use Socialtext::JSON qw/encode_json/;
use Socialtext::SQL qw/sql_txn/;
use Try::Tiny;
use namespace::clean -except => 'meta';

sub permission { +{} }
sub collection_name { 'Uploads' }

sub _entities_for_query {
    my $self = shift;
    unless ($self->rest->user->is_business_admin) {
        $self->rest->header( -status => HTTP_401_Unauthorized );
        return '';
    }
    my @dirs;
    opendir my $dir, $Socialtext::Upload::UPLOAD_DIR or return ();
    while (my $file = readdir $dir) {
        next if $file =~ /^\./;
        push @dirs, $file;
    }
    return @dirs;
}

sub _entity_hash {
    my $self = shift;
    my $id   = shift;
    return { name => $id, uri => "/data/uploads/$id" };
}

around 'POST_file' => \&sql_txn;
sub POST_file {
    my $self = shift;
    my $rest = shift;
    my $q = $rest->query;

    unless ($self->rest->user->is_authenticated) {
        return $self->_post_failure(
            $rest, HTTP_401_Unauthorized, 'user is not authenticated'
        );
    }

    my $fail_msg;
    my $upload = try {
        Socialtext::Upload->Create(
            cgi => $q,
            cgi_param => 'file',
            creator => $rest->user,
        );
    }
    catch {
        if (/no upload field/) {
            $fail_msg = '"file" is a required parameter for form-type uploads';
        }
        elsif (/no (?:filename|Content-Type)/) {
            $fail_msg = 'file part was missing filename or Content-Type metadata in the Content-Disposition header';
        }
        elsif (/^Error during sql_/) {
            warn $_;
            $fail_msg = "could not store file; a database error occurred";
        }
        else {
            ($fail_msg = $_) =~ s{(?:^Trace begun)? at \S+ line .+}{}ims;
        }
    };

    return $self->_post_failure($rest, HTTP_400_Bad_Request, $fail_msg)
        if ($fail_msg);

    $rest->header( -status => HTTP_201_Created );

    my $response = encode_json({
        status  => 'success',
        id      => $upload->attachment_uuid,
        message => 'file uploaded',
    });

    if (Socialtext::BrowserDetect::adobe_air()) {
        return << ".";
<html><head>
    <script>window.childSandboxBridge = $response;</script>
</head><body>success</body></html>
.
    }

    return $response;
}

sub _post_failure {
    my $self    = shift;
    my $rest    = shift;
    my $status  = shift;
    my $message = shift;

    $rest->header($rest->header(), -status => $status);
    return encode_json( {status => 'failure', message => $message} );
}

__PACKAGE__->meta->make_immutable(inline_constructor => 0);
1;

=head1 NAME

Socialtext::Rest::Uploads - Upload temporary files for later use

=head1 SYNOPSIS

    GET /data/uploads
    POST /data/uploads

=head1 DESCRIPTION

Upload files for temporary use as logos, etc

=cut
