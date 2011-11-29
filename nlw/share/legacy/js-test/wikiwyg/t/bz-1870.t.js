var t = new Test.Wikiwyg();

t.filters({
    html: ['html_to_wikitext']
});

t.plan(4);

t.run_is('html', 'text');

/* Test
=== Space preserved around WAFLs in TDs -- from Wysiwyg
--- html
<span></span><div class="wiki"><table style="border-collapse: collapse;" class="formatter_table"><tbody><tr><td style="border: 1px solid black; padding: 0.2em;"><img title="Table of contents for ''. Click to edit." alt="st-widget-{toc: }" src="/static/3.2.0.1/widgets/03d5fa9d21dab14f4f0df57628425f30.png"></td></tr></tbody></table></div>

--- text
| {toc: } |

=== Space preserved around WAFLs in TDs -- from Display
--- html
<span></span><div class="wiki"><table style="border-collapse: collapse;" class="formatter_table"><tbody><tr><td style="border: 1px solid black; padding: 0.2em;"><div class="nlw_phrase"><table class="wafl_container"><tbody><tr><td><div class="wafl_box"><a href="/admin/index.cgi?admin_wiki">Admin Wiki</a> does not have any headers. </div></td></tr></tbody></table><!-- wiki: {toc: } --></div></td> 

--- text
| {toc: } |

=== Space preserved around WAFLs in TDs -- from Display with 2 TDs
--- html
<span></span><div class="wiki"><table style="border-collapse: collapse;" class="formatter_table"><tbody><tr><td style="border: 1px solid black; padding: 0.2em;"><div class="nlw_phrase"><table class="wafl_container"><tbody><tr><td><div class="wafl_box"><a href="/admin/index.cgi?admin_wiki">Admin Wiki</a> does not have any headers. </div></td></tr></tbody></table><!-- wiki: {toc: } --></div></td><td style="border: 1px solid black; padding: 0.2em;"><div class="nlw_phrase"><table class="wafl_container"><tbody><tr><td><div class="wafl_box"><a href="/admin/index.cgi?admin_wiki">Admin Wiki</a> does not have any headers. </div></td></tr></tbody></table><!-- wiki: {toc: } --></div></td></tr></tbody></table></div> 

--- text
| {toc: } | {toc: } |

=== Space preserved around WAFLs in TDs -- from Wysiwyg with as-is WAFL
--- html
<span></span><div class="wiki"><table style="border-collapse: collapse;" class="formatter_table"><tbody><tr><td style="border: 1px solid black; padding: 0.2em;"><img src="/static/3.2.0.1/widgets/3e34be9a86c2efb6bb4a55602c0c0371.png" alt="st-widget-{{ || }}" title="Unformatted Content"/></td></tr></tbody></table></div>

--- text
| {{ || }} |

*/
