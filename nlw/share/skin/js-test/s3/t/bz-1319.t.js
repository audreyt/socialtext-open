var t = new Test.Visual();

t.plan(1);

t.runAsync([
    function() {
        t.open_iframe("/admin/?" + t.gensym(), t.nextStep(3000), { w: '500px' });
    },
            
    function() { 
        t.is(
            t.$('#st-editing-tools-edit').offset().top,
            t.$('#controlsRight').offset().top,
            'controlsRight did not drop down to reveal a giant blue bar.'
        );

        t.endAsync();
    }
]);
