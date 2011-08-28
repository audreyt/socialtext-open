var t = new Test.Visual();

t.plan(3);

var doClickAddTagButton = function() { 
    return function() {
        t.$('#st-tags-addlink').click();
        t.poll(function(){
            return t.$('#st-tags-field').is(':visible');
        }, function () { t.callNextStep(1000) } );
    };
};

var doSubmitAddTagForm = function(tag) {
    return function() {
        t.$('#st-tags-field').val(tag);
        t.$('#st-tags-form').submit();
        t.poll(function(){
            t.scrollTo(t.$('#st-tags-plusbutton-link').offset().top);
            return t.$('#st-tags-plusbutton-link').is(':visible');
        }, function () { t.callNextStep() } );
    };
};

var testOffsets = function() { 
    return function() {
        t.scrollTo(t.$('#st-tags-field').offset().top);
        t.ok(
            t.$('#st-tags-field').offset().left
                < t.$('#st-tags-addbutton-link').offset().left,
            "Adding a tag: Input and button does not wrap inbetween"
        );
        t.callNextStep();
    };
};
t.runAsync([
    t.doCreatePage('fnord', {w: '1024px'}),

    doClickAddTagButton(),
    testOffsets(),
    doSubmitAddTagForm('Hello World'),
            
    doClickAddTagButton(),
    testOffsets(),
    doSubmitAddTagForm('xxx'),

    doClickAddTagButton(),
    testOffsets(),
    
    function() { 
        t.endAsync();
    }
]);
