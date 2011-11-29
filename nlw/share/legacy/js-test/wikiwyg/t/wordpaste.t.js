var t = new Test.Wikiwyg();

var filters = {
    html: ['html_to_wikitext']
};

t.plan(1);

t.filters(filters);
t.run_is('html', 'wikitext');



/* Test
=== Strip gunk from MSWord paste
--- html
<p class="MsoNormal"><span style="font-size: 10pt;">The
<st1:place w:st="on"><st1:PlaceName w:st="on">California-Brazil</st1:PlaceName>
 <st1:PlaceType w:st="on">Center</st1:PlaceType></st1:place> for International
 Trade in Renewable Energy (CITRE)<o:p></o:p></span></p>

             <p class="MsoNormal" style="margin-left: 0.5in; text-indent: -0.25in;"><span style="font-size: 10pt; font-family: &quot;Times New Roman&quot;;"><span style="">.<span style="font-family: &quot;Times New Roman&quot;; font-style: normal; font-variant: normal; font-weight: normal; font-size: 7pt; line-height: normal; font-size-adjust: none; font-stretch: normal;">&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;
             </span></span></span><span style="font-size: 10pt;">Polo Nacional de Biocombustiveis . <b style="">the</b>
--- wikitext
The California-Brazil Center for International Trade in Renewable Energy (CITRE)

> . Polo Nacional de Biocombustiveis . *the*

*/
