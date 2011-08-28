var tests = 2;
plan({ 'tests': tests });

// Initializing
var die_msg = '';
Ajax.Req.prototype.die = function(message) {
    die_msg = message;
};

// Testing

var test_timeout = 5000;
var async_id = beginAsync(test_timeout);
var ending_count = 0 ;

var ending = function() {
    ending_count++;
    if( ending_count >= tests) {
        endAsync(async_id);
    }
};

var cb = function(text) {
    is(text, 'basic test\n', 'Fetch basic.txt asynchrnously');
    ending();
};
Ajax.get('data/basic.txt', cb);

var cb2 = function(text) {
    if( die_msg ) {
        is( die_msg , 'Ajax request for "data/nonexists" failed with status: 404', 'Testing on nonexist URL');
    }
};
Ajax.get('data/nonexists', cb2);
