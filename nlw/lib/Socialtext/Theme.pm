package Socialtext::Theme;
use Moose;
use Socialtext::JSON qw(decode_json encode_json);
use Socialtext::SQL qw(sql_singlevalue sql_execute sql_txn);
use Socialtext::SQL::Builder qw(sql_insert sql_update sql_nextval);
use Socialtext::File qw(mime_type);
use Socialtext::AppConfig;
use Socialtext::User;
use Socialtext::Upload;
use YAML ();
use namespace::clean -except => 'meta';

my @COLUMNS = qw( theme_id name header_color header_image_id
    header_image_tiling header_image_position background_color
    background_image_id background_image_tiling background_image_position
    primary_color secondary_color tertiary_color header_font body_font
    is_default
);

my @UPLOADS = qw(header_image background_image);

has $_ => (is=>'ro', isa=>'Str', required=>1) for @COLUMNS;
has $_ => (is=>'ro', isa=>'Socialtext::Upload', lazy_build=>1) for @UPLOADS;

sub _build_header_image {
    my $self = shift;
    return Socialtext::Upload->Get(attachment_id => $self->header_image_id);
}

sub _build_background_image {
    my $self = shift;
    return Socialtext::Upload->Get(attachment_id => $self->background_image_id);
}

sub Load {
    my $class = shift;
    my $field = shift;
    my $value = shift;

    die "must use a unique identifier"
        unless grep { $_ eq $field } qw(theme_id name);

    my $sth = sql_execute(qq{
        SELECT }. join(',', @COLUMNS) .qq{
          FROM theme
         WHERE $field = ?
    }, $value);

    my $rows = $sth->fetchall_arrayref({});

    return scalar(@$rows)
        ? $class->new(%{$rows->[0]})
        : undef;
}

sub All {
    my $class = shift;
    return [
        map { $class->new(%$_) } @{$class->_AllThemes()}
    ];
}

sub Default {
    my $class = shift;

    my $sth = sql_execute(qq{
        SELECT }. join(',', @COLUMNS) .qq{
          FROM theme
         WHERE is_default IS true
    });

    my $rows = $sth->fetchall_arrayref({});

    die "cannot determine default theme"
        unless scalar(@$rows) == 1;

    return $class->new(%{$rows->[0]})
}

sub as_hash {
    my $self = shift;
    my $params = (@_ == 1) ? shift : {@_};

    my %as_hash = map { $_ => $self->$_ } @COLUMNS;

    if (!$params->{set} || $params->{set} ne 'minimal') {
        my $header = $self->header_image;
        $as_hash{header_image_url} = $self->_attachment_url('header');
        $as_hash{header_image_filename} = $header->filename;
        $as_hash{header_image_mime_type} = $header->mime_type;

        my $background = $self->background_image;
        $as_hash{background_image_url} = $self->_attachment_url('background');
        $as_hash{background_image_filename} = $background->filename;
        $as_hash{background_image_mime_type} = $background->mime_type;
    }

    return \%as_hash;
}

sub Update {
    my $class = shift;
    my $params = (@_ == 1) ? shift : {@_};

    die "no theme_id for installed theme ($params->{name})\n"
        unless $params->{theme_id};
    my $to_update = $class->_CleanParams($params);

    sql_update(theme => $to_update, 'theme_id');
    return $class->new(%$to_update);
}

sub Create {
    my $class = shift;
    my $params = (@_ == 1) ? shift : {@_};

    $params->{theme_id} ||= sql_nextval('theme_theme_id');
    my $to_insert = $class->_CleanParams($params);

    sql_insert(theme => $to_insert);

    return $class->new(%$to_insert);
}

sub MakeImportable {
    my $class = shift;
    my $data = shift;
    my $dir = shift;

    my $name = delete $data->{base_theme};
    my $base_theme = $name
        ? $class->Load(name=>$name) || $class->Default()
        : $class->Default();
    $data->{base_theme_id} = $base_theme->theme_id;

    $class->_CreateAttachmentsIfNeeded($dir, $data);

    return $data;
}

sub MakeExportable {
    my $class = shift;
    my $data = shift;
    my $themedir = shift;

    my $base_theme = $class->Load(theme_id => delete $data->{base_theme_id});
    $data->{base_theme} = $base_theme->name;

    for my $image_name (@UPLOADS) {
        my $id_field = $image_name . "_id";
        my $image = Socialtext::Upload->Get(attachment_id=>$data->{$id_field});
        my $copy_to = $themedir . "/" . $image->filename;
        $image->copy_to_file($copy_to);

        $data->{$image_name} = $image->filename;
        delete $data->{$id_field};
    }

    return $data;
}

sub ValidSettings {
    my $class = shift;
    my $settings = (@_ == 1) ? shift : {@_};

    my %tests = (
        base_theme_id => \&_valid_theme_id,
        header_color => \&_valid_hex_color,
        header_image_id => \&_valid_attachment_id,
        header_image_tiling => \&_valid_tiling,
        header_image_position => \&_valid_position,
        background_color => \&_valid_hex_color,
        background_image_id => \&_valid_attachment_id,
        background_image_tiling => \&_valid_tiling,
        background_image_position => \&_valid_position,
        primary_color => \&_valid_hex_color,
        secondary_color => \&_valid_hex_color,
        tertiary_color => \&_valid_hex_color,
        header_font => \&_valid_font,
        body_font => \&_valid_font,
    );

    for my $name ( keys %$settings ) {
        my $test = $tests{$name};

        return 0 unless $test;
        return 0 unless $test->($settings->{$name});
    }

    return 1;
}

sub EnsureRequiredDataIsPresent {
    my $class = shift;
    my $themedir = Socialtext::AppConfig->code_base . '/themes';

    my $installed = { map { $_->{name} => $_ } @{$class->_AllThemes()} };
    my $all = YAML::LoadFile("$themedir/themes.yaml");

    for my $name (keys %$all) {
        my $theme = $all->{$name};
        $theme->{name} = $name;

        my %to_check = %$theme;
        delete $to_check{$_} for qw(
            header_image is_default name theme_id background_image);
        die "theme $name has invalid settings, refusing to install/update"
            unless $class->ValidSettings(%to_check);


        if (my $existing = $installed->{$name}) {
            die "no theme_id for installed theme ($name)?\n"
                unless $existing->{theme_id};

            $class->Update(%$existing, %$theme);
        }
        else {
            $class->Create($theme);
        }
    }
}

sub _valid_hex_color {
    my $color = shift;

    return lc($color) =~ /^#[0-9a-f]{6}$/;
}

sub _valid_position {
    my $position = shift;
    my @pos = split(/ /, $position);

    return 0 unless scalar(@pos) == 2;
    return 0 unless grep { lc($pos[0]) eq $_ } qw(left center right);
    return 0 unless grep { lc($pos[1]) eq $_ } qw(top center bottom);
    return 1;
}

sub _valid_tiling {
    my $tiling = shift;

    return grep { lc($tiling)  eq $_ } qw(horizontal vertical both none);
}

sub _valid_font {
    my $font = shift;

    return grep { $font eq $_ }
        qw(Arial Georgia Helvetica Lucinda Trebuchet Times)
}

sub _valid_attachment_id {
    my $id = shift;

    return 0 unless $id =~ /^\d+$/;

    my $count = eval {
        sql_singlevalue(q{
            SELECT COUNT(1)
              FROM attachment
             WHERE attachment_id = ?
        }, $id)
    };

    return $count;
}

sub _valid_theme_id {
    my $id = shift;

    return 0 unless $id =~ /^\d+$/;

    my $count = eval {
        sql_singlevalue(q{
            SELECT COUNT(1)
              FROM theme
             WHERE theme_id = ?
        }, $id)
    };

    return $count;
}

sub _attachment_url {
    my $self = shift;
    my $image = shift;

    my $name = $self->name;
    return "/data/themes/$name/images/$image";
}

sub _CleanParams {
    my $class = shift;
    my $params = shift;
    my $themedir = Socialtext::AppConfig->code_base . '/themes';

    $class->_CreateAttachmentsIfNeeded($themedir, $params);
    return +{ map { $_ => $params->{$_} } @COLUMNS };

}

sub _AllThemes {
    my $class = shift;

    my $sth = sql_execute(qq{
        SELECT }. join(', ', @COLUMNS) .qq{
          FROM theme
    });

    return $sth->fetchall_arrayref({}) || [];
}

sub _CreateAttachmentsIfNeeded {
    my $class = shift;
    my $themedir = shift;
    my $params = shift;

    my $creator = Socialtext::User->SystemUser;

    # Don't worry about breaking links to old upload objects, they'll get
    # auto-cleaned.
    for my $temp_field (@UPLOADS) {
        my $filename = delete $params->{$temp_field};
        next unless $filename;

        my $db_field = $temp_field . "_id";

        my @parts = split(/\./, $filename);
        my $mime_guess = 'image/'. $parts[-1];

        my $tempfile = "$themedir/$filename";
        my $file = Socialtext::Upload->Create(
            creator => $creator,
            temp_filename => $tempfile,
            filename => $filename,
            mime_type => mime_type($tempfile, $filename, $mime_guess),
        );
        $file->make_permanent(actor => $creator); 

        $params->{$db_field} = $file->attachment_id;
    }
}

__PACKAGE__->meta->make_immutable;
1;

=head1 NAME

Socialtext::Theme - Manage Socialtext Themes

=head1 SYNOPSIS

    use Socialtext::Theme
    my $theme = Socialtext::Theme->Load(theme_id=>1);

=head1 DESCRIPTION

Keep default themes up-to-date and manage user editable theme fields.
