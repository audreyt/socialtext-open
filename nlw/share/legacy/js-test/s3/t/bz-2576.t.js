var t = new Test.Visual();

t.plan(1);

t.runAsync([
    function() {
        t.open_iframe(
	    '/?action=search_people&scope=_&search_term=devnull1%40socialtext.com'
	    , t.nextStep()
	)
    },

    function() { 
        t.is( t.$('a.realName').text(), 'devnull1', 'People search works on strings containing @');
        t.endAsync();
    }
]);
