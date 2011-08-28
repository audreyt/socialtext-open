#!perl
# @COPYRIGHT@

use strict;
use warnings;
use YAML;
use Test::Socialtext tests => 116;

fixtures(qw( empty ));

BEGIN {
    use_ok( 'Socialtext::WikiwygPlugin' );
}

my $hub       = new_hub('empty');
my $yaml_path = Socialtext::AppConfig->code_base .
                '/skin/wikiwyg/javascript/Widgets.yaml';

SET_FIELDS_with_search: {
    my $widget = {id => 'search'};
    my $args = '<workspace> magic phrase';
    my $widgets = {
        widget => {
            search => {
                fields => ['search_term', 'workspace_id'],
                parse => {
                    regexp => '^(?:<(\S+)>)?\s*(.*?)?\s*$',
                    fields => ['workspace_id', 'search_term'],
                },
            },
        },
    };
    $hub->wikiwyg->set_fields($widget, $args, $widgets);
    is( $widget->{workspace_id}, 'workspace', 'workspace_id set' );
    is( $widget->{search_term}, 'magic phrase', 'search_term set' );
    is( $widget->{search_type}, 'text', 'text search type' );
}

SET_FIELDS_with_category_search: {
    my $widget = {id => 'search'};
    my $args = '<workspace> category:cat1';
    my $widgets = {
        widget => {
            search => {
                fields => ['search_term', 'workspace_id'],
                parse => {
                    regexp => '^(?:<(\S+)>)?\s*(.*?)?\s*$',
                    fields => ['workspace_id', 'search_term'],
                },
            },
        },
    };
    $hub->wikiwyg->set_fields($widget, $args, $widgets);
    is( $widget->{workspace_id}, 'workspace', 'workspace_id set' );
    is( $widget->{search_term}, 'cat1', 'search_term set' );
    is( $widget->{search_type}, 'category', 'category search type' );
}

SET_FIELDS_1: {
    my $widget = {id => 'toc'};
    my $args = 'workspace [page]';
    my $widgets = {
        widget => {
            toc => {
                fields => ['workspace_id', 'page_title'],
                parse => {
                    regexp => '^(\S*)?\s*\[([^\]]*)\]\s*$',
                    no_match => 'workspace_id',
                },
            },
        },
    };
    $hub->wikiwyg->set_fields($widget, $args, $widgets);
    is( $widget->{workspace_id}, 'workspace', 'workspace_id set' );
    is( $widget->{page_title}, 'page', 'page_title set' );
}

SET_FIELDS_2: {
    my $widget = {id => 'image'};
    my $args = 'workspace [page] filename';
    my $widgets = {
        widget => {
            image => {
                fields => ['image_name', 'workspace_id', 'page_title', 'label'],
                parse => {
                    regexp => '?three-part-link',
                    no_match => 'image_name',
                    fields => ['workspace_id', 'page_title', 'image_name'],
                },
            },
        },
        regexps => {
            'three-part-link' => '^(\S*)?\s*\[([^\]]*)\]\s*(.*?)?\s*$',
            'workspace-value' => '^(?:(\S+);)?\s*(.*?)?\s*$',
        }
    };
    $hub->wikiwyg->set_fields($widget, $args, $widgets);
    is( $widget->{workspace_id}, 'workspace', 'workspace_id set' );
    is( $widget->{page_title}, 'page', 'page_title set' );
    is( $widget->{image_name}, 'filename', 'image_name set' );
}

SET_FIELDS_3: {
    my $widget = {id => 'skype'};
    my $args = 'testuser';
    my $widgets = {
        widget => {
            skype => {
                field => 'skype_id',
            },
        },
        regexps => {
            'three-part-link' => '^(\S*)?\s*\[([^\]]*)\]\s*(.*?)?\s*$',
            'workspace-value' => '^(?:(\S+);)?\s*(.*?)?\s*$',
        }
    };
    $hub->wikiwyg->set_fields($widget, $args, $widgets);
    is( $widget->{skype_id}, 'testuser', 'skype_id set' );
}

PARSE_WIDGET_full: {
    my $widgets = {
        widget => {
            toc => {
                fields => ['workspace_id', 'page_title'],
                parse => {
                    regexp => '^(\S*)?\s*\[([^\]]*)\]\s*$',
                    no_match => 'workspace_id',
                },
            },
        },
    };
    my $wafl = "{toc_full}";
    my $widget = $hub->wikiwyg->parse_widget($wafl, $widgets);
    is( $widget->{id}, 'toc', '*full* widget id' );
    is( $widget->{full}, '1', 'full flag is true' );
}

PARSE_WIDGET_not_full: {
    my $widgets = {
        widget => {
            toc => {
                fields => ['workspace_id', 'page_title'],
                parse => {
                    regexp => '^(\S*)?\s*\[([^\]]*)\]\s*$',
                    no_match => 'workspace_id',
                },
            },
        },
    };
    my $wafl = "{toc}";
    my $widget = $hub->wikiwyg->parse_widget($wafl, $widgets);
    is( $widget->{full}, '0', 'full flag is false' );
}

PARSE_WIDGET_toc_blank: {
    my $widgets = {
        widget => {
            toc => {
                fields => ['workspace_id', 'page_title'],
                parse => {
                    regexp => '^(\S*)?\s*\[([^\]]*)\]\s*$',
                    no_match => 'workspace_id',
                },
            },
        },
    };
    my $wafl = "{toc}";
    my $widget = $hub->wikiwyg->parse_widget($wafl, $widgets);
    is( $widget->{id}, 'toc', 'plain toc' );
    is( $widget->{workspace_id}, '', 'plain toc workspace_id' );
    is( $widget->{page_title}, '', 'plain toc page_title' );
}

PARSE_WIDGET_toc_alternate_page: {
    my $widgets = {
        widget => {
            toc => {
                fields => ['workspace_id', 'page_title'],
                parse => {
                    regexp => '^(\S*)?\s*\[([^\]]*)\]\s*$',
                    no_match => 'workspace_id',
                },
            },
        },
    };
    my $wafl = "{toc: [Test Page]}";
    my $widget = $hub->wikiwyg->parse_widget($wafl, $widgets);
    is( $widget->{id}, 'toc', 'alt page toc id' );
    is(  $widget->{page_title}, 'Test Page', 'alt page toc page_title' );
}

PARSE_WIDGET_tag: {
    my $widgets = YAML::LoadFile($yaml_path);
    my $wafl = '"label"{tag: workspace; tag}';
    my $widget = $hub->wikiwyg->parse_widget($wafl, $widgets);
    is( $widget->{id}, 'tag', 'tag widget id' );
    is( $widget->{workspace_id}, 'workspace', 'tag workspace_id' );
    is( $widget->{tag_name}, 'tag', 'tag name' );
    is( $widget->{label}, 'label', 'tag label' );
}

PARSE_WIDGET_section: {
    my $widgets = YAML::LoadFile($yaml_path);
    my $wafl = '{section: name}';
    my $widget = $hub->wikiwyg->parse_widget($wafl, $widgets);
    is( $widget->{id}, 'section', 'section widget id' );
    is( $widget->{section_name}, 'name', 'section name' );
}

PARSE_WIDGET_image: {
    my $widgets = YAML::LoadFile($yaml_path);
    my $wafl = '"label"{image: workspace [page] name}';
    my $widget = $hub->wikiwyg->parse_widget($wafl, $widgets);
    is( $widget->{id}, 'image', 'image widget id' );
    is( $widget->{label}, 'label', 'image has label' );
    is( $widget->{workspace_id}, 'workspace', 'image workspace id' );
    is( $widget->{page_title}, 'page', 'image page title' );
    is( $widget->{image_name}, 'name', 'image name' );
}

PARSE_WIDGET_file: {
    my $widgets = YAML::LoadFile($yaml_path);
    my $wafl = '"label"{file: workspace [page] name}';
    my $widget = $hub->wikiwyg->parse_widget($wafl, $widgets);
    is( $widget->{id}, 'file', 'file widget id' );
    is( $widget->{label}, 'label', 'file has label' );
    is( $widget->{workspace_id}, 'workspace', 'file workspace id' );
    is( $widget->{page_title}, 'page', 'file page title' );
    is( $widget->{file_name}, 'name', 'file name' );
}

PARSE_WIDGET_weblog: {
    my $widgets = YAML::LoadFile($yaml_path);
    my $wafl = '"label"{weblog: workspace; name}';
    my $widget = $hub->wikiwyg->parse_widget($wafl, $widgets);
    is( $widget->{id}, 'weblog', 'weblog widget id' );
    is( $widget->{label}, 'label', 'weblog has label' );
    is( $widget->{workspace_id}, 'workspace', 'weblog workspace id' );
    is( $widget->{weblog_name}, undef, 'weblog name' );
}

PARSE_WIDGET_blog: {
    my $widgets = YAML::LoadFile($yaml_path);
    my $wafl = '"label"{blog: workspace; name}';
    my $widget = $hub->wikiwyg->parse_widget($wafl, $widgets);
    is( $widget->{id}, 'blog', 'blog widget id' );
    is( $widget->{label}, 'label', 'blog has label' );
    is( $widget->{workspace_id}, 'workspace', 'blog workspace id' );
    is( $widget->{blog_name}, 'name', 'blog name' );
}

PARSE_WIDGET_search: {
    my $widgets = YAML::LoadFile($yaml_path);
    my $wafl = '{search: <workspace> term}';
    my $widget = $hub->wikiwyg->parse_widget($wafl, $widgets);
    is( $widget->{id}, 'search', 'search widget id' );
    is( $widget->{workspace_id}, 'workspace', 'search workspace id' );
    is( $widget->{search_term}, 'term', 'search term' );
    is( $widget->{search_type}, 'text', 'search type: text' );
}

PARSE_WIDGET_include: {
    my $widgets = YAML::LoadFile($yaml_path);
    my $wafl = '{include: workspace [page]}';
    my $widget = $hub->wikiwyg->parse_widget($wafl, $widgets);
    is( $widget->{id}, 'include', 'include widget id' );
    is( $widget->{workspace_id}, 'workspace', 'include workspace id' );
    is( $widget->{page_title}, 'page', 'include page' );
}

PARSE_WIDGET_new_form_page: {
    my $widgets = YAML::LoadFile($yaml_path);
    my $wafl = '{new_form_page: name text}';
    my $widget = $hub->wikiwyg->parse_widget($wafl, $widgets);
    is( $widget->{id}, 'new_form_page', 'new_form_page widget id' );
    is( $widget->{form_name}, 'name', 'new_form_page form name' );
    is( $widget->{form_text}, 'text', 'new_form_page text' );
}

PARSE_WIDGET_fetchrss: {
    my $widgets = YAML::LoadFile($yaml_path);
    my $wafl = "{fetchrss: url}";
    my $widget = $hub->wikiwyg->parse_widget($wafl, $widgets);
    is( $widget->{id}, 'fetchrss', 'fetchrss widget id' );
    is( $widget->{rss_url}, 'url', 'fetchrss url' );
}

PARSE_WIDGET_fetchatom: {
    my $widgets = YAML::LoadFile($yaml_path);
    my $wafl = "{fetchatom: url}";
    my $widget = $hub->wikiwyg->parse_widget($wafl, $widgets);
    is( $widget->{id}, 'fetchatom', 'fetchatom widget id' );
    is( $widget->{atom_url}, 'url', 'fetchatom url' );
}

PARSE_WIDGET_googlesoap: {
    my $widgets = YAML::LoadFile($yaml_path);
    my $wafl = "{googlesoap: term}";
    my $widget = $hub->wikiwyg->parse_widget($wafl, $widgets);
    is( $widget->{id}, 'googlesoap', 'googlesoap widget id' );
    is( $widget->{search_term}, 'term', 'googlesoap search' );
}

PARSE_WIDGET_googlesearch: {
    my $widgets = YAML::LoadFile($yaml_path);
    my $wafl = "{googlesearch term}";
    my $widget = $hub->wikiwyg->parse_widget($wafl, $widgets);
    is( $widget->{id}, 'googlesearch', 'googlesearch widget id' );
    is( $widget->{search_term}, 'term', 'googlesearch search' );
}

PARSE_WIDGET_recent_changes: {
    my $widgets = YAML::LoadFile($yaml_path);
    my $wafl = "{recent_changes: workspace}";
    my $widget = $hub->wikiwyg->parse_widget($wafl, $widgets);
    is( $widget->{id}, 'recent_changes', 'recent_changes widget id' );
    is( $widget->{workspace_id}, 'workspace', 'recent_changes workspace' );
    is( $widget->{full}, '0', 'recent_changes defaults to not full' );
}

PARSE_WIDGET_tag_list: {
    my $widgets = YAML::LoadFile($yaml_path);
    my $wafl = "{tag_list: <workspace> name}";
    my $widget = $hub->wikiwyg->parse_widget($wafl, $widgets);
    is( $widget->{id}, 'tag_list', 'tag_list widget id' );
    is( $widget->{workspace_id}, 'workspace', 'tag_list workspace' );
    is( $widget->{tag_name}, 'name', 'tag_list name' );
    is( $widget->{full}, '0', 'tag_list defaults to not full' );
}

PARSE_WIDGET_weblog_list: {
    my $widgets = YAML::LoadFile($yaml_path);
    my $wafl = "{weblog_list: <workspace> name}";
    my $widget = $hub->wikiwyg->parse_widget($wafl, $widgets);
    is( $widget->{id}, 'weblog_list', 'weblog_list widget id' );
    is( $widget->{workspace_id}, 'workspace', 'weblog_list workspace' );
    is( $widget->{weblog_name}, undef, 'weblog_list name' );
    is( $widget->{full}, '0', 'weblog_list defaults to not full' );
}

PARSE_WIDGET_blog_list: {
    my $widgets = YAML::LoadFile($yaml_path);
    my $wafl = "{blog_list: <workspace> name}";
    my $widget = $hub->wikiwyg->parse_widget($wafl, $widgets);
    is( $widget->{id}, 'blog_list', 'blog_list widget id' );
    is( $widget->{workspace_id}, 'workspace', 'blog_list workspace' );
    is( $widget->{blog_name}, 'name', 'blog_list name' );
    is( $widget->{full}, '0', 'blog_list defaults to not full' );
}

PARSE_WIDGET_aim: {
    my $widgets = YAML::LoadFile($yaml_path);
    my $wafl = "{aim: name}";
    my $widget = $hub->wikiwyg->parse_widget($wafl, $widgets);
    is( $widget->{id}, 'aim', 'aim widget id' );
    is( $widget->{aim_id}, 'name', 'aim user id' );
}

PARSE_WIDGET_aim: {
    my $widgets = YAML::LoadFile($yaml_path);
    my $wafl = "aim:testuser";
    my $widget = $hub->wikiwyg->parse_widget($wafl, $widgets);
    is( $widget->{id}, 'aim', 'aim widget id' );
    is( $widget->{aim_id}, 'testuser', 'aim user id' );
}

PARSE_WIDGET_yahoo: {
    my $widgets = YAML::LoadFile($yaml_path);
    my $wafl = "{yahoo: name}";
    my $widget = $hub->wikiwyg->parse_widget($wafl, $widgets);
    is( $widget->{id}, 'yahoo', 'yahoo widget id' );
    is( $widget->{yahoo_id}, 'name', 'yahoo user id' );
}

PARSE_WIDGET_skype: {
    my $widgets = YAML::LoadFile($yaml_path);
    my $wafl = "{skype: name}";
    my $widget = $hub->wikiwyg->parse_widget($wafl, $widgets);
    is( $widget->{id}, 'skype', 'skype widget id' );
    is( $widget->{skype_id}, 'name', 'skype user id' );
}

PARSE_WIDGET_user: {
    my $widgets = YAML::LoadFile($yaml_path);
    my $wafl = "{user: name}";
    my $widget = $hub->wikiwyg->parse_widget($wafl, $widgets);
    is( $widget->{id}, 'user', 'user widget id' );
    is( $widget->{user_email}, 'name', 'user user id' );
}

PARSE_WIDGET_date: {
    my $widgets = YAML::LoadFile($yaml_path);
    my $wafl = "{date: D T TZ}";
    my $widget = $hub->wikiwyg->parse_widget($wafl, $widgets);
    is( $widget->{id}, 'date', 'date widget id' );
    is( $widget->{date_string}, 'D T TZ', 'date date string' );
}

PARSE_WIDGET_asis: {
    my $widgets = YAML::LoadFile($yaml_path);
    my $wafl = '{{_text_}}';
    my $widget = $hub->wikiwyg->parse_widget($wafl, $widgets);
    is( $widget->{id}, 'asis', 'asis widget id' );
    is( $widget->{asis_content}, '_text_', 'asis asis_content' );
}

PARSE_WIDGET_interworkspace_link: {
    my $widgets = YAML::LoadFile($yaml_path);
    my $wafl = '"label"{link: workspace [page] section}';
    my $widget = $hub->wikiwyg->parse_widget($wafl, $widgets);
    is( $widget->{id}, 'link2', 'link2 widget id' );
    is( $widget->{label}, 'label', 'link2 has label' );
    is( $widget->{workspace_id}, 'workspace', 'link2 workspace id' );
    is( $widget->{page_title}, 'page', 'link2 page title' );
    is( $widget->{section_name}, 'section', 'link2 section_name' );
}

PARSE_WIDGET_link2: {
    my $widgets = YAML::LoadFile($yaml_path);
    my $wafl = '"label"{link: [page] section}';
    my $widget = $hub->wikiwyg->parse_widget($wafl, $widgets);
    is( $widget->{id}, 'link2', 'link2 widget id' );
    is( $widget->{label}, 'label', 'link2 has label' );
    is( $widget->{workspace_id}, '', 'link2 workspace id is blank' );
    is( $widget->{page_title}, 'page', 'link2 page title' );
    is( $widget->{section_name}, 'section', 'link2 section_name' );
}

RESOLVE_SYNONYMS: {
    my $widgets = {
        synonyms => {
            abc => '123',
            def => '456',
        },
    };
    my $cleanedup = $hub->wikiwyg->resolve_synonyms('abc', $widgets);
    is( $cleanedup, '123', 'resolve synonym' );
    $cleanedup = $hub->wikiwyg->resolve_synonyms('dabc', $widgets);
    is( $cleanedup, 'dabc', 'no synonym match' );
}

IS_MULTIPLE: {
    my $widgets = {
        widget => {
            link1 => '123',
            link2 => '456',
            plain => '456',
        },
    };
    my $bool = $hub->wikiwyg->is_multiple('link', $widgets);
    is( $bool, 1, 'link is a multiple' );
    $bool = $hub->wikiwyg->is_multiple('plain', $widgets);
    is( $bool, 0, 'plain is not a multiple' );
}

GET_FIRST_MULTIPLE: {
    my $widgets = {
        widget => {
            link1 => '123',
            link2 => '456',
            plain => '456',
        },
    };
    my $id = $hub->wikiwyg->get_first_multiple('link', $widgets);
    isnt( $id, 'link', 'id returned from first multiple for link is a multiple' );
    $id = $hub->wikiwyg->get_first_multiple('plain', $widgets);
    is( $id, 'plain', 'plain has no multiple so the id is returned' );
}

MAP_MULTIPLE_SAME_WIDGETS: {
    my $widgets = {
        widgets => ['a', 'b', 'c1', 'c2', 'e', 'f', 'g'],
        widget => {
            c1 => {
                select_if => {
                    'defined' => ['f1'],
                }
            },
            c2 => {
                select_if => {
                    'blank' => ['f1'],
                }
            },
        },
    };
    my $widget = {
        id => 'c1',
        'f1' => 'has value',
    };
    my $id = $hub->wikiwyg->map_multiple_same_widgets($widget, $widgets);
    is( $id, 'c1', 'c1 widget with f1 maps to c1' );

    $widget = {
        id => 'c2',
        'f1' => 'has value',
    };
    $id = $hub->wikiwyg->map_multiple_same_widgets($widget, $widgets);
    is( $id, 'c1', 'c2 widget with f1 maps to c1' );

    $widget->{f1} = '';
    $id = $hub->wikiwyg->map_multiple_same_widgets($widget, $widgets);
    is( $id, 'c2', 'widget without f1 maps to c2' );

    $widget->{id} = 'c2';
    $id = $hub->wikiwyg->map_multiple_same_widgets($widget, $widgets);
    is( $id, 'c2', 'c2 widget without f1 maps to c2' );
}

WIDGET_IMAGE_TEXT: {
    my $wafl = '{image: workspace [page] name}';
    my $text = $hub->wikiwyg->widget_image_text($wafl);
    is($text, 'image: name', 'image text is the name of the image');
}

WIDGET_IMAGE_TEXT_with_label: {
    my $wafl = '"label"{image: workspace [page] name}';
    my $text = $hub->wikiwyg->widget_image_text($wafl);
    is($text, 'image: label', 'image text is the label');
}

WIDGET_IMAGE_TEXT_no_brace: {
    my $wafl = 'aim:name';
    my $text = $hub->wikiwyg->widget_image_text($wafl);
    is($text, 'AIM: name', 'no brace wafl has correct text');
}

WIDGET_IMAGE_TEXT_synonym: {
    my $wafl = 'ymsgr:name';
    my $text = $hub->wikiwyg->widget_image_text($wafl);
    is($text, 'Yahoo! IM: name', 'synonym wafl has correct text');
}
