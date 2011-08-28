(function($){

if (typeof(Socialtext) == 'undefined') Socialtext = {};
Socialtext.Base = function() {};

Socialtext.Base.errorCallback = function(callback) {
    return function(xhr, textStatus, errorThrown) {
        var error = xhr ? xhr.responseText : errorThrown;
        if (!error) error = 'An unknown error occured';
        if (callback)
            callback({errors: [error]});
        else 
            alert(error);
    };
};

Socialtext.Base.prototype = {
    errorCallback: function(callback) {
        return Socialtext.Base.errorCallback(callback);
    },

    successCallback: function(callback) {
        return function(data) { callback({ data: data }) };
    },

    /**
     * run several operations asynchronously
     *
     * takes an array of jobs, each is required to take a callback parameter
     * and call the callback after the operation is completed
     */
    runAsynch: function(jobs, callback) {
        var errors = [];

        var self = this;
        var runJob = function() {
            var job = jobs.shift();
            if (!job) { // done
                self.errors = errors;
                callback({errors: errors});
                return;
            }
            job(function(res) {
                if (res.errors && res.errors.length) {
                    errors = errors.concat(res.errors);
                }
                runJob();
            });
        };
        runJob();
    }
}

})(jQuery);
