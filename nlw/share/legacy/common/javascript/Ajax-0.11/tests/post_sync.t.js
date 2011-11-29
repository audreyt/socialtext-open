plan({ tests: 3 });

// Initializing
var die_msg = 'I lived';
Ajax.Req.prototype.die = function(message) { die_msg = message; };

// Testing
is( Ajax.post('data/basic.txt'), 'basic test\n', 'basic post() method' );

Ajax.post('data/nonexists');
is( die_msg , 'Ajax request for "data/nonexists" failed with status: 404', 'Testing on nonexist URL');

// Test Object Interface

var a = new Ajax.Req();
is( a.post({ 'url': 'data/basic.txt' }), 'basic test\n', 'object interface .post()' ) ;

/*
a.post({ 'url': 'data/basic.txt' });
var expected_die_msg = "Don't yet support multiple requests on the same Ajax object"
is( die_msg, expected_die_msg, expected_die_msg);
*/
